import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'storage_budget.dart';
import 'storage_support.dart';

/// Foreground, push-only receive store. Owns its private directory; it never
/// writes into arbitrary paths supplied by the sender. Files are committed
/// under `received/<transfer>/<incarnation>/<safe name>`, preserving existing results.
class DurableInbox {
  DurableInbox._(
    this.root,
    this._db,
    this.checkpointBytes,
    this.checkpointInterval,
    this._lease,
    this._budget,
    this.offerLifetime,
    this._wallClock,
    this._monotonicClock,
  );

  final Directory root;
  final Database _db;
  final StorageLease _lease;
  final StorageBudget? _budget;
  String get _budgetScope => 'inbox:${root.path}';
  final int checkpointBytes;
  final Duration checkpointInterval;
  final Duration offerLifetime;
  final DateTime Function() _wallClock;
  final Duration Function() _monotonicClock;
  final _offerDeadlines = <String, Duration>{};
  Timer? _offerTimer;
  final _controls = _ControlQueue();
  final _events = StreamController<TransferSnapshot>.broadcast();
  _Writer? _writer;
  bool _closed = false;
  bool _closing = false;

  Stream<TransferSnapshot> get changes => _events.stream;

  static Future<DurableInbox> open(
    Directory directory, {
    int checkpointBytes = 4 * 1024 * 1024,
    Duration checkpointInterval = const Duration(seconds: 2),
    StorageBudget? budget,
    Duration offerLifetime = const Duration(seconds: 120),
    DateTime Function()? wallClock,
    Duration Function()? monotonicClock,
  }) async {
    if (checkpointBytes < 1 || checkpointInterval <= Duration.zero) {
      throw ArgumentError('Positive checkpoint parameters required.');
    }
    if (offerLifetime <= Duration.zero) {
      throw ArgumentError.value(
        offerLifetime,
        'offerLifetime',
        'Must be positive.',
      );
    }
    final stopwatch = Stopwatch()..start();
    final now = wallClock ?? DateTime.now;
    final elapsed = monotonicClock ?? () => stopwatch.elapsed;
    final root = await prepareStorageDirectory(directory);
    await ensurePlainDirectory(Directory(p.join(root.path, '.staging')));
    await ensurePlainDirectory(Directory(p.join(root.path, 'received')));
    final lease = await StorageLease.acquire(root, 'inbox');
    Database? opened;
    try {
      final db = openJournal(File(p.join(root.path, 'inbox.sqlite')));
      opened = db;
      db.execute('''
        CREATE TABLE IF NOT EXISTS inbox_transfers (
          id TEXT PRIMARY KEY, peer_id TEXT NOT NULL, request_id TEXT NOT NULL,
          manifest TEXT NOT NULL, state TEXT NOT NULL,
          paused_source INTEGER NOT NULL DEFAULT 0,
          paused_sink INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          offer_expires_at TEXT,
          UNIQUE(peer_id, request_id)
        );
        CREATE TABLE IF NOT EXISTS inbox_files (
          transfer_id TEXT NOT NULL REFERENCES inbox_transfers(id),
          file_id TEXT NOT NULL, ordinal INTEGER NOT NULL,
          manifest TEXT NOT NULL, durable_offset INTEGER NOT NULL DEFAULT 0,
          state TEXT NOT NULL, incarnation TEXT NOT NULL,
          temporary_path TEXT NOT NULL, final_path TEXT,
          error_code TEXT, PRIMARY KEY(transfer_id, file_id)
        );
      ''');
      // Alpha 0.1/0.2 journals did not have offer deadlines. Use their original
      // creation time, never the recovery-refreshed updated_at value.
      journalTransaction(db, () {
        final columns = db.select('PRAGMA table_info(inbox_transfers)');
        if (!columns.any((column) => column['name'] == 'offer_expires_at')) {
          db.execute(
            'ALTER TABLE inbox_transfers ADD COLUMN offer_expires_at TEXT',
          );
        }
        for (final row in db.select(
          'SELECT id,created_at FROM inbox_transfers WHERE offer_expires_at IS NULL',
        )) {
          final created = DateTime.parse(row['created_at'] as String).toUtc();
          db.execute(
            'UPDATE inbox_transfers SET offer_expires_at=? WHERE id=?',
            [created.add(offerLifetime).toIso8601String(), row['id']],
          );
        }
      });
      final store = DurableInbox._(
        root,
        db,
        checkpointBytes,
        checkpointInterval,
        lease,
        budget,
        offerLifetime,
        now,
        elapsed,
      );
      await store._recover();
      await store._restoreBudget();
      store._restoreOfferDeadlines();
      store.expireOffers();
      return store;
    } catch (_) {
      opened?.close();
      await lease.release();
      rethrow;
    }
  }

  void _restoreOfferDeadlines() {
    final wall = _wallClock().toUtc();
    final mono = _monotonicClock();
    for (final row in _db.select(
      "SELECT id,created_at,offer_expires_at FROM inbox_transfers WHERE state='offered'",
    )) {
      final created = DateTime.parse(row['created_at'] as String).toUtc();
      final expires = DateTime.parse(row['offer_expires_at'] as String).toUtc();
      // A restarted process cannot recover a previous monotonic clock. An
      // observed wall-clock rollback fails closed rather than extending consent.
      var remaining = wall.isBefore(created)
          ? Duration.zero
          : expires.difference(wall);
      if (remaining < Duration.zero) remaining = Duration.zero;
      if (remaining > offerLifetime) remaining = offerLifetime;
      _offerDeadlines[row['id'] as String] = mono + remaining;
    }
  }

