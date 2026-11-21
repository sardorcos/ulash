import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'storage_budget.dart';
import 'storage_support.dart';

/// Immutable staged copies and persistent outgoing requests. User originals
/// are never moved, renamed or deleted. This alpha supports ordinary local
/// files; native coordinated file-provider snapshots are a separate adapter.
class DurableOutbox {
  DurableOutbox._(this.root, this._db, this._lease, this._budget);
  final Directory root;
  final Database _db;
  final StorageLease _lease;
  final StorageBudget? _budget;
  String get _budgetScope => 'outbox:${root.path}';
  bool _closed = false;
  int _preparing = 0;

  /// 1 = 0.1–0.3 layout, 2 = store-relative snapshot paths.
  static const int schemaVersion = 2;
  static const _managed = {'files'};
  static final _blobName = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.blob$',
  );

  static Future<DurableOutbox> open(
    Directory directory, {
    StorageBudget? budget,
  }) async {
    final root = await prepareStorageDirectory(directory);
    await ensurePlainDirectory(Directory(p.join(root.path, '.preparing')));
    await ensurePlainDirectory(Directory(p.join(root.path, 'files')));
    final lease = await StorageLease.acquire(root, 'outbox');
    Database? opened;
    try {
      final db = openJournal(
        File(p.join(root.path, 'outbox.sqlite')),
        version: schemaVersion,
        migrate: _migrate,
      );
      opened = db;
      // An interrupted preparation has no published manifest and cannot be
      // resumed under an existing fileId. Retain no misleading partial source.
      await for (final entity in Directory(
        p.join(root.path, '.preparing'),
      ).list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.part')) {
          await entity.delete();
        }
      }
      final store = DurableOutbox._(root, db, lease, budget);
      await store._deleteOrphanBlobs();
      await store._restoreBudget();
      return store;
    } catch (_) {
      opened?.close();
      await lease.release();
      rethrow;
    }
  }

  static void _migrate(Database db, int from) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS outbox_files (
        file_id TEXT PRIMARY KEY, manifest TEXT NOT NULL,
        path TEXT NOT NULL, created_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS outbox_transfers (
        request_id TEXT PRIMARY KEY, peer_id TEXT NOT NULL,
        manifest TEXT NOT NULL, remote_transfer_id TEXT,
        state TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      );
    ''');
    // Step 2: earlier builds stored absolute paths; the snapshot location is
    // fully determined by its fileId, so rewrite it relative to the root.
    db.execute(
      "UPDATE outbox_files SET path='files/' || file_id || '.blob' "
      "WHERE path != 'files/' || file_id || '.blob'",
    );
  }

  /// Moves a damaged `outbox.sqlite` (and WAL/SHM) aside after
  /// `JOURNAL_CORRUPT`. Unreferenced snapshots are removed on the next [open].
  static Future<List<String>> quarantineJournal(Directory directory) async {
    final root = await prepareStorageDirectory(directory);
    final lease = await StorageLease.acquire(root, 'outbox');
    try {
      return await quarantineJournalFiles(
        File(p.join(root.path, 'outbox.sqlite')),
      );
    } finally {
      await lease.release();
    }
  }

  String _abs(String stored) =>
      resolveStoredPath(root, stored, managedTopLevel: _managed);

  /// A crash between publishing a snapshot (rename) and inserting its row
  /// leaves a blob that nothing references and that can never be sent. Only
  /// the store's own `<uuid>.blob` files are removed.
  Future<void> _deleteOrphanBlobs() async {
    final referenced = {
      for (final row in _db.select('SELECT file_id FROM outbox_files'))
        '${row['file_id']}.blob',
    };
    await for (final entity in Directory(
      p.join(root.path, 'files'),
    ).list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is! File ||
          !_blobName.hasMatch(name) ||
          referenced.contains(name)) {
        continue;
      }
      try {
        await entity.delete();
      } on FileSystemException {
        // Accounted below as an orphan claim.
      }
    }
  }

  Future<void> _restoreBudget() async {
    if (_budget == null) return;
    final idsByPath = <String, String>{
      for (final row in _db.select('SELECT file_id,path FROM outbox_files'))
        _abs(row['path'] as String): row['file_id'] as String,
    };
    final claims = <StorageBudgetClaim>[];
    // Unknown files that are not store snapshots consume quota but are never
    // deleted automatically.
    await for (final entity in Directory(
      p.join(root.path, 'files'),
    ).list(followLinks: false)) {
      if (entity is! File) continue;
      final length = await entity.length();
      claims.add(
        StorageBudgetClaim(
          key: idsByPath[entity.path] ?? 'orphan:${entity.path}',
          usedBytes: length,
          totalBytes: length,
        ),
      );
    }
    await _budget.restoreScope(_budgetScope, claims);
  }

  Future<void> _reserve(String fileId, int length) async {
    await _budget?.reserveAll(_budgetScope, [
      StorageBudgetClaim(key: fileId, usedBytes: 0, totalBytes: length),
    ]);
  }

  Future<void> _write(
    String fileId,
    RandomAccessFile handle,
    List<int> chunk,
  ) async {
    for (var cursor = 0; cursor < chunk.length;) {
      final end = math.min(cursor + 256 * 1024, chunk.length);
      if (_budget == null) {
        await handle.writeFrom(chunk, cursor, end);
      } else {
        await _budget.write(_budgetScope, fileId, end - cursor, () async {
          await handle.writeFrom(chunk, cursor, end);
        });
      }
      cursor = end;
    }
  }

  Future<void> _settleFailedPreparation(
    String fileId,
    File temporary,
    File ready,
  ) async {
    if (_budget == null) return;
    var bytes = 0;
    for (final file in [temporary, ready]) {
      if (await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.file) {
        bytes += await file.length();
      }
    }
    if (bytes == 0) {
      await _budget.forget(_budgetScope, fileId);
    } else {
      await _budget.reconcile(
        _budgetScope,
        StorageBudgetClaim(key: fileId, usedBytes: bytes, totalBytes: bytes),
      );
    }
  }

  void _checkOpen() {
    if (_closed) {
      throw const StorageException('STORE_CLOSED', 'Outbox is closed.');
    }
  }

  Future<PreparedFile> stageFile(
    File source, {
    String? displayName,
    String? mimeType,
    void Function(int bytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    _checkOpen();
    final before = await source.stat();
    if (before.type != FileSystemEntityType.file) {
      throw const StorageException(
        'SOURCE_UNAVAILABLE',
        'Select an ordinary local file.',
      );
    }
    if (before.size > TransferLimits.maxFileBytes) {
      throw const StorageException(
        'FILE_TOO_LARGE',
        'Source exceeds the supported size.',
      );
    }
    final fileId = const Uuid().v4();
    final temporary = File(p.join(root.path, '.preparing', '$fileId.part'));
    final ready = File(p.join(root.path, 'files', '$fileId.blob'));
    RandomAccessFile? handle;
    var published = false;
    _preparing++;
    void checkCancelled() {
      if (isCancelled?.call() == true) {
        throw const StorageException(
          'PREPARATION_CANCELLED',
          'Preparation cancelled.',
        );
      }
    }

    try {
      checkCancelled();
      await _reserve(fileId, before.size);
      await validateManagedDirectory(root, temporary.parent);
      await validateManagedDirectory(root, ready.parent);
      await temporary.create(exclusive: true);
      handle = await temporary.open(mode: FileMode.write);
      final collector = DigestCollector();
      final digest = sha256.startChunkedConversion(collector);
      var length = 0;
      await for (final chunk in source.openRead()) {
        checkCancelled();
        length += chunk.length;
        if (length > TransferLimits.maxFileBytes || length > before.size) {
          throw const StorageException(
            'SOURCE_CHANGED',
            'Source length changed during preparation.',
          );
        }
        digest.add(chunk);
        await _write(fileId, handle, chunk);
        onProgress?.call(length);
      }
      digest.close();
      await handle.flush();
      await handle.close();
      handle = null;
      final afterCopy = await source.stat();
      if (!_sameSource(before, afterCopy) || length != before.size) {
        throw const StorageException(
          'SOURCE_CHANGED',
          'Source changed during preparation.',
        );
      }
      // The second streaming pass detects ordinary concurrent edits even when
      // timestamp resolution is coarse. Native coordinated snapshots remain
      // necessary for stronger guarantees on changing document providers.
      final sourceHash = await hashStoredFile(source, check: checkCancelled);
      final afterHash = await source.stat();
      final hash = collector.value!.toString();
      if (!_sameSource(before, afterHash) || sourceHash != hash) {
        throw const StorageException(
          'SOURCE_CHANGED',
          'Source is not a stable snapshot.',
        );
      }
      final manifest = FileManifest(
        fileId: fileId,
        displayName: displayName ?? p.basename(source.path),
        sizeBytes: length,
        sha256: hash,
        mimeType: mimeType,
      );
      checkCancelled();
      if (await FileSystemEntity.type(ready.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const StorageException(
          'DESTINATION_EXISTS',
          'Snapshot already exists.',
        );
      }
      await temporary.rename(ready.path);
      final created = DateTime.now().toUtc();
      journalTransaction(_db, () {
        _db.execute(
          'INSERT INTO outbox_files(file_id,manifest,path,created_at) VALUES(?,?,?,?)',
          [
            fileId,
            jsonEncode(manifest.toJson()),
            toStoredPath(root, ready.path),
            created.toIso8601String(),
          ],
        );
      });
      published = true;
      return PreparedFile(
        manifest: manifest,
        path: ready.path,
        createdAt: created,
      );
    } catch (error) {
      if (error is StorageException) rethrow;
      throw storageIoError(error);
    } finally {
      await handle?.close();
      try {
        if (!published) {
          try {
            if (await temporary.exists()) await temporary.delete();
            if (await ready.exists()) await ready.delete();
          } finally {
            await _settleFailedPreparation(fileId, temporary, ready);
          }
        }
      } finally {
        _preparing--;
      }
    }
  }

  bool _sameSource(FileStat first, FileStat second) =>
      second.type == FileSystemEntityType.file &&
      first.size == second.size &&
      first.modified == second.modified &&
      first.changed == second.changed;

  /// Snapshots the bytes supplied by a native picker/provider without requiring
  /// a filesystem path. Provider version/coordinated-read guarantees belong to
  /// the native adapter; this method never claims to verify the provider's
  /// original mutable document independently of the received stream.
  Future<PreparedFile> stageStream(
    Stream<List<int>> source, {
    required String displayName,
    int? expectedSizeBytes,
    String? mimeType,
    void Function(int bytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    _checkOpen();
    if (expectedSizeBytes != null &&
        (expectedSizeBytes < 0 ||
            expectedSizeBytes > TransferLimits.maxFileBytes)) {
      throw const StorageException(
        'FILE_TOO_LARGE',
        'Unsupported source size.',
      );
    }
    // Validate display metadata before consuming a potentially costly provider.
    FileManifest(
      fileId: 'validation',
      displayName: displayName,
      sizeBytes: 0,
      sha256: sha256.convert(const <int>[]).toString(),
      mimeType: mimeType,
    );
    final fileId = const Uuid().v4();
    final temporary = File(p.join(root.path, '.preparing', '$fileId.part'));
    final ready = File(p.join(root.path, 'files', '$fileId.blob'));
    RandomAccessFile? handle;
    var published = false;
    _preparing++;
    try {
      await _reserve(fileId, expectedSizeBytes ?? 0);
      await validateManagedDirectory(root, temporary.parent);
      await validateManagedDirectory(root, ready.parent);
      await temporary.create(exclusive: true);
      handle = await temporary.open(mode: FileMode.write);
      final collector = DigestCollector();
      final digest = sha256.startChunkedConversion(collector);
      var length = 0;
      await for (final chunk in source) {
        if (isCancelled?.call() == true) {
          throw const StorageException(
            'PREPARATION_CANCELLED',
            'Preparation cancelled.',
          );
        }
        if (chunk.length > TransferLimits.maxFileBytes - length ||
            (expectedSizeBytes != null &&
                chunk.length > expectedSizeBytes - length)) {
          throw const StorageException(
            'SOURCE_CHANGED',
            'Provider exceeded the expected source size.',
          );
        }
        length += chunk.length;
        digest.add(chunk);
        // Providers are responsible for bounded emitted chunks; the store adds
        // no unbounded buffers and consumes each event with backpressure.
        await _write(fileId, handle, chunk);
        onProgress?.call(length);
      }
      digest.close();
      if (isCancelled?.call() == true) {
        throw const StorageException(
          'PREPARATION_CANCELLED',
          'Preparation cancelled.',
        );
      }
      if (expectedSizeBytes != null && length != expectedSizeBytes) {
        throw const StorageException(
          'SOURCE_CHANGED',
          'Provider returned an incomplete source.',
        );
      }
      await handle.flush();
      await handle.close();
      handle = null;
      final manifest = FileManifest(
        fileId: fileId,
        displayName: displayName,
        sizeBytes: length,
        sha256: collector.value!.toString(),
        mimeType: mimeType,
      );
      if (await FileSystemEntity.type(ready.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const StorageException(
          'DESTINATION_EXISTS',
          'Snapshot already exists.',
        );
      }
      await temporary.rename(ready.path);
      final created = DateTime.now().toUtc();
      _db.execute(
        'INSERT INTO outbox_files(file_id,manifest,path,created_at) VALUES(?,?,?,?)',
        [
          fileId,
          jsonEncode(manifest.toJson()),
          toStoredPath(root, ready.path),
          created.toIso8601String(),
        ],
      );
      published = true;
      return PreparedFile(
        manifest: manifest,
        path: ready.path,
        createdAt: created,
      );
    } catch (error) {
      if (error is StorageException) rethrow;
      throw storageIoError(error);
    } finally {
      await handle?.close();
      try {
        if (!published) {
          try {
            if (await temporary.exists()) await temporary.delete();
            if (await ready.exists()) await ready.delete();
          } finally {
            await _settleFailedPreparation(fileId, temporary, ready);
          }
        }
      } finally {
        _preparing--;
      }
    }
  }

  PreparedFile get(String fileId) {
    _checkOpen();
    final rows = _db.select('SELECT * FROM outbox_files WHERE file_id=?', [
      fileId,
    ]);
    if (rows.isEmpty) {
      throw const StorageException('NOT_FOUND', 'Prepared source not found.');
    }
    return _preparedFile(rows.first);
  }

  PreparedFile _preparedFile(Row row) => PreparedFile(
    manifest: FileManifest.fromJson(
      jsonDecode(row['manifest'] as String) as Map<String, dynamic>,
    ),
    path: _abs(row['path'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
  );

  List<PreparedFile> list() {
    _checkOpen();
    return _db
        .select('SELECT * FROM outbox_files ORDER BY created_at')
        .map(_preparedFile)
        .toList();
  }

  Stream<List<int>> read(String fileId, {int offset = 0}) async* {
    final prepared = get(fileId);
    if (offset < 0 || offset > prepared.manifest.sizeBytes) {
      throw const StorageException('OFFSET_MISMATCH', 'Invalid source offset.');
    }
    requireContainedPath(root, prepared.path);
    final file = File(prepared.path);
    await validateManagedDirectory(root, file.parent);
    await ensurePlainFile(file);
    if (await file.length() != prepared.manifest.sizeBytes) {
      throw const StorageException(
        'SOURCE_CHANGED',
        'Prepared copy length changed.',
      );
    }
    yield* file.openRead(offset, prepared.manifest.sizeBytes);
  }

  Future<PreparedTransfer> createTransfer(
    List<String> fileIds, {
    required String peerId,
    String? requestId,
  }) async {
    _checkOpen();
    if (peerId.isEmpty || peerId.length > 512) {
      throw const StorageException('INVALID_PEER', 'Invalid peer identity.');
    }
    final manifest = TransferManifest(
      requestId: requestId ?? const Uuid().v4(),
      files: fileIds.map((id) => get(id).manifest).toList(),
    );
    final json = jsonEncode(manifest.toJson());
    final existing = _db.select(
      'SELECT * FROM outbox_transfers WHERE request_id=?',
      [manifest.requestId],
    );
    if (existing.isNotEmpty) {
      if (existing.first['peer_id'] != peerId ||
          existing.first['manifest'] != json) {
        throw const StorageException(
          'REQUEST_CONFLICT',
          'Outgoing requestId conflicts.',
        );
      }
      return _preparedTransfer(existing.first);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      'INSERT INTO outbox_transfers(request_id,peer_id,manifest,state,created_at,updated_at) VALUES(?,?,?,?,?,?)',
      [manifest.requestId, peerId, json, 'prepared', now, now],
    );
    return transfer(manifest.requestId);
  }

  PreparedTransfer transfer(String requestId) {
    _checkOpen();
    final rows = _db.select(
      'SELECT * FROM outbox_transfers WHERE request_id=?',
      [requestId],
    );
    if (rows.isEmpty) {
      throw const StorageException('NOT_FOUND', 'Outgoing request not found.');
    }
    return _preparedTransfer(rows.first);
  }

  List<PreparedTransfer> transfers() {
    _checkOpen();
    return _db
        .select('SELECT * FROM outbox_transfers ORDER BY created_at DESC')
        .map(_preparedTransfer)
        .toList();
  }

  PreparedTransfer _preparedTransfer(Row row) => PreparedTransfer(
    manifest: TransferManifest.fromJson(
      jsonDecode(row['manifest'] as String) as Map<String, dynamic>,
    ),
    peerId: row['peer_id'] as String,
    state: row['state'] as String,
    remoteTransferId: row['remote_transfer_id'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );

  /// The caller may mark delivery completed only after a verified sink status.
  Future<PreparedTransfer> updateTransfer(
    String requestId, {
    String? remoteTransferId,
    String? state,
  }) async {
    final existing = transfer(requestId);
    if (remoteTransferId != null) {
      validateOpaqueId(remoteTransferId, 'remoteTransferId');
      if (existing.remoteTransferId != null &&
          existing.remoteTransferId != remoteTransferId) {
        throw const StorageException(
          'REQUEST_CONFLICT',
          'Remote transfer identity changed.',
        );
      }
    }
    if (state != null &&
        !{
          'prepared',
          'offered',
          'accepted',
          'transferring',
          'awaiting_confirmation',
          'paused',
          'completed',
          'partially_completed',
          'rejected',
          'cancelled',
          'failed',
        }.contains(state)) {
      throw const StorageException('INVALID_STATE', 'Unknown outgoing state.');
    }
    _db.execute(
      'UPDATE outbox_transfers SET remote_transfer_id=?,state=?,updated_at=? WHERE request_id=?',
      [
        remoteTransferId ?? existing.remoteTransferId,
        state ?? existing.state,
        DateTime.now().toUtc().toIso8601String(),
        requestId,
      ],
    );
    return transfer(requestId);
  }

  Future<void> remove(String fileId) async {
    final file = get(fileId);
    final active = transfers().where(
      (transfer) => !{
        'completed',
        'partially_completed',
        'rejected',
        'cancelled',
        'failed',
      }.contains(transfer.state),
    );
    if (active.any(
      (transfer) =>
          transfer.manifest.files.any((file) => file.fileId == fileId),
    )) {
      throw const StorageException(
        'FILE_IN_USE',
        'Source belongs to an unfinished transfer.',
      );
    }
    requireContainedPath(root, file.path);
    final snapshot = File(file.path);
    await validateManagedDirectory(root, snapshot.parent);
    final kind = await FileSystemEntity.type(snapshot.path, followLinks: false);
    if (kind == FileSystemEntityType.file) {
      await ensurePlainFile(snapshot);
      await snapshot.delete();
    } else if (kind != FileSystemEntityType.notFound) {
      throw const StorageException(
        'UNSAFE_PATH',
        'Prepared copy is not an ordinary file.',
      );
    }
    _db.execute('DELETE FROM outbox_files WHERE file_id=?', [fileId]);
    await _budget?.forget(_budgetScope, fileId);
  }

  /// Retention for outgoing request records. Only terminal requests last
  /// updated before now-[olderThan] are removed; prepared snapshots are not.
  Future<int> pruneTerminalTransfers({required Duration olderThan}) async {
    _checkOpen();
    final cutoff = DateTime.now().toUtc().subtract(olderThan).toIso8601String();
    _db.execute(
      'DELETE FROM outbox_transfers WHERE updated_at < ? AND state IN '
      "('completed','partially_completed','rejected','cancelled','failed')",
      [cutoff],
    );
    return _db.updatedRows;
  }

  Future<void> close() async {
    if (_closed) return;
    if (_preparing > 0) {
      throw const StorageException('BUSY', 'Source preparation is active.');
    }
    _db.close();
    _closed = true;
    await _lease.release();
  }
}
