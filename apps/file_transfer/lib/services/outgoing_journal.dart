import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:transfer_core/transfer_core.dart';

/// Local source-side journal. A remote snapshot is evidence from the Sink;
/// local socket progress is never promoted to a committed receipt.
class OutgoingJob {
  OutgoingJob({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.manifest,
    required this.createdAt,
    this.remoteId,
    this.snapshot,
    this.localState = 'queued',
    this.detail,
    this.detailCode,
    List<String>? detailArgs,
    this.messageText,
  }) : detailArgs = detailArgs ?? const [];

  final String id;
  final String peerId;
  final String peerName;
  final TransferManifest manifest;
  final DateTime createdAt;
  String? remoteId;
  TransferSnapshot? snapshot;
  String localState;

  /// Legacy, already-localized explanation from journals written by 1.0.
  /// New code stores [detailCode] + [detailArgs] and translates on display,
  /// so the history follows the current language.
  String? detail;
  String? detailCode;
  List<String> detailArgs;

  void setDetail(String? code, [List<Object?> args = const []]) {
    detailCode = code;
    detailArgs = [for (final arg in args) '$arg'];
    detail = null;
  }

  bool get hasDetail => detailCode != null || detail != null;

  /// Text of a message job (≤ 64 KiB), kept so history can show it after
  /// the prepared copy is cleaned up.
  final String? messageText;

  bool get isTerminal =>
      localState == 'completed' ||
      localState == 'cancelled' ||
      localState == 'rejected' ||
      localState == 'expired' ||
      localState == 'failed' ||
      localState == 'partially_completed';

  Map<String, dynamic> toJson() => {
    'id': id,
    'peerId': peerId,
    'peerName': peerName,
    'manifest': manifest.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'remoteId': remoteId,
    'snapshot': snapshot?.toJson(),
    'localState': localState,
    if (detail != null) 'detail': detail,
    if (detailCode != null) 'detailCode': detailCode,
    if (detailArgs.isNotEmpty) 'detailArgs': detailArgs,
    if (messageText != null) 'messageText': messageText,
  };

  factory OutgoingJob.fromJson(Map<String, dynamic> json) => OutgoingJob(
    id: json['id'] as String,
    peerId: json['peerId'] as String,
    peerName: json['peerName'] as String,
    manifest: TransferManifest.fromJson(
      json['manifest'] as Map<String, dynamic>,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    remoteId: json['remoteId'] as String?,
    snapshot: json['snapshot'] == null
        ? null
        : TransferSnapshot.fromJson(json['snapshot'] as Map<String, dynamic>),
    localState: json['localState'] as String,
    detail: json['detail'] as String?,
    detailCode: json['detailCode'] as String?,
    detailArgs: (json['detailArgs'] as List?)?.map((e) => '$e').toList(),
    messageText: json['messageText'] as String?,
  );
}

class OutgoingJournal {
  OutgoingJournal(Directory root) {
    root.createSync(recursive: true);
    // Shared versioned opener: WAL + FULL sync, integrity check, refuses a
    // journal written by a newer app version (JOURNAL_TOO_NEW).
    _db = openVersionedJournal(
      File(p.join(root.path, 'outgoing.sqlite3')),
      version: schemaVersion,
      migrate: (db, from) => db.execute(
        'CREATE TABLE IF NOT EXISTS jobs ('
        'id TEXT PRIMARY KEY, payload TEXT NOT NULL, created TEXT NOT NULL)',
      ),
    );
  }

  late final Database _db;

  /// Schema version written to PRAGMA user_version (the table layout itself
  /// is unchanged since 1.0; versioning protects against downgrades).
  static const schemaVersion = 1;

  /// Number of rows that could not be read during the last [recover]. Such
  /// rows are left untouched (never deleted automatically) and skipped.
  int skippedRows = 0;

  /// Jobs that were running when the app closed are paused with the detail
  /// code `interruptedOnClose` (translated on display). [interruptedDetail]
  /// is accepted for compatibility and ignored.
  List<OutgoingJob> recover({String? interruptedDetail}) {
    skippedRows = 0;
    final result = <OutgoingJob>[];
    for (final row in _db.select(
      'SELECT payload FROM jobs ORDER BY created DESC',
    )) {
      try {
        result.add(
          OutgoingJob.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // One unreadable row (e.g. validation tightened in an update) must
        // not prevent the app from starting.
        skippedRows++;
      }
    }
    for (final job in result) {
      if (!job.isTerminal &&
          job.localState != 'cancelling' &&
          job.localState != 'failed') {
        job.localState = 'paused';
        job.setDetail('interruptedOnClose');
        save(job);
      }
    }
    return result;
  }

  void save(OutgoingJob job) => _db.execute(
    'INSERT INTO jobs(id,payload,created) VALUES(?,?,?) '
    'ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
    [job.id, jsonEncode(job.toJson()), job.createdAt.toUtc().toIso8601String()],
  );

  void delete(String id) => _db.execute('DELETE FROM jobs WHERE id=?', [id]);

  /// Removes journal records (retention). Prepared copies are not touched.
  void deleteAll(Iterable<String> ids) {
    for (final id in ids) {
      delete(id);
    }
  }

  void close() => _db.close();
}