  /// Persists terminal expiry and keeps the original idempotency record. Reads
  /// call this too, so a delayed event loop cannot permit late consent.
  List<TransferSnapshot> expireOffers() {
    _checkOpen();
    final mono = _monotonicClock();
    final expired = <String>[];
    for (final entry in _offerDeadlines.entries.toList()) {
      if (mono < entry.value) continue;
      journalTransaction(_db, () {
        final row = _db.select('SELECT state FROM inbox_transfers WHERE id=?', [
          entry.key,
        ]);
        if (row.isNotEmpty && row.first['state'] == 'offered') {
          _db.execute(
            "UPDATE inbox_files SET state='expired',error_code='OFFER_EXPIRED' WHERE transfer_id=? AND state='offered'",
            [entry.key],
          );
          _refreshTransfer(entry.key);
          expired.add(entry.key);
        }
      });
      _offerDeadlines.remove(entry.key);
    }
    _scheduleOfferExpiry();
    final snapshots = expired.map(_readStatus).toList();
    for (final snapshot in snapshots) {
      if (!_events.isClosed) _events.add(snapshot);
    }
    return List.unmodifiable(snapshots);
  }

  void _scheduleOfferExpiry() {
    _offerTimer?.cancel();
    _offerTimer = null;
    if (_closed || _closing || _offerDeadlines.isEmpty) return;
    final next = _offerDeadlines.values.reduce((a, b) => a < b ? a : b);
    final wait = next - _monotonicClock();
    _offerTimer = Timer(wait > Duration.zero ? wait : Duration.zero, () {
      _offerTimer = null;
      if (_closed || _closing) return;
      try {
        expireOffers();
      } catch (_) {
        // A transient journal error must not crash the isolate. Any attempted
        // status/consent still rechecks the deadline and fails closed on error.
        _offerTimer = Timer(const Duration(seconds: 5), () {
          if (!_closed && !_closing) _scheduleOfferExpiry();
        });
      }
    });
  }

  static const _reservedStates = {
    'accepted',
    'transferring',
    'paused',
    'verifying',
    'committing',
  };

  StorageBudgetClaim _budgetClaim(Row row, int length) {
    final target = _reservedStates.contains(row['state'])
        ? math.max(_fileSnapshot(row).manifest.sizeBytes, length)
        : length;
    return StorageBudgetClaim(
      key: row['incarnation'] as String,
      usedBytes: length,
      totalBytes: target,
    );
  }

  Future<void> _restoreBudget() async {
    if (_budget == null) return;
    final rows = _db.select('SELECT * FROM inbox_files');
    final rowsByPath = <String, Row>{
      for (final row in rows) row['temporary_path'] as String: row,
    };
    final lengths = <String, int>{};
    final claims = <StorageBudgetClaim>[];
    await for (final entity in Directory(
      p.join(root.path, '.staging'),
    ).list(followLinks: false)) {
      if (entity is! File) continue;
      final length = await entity.length();
      lengths[entity.path] = length;
      if (!rowsByPath.containsKey(entity.path)) {
        claims.add(
          StorageBudgetClaim(
            key: 'orphan:${entity.path}',
            usedBytes: length,
            totalBytes: length,
          ),
        );
      }
    }
    for (final row in rows) {
      final length = lengths[row['temporary_path']] ?? 0;
      if (row['state'] == 'committed' && length == 0) continue;
      claims.add(_budgetClaim(row, length));
    }
    await _budget.restoreScope(_budgetScope, claims);
  }

  Future<void> _reconcileBudgetRow(Row row) async {
    if (_budget == null) return;
    final file = File(row['temporary_path'] as String);
    requireContainedPath(root, file.path);
    await validateManagedDirectory(root, file.parent);
    final kind = await FileSystemEntity.type(file.path, followLinks: false);
    final length = kind == FileSystemEntityType.file ? await file.length() : 0;
    if (row['state'] == 'committed' && length == 0) {
      await _budget.forget(_budgetScope, row['incarnation'] as String);
    } else {
      await _budget.reconcile(_budgetScope, _budgetClaim(row, length));
    }
  }

  Future<void> _reconcileBudgetTransfer(String id) async {
    if (_budget == null) return;
    for (final row in _db.select(
      'SELECT * FROM inbox_files WHERE transfer_id=?',
      [id],
    )) {
      await _reconcileBudgetRow(row);
    }
  }

  void _checkOpen() {
    if (_closed || _closing) {
      throw const StorageException('STORE_CLOSED', 'Inbox is closed.');
    }
  }

