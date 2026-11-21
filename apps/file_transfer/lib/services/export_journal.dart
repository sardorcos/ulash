import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:transfer_core/transfer_core.dart' show StorageException;
import 'package:uuid/uuid.dart';

/// A system export is independent of the network's committed receipt.
/// A missing native callback is not evidence that a provider did not copy data.
enum ExportState { exporting, exported, cancelled, failed, unknown }

class ExportRecord {
  const ExportRecord({
    required this.id,
    required this.transferId,
    required this.fileId,
    required this.state,
    required this.createdAt,
    this.destinationLabel,
    this.platformReference,
    this.errorCode,
  });

  final String id;
  final String transferId;
  final String fileId;
  final ExportState state;
  final DateTime createdAt;
  final String? destinationLabel;
  final String? platformReference;
  final String? errorCode;
}

class ExportJournal {
  ExportJournal(Directory root) {
    root.createSync(recursive: true);
    _db = sqlite3.open(p.join(root.path, 'exports.sqlite3'));
    _db.execute('PRAGMA busy_timeout=5000');
    _db.execute('PRAGMA journal_mode=WAL');
    _db.execute('PRAGMA synchronous=FULL');
    final check = _db.select('PRAGMA quick_check');
    if (check.isEmpty || check.first.values.first != 'ok') {
      _db.close();
      throw const StorageException('JOURNAL_CORRUPT', 'Export journal damaged');
    }
    _db.execute('''
      CREATE TABLE IF NOT EXISTS exports (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        id TEXT NOT NULL UNIQUE,
        transfer_id TEXT NOT NULL, file_id TEXT NOT NULL,
        state TEXT NOT NULL, created_at TEXT NOT NULL,
        destination_label TEXT, platform_reference TEXT, error_code TEXT
      );
      CREATE INDEX IF NOT EXISTS exports_file ON exports(transfer_id,file_id,sequence);
    ''');
    // No automatic retry: a destination may already contain the exported copy.
    _db.execute(
      "UPDATE exports SET state='unknown', error_code='EXPORT_INTERRUPTED' "
      "WHERE state='exporting'",
    );
  }

  late final Database _db;

  ExportRecord begin(String transferId, String fileId) {
    final id = const Uuid().v4();
    final created = DateTime.now().toUtc();
    _db.execute(
      'INSERT INTO exports(id,transfer_id,file_id,state,created_at) '
      'VALUES(?,?,?,?,?)',
      [id, transferId, fileId, 'exporting', created.toIso8601String()],
    );
    return _byId(id);
  }

  ExportRecord finish(
    String id,
    ExportState state, {
    String? destinationLabel,
    String? platformReference,
    String? errorCode,
  }) {
    final current = _byId(id);
    if (current.state != ExportState.exporting ||
        state == ExportState.exporting) {
      throw StateError(
        'Only an in-progress export can receive one final result.',
      );
    }
    if (state == ExportState.exported &&
        (destinationLabel == null || destinationLabel.trim().isEmpty)) {
      throw ArgumentError('An exported result needs an actual destination.');
    }
    _db.execute(
      'UPDATE exports SET state=?,destination_label=?,platform_reference=?,error_code=? '
      'WHERE id=? AND state=?',
      [
        state.name,
        destinationLabel,
        platformReference,
        errorCode,
        id,
        'exporting',
      ],
    );
    return _byId(id);
  }

  ExportRecord? latest(String transferId, String fileId) {
    final rows = _db.select(
      'SELECT * FROM exports WHERE transfer_id=? AND file_id=? '
      'ORDER BY sequence DESC LIMIT 1',
      [transferId, fileId],
    );
    return rows.isEmpty ? null : _record(rows.first);
  }

  ExportRecord? lastSuccess(String transferId, String fileId) {
    final rows = _db.select(
      "SELECT * FROM exports WHERE transfer_id=? AND file_id=? AND state='exported' "
      'ORDER BY sequence DESC LIMIT 1',
      [transferId, fileId],
    );
    return rows.isEmpty ? null : _record(rows.first);
  }

  ExportRecord _byId(String id) {
    final rows = _db.select('SELECT * FROM exports WHERE id=?', [id]);
    if (rows.isEmpty) throw StateError('Unknown export.');
    return _record(rows.first);
  }

  ExportRecord _record(Row row) => ExportRecord(
    id: row['id'] as String,
    transferId: row['transfer_id'] as String,
    fileId: row['file_id'] as String,
    state: ExportState.values.byName(row['state'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
    destinationLabel: row['destination_label'] as String?,
    platformReference: row['platform_reference'] as String?,
    errorCode: row['error_code'] as String?,
  );

  /// Removes export history of a deleted transfer.
  void deleteTransfer(String transferId) =>
      _db.execute('DELETE FROM exports WHERE transfer_id=?', [transferId]);

  void close() => _db.close();
}
