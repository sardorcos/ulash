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
/// writes into arbitrary paths supplied by the sender. Without a
/// `receivedDirectory`, files are committed under
/// `received/<transfer>/<incarnation>/<folder?>/<safe name>`. With one, they
/// are committed to a user-visible layout
/// `<receivedDirectory>/<yyyy-MM-dd HH.mm> (<id6>)/<folder?>/<safe name>`
/// (collisions get ` (2)`, never overwriting). Existing results are preserved.
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
    this.maxOffersPerWindow,
    this.offerRateWindow,
    this.maxRetainedUnacceptedOffersPerPeer,
    this.receivedRoot,
    this.maxPendingOffersPerPeer,
  );

  /// Current journal schema. 1 = 0.1–0.3 layout with offer deadlines,
  /// 2 = store-relative payload paths, 3 = user-visible received directory
  /// (`r:` final paths and the crash-safe `moved_from` migration marker).
  static const int schemaVersion = 3;

  /// Root of the user-visible received layout, or null for the private
  /// `received/` layout inside [root].
  final Directory? receivedRoot;

  /// Pending (offered/accepted/active) transfers allowed per peer, in addition
  /// to the global cap, so one paired device cannot occupy the whole queue.
  final int maxPendingOffersPerPeer;
  final _manifestCache = <String, TransferManifest>{};
  final _fileManifestCache = <String, FileManifest>{};
  static const _managed = {'.staging', 'received'};

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

  /// Per-peer admission limit for new offers (idempotent replays not counted).
  final int maxOffersPerWindow;
  final Duration offerRateWindow;

  /// Rejected/expired/cancelled offers that never received data are history
  /// only. Older ones beyond this count are removed per peer.
  final int maxRetainedUnacceptedOffersPerPeer;
  final _offerHistory = <String, List<Duration>>{};
  final _offerDeadlines = <String, Duration>{};
  Timer? _offerTimer;
  final _controls = _ControlQueue();
  final _events = StreamController<TransferSnapshot>.broadcast();
  _Writer? _writer;
  bool _closed = false;
  bool _closing = false;

  Stream<TransferSnapshot> get changes => _events.stream;

  /// The id of every transfer whose state or progress changed.
  Stream<String> get changedTransfers =>
      _events.stream.map((snapshot) => snapshot.transferId);

  /// Testing seam only: awaited at internal race points ('afterFinalClose',
  /// 'beforeVerifying') so tests can interleave cancel/pause deterministically.
  /// Must stay null in production.
  Future<void> Function(String stage)? debugStageHook;

  static Future<DurableInbox> open(
    Directory directory, {
    int checkpointBytes = 8 * 1024 * 1024,
    Duration checkpointInterval = const Duration(seconds: 2),
    StorageBudget? budget,
    Duration offerLifetime = const Duration(seconds: 120),
    DateTime Function()? wallClock,
    Duration Function()? monotonicClock,
    int maxOffersPerWindow = 20,
    Duration offerRateWindow = const Duration(minutes: 10),
    int maxRetainedUnacceptedOffersPerPeer = 50,
    Directory? receivedDirectory,
    int maxPendingOffersPerPeer = 5,
  }) async {
    if (maxPendingOffersPerPeer < 1) {
      throw ArgumentError('maxPendingOffersPerPeer must be positive.');
    }
    if (maxOffersPerWindow < 1 ||
        offerRateWindow <= Duration.zero ||
        maxRetainedUnacceptedOffersPerPeer < 0) {
      throw ArgumentError('Invalid offer admission limits.');
    }
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
    final receivedRoot = receivedDirectory == null
        ? null
        : await prepareStorageDirectory(receivedDirectory);
    final lease = await StorageLease.acquire(root, 'inbox');
    Database? opened;
    try {
      final db = openJournal(
        File(p.join(root.path, 'inbox.sqlite')),
        version: schemaVersion,
        migrate: (db, from) => _migrate(db, from, offerLifetime),
      );
      opened = db;
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
        maxOffersPerWindow,
        offerRateWindow,
        maxRetainedUnacceptedOffersPerPeer,
        receivedRoot,
        maxPendingOffersPerPeer,
      );
      await store._recover();
      await store._migrateReceivedLayout();
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

  /// Idempotent schema steps. They run on every open inside one transaction so
  /// that a journal edited by an older build is normalised again.
  static void _migrate(Database db, int from, Duration offerLifetime) {
    // Step 1 (0.1–0.3): base tables and offer deadlines.
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
      CREATE INDEX IF NOT EXISTS inbox_transfers_peer
        ON inbox_transfers(peer_id, created_at);
      CREATE INDEX IF NOT EXISTS inbox_transfers_state
        ON inbox_transfers(state);
    ''');
    // Alpha 0.1/0.2 journals did not have offer deadlines. Use their original
    // creation time, never the recovery-refreshed updated_at value.
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
      db.execute('UPDATE inbox_transfers SET offer_expires_at=? WHERE id=?', [
        created.add(offerLifetime).toIso8601String(),
        row['id'],
      ]);
    }
    // Step 3: crash-safe marker for moving results into the received layout.
    final fileColumns = db.select('PRAGMA table_info(inbox_files)');
    if (!fileColumns.any((column) => column['name'] == 'moved_from')) {
      db.execute('ALTER TABLE inbox_files ADD COLUMN moved_from TEXT');
    }
    // Step 2: store-relative paths. Earlier builds persisted absolute paths,
    // which break when the app container moves (iOS update/restore).
    for (final row in db.select(
      "SELECT transfer_id,file_id,incarnation,temporary_path,final_path FROM inbox_files "
      "WHERE temporary_path NOT LIKE '.staging/%' "
      "OR (final_path IS NOT NULL AND final_path NOT LIKE 'received/%' "
      "AND final_path NOT LIKE 'r:%')",
    )) {
      final finalPath = row['final_path'] as String?;
      final rebased = finalPath == null
          ? null
          : (rebaseLegacyPath(finalPath, managedTopLevel: const {'received'}) ??
                finalPath);
      db.execute(
        'UPDATE inbox_files SET temporary_path=?,final_path=? WHERE transfer_id=? AND file_id=?',
        [
          '.staging/${row['incarnation']}.part',
          rebased,
          row['transfer_id'],
          row['file_id'],
        ],
      );
    }
  }

  /// Moves a damaged `inbox.sqlite` (and WAL/SHM) aside after
  /// [StorageException] `JOURNAL_CORRUPT`. Received files stay on disk; the
  /// next [open] starts a new journal and removes unreferenced staging parts.
  static Future<List<String>> quarantineJournal(Directory directory) async {
    final root = await prepareStorageDirectory(directory);
    final lease = await StorageLease.acquire(root, 'inbox');
    try {
      return await quarantineJournalFiles(
        File(p.join(root.path, 'inbox.sqlite')),
      );
    } finally {
      await lease.release();
    }
  }

  String _abs(String stored) =>
      resolveStoredPath(root, stored, managedTopLevel: _managed);

  /// Resolves a stored final path: `r:<relative>` lives under
  /// [receivedRoot], anything else under the private store root.
  String _finalAbs(String stored) {
    if (!stored.startsWith('r:')) return _abs(stored);
    final base = receivedRoot;
    if (base == null) {
      throw const StorageException(
        'UNSAFE_PATH',
        'Received directory is not configured.',
      );
    }
    final parts = stored.substring(2).split('/');
    if (parts.length < 2 ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const StorageException('UNSAFE_PATH', 'Unsafe stored path.');
    }
    final absolute = p.joinAll([base.path, ...parts]);
    requireContainedPath(base, absolute);
    return absolute;
  }

  /// `yyyy-MM-dd HH.mm (abc123)` from the transfer's creation time (local
  /// time, as the user sees it) and its id: never from sender-chosen text.
  static String _transferFolderName(String transferId, DateTime createdUtc) {
    final local = createdUtc.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final short = transferId.replaceAll('-', '');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}.${two(local.minute)} '
        '(${short.substring(0, math.min(6, short.length))})';
  }

  /// Picks a free file name in [directory] and reserves it with an exclusive
  /// create, so a concurrent file is never overwritten by the later rename.
  static Future<String> _reserveUniqueName(
    Directory directory,
    String safeName,
  ) async {
    final extension = p.extension(safeName);
    final stem = extension.isEmpty
        ? safeName
        : safeName.substring(0, safeName.length - extension.length);
    for (var index = 1; index <= 1000; index++) {
      final candidate = p.join(
        directory.path,
        index == 1 ? safeName : '$stem ($index)$extension',
      );
      try {
        await File(candidate).create(exclusive: true);
        return candidate;
      } on FileSystemException {
        continue;
      }
    }
    throw const StorageException(
      'DESTINATION_EXISTS',
      'No free name for the received file.',
    );
  }

  /// Target for committing [file] of [transferId]: (absolute path, stored
  /// journal value). The user-visible layout reserves the name up front.
  Future<(String, String)> _commitTarget(
    String transferId,
    String incarnation,
    FileManifest file,
  ) async {
    final folders = file.relativeDirectory == null
        ? const <String>[]
        : file.relativeDirectory!.split('/').map(safeDisplayName).toList();
    final base = receivedRoot;
    if (base == null) {
      final directory = Directory(
        p.joinAll([root.path, 'received', transferId, incarnation, ...folders]),
      );
      await validateManagedDirectory(root, directory, create: true);
      final finalPath = p.join(
        directory.path,
        safeDisplayName(file.displayName),
      );
      requireContainedPath(root, finalPath);
      if (await FileSystemEntity.type(finalPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const StorageException(
          'DESTINATION_EXISTS',
          'Existing result will not be overwritten.',
        );
      }
      return (finalPath, toStoredPath(root, finalPath));
    }
    final record = _db.select(
      'SELECT created_at FROM inbox_transfers WHERE id=?',
      [transferId],
    ).first;
    final created = DateTime.parse(record['created_at'] as String).toUtc();
    final directory = Directory(
      p.joinAll([
        base.path,
        _transferFolderName(transferId, created),
        ...folders,
      ]),
    );
    await validateManagedDirectory(base, directory, create: true);
    final finalPath = await _reserveUniqueName(
      directory,
      safeDisplayName(file.displayName),
    );
    requireContainedPath(base, finalPath);
    return (finalPath, 'r:${toStoredPath(base, finalPath)}');
  }

  String _temporaryOf(Row row) => _abs(row['temporary_path'] as String);

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

  /// Moves results committed under the private `received/` layout into the
  /// user-visible [receivedRoot]. Crash-safe and idempotent: the journal row
  /// is switched to the reserved target with `moved_from` = old path before
  /// the file moves, and `moved_from` is cleared after; a row found with
  /// `moved_from` set on the next open is finished first. A file that cannot
  /// be moved keeps its old location (it is never lost).
  Future<void> _migrateReceivedLayout() async {
    if (receivedRoot == null) return;
    final legacyRoot = Directory(p.join(root.path, 'received'));
    for (final row in _db.select(
      'SELECT transfer_id,file_id,final_path,moved_from FROM inbox_files '
      'WHERE moved_from IS NOT NULL',
    )) {
      await _finishMove(row, legacyRoot);
    }
    for (final row in _db.select(
      "SELECT * FROM inbox_files WHERE state='committed' "
      "AND final_path LIKE 'received/%' AND moved_from IS NULL",
    )) {
      final transferId = row['transfer_id'] as String;
      final fileId = row['file_id'] as String;
      final oldStored = row['final_path'] as String;
      final String oldPath;
      try {
        oldPath = _abs(oldStored);
        if (await FileSystemEntity.type(oldPath, followLinks: false) !=
            FileSystemEntityType.file) {
          continue; // Reported as FILE_MISSING; nothing to move.
        }
        await validateManagedDirectory(root, File(oldPath).parent);
      } on Object {
        continue;
      }
      String? newStored;
      try {
        final (_, stored) = await _commitTarget(
          transferId,
          row['incarnation'] as String,
          _fileSnapshot(row).manifest,
        );
        newStored = stored;
        journalTransaction(_db, () {
          _db.execute(
            'UPDATE inbox_files SET final_path=?,moved_from=? '
            'WHERE transfer_id=? AND file_id=?',
            [stored, oldStored, transferId, fileId],
          );
        });
        await _moveFile(File(oldPath), _finalAbs(stored));
        _db.execute(
          'UPDATE inbox_files SET moved_from=NULL WHERE transfer_id=? AND file_id=?',
          [transferId, fileId],
        );
        await _removeEmptyParents(File(oldPath).parent, legacyRoot);
      } on Object {
        // Keep the result where it is; release the reserved name.
        _db.execute(
          'UPDATE inbox_files SET final_path=?,moved_from=NULL '
          'WHERE transfer_id=? AND file_id=?',
          [oldStored, transferId, fileId],
        );
        if (newStored != null) {
          try {
            final target = File(_finalAbs(newStored));
            if (await target.exists() && await target.length() == 0) {
              await target.delete();
            }
            await _removeEmptyParents(target.parent, receivedRoot!);
          } on Object {
            // Best effort.
          }
        }
      }
    }
  }

  Future<void> _finishMove(Row row, Directory legacyRoot) async {
    final transferId = row['transfer_id'] as String;
    final fileId = row['file_id'] as String;
    final oldStored = row['moved_from'] as String;
    try {
      final oldPath = _abs(oldStored);
      final target = _finalAbs(row['final_path'] as String);
      if (await FileSystemEntity.type(oldPath, followLinks: false) ==
          FileSystemEntityType.file) {
        // The move did not complete; the target is our reservation (or a
        // partial copy of this very file), so replacing it is safe.
        await validateManagedDirectory(receivedRoot!, File(target).parent);
        await _moveFile(File(oldPath), target);
      }
      _db.execute(
        'UPDATE inbox_files SET moved_from=NULL WHERE transfer_id=? AND file_id=?',
        [transferId, fileId],
      );
      await _removeEmptyParents(File(oldPath).parent, legacyRoot);
    } on Object {
      _db.execute(
        'UPDATE inbox_files SET final_path=?,moved_from=NULL '
        'WHERE transfer_id=? AND file_id=?',
        [oldStored, transferId, fileId],
      );
    }
  }

  /// Rename, or copy+flush+delete when the target is on another volume.
  static Future<void> _moveFile(File source, String target) async {
    try {
      await source.rename(target);
      return;
    } on FileSystemException {
      // Cross-device: fall through to copy.
    }
    final output = await File(target).open(mode: FileMode.write);
    try {
      await for (final chunk in source.openRead()) {
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    await source.delete();
  }

  Future<void> _restoreBudget() async {
    if (_budget == null) return;
    final rows = _db.select('SELECT * FROM inbox_files');
    final rowsByPath = <String, Row>{
      for (final row in rows) _temporaryOf(row): row,
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
      final length = lengths[_temporaryOf(row)] ?? 0;
      if (row['state'] == 'committed' && length == 0) continue;
      claims.add(_budgetClaim(row, length));
    }
    await _budget.restoreScope(_budgetScope, claims);
  }

  Future<void> _reconcileBudgetRow(Row row) async {
    if (_budget == null) return;
    final file = File(_temporaryOf(row));
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
    final quota = _budget?.temporaryQuotaBytes;
    if (quota != null && manifest.totalBytes > quota) {
      throw const StorageException(
        'QUOTA_EXCEEDED',
        'The package is larger than the receiver storage limit.',
      );
    }
    final admittedAt = _monotonicClock();
    final history = _offerHistory.putIfAbsent(peerId, () => [])
      ..removeWhere((time) => admittedAt - time >= offerRateWindow);
    if (history.length >= maxOffersPerWindow) {
      throw const StorageException(
        'RATE_LIMITED',
        'Too many offers from this device. Try again later.',
      );
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
    final pendingFromPeer =
        _db.select(
              "SELECT COUNT(*) AS n FROM inbox_transfers WHERE peer_id=? AND state IN ('offered','accepted','transferring','paused')",
              [peerId],
            ).first['n']
            as int;
    if (pendingFromPeer >= maxPendingOffersPerPeer) {
      throw const StorageException(
        'BUSY',
        'Too many pending offers from this device.',
      );
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
            '.staging/$incarnation.part',
          ],
        );
      }
    });
    history.add(admittedAt);
    _offerDeadlines[id] = createdMonotonic + offerLifetime;
    _scheduleOfferExpiry();
    await _pruneUnacceptedOffers(peerId);
    return _emit(id);
  }

  static const _unacceptedTerminal = "('rejected','expired','cancelled')";

  /// Removes the oldest terminal offers that never stored a byte, beyond
  /// [maxRetainedUnacceptedOffersPerPeer]. Prevents a paired peer from growing
  /// the journal without bound by repeatedly offering and cancelling.
  Future<void> _pruneUnacceptedOffers(String peerId) async {
    final candidates = _db.select(
      'SELECT t.id FROM inbox_transfers t WHERE t.peer_id=? AND t.state IN $_unacceptedTerminal '
      'AND NOT EXISTS (SELECT 1 FROM inbox_files f WHERE f.transfer_id=t.id '
      "AND (f.durable_offset>0 OR f.state='committed' OR f.final_path IS NOT NULL)) "
      'ORDER BY t.created_at DESC LIMIT -1 OFFSET ?',
      [peerId, maxRetainedUnacceptedOffersPerPeer],
    );
    for (final candidate in candidates) {
      await _removeTransferRows(candidate['id'] as String);
    }
  }

  /// Deletes staging parts, the received directory and journal rows of one
  /// transfer and forgets its storage claims. Caller checked it is terminal.
  Future<int> _removeTransferRows(String id) async {
    final rows = _db.select('SELECT * FROM inbox_files WHERE transfer_id=?', [
      id,
    ]);
    var removedBytes = 0;
    for (final row in rows) {
      removedBytes += await _deleteTemporary(row) ?? 0;
      final stored = row['final_path'] as String?;
      if (stored != null && stored.startsWith('r:')) {
        removedBytes += await _deleteReceivedFile(stored);
      }
    }
    final directory = Directory(p.join(root.path, 'received', id));
    final kind = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (kind == FileSystemEntityType.directory) {
      await validateManagedDirectory(root, directory);
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) removedBytes += await entity.length();
      }
      // Directory.delete never follows links; a planted link is removed only.
      await directory.delete(recursive: true);
    } else if (kind != FileSystemEntityType.notFound) {
      throw const StorageException(
        'UNSAFE_PATH',
        'Received transfer path is not a directory.',
      );
    }
    journalTransaction(_db, () {
      _db.execute('DELETE FROM inbox_files WHERE transfer_id=?', [id]);
      _db.execute('DELETE FROM inbox_transfers WHERE id=?', [id]);
    });
    _forgetCached(id, rows.map((row) => row['incarnation'] as String));
    _offerDeadlines.remove(id);
    for (final row in rows) {
      await _budget?.forget(_budgetScope, row['incarnation'] as String);
    }
    return removedBytes;
  }

  /// Deletes one result in the user-visible layout (only a regular file, never
  /// through a link) and then its now-empty parent folders up to the root.
  Future<int> _deleteReceivedFile(String stored) async {
    final String absolute;
    try {
      absolute = _finalAbs(stored);
    } on StorageException {
      return 0;
    }
    var removed = 0;
    if (await FileSystemEntity.type(absolute, followLinks: false) ==
        FileSystemEntityType.file) {
      final file = File(absolute);
      removed = await file.length();
      await file.delete();
    }
    await _removeEmptyParents(Directory(p.dirname(absolute)), receivedRoot!);
    return removed;
  }

  /// Removes [directory] and its ancestors while they are empty plain
  /// directories strictly inside [stop].
  static Future<void> _removeEmptyParents(
    Directory directory,
    Directory stop,
  ) async {
    var current = directory;
    while (p.isWithin(stop.path, current.path)) {
      if (await FileSystemEntity.type(current.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return;
      }
      if (!await current.list(followLinks: false).isEmpty) return;
      try {
        await current.delete();
      } on FileSystemException {
        return;
      }
      current = current.parent;
    }
  }

  void _forgetCached(String transferId, Iterable<String> incarnations) {
    _manifestCache.remove(transferId);
    for (final incarnation in incarnations) {
      _fileManifestCache.remove(incarnation);
    }
  }

  /// Removes a finished transfer from history together with its received files
  /// and any leftover partial data. Active transfers must be cancelled first.
  /// Returns the number of bytes removed from disk.
  Future<int> deleteTransfer(String id) => _controls.run(() async {
    final snapshot = status(id);
    if (!_terminal(snapshot.state) ||
        _writer?.transferId == id ||
        snapshot.files.any((file) => file.state == FileState.committing)) {
      throw const StorageException(
        'TRANSFER_ACTIVE',
        'Only finished transfers can be deleted.',
      );
    }
    try {
      return await _removeTransferRows(id);
    } catch (error) {
      throw storageIoError(error);
    }
  });

  /// Retention: removes terminal transfers last updated before now-[olderThan].
  /// By default transfers that still own received files are kept (only failed,
  /// rejected, expired and cancelled history disappears); pass
  /// [includeReceivedFiles] to also delete completed transfers and their files.
  /// Returns the number of transfers removed.
  Future<int> pruneTerminal({
    required Duration olderThan,
    bool includeReceivedFiles = false,
  }) => _controls.run(() async {
    _checkOpen();
    expireOffers();
    final cutoff = _wallClock().toUtc().subtract(olderThan).toIso8601String();
    final rows = _db.select(
      'SELECT id FROM inbox_transfers WHERE updated_at < ? AND state IN '
      "('completed','partially_completed','rejected','cancelled','failed','expired')",
      [cutoff],
    );
    var removed = 0;
    for (final row in rows) {
      final id = row['id'] as String;
      if (_writer?.transferId == id) continue;
      final snapshot = _readStatus(id);
      if (snapshot.files.any((file) => file.state == FileState.committing)) {
        continue;
      }
      if (!includeReceivedFiles &&
          snapshot.files.any((file) => file.state == FileState.committed)) {
        continue;
      }
      try {
        await _removeTransferRows(id);
      } catch (error) {
        throw storageIoError(error);
      }
      removed++;
    }
    return removed;
  });

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
    final files = _db.select(
      'SELECT * FROM inbox_files WHERE transfer_id=? ORDER BY ordinal',
      [id],
    );
    return _snapshotOf(records.first, files);
  }

  /// Manifests are immutable once stored, so their decoded form is cached by
  /// transfer id / storage incarnation (cleared when the rows are deleted).
  TransferManifest _manifestOf(Row record) =>
      _manifestCache[record['id'] as String] ??= TransferManifest.fromJson(
        jsonDecode(record['manifest'] as String) as Map<String, dynamic>,
      );

  TransferSnapshot _snapshotOf(Row record, Iterable<Row> files) =>
      TransferSnapshot(
        transferId: record['id'] as String,
        peerId: record['peer_id'] as String,
        manifest: _manifestOf(record),
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

  /// All transfers, newest first. Two queries regardless of history size.
  List<TransferSnapshot> list({String? peerId}) {
    _checkOpen();
    expireOffers();
    return _query(
      peerId == null ? '' : 'WHERE peer_id=?',
      peerId == null ? const [] : [peerId],
    );
  }

  /// At most [limit] transfers created strictly before [before] (all when
  /// null), newest first; page with the last item's `createdAt`.
  List<TransferSnapshot> listRecent({int limit = 200, DateTime? before}) {
    _checkOpen();
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    expireOffers();
    return _query(before == null ? '' : 'WHERE created_at < ?', [
      if (before != null) before.toUtc().toIso8601String(),
    ], limit: limit);
  }

  /// Number of transfers in history.
  int count({String? peerId}) {
    _checkOpen();
    return _db
            .select(
              'SELECT COUNT(*) AS n FROM inbox_transfers ${peerId == null ? '' : 'WHERE peer_id=?'}',
              peerId == null ? const [] : [peerId],
            )
            .first['n']
        as int;
  }

  List<TransferSnapshot> _query(
    String where,
    List<Object?> parameters, {
    int? limit,
  }) {
    final records = _db.select(
      'SELECT * FROM inbox_transfers $where ORDER BY created_at DESC, id '
      '${limit == null ? '' : 'LIMIT $limit'}',
      parameters,
    );
    if (records.isEmpty) return const [];
    final byTransfer = <String, List<Row>>{};
    final ids = [for (final record in records) record['id'] as String];
    // Chunked to stay below SQLite's bound-parameter limit.
    for (var start = 0; start < ids.length; start += 500) {
      final chunk = ids.sublist(start, math.min(ids.length, start + 500));
      final files = _db.select(
        'SELECT * FROM inbox_files WHERE transfer_id IN '
        '(${List.filled(chunk.length, '?').join(',')}) ORDER BY ordinal',
        chunk,
      );
      for (final file in files) {
        byTransfer
            .putIfAbsent(file['transfer_id'] as String, () => [])
            .add(file);
      }
    }
    return [
      for (final record in records)
        _snapshotOf(record, byTransfer[record['id'] as String] ?? const []),
    ];
  }

  FileSnapshot _fileSnapshot(Row row) => FileSnapshot(
    manifest: _fileManifestCache[row['incarnation'] as String] ??=
        FileManifest.fromJson(
          jsonDecode(row['manifest'] as String) as Map<String, dynamic>,
        ),
    offset: row['durable_offset'] as int,
    state: FileState.fromWire(row['state'] as String),
    storageIncarnationId: row['incarnation'] as String,
    finalPath: _resolvedFinalPath(row['final_path'] as String?),
    errorCode: row['error_code'] as String?,
  );

  String? _resolvedFinalPath(String? stored) {
    if (stored == null) return null;
    try {
      return _finalAbs(stored);
    } on StorageException {
      // An unrecognised legacy value is reported as unavailable, never as a
      // path outside managed storage.
      return null;
    }
  }

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
        final file = File(_temporaryOf(row));
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
    final file = File(_temporaryOf(row));
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
      final temporary = File(_temporaryOf(row));
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
      await debugStageHook?.call('afterFinalClose');
      // Cancel/pause may have run during the awaits above. They own the state.
      writer.check();
      if (written == initial.manifest.sizeBytes) {
        return await _finishInternal(writer);
      }
      _db.execute(
        "UPDATE inbox_files SET state='paused' WHERE transfer_id=? AND file_id=? AND state IN ('accepted','transferring')",
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
      if (_recordFailure(writer, mapped)) {
        try {
          await handle?.close();
        } catch (_) {
          /* Closing before deletion; failure is already journaled. */
        }
        handle = null;
        await _discardFailedPayload(writer);
      }
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
      if (_recordFailure(writer, mapped)) await _discardFailedPayload(writer);
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
    final temporary = File(_temporaryOf(row));
    await ensurePlainFile(temporary);
    if (await temporary.length() != file.manifest.sizeBytes) {
      throw const StorageException(
        'RECOVERY_INCONSISTENT',
        'Stored length differs from manifest.',
      );
    }
    await debugStageHook?.call('beforeVerifying');
    writer.check();
    // Never overwrite a concurrent cancel/pause decision with 'verifying'.
    _db.execute(
      "UPDATE inbox_files SET state='verifying' WHERE transfer_id=? AND file_id=? "
      "AND state IN ('accepted','transferring','paused') "
      'AND (SELECT paused_source+paused_sink FROM inbox_transfers WHERE id=?)=0',
      [writer.transferId, writer.fileId, writer.transferId],
    );
    if (_db.updatedRows == 0) {
      throw StorageException(
        writer.stopCode ?? 'TRANSFER_CANCELLED',
        'Transfer stopped.',
      );
    }
    _refreshTransfer(writer.transferId);
    _emit(writer.transferId);
    final hash = await hashFileIsolated(temporary, check: writer.check);
    if (hash != file.manifest.sha256) {
      throw const StorageException(
        'INTEGRITY_MISMATCH',
        'Received SHA-256 does not match.',
      );
    }
    writer.check();
    final (finalPath, storedFinal) = await _commitTarget(
      writer.transferId,
      writer.incarnation,
      file.manifest,
    );
    try {
      writer.check();
    } catch (_) {
      // Release the name reserved in the user-visible layout.
      if (receivedRoot != null) await _deleteReceivedFile(storedFinal);
      rethrow;
    }
    // No async gap between acquiring the commit lock and persisting intent.
    // Cancel/pause now wait for this sink-authoritative commit decision.
    writer.commitLocked = true;
    journalTransaction(_db, () {
      _db.execute(
        "UPDATE inbox_files SET state='committing',final_path=? WHERE transfer_id=? AND file_id=?",
        [storedFinal, writer.transferId, writer.fileId],
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

  /// Returns true when the file became terminally `failed` (its partial
  /// payload can no longer be resumed and should be discarded).
  bool _recordFailure(_Writer writer, StorageException error) {
    final row = _fileRow(writer.transferId, writer.fileId);
    if ({
      'committed',
      'cancelled',
      'rejected',
      'expired',
      'failed',
    }.contains(row['state'])) {
      return false;
    }
    // Preserve commit intent after an interrupted rename/DB operation. Recovery
    // decides whether the old temporary file or the final file is authoritative.
    if (row['state'] == 'committing') return false;
    final recoverable = {
      'TRANSFER_INTERRUPTED',
      'TRANSFER_TOO_SLOW',
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
    return !recoverable;
  }

  /// Deletes the partial payload of a terminally failed file (for example an
  /// integrity mismatch) so it does not hold temporary quota indefinitely.
  Future<void> _discardFailedPayload(_Writer writer) async {
    try {
      final row = _fileRow(writer.transferId, writer.fileId);
      if (row['state'] != 'failed') return;
      await _deleteTemporary(row);
    } catch (_) {
      // Best effort: the row is already failed; explicit cleanup still works.
    }
  }

  void _refreshTransfer(String id, {bool touch = true}) {
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
    if (!touch) {
      final current = _db.select(
        'SELECT state FROM inbox_transfers WHERE id=?',
        [id],
      ).first['state'];
      if (current == state) return;
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

  /// Startup recovery. Only non-terminal files are inspected; journal updates
  /// are applied in one transaction and `updated_at` changes only when a
  /// transfer state actually changes, so history order is preserved.
  Future<void> _recover() async {
    final updates = <(String, List<Object?>)>[];
    final touched = <String>{};
    void update(String transferId, String sql, List<Object?> parameters) {
      updates.add((sql, parameters));
      touched.add(transferId);
    }

    for (final row in _db.select(
      "SELECT * FROM inbox_files WHERE state NOT IN ('offered','rejected','cancelled','failed','committed','expired')",
    )) {
      final state = row['state'] as String;
      final transferId = row['transfer_id'] as String;
      final fileId = row['file_id'] as String;
      try {
        final file = _fileSnapshot(row);
        final temporary = File(_temporaryOf(row));
        requireContainedPath(root, temporary.path);
        await validateManagedDirectory(root, temporary.parent);
        if (state == 'committing') {
          final stored = row['final_path'] as String?;
          if (stored == null) {
            throw const StorageException(
              'RECOVERY_INCONSISTENT',
              'Commit target missing.',
            );
          }
          if (stored.startsWith('r:') && receivedRoot == null) {
            // Opened without the received directory this commit targets:
            // leave the intent for a later open that has it.
            continue;
          }
          final finalPath = _finalAbs(stored);
          final target = File(finalPath);
          final targetBase = stored.startsWith('r:') ? receivedRoot! : root;
          await validateManagedDirectory(targetBase, target.parent);
          // The temporary still existing means the rename did not happen; the
          // target may then be the empty reservation of the user-visible name.
          final temporaryKind = await FileSystemEntity.type(
            temporary.path,
            followLinks: false,
          );
          final renamed = temporaryKind == FileSystemEntityType.notFound;
          final candidate = renamed ? target : temporary;
          await ensurePlainFile(candidate);
          if (await candidate.length() != file.manifest.sizeBytes ||
              await hashFileIsolated(candidate) != file.manifest.sha256) {
            throw const StorageException(
              'RECOVERY_INCONSISTENT',
              'Commit candidate failed verification.',
            );
          }
          if (!renamed) {
            final targetKind = await FileSystemEntity.type(
              finalPath,
              followLinks: false,
            );
            if (targetKind != FileSystemEntityType.notFound &&
                (targetKind != FileSystemEntityType.file ||
                    await target.length() != 0)) {
              throw const StorageException(
                'DESTINATION_EXISTS',
                'Existing result will not be overwritten.',
              );
            }
            await temporary.rename(finalPath);
          }
          update(
            transferId,
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
          update(
            transferId,
            "UPDATE inbox_files SET state='paused',error_code=? WHERE transfer_id=? AND file_id=?",
            [cause, transferId, fileId],
          );
        }
      } catch (error) {
        final code = error is StorageException
            ? error.code
            : 'RECOVERY_INCONSISTENT';
        update(
          transferId,
          "UPDATE inbox_files SET state='failed',error_code=? WHERE transfer_id=? AND file_id=?",
          [code, transferId, fileId],
        );
      }
    }
    // Committed results can disappear (manual deletion, interrupted restore,
    // power loss before the directory entry reached disk). Report, never crash.
    for (final row in _db.select(
      "SELECT transfer_id,file_id,final_path,error_code FROM inbox_files WHERE state='committed'",
    )) {
      final path = _resolvedFinalPath(row['final_path'] as String?);
      final present =
          path != null &&
          await FileSystemEntity.type(path, followLinks: false) ==
              FileSystemEntityType.file;
      final flagged = row['error_code'] == 'FILE_MISSING';
      if (present == !flagged) continue;
      updates.add((
        'UPDATE inbox_files SET error_code=? WHERE transfer_id=? AND file_id=?',
        [present ? null : 'FILE_MISSING', row['transfer_id'], row['file_id']],
      ));
    }
    await _deleteOrphanStaging();
    journalTransaction(_db, () {
      for (final (sql, parameters) in updates) {
        _db.execute(sql, parameters);
      }
      final pending = _db
          .select(
            "SELECT id FROM inbox_transfers WHERE state NOT IN ('completed','partially_completed','rejected','cancelled','failed','expired')",
          )
          .map((row) => row['id'] as String);
      for (final id in {...touched, ...pending}) {
        _refreshTransfer(id, touch: false);
      }
    });
  }

  static final _stagingName = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.part$',
  );

  /// A staging part without a journal row cannot be resumed (its durable
  /// offset is unknown), for example after a journal was quarantined. Only
  /// files with the store's own `<uuid>.part` name are removed.
  Future<void> _deleteOrphanStaging() async {
    final referenced = {
      for (final row in _db.select('SELECT incarnation FROM inbox_files'))
        '${row['incarnation']}.part',
    };
    final staging = Directory(p.join(root.path, '.staging'));
    await for (final entity in staging.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is! File ||
          !_stagingName.hasMatch(name) ||
          referenced.contains(name)) {
        continue;
      }
      try {
        await entity.delete();
      } on FileSystemException {
        // Left for the budget to account as an orphan claim.
      }
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