  Future<TransferSnapshot> createOffer(
    TransferManifest manifest, {
    required String peerId,
  }) async {
    _checkOpen();
    expireOffers();
    if (peerId.isEmpty || peerId.length > 512) {
      throw const StorageException('INVALID_PEER', 'Invalid peer identity.');
    }
    final normalized = jsonEncode(manifest.toJson());
    final prior = _db.select(
      'SELECT id, manifest FROM inbox_transfers WHERE peer_id=? AND request_id=?',
      [peerId, manifest.requestId],
    );
    if (prior.isNotEmpty) {
      if (prior.first['manifest'] != normalized) {
        throw const StorageException(
          'REQUEST_CONFLICT',
          'requestId was reused with different data.',
        );
      }
      return status(prior.first['id'] as String);
    }
    final pending =
        _db
                .select(
                  "SELECT COUNT(*) AS n FROM inbox_transfers WHERE state IN ('offered','accepted','transferring','paused')",
                )
                .first['n']
            as int;
    if (pending >= 10) {
      throw const StorageException('BUSY', 'Incoming queue is full.');
    }
    final id = const Uuid().v4();
    final created = _wallClock().toUtc();
    final createdMonotonic = _monotonicClock();
    final now = created.toIso8601String();
    final deadline = created.add(offerLifetime).toIso8601String();
    journalTransaction(_db, () {
      _db.execute(
        'INSERT INTO inbox_transfers(id,peer_id,request_id,manifest,state,created_at,updated_at,offer_expires_at) VALUES(?,?,?,?,?,?,?,?)',
        [
          id,
          peerId,
          manifest.requestId,
          normalized,
          'offered',
          now,
          now,
          deadline,
        ],
      );
      for (var index = 0; index < manifest.files.length; index++) {
        final file = manifest.files[index];
        final incarnation = const Uuid().v4();
        _db.execute(
          'INSERT INTO inbox_files(transfer_id,file_id,ordinal,manifest,state,incarnation,temporary_path) VALUES(?,?,?,?,?,?,?)',
          [
            id,
            file.fileId,
            index,
            jsonEncode(file.toJson()),
            'offered',
            incarnation,
            p.join(root.path, '.staging', '$incarnation.part'),
          ],
        );
      }
    });
    _offerDeadlines[id] = createdMonotonic + offerLifetime;
    _scheduleOfferExpiry();
    return _emit(id);
  }

  TransferSnapshot status(String id) {
    _checkOpen();
    expireOffers();
    return _readStatus(id);
  }

  TransferSnapshot _readStatus(String id) {
    final records = _db.select('SELECT * FROM inbox_transfers WHERE id=?', [
      id,
    ]);
    if (records.isEmpty) {
      throw const StorageException('NOT_FOUND', 'Transfer not found.');
    }
    final record = records.first;
    final files = _db.select(
      'SELECT * FROM inbox_files WHERE transfer_id=? ORDER BY ordinal',
      [id],
    );
    return TransferSnapshot(
      transferId: id,
      peerId: record['peer_id'] as String,
      manifest: TransferManifest.fromJson(
        jsonDecode(record['manifest'] as String) as Map<String, dynamic>,
      ),
      state: TransferState.fromWire(record['state'] as String),
      files: files.map(_fileSnapshot).toList(),
      createdAt: DateTime.parse(record['created_at'] as String),
      updatedAt: DateTime.parse(record['updated_at'] as String),
      pausedBySource: record['paused_source'] == 1,
      pausedBySink: record['paused_sink'] == 1,
      offerExpiresAt: record['offer_expires_at'] == null
          ? null
          : DateTime.parse(record['offer_expires_at'] as String).toUtc(),
    );
  }

  List<TransferSnapshot> list({String? peerId}) {
    _checkOpen();
    final rows = _db.select(
      'SELECT id FROM inbox_transfers ${peerId == null ? '' : 'WHERE peer_id=?'} ORDER BY created_at DESC',
      peerId == null ? [] : [peerId],
    );
    return rows.map((row) => status(row['id'] as String)).toList();
  }

  FileSnapshot _fileSnapshot(Row row) => FileSnapshot(
    manifest: FileManifest.fromJson(
      jsonDecode(row['manifest'] as String) as Map<String, dynamic>,
    ),
    offset: row['durable_offset'] as int,
    state: FileState.fromWire(row['state'] as String),
    storageIncarnationId: row['incarnation'] as String,
    finalPath: row['final_path'] as String?,
    errorCode: row['error_code'] as String?,
  );

  Row _fileRow(String transferId, String fileId) {
    final rows = _db.select(
      'SELECT * FROM inbox_files WHERE transfer_id=? AND file_id=?',
      [transferId, fileId],
    );
    if (rows.isEmpty) {
      throw const StorageException('NOT_FOUND', 'File not found.');
    }
    return rows.first;
  }

