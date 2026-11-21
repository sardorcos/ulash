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
  });

  final String id;
  final String peerId;
  final String peerName;
  final TransferManifest manifest;
  final DateTime createdAt;
  String? remoteId;
  TransferSnapshot? snapshot;
  String localState;
  String? detail;

  bool get isTerminal =>
      localState == 'completed' ||
      localState == 'cancelled' ||
      localState == 'rejected' ||
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
    'detail': detail,
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
  );
}

class OutgoingJournal {
  OutgoingJournal(Directory root) {
    root.createSync(recursive: true);
    _db = sqlite3.open(p.join(root.path, 'outgoing.sqlite3'));
    _db.execute('PRAGMA journal_mode=WAL');
    _db.execute('PRAGMA synchronous=FULL');
    _db.execute(
      'CREATE TABLE IF NOT EXISTS jobs ('
      'id TEXT PRIMARY KEY, payload TEXT NOT NULL, created TEXT NOT NULL)',
    );
  }

  late final Database _db;

  List<OutgoingJob> recover() {
    final result = _db
        .select('SELECT payload FROM jobs ORDER BY created DESC')
        .map(
          (row) => OutgoingJob.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
    for (final job in result) {
      if (!job.isTerminal &&
          job.localState != 'cancelling' &&
          job.localState != 'failed') {
        job.localState = 'paused';
        job.detail =
            'Передача остановлена при закрытии приложения. '
            'Нажмите «Продолжить» для проверки состояния у получателя.';
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

  void close() => _db.close();
}