  Future<TransferSnapshot> accept(String id) => _controls.run(() async {
    final snapshot = status(id);
    if (snapshot.state == TransferState.expired) {
      throw const StorageException(
        'OFFER_EXPIRED',
        'Offer consent deadline expired.',
      );
    }
    if (snapshot.state != TransferState.offered) {
      if ({
        TransferState.accepted,
        TransferState.transferring,
        TransferState.paused,
        TransferState.completed,
      }.contains(snapshot.state)) {
        return snapshot;
      }
      throw const StorageException(
        'INVALID_STATE',
        'Offer cannot be accepted.',
      );
    }
    final rows = _db.select('SELECT * FROM inbox_files WHERE transfer_id=?', [
      id,
    ]);
    try {
      // Reserve the full batch atomically, before any consent is persisted.
      await _budget?.reserveAll(_budgetScope, [
        for (final row in rows)
          StorageBudgetClaim(
            key: row['incarnation'] as String,
            usedBytes: 0,
            totalBytes: _fileSnapshot(row).manifest.sizeBytes,
          ),
      ]);
      for (final row in rows) {
        final file = File(row['temporary_path'] as String);
        requireContainedPath(root, file.path);
        await validateManagedDirectory(root, file.parent);
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          await file.create(exclusive: true);
        } else {
          await ensurePlainFile(file);
          if (await file.length() != 0) {
            throw const StorageException(
              'RECOVERY_INCONSISTENT',
              'Unaccepted file contains data.',
            );
          }
        }
      }
      // Capacity and filesystem checks await external work. The lifetime may
      // end during those awaits; commit consent only after one final check.
      if (status(id).state == TransferState.expired) {
        throw const StorageException(
          'OFFER_EXPIRED',
          'Offer consent deadline expired.',
        );
      }
      journalTransaction(_db, () {
        _db.execute(
          "UPDATE inbox_files SET state='accepted' WHERE transfer_id=? AND state='offered'",
          [id],
        );
        _refreshTransfer(id);
      });
    } catch (error) {
      try {
        if (_readStatus(id).state == TransferState.expired) {
          for (final row in rows) {
            await _deleteTemporary(row);
          }
        }
      } finally {
        await _reconcileBudgetTransfer(id);
      }
      throw storageIoError(error);
    }
    return _emit(id);
  });

  Future<TransferSnapshot> reject(String id) => _controls.run(() async {
    final snapshot = status(id);
    if (snapshot.state == TransferState.rejected) return snapshot;
    if (snapshot.state != TransferState.offered) {
      throw const StorageException(
        'INVALID_STATE',
        'Only pending offers can be rejected.',
      );
    }
    journalTransaction(_db, () {
      _db.execute(
        "UPDATE inbox_files SET state='rejected' WHERE transfer_id=?",
        [id],
      );
      _refreshTransfer(id);
    });
    return _emit(id);
  });

  Future<TransferSnapshot> pause(String id, {bool bySource = false}) =>
      _controls.run(() async {
        final snapshot = status(id);
        if (_terminal(snapshot.state)) return snapshot;
        if (snapshot.state == TransferState.offered) {
          throw const StorageException(
            'NOT_ACCEPTED',
            'Offer has not been accepted.',
          );
        }
        if (_writer?.transferId == id && _writer!.commitLocked) {
          await _writer!.done.future;
          if (_terminal(status(id).state)) return status(id);
        }
        final column = bySource ? 'paused_source' : 'paused_sink';
        journalTransaction(_db, () {
          _db.execute('UPDATE inbox_transfers SET $column=1 WHERE id=?', [id]);
          _db.execute(
            "UPDATE inbox_files SET state='paused' WHERE transfer_id=? AND state IN ('accepted','transferring','verifying')",
            [id],
          );
          _refreshTransfer(id);
        });
        await _stopWriter(id, 'TRANSFER_PAUSED');
        return _emit(id);
      });

  Future<TransferSnapshot> resume(String id, {bool bySource = false}) =>
      _controls.run(() async {
        final snapshot = status(id);
        if (_terminal(snapshot.state)) return snapshot;
        if (snapshot.state == TransferState.offered) {
          throw const StorageException(
            'NOT_ACCEPTED',
            'Offer has not been accepted.',
          );
        }
        final column = bySource ? 'paused_source' : 'paused_sink';
        journalTransaction(_db, () {
          _db.execute('UPDATE inbox_transfers SET $column=0 WHERE id=?', [id]);
          final flags = _db.select(
            'SELECT paused_source,paused_sink FROM inbox_transfers WHERE id=?',
            [id],
          ).first;
          if (flags['paused_source'] == 0 && flags['paused_sink'] == 0) {
            _db.execute(
              "UPDATE inbox_files SET state='accepted',error_code=NULL WHERE transfer_id=? AND state='paused'",
              [id],
            );
          }
          _refreshTransfer(id);
        });
        return _emit(id);
      });

  Future<TransferSnapshot> cancel(String id) => _controls.run(() async {
    var snapshot = status(id);
    if (_terminal(snapshot.state)) return snapshot;
    if (_writer?.transferId == id && _writer!.commitLocked) {
      await _writer!.done.future;
      snapshot = status(id);
      if (_terminal(snapshot.state)) return snapshot;
    }
    journalTransaction(_db, () {
      _db.execute(
        "UPDATE inbox_files SET state='cancelled',error_code=NULL WHERE transfer_id=? AND state NOT IN ('committed','rejected','failed','expired')",
        [id],
      );
      _refreshTransfer(id);
    });
    await _stopWriter(id, 'TRANSFER_CANCELLED');
    try {
      for (final row in _db.select(
        "SELECT * FROM inbox_files WHERE transfer_id=? AND state='cancelled'",
        [id],
      )) {
        await _deleteTemporary(row);
      }
    } finally {
      await _reconcileBudgetTransfer(id);
    }
    return _emit(id);
  });

  /// A preview describes only journal-owned temporary files and future payload
  /// allocations. It never scans arbitrary orphan files or completed results.
  Future<List<IncomingCleanupItem>> previewIncompleteCleanup() => _controls.run(
    () async {
      _checkOpen();
      expireOffers();
      final preview = <IncomingCleanupItem>[];
      for (final snapshot in list()) {
        // A durable commit intent with no live writer is indeterminate until
        // recovery verifies its temporary/final candidate. Protect the whole
        // batch rather than turning cleanup into destructive recovery.
        if (snapshot.files.any((file) => file.state == FileState.committing)) {
          continue;
        }
        var temporaryBytes = 0;
        var reservedBytes = 0;
        var incompleteFileCount = 0;
        var committedFileCount = 0;
        for (final original in _db.select(
          'SELECT * FROM inbox_files WHERE transfer_id=?',
          [snapshot.transferId],
        )) {
          if (original['state'] == 'committed') {
            committedFileCount++;
            continue;
          }
          // Commit can progress while filesystem I/O is awaited. Re-read its
          // state afterwards before including a possibly stale candidate.
          final file = await _checkedTemporary(original);
          var length = 0;
          try {
            if (await FileSystemEntity.type(file.path, followLinks: false) ==
                FileSystemEntityType.file) {
              length = await file.length();
            }
          } on FileSystemException {
            if (_fileRow(
                  snapshot.transferId,
                  original['file_id'] as String,
                )['state'] !=
                'committed') {
              rethrow;
            }
          }
          final row = _fileRow(
            snapshot.transferId,
            original['file_id'] as String,
          );
          if (row['state'] == 'committed') {
            committedFileCount++;
            continue;
          }
          temporaryBytes += length;
          if (_reservedStates.contains(row['state'])) {
            reservedBytes += math.max(
              0,
              _fileSnapshot(row).manifest.sizeBytes - length,
            );
          }
          if (_reservedStates.contains(row['state']) || length > 0) {
            incompleteFileCount++;
          }
        }
        if (temporaryBytes > 0 || reservedBytes > 0) {
          preview.add(
            IncomingCleanupItem(
              transferId: snapshot.transferId,
              temporaryBytes: temporaryBytes,
              reservedBytes: reservedBytes,
              incompleteFileCount: incompleteFileCount,
              committedFileCount: committedFileCount,
            ),
          );
        }
      }
      return List.unmodifiable(preview);
    },
  );

  /// Explicitly stops a previously previewed batch and removes only its
  /// unfinished private payloads. The committed files and receipt rows survive.
  /// A late confirmation after commit safely returns a zero-removal result.
  Future<IncomingCleanupResult> discardIncomplete(String id) =>
      _controls.run(() async {
        var snapshot = status(id);
        if (_writer?.transferId == id && _writer!.commitLocked) {
          await _writer!.done.future;
          snapshot = status(id);
        }
        if (snapshot.files.any((file) => file.state == FileState.committing)) {
          return IncomingCleanupResult(
            snapshot: snapshot,
            removedFileCount: 0,
            removedBytes: 0,
          );
        }
        journalTransaction(_db, () {
          _db.execute(
            "UPDATE inbox_files SET state='cancelled',error_code=NULL WHERE transfer_id=? AND state IN ('offered','accepted','transferring','paused','verifying')",
            [id],
          );
          _refreshTransfer(id);
        });
        await _stopWriter(id, 'TRANSFER_CANCELLED');
        var removedFiles = 0;
        var removedBytes = 0;
        try {
          for (final row in _db.select(
            "SELECT * FROM inbox_files WHERE transfer_id=? AND state != 'committed'",
            [id],
          )) {
            final deleted = await _deleteTemporary(row);
            if (deleted != null) {
              removedFiles++;
              removedBytes += deleted;
            }
          }
        } catch (error) {
          throw storageIoError(error);
        } finally {
          await _reconcileBudgetTransfer(id);
          _emit(id);
        }
        snapshot = status(id);
        return IncomingCleanupResult(
          snapshot: snapshot,
          removedFileCount: removedFiles,
          removedBytes: removedBytes,
        );
      });

  Future<File> _checkedTemporary(Row row) async {
    final file = File(row['temporary_path'] as String);
    final staging = Directory(p.join(root.path, '.staging'));
    final expected = p.join(staging.path, '${row['incarnation']}.part');
    requireContainedPath(staging, file.path);
    if (p.normalize(p.absolute(file.path)) != expected) {
      throw const StorageException('UNSAFE_PATH', 'Unexpected temporary path.');
    }
    await validateManagedDirectory(root, staging);
    final kind = await FileSystemEntity.type(file.path, followLinks: false);
    if (kind != FileSystemEntityType.notFound &&
        kind != FileSystemEntityType.file) {
      throw const StorageException(
        'UNSAFE_PATH',
        'Temporary payload is not a plain file.',
      );
    }
    return file;
  }

  Future<int?> _deleteTemporary(Row row) async {
    final file = await _checkedTemporary(row);
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      _clearDeletedOffset(row);
      return null;
    }
    final length = await file.length();
    await file.delete();
    // No byte from the deleted prefix remains resumable; preserve its terminal
    // record but never advertise an offset that no longer exists.
    _clearDeletedOffset(row);
    return length;
  }

  void _clearDeletedOffset(Row row) => _db.execute(
    'UPDATE inbox_files SET durable_offset=0 WHERE transfer_id=? AND file_id=?',
    [row['transfer_id'], row['file_id']],
  );

  bool _terminal(TransferState state) => {
    TransferState.completed,
    TransferState.partiallyCompleted,
    TransferState.rejected,
    TransferState.cancelled,
    TransferState.failed,
    TransferState.expired,
  }.contains(state);

  Future<void> _stopWriter(String id, String code) async {
    final writer = _writer;
    if (writer == null || writer.transferId != id) return;
    if (!writer.commitLocked) {
      writer.stopCode = code;
      await writer.iterator?.cancel();
    }
    await writer.done.future;
  }

  void _checkWriteAllowed(String id, FileSnapshot file, String incarnation) {
    final transfer = status(id);
    if (file.storageIncarnationId != incarnation) {
      throw const StorageException(
        'INCARNATION_MISMATCH',
        'Receive incarnation changed.',
      );
    }
    if (transfer.pausedBySource || transfer.pausedBySink) {
      throw const StorageException(
        'TRANSFER_PAUSED',
        'Transfer paused by a participant.',
      );
    }
    if (!{
      FileState.accepted,
      FileState.paused,
      FileState.transferring,
    }.contains(file.state)) {
      throw StorageException(
        file.state == FileState.offered ? 'NOT_ACCEPTED' : 'INVALID_STATE',
        'File does not accept bytes in its current state.',
      );
    }
  }

  Future<FileSnapshot> writeFile(
    String transferId,
    String fileId, {
    required int offset,
    required String incarnation,
    required Stream<List<int>> bytes,
  }) async {
    _checkOpen();
    final row = _fileRow(transferId, fileId);
    final initial = _fileSnapshot(row);
    _checkWriteAllowed(transferId, initial, incarnation);
    if (offset != initial.offset) {
      throw StorageException(
        'OFFSET_MISMATCH',
        'Use the receiver durable offset.',
        offset: initial.offset,
      );
    }
    if (_writer != null) {
      throw const StorageException('BUSY', 'Another file is being written.');
    }
    final writer = _Writer(transferId, fileId, incarnation);
    _writer = writer;
    RandomAccessFile? handle;
    var written = offset;
    var checkpointOffset = offset;
    final timer = Stopwatch()..start();
    try {
      final temporary = File(row['temporary_path'] as String);
      requireContainedPath(root, temporary.path);
      await validateManagedDirectory(root, temporary.parent);
      await ensurePlainFile(temporary);
      if (await temporary.length() < offset) {
        throw const StorageException(
          'RECOVERY_INCONSISTENT',
          'Temporary file is shorter than the journal.',
        );
      }
      handle = await temporary.open(mode: FileMode.append);
      await handle.truncate(offset);
      await handle.setPosition(offset);
      await _reconcileBudgetRow(_fileRow(transferId, fileId));
      await _budget?.check();
      writer.check();
      _db.execute(
        "UPDATE inbox_files SET state='transferring',error_code=NULL WHERE transfer_id=? AND file_id=?",
        [transferId, fileId],
      );
      _refreshTransfer(transferId);
      _emit(transferId);
      writer.iterator = StreamIterator(bytes);
      while (await writer.iterator!.moveNext()) {
        writer.check();
        final chunk = writer.iterator!.current;
        if (chunk.length > initial.manifest.sizeBytes - written) {
          throw const StorageException(
            'LENGTH_EXCEEDED',
            'Body exceeds the agreed file length.',
          );
        }
        var cursor = 0;
        while (cursor < chunk.length) {
          writer.check();
          final length = math.min(
            256 * 1024,
            math.min(
              chunk.length - cursor,
              checkpointBytes - (written - checkpointOffset),
            ),
          );
          if (_budget == null) {
            await handle.writeFrom(chunk, cursor, cursor + length);
          } else {
            await _budget.write(_budgetScope, incarnation, length, () async {
              await handle!.writeFrom(chunk, cursor, cursor + length);
            });
          }
          cursor += length;
          written += length;
          if (written - checkpointOffset >= checkpointBytes ||
              timer.elapsed >= checkpointInterval) {
            await _checkpoint(writer, handle, written);
            checkpointOffset = written;
            timer.reset();
          }
        }
      }
      writer.check();
      await _checkpoint(writer, handle, written);
      await handle.close();
      handle = null;
      if (written == initial.manifest.sizeBytes) {
        return await _finishInternal(writer);
      }
      _db.execute(
        "UPDATE inbox_files SET state='paused' WHERE transfer_id=? AND file_id=?",
        [transferId, fileId],
      );
      _refreshTransfer(transferId);
      _emit(transferId);
      return _fileSnapshot(_fileRow(transferId, fileId));
    } catch (error) {
      final mapped = writer.stopCode != null
          ? StorageException(writer.stopCode!, 'Transfer stopped.')
          : storageIoError(error);
      if (handle != null &&
          mapped.code != 'STORAGE_FAILURE' &&
          mapped.code != 'DISK_FULL') {
        try {
          await _checkpoint(writer, handle, written);
        } catch (_) {
          /* Keep last committed offset. */
        }
      }
      _recordFailure(writer, mapped);
      throw mapped;
    } finally {
      try {
        await writer.iterator?.cancel();
      } catch (_) {
        /* Input already failed. */
      }
      try {
        await handle?.close();
      } catch (_) {
        /* Failure is already reflected by the journal. */
      }
      try {
        await _reconcileBudgetRow(_fileRow(transferId, fileId));
      } finally {
        _writer = null;
        writer.done.complete();
      }
    }
  }

  Future<void> _checkpoint(
    _Writer writer,
    RandomAccessFile handle,
    int offset,
  ) async {
    await handle.flush();
    journalTransaction(_db, () {
      final row = _fileRow(writer.transferId, writer.fileId);
      if (row['incarnation'] != writer.incarnation) {
        throw const StorageException(
          'INCARNATION_MISMATCH',
          'Receive incarnation changed.',
        );
      }
      if ({
        'cancelled',
        'rejected',
        'failed',
        'committed',
      }.contains(row['state'])) {
        return;
      }
      _db.execute(
        'UPDATE inbox_files SET durable_offset=? WHERE transfer_id=? AND file_id=?',
        [offset, writer.transferId, writer.fileId],
      );
      _refreshTransfer(writer.transferId);
    });
    if (!_closing) _emit(writer.transferId);
  }

  Future<FileSnapshot> finishFile(
    String transferId,
    String fileId, {
    required String incarnation,
  }) async {
    _checkOpen();
    final file = _fileSnapshot(_fileRow(transferId, fileId));
    if (file.storageIncarnationId != incarnation) {
      throw const StorageException(
        'INCARNATION_MISMATCH',
        'Receive incarnation changed.',
      );
    }
    if (file.state == FileState.committed) return file;
    _checkWriteAllowed(transferId, file, incarnation);
    if (_writer != null) {
      throw const StorageException('BUSY', 'Another file is being written.');
    }
    final writer = _Writer(transferId, fileId, incarnation);
    _writer = writer;
    try {
      return await _finishInternal(writer);
    } catch (error) {
      final mapped = writer.stopCode == null
          ? storageIoError(error)
          : StorageException(writer.stopCode!, 'Transfer stopped.');
      _recordFailure(writer, mapped);
      throw mapped;
    } finally {
      try {
        await _reconcileBudgetRow(_fileRow(transferId, fileId));
      } finally {
        _writer = null;
        writer.done.complete();
      }
    }
  }

  Future<FileSnapshot> _finishInternal(_Writer writer) async {
    final row = _fileRow(writer.transferId, writer.fileId);
    final file = _fileSnapshot(row);
    writer.check();
    if (file.offset != file.manifest.sizeBytes) {
      throw StorageException(
        'INCOMPLETE_FILE',
        'Not all bytes are durable.',
        offset: file.offset,
      );
    }
    final temporary = File(row['temporary_path'] as String);
    await ensurePlainFile(temporary);
    if (await temporary.length() != file.manifest.sizeBytes) {
      throw const StorageException(
        'RECOVERY_INCONSISTENT',
        'Stored length differs from manifest.',
      );
    }
    _db.execute(
      "UPDATE inbox_files SET state='verifying' WHERE transfer_id=? AND file_id=?",
      [writer.transferId, writer.fileId],
    );
    _refreshTransfer(writer.transferId);
    _emit(writer.transferId);
    final hash = await hashStoredFile(temporary, check: writer.check);
    if (hash != file.manifest.sha256) {
      throw const StorageException(
        'INTEGRITY_MISMATCH',
        'Received SHA-256 does not match.',
      );
    }
    writer.check();
    final transferDirectory = Directory(
      p.join(root.path, 'received', writer.transferId),
    );
    final fileDirectory = Directory(
      p.join(transferDirectory.path, writer.incarnation),
    );
    await validateManagedDirectory(root, transferDirectory, create: true);
    await validateManagedDirectory(root, fileDirectory, create: true);
    final finalPath = p.join(
      fileDirectory.path,
      safeDisplayName(file.manifest.displayName),
    );
    requireContainedPath(root, finalPath);
    if (await FileSystemEntity.type(finalPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const StorageException(
        'DESTINATION_EXISTS',
        'Existing result will not be overwritten.',
      );
    }
    writer.check();
    // No async gap between acquiring the commit lock and persisting intent.
    // Cancel/pause now wait for this sink-authoritative commit decision.
    writer.commitLocked = true;
    journalTransaction(_db, () {
      _db.execute(
        "UPDATE inbox_files SET state='committing',final_path=? WHERE transfer_id=? AND file_id=?",
        [finalPath, writer.transferId, writer.fileId],
      );
      _refreshTransfer(writer.transferId);
    });
    await temporary.rename(finalPath);
    journalTransaction(_db, () {
      _db.execute(
        "UPDATE inbox_files SET state='committed',error_code=NULL WHERE transfer_id=? AND file_id=?",
        [writer.transferId, writer.fileId],
      );
      _refreshTransfer(writer.transferId);
    });
    _emit(writer.transferId);
    return _fileSnapshot(_fileRow(writer.transferId, writer.fileId));
  }

  void _recordFailure(_Writer writer, StorageException error) {
    final row = _fileRow(writer.transferId, writer.fileId);
    if ({
      'committed',
      'cancelled',
      'rejected',
      'expired',
    }.contains(row['state'])) {
      return;
    }
    // Preserve commit intent after an interrupted rename/DB operation. Recovery
    // decides whether the old temporary file or the final file is authoritative.
    if (row['state'] == 'committing') return;
    final recoverable = {
      'TRANSFER_INTERRUPTED',
      'TRANSFER_PAUSED',
      'INCOMPLETE_FILE',
      'DISK_FULL',
      'TEMP_QUOTA_EXCEEDED',
      'CAPACITY_UNAVAILABLE',
      'STORAGE_FAILURE',
    }.contains(error.code);
    _db.execute(
      'UPDATE inbox_files SET state=?,error_code=? WHERE transfer_id=? AND file_id=?',
      [
        recoverable ? 'paused' : 'failed',
        error.code,
        writer.transferId,
        writer.fileId,
      ],
    );
    _refreshTransfer(writer.transferId);
    if (!_closing) _emit(writer.transferId);
  }

  void _refreshTransfer(String id) {
    final transfer = _db.select(
      'SELECT paused_source,paused_sink FROM inbox_transfers WHERE id=?',
      [id],
    ).first;
    final states = _db
        .select('SELECT state FROM inbox_files WHERE transfer_id=?', [id])
        .map((row) => row['state'] as String)
        .toList();
    String state;
    final terminal = states.every(
      (state) => {
        'committed',
        'rejected',
        'cancelled',
        'failed',
        'expired',
      }.contains(state),
    );
    if (states.every((state) => state == 'committed')) {
      state = 'completed';
    } else if (states.every((state) => state == 'offered')) {
      state = 'offered';
    } else if (states.every((state) => state == 'rejected')) {
      state = 'rejected';
    } else if (states.every((state) => state == 'expired')) {
      state = 'expired';
    } else if (terminal) {
      state = states.contains('committed')
          ? 'partially_completed'
          : states.contains('failed')
          ? 'failed'
          : 'cancelled';
    } else if (states.any(
      (state) => {'transferring', 'verifying', 'committing'}.contains(state),
    )) {
      state = 'transferring';
    } else if (transfer['paused_source'] == 1 ||
        transfer['paused_sink'] == 1 ||
        states.contains('paused')) {
      state = 'paused';
    } else {
      state = 'accepted';
    }
    _db.execute('UPDATE inbox_transfers SET state=?,updated_at=? WHERE id=?', [
      state,
      _wallClock().toUtc().toIso8601String(),
      id,
    ]);
    if (state != 'offered') _offerDeadlines.remove(id);
  }

  TransferSnapshot _emit(String id) {
    final result = status(id);
    if (!_events.isClosed) _events.add(result);
    return result;
  }

  Future<void> _recover() async {
    for (final row in _db.select('SELECT * FROM inbox_files')) {
      final state = row['state'] as String;
      if ({
        'offered',
        'rejected',
        'cancelled',
        'failed',
        'committed',
        'expired',
      }.contains(state)) {
        continue;
      }
      final transferId = row['transfer_id'] as String;
      final fileId = row['file_id'] as String;
      try {
        final file = _fileSnapshot(row);
        final temporary = File(row['temporary_path'] as String);
        requireContainedPath(root, temporary.path);
        await validateManagedDirectory(root, temporary.parent);
        if (state == 'committing') {
          final finalPath = row['final_path'] as String?;
          if (finalPath == null) {
            throw const StorageException(
              'RECOVERY_INCONSISTENT',
              'Commit target missing.',
            );
          }
          requireContainedPath(root, finalPath);
          final target = File(finalPath);
          await validateManagedDirectory(root, target.parent);
          final targetKind = await FileSystemEntity.type(
            finalPath,
            followLinks: false,
          );
          final candidate = targetKind == FileSystemEntityType.notFound
              ? temporary
              : target;
          await ensurePlainFile(candidate);
          if (await candidate.length() != file.manifest.sizeBytes ||
              await hashStoredFile(candidate) != file.manifest.sha256) {
            throw const StorageException(
              'RECOVERY_INCONSISTENT',
              'Commit candidate failed verification.',
            );
          }
          if (targetKind == FileSystemEntityType.notFound) {
            await temporary.rename(finalPath);
          }
          _db.execute(
            "UPDATE inbox_files SET state='committed',error_code=NULL WHERE transfer_id=? AND file_id=?",
            [transferId, fileId],
          );
          continue;
        }
        await ensurePlainFile(temporary);
        final length = await temporary.length();
        if (length < file.offset) {
          throw const StorageException(
            'RECOVERY_INCONSISTENT',
            'Durable prefix is missing.',
          );
        }
        if (length > file.offset) {
          final handle = await temporary.open(mode: FileMode.append);
          try {
            await handle.truncate(file.offset);
            await handle.flush();
          } finally {
            await handle.close();
          }
        }
        if (state != 'accepted') {
          // A validated paused prefix keeps its existing reason (for example
          // DISK_FULL). Restart is not a new cause and must not hide the action
          // the user still needs to take before resuming. Previously active
          // states, or a pause without a recorded reason, are interrupted.
          final cause = state == 'paused' && file.errorCode?.isNotEmpty == true
              ? file.errorCode!
              : 'TRANSFER_INTERRUPTED';
          _db.execute(
            "UPDATE inbox_files SET state='paused',error_code=? WHERE transfer_id=? AND file_id=?",
            [cause, transferId, fileId],
          );
        }
      } catch (error) {
        final code = error is StorageException
            ? error.code
            : 'RECOVERY_INCONSISTENT';
        _db.execute(
          "UPDATE inbox_files SET state='failed',error_code=? WHERE transfer_id=? AND file_id=?",
          [code, transferId, fileId],
        );
      }
    }
    for (final row in _db.select('SELECT id FROM inbox_transfers')) {
      _refreshTransfer(row['id'] as String);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _offerTimer?.cancel();
    _offerTimer = null;
    final writer = _writer;
    if (writer != null) await _stopWriter(writer.transferId, 'TRANSFER_PAUSED');
    await _controls.run(() async {
      if (_closed) return;
      _closing = true;
      // A writer finishing while close awaited it may have emitted a status
      // and rearmed the offer timer. Cancel again at the final DB boundary.
      _offerTimer?.cancel();
      _offerTimer = null;
      _db.close();
      _closed = true;
      await _lease.release();
      await _events.close();
    });
  }
}

class IncomingCleanupItem {
  const IncomingCleanupItem({
    required this.transferId,
    required this.temporaryBytes,
    required this.reservedBytes,
    required this.incompleteFileCount,
    required this.committedFileCount,
  });

  final String transferId;
  final int temporaryBytes;
  final int reservedBytes;
  final int incompleteFileCount;
  final int committedFileCount;
}

class IncomingCleanupResult {
  const IncomingCleanupResult({
    required this.snapshot,
    required this.removedFileCount,
    required this.removedBytes,
  });

  final TransferSnapshot snapshot;
  final int removedFileCount;
  final int removedBytes;
}

class _Writer {
  _Writer(this.transferId, this.fileId, this.incarnation);
  final String transferId;
  final String fileId;
  final String incarnation;
  final done = Completer<void>();
  StreamIterator<List<int>>? iterator;
  String? stopCode;
  bool commitLocked = false;
  void check() {
    if (stopCode != null) {
      throw StorageException(stopCode!, 'Transfer stopped.');
    }
  }
}

class _ControlQueue {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() work) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await previous;
    try {
      return await work();
    } finally {
      release.complete();
    }
  }
}
