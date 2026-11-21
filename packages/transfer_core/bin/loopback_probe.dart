import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:transfer_core/src/models.dart';
import 'package:transfer_core/src/network/core_client.dart';
import 'package:transfer_core/src/network/core_host.dart';
import 'package:transfer_core/src/network/network_error.dart';
import 'package:transfer_core/src/network/pinned_http_client.dart';
import 'package:transfer_core/src/security/device_identity.dart';
import 'package:transfer_core/src/security/secret_store.dart';
import 'package:transfer_core/src/security/trusted_peer_store.dart';
import 'package:transfer_core/src/storage/durable_inbox.dart';
import 'package:uuid/uuid.dart';

/// An actual HTTPS + SQLite + disk probe, not a UI progress simulation.
/// Identities and credentials live ONLY in process memory for this explicit
/// temporary test session. No private key or token is written to the output.
Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    stdout.writeln(
      'dart run bin/loopback_probe.dart [--mib 16] [--output /empty/directory]',
    );
    stdout.writeln(
      'Size: 8–10240 MiB. Files and result.json are retained for independent verification.',
    );
    return;
  }
  try {
    final configuration = _parseArguments(arguments);
    final result = await _run(configuration.$1, configuration.$2);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  } catch (error, trace) {
    final code = error is NetworkException
        ? error.code
        : error is StorageException
        ? error.code
        : error is FormatException
        ? 'INVALID_ARGUMENT'
        : 'PROBE_FAILED';
    stderr.writeln(jsonEncode({'status': 'failed', 'code': code}));
    // Stack traces have source locations, not secret-bearing HTTP bodies.
    stderr.writeln(trace);
    exitCode = 1;
  }
}

(int, String?) _parseArguments(List<String> args) {
  var mib = 16;
  String? output;
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if ((argument != '--mib' && argument != '--output') ||
        index + 1 >= args.length) {
      throw const FormatException('Expected --mib N or --output DIRECTORY');
    }
    final value = args[++index];
    if (argument == '--mib') {
      mib = int.tryParse(value) ?? -1;
    } else {
      output = value;
    }
  }
  if (mib < 8 || mib > 10240) {
    throw const FormatException('Probe size must be 8–10240 MiB');
  }
  return (mib, output);
}

Future<Map<String, dynamic>> _run(int mib, String? outputPath) async {
  const oneMiB = 1024 * 1024;
  const checkpoint = 4 * oneMiB;
  final output = outputPath == null
      ? await Directory.systemTemp.createTemp('file-transfer-probe-')
      : Directory(p.absolute(outputPath));
  await output.create(recursive: true);
  final source = File(p.join(output.path, 'source.bin'));
  final reportFile = File(p.join(output.path, 'result.json'));
  final inboxRoot = Directory(p.join(output.path, 'receiver'));
  if (await source.exists() ||
      await reportFile.exists() ||
      await inboxRoot.exists()) {
    throw const FormatException(
      'Use a fresh output directory; existing files are not overwritten',
    );
  }
  final totalBytes = mib * oneMiB;
  final started = Stopwatch()..start();
  final buffer = Uint8List.fromList(
    List<int>.generate(oneMiB, (i) => (i * 37 + 19) % 251),
  );
  final handle = await source.open(mode: FileMode.write);
  try {
    for (var index = 0; index < mib; index++) {
      await handle.writeFrom(buffer);
    }
    await handle.flush();
  } finally {
    await handle.close();
  }
  final sourceHash = (await sha256.bind(source.openRead()).first).toString();
  final senderSecrets = MemorySecretStore();
  final receiverSecrets = MemorySecretStore();
  final senderPeers = TrustedPeerStore(senderSecrets);
  final receiverPeers = TrustedPeerStore(receiverSecrets);
  CoreHost? host;
  DurableInbox? inbox;
  CoreClient? client;
  HttpClient? raw;
  try {
    final senderIdentity = await DeviceIdentity.loadOrCreate(
      senderSecrets,
      displayName: 'Probe sender',
    );
    final receiverIdentity = await DeviceIdentity.loadOrCreate(
      receiverSecrets,
      displayName: 'Probe receiver',
    );
    inbox = await DurableInbox.open(inboxRoot, checkpointBytes: checkpoint);
    host = CoreHost(
      identity: receiverIdentity,
      peers: receiverPeers,
      inbox: inbox,
    );
    var endpoint = await host.start();
    client = CoreClient(
      endpoint: endpoint,
      serverPin: receiverIdentity.serverPin,
    );
    final invitation = host.createInvite();
    final pending = await client.requestPairing(
      invitation,
      identity: senderIdentity,
      peers: senderPeers,
    );
    if (await client.completePairing(
          identity: senderIdentity,
          peers: senderPeers,
        ) !=
        null) {
      throw StateError(
        'Pairing unexpectedly succeeded without manual approval',
      );
    }
    await host.approvePairing(pending.requestId);
    final peer = await client.completePairing(
      identity: senderIdentity,
      peers: senderPeers,
    );
    if (peer == null) throw StateError('Approved pairing did not complete');
    final fileId = const Uuid().v4();
    final transfer = await client.offer(
      TransferManifest(
        requestId: const Uuid().v4(),
        files: [
          FileManifest(
            fileId: fileId,
            displayName: 'source.bin',
            sizeBytes: totalBytes,
            sha256: sourceHash,
          ),
        ],
      ),
    );
    var consentChecked = false;
    try {
      await client.headFile(transfer.id, fileId);
    } on NetworkException catch (error) {
      consentChecked = error.statusCode == 403;
    }
    if (!consentChecked) {
      throw StateError('Data endpoint was not consent-gated');
    }
    await host.acceptTransfer(transfer.id);
    final position = await client.headFile(transfer.id, fileId);
    raw = createPinnedHttpClient(endpoint, receiverIdentity.serverPin);
    final request = await raw.openUrl(
      'PATCH',
      endpoint.replace(path: '/v1/transfers/${transfer.id}/files/$fileId/data'),
    );
    request.headers.set('Authorization', 'Bearer ${client.credential}');
    request.headers.set('Tus-Resumable', '1.0.0');
    request.headers.set('Upload-Offset', '0');
    request.headers.set('X-Storage-Incarnation', position.incarnation);
    request.headers.contentType = ContentType(
      'application',
      'offset+octet-stream',
    );
    request.contentLength = totalBytes;
    unawaited(request.done.then<void>((_) {}, onError: (Object _) {}));
    // Send > one durable checkpoint, then interrupt a deliberately incomplete
    // Content-Length body. This is a genuine TCP/TLS interruption.
    await request.addStream(source.openRead(0, checkpoint + oneMiB ~/ 2));
    await request.flush();
    final firstInbox = inbox;
    await _until(
      () => firstInbox.status(transfer.id).files.single.offset >= checkpoint,
    );
    request.abort();
    raw.close(force: true);
    raw = null;
    await _until(
      () =>
          firstInbox.status(transfer.id).files.single.state == FileState.paused,
    );
    final beforeRestart = firstInbox.status(transfer.id).files.single.offset;
    if (beforeRestart < checkpoint || beforeRestart >= totalBytes) {
      throw StateError('Interruption did not produce a valid durable prefix');
    }
    client.close();
    client = null;
    await host.close();
    host = null;
    await inbox.close();
    inbox = null;
    // Open the receiver from its actual SQLite and .part files. A new listener
    // address is allowed, while the pinned device identity remains unchanged.
    inbox = await DurableInbox.open(inboxRoot, checkpointBytes: checkpoint);
    host = CoreHost(
      identity: receiverIdentity,
      peers: receiverPeers,
      inbox: inbox,
    );
    endpoint = await host.start();
    client = CoreClient.forPeer(peer, endpoint: endpoint);
    final recovered = await client.headFile(transfer.id, fileId);
    if (recovered.offset != beforeRestart) {
      throw StateError('Durable offset changed after restart');
    }
    await client.resume(transfer.id);
    await client.uploadFile(
      transferId: transfer.id,
      fileId: fileId,
      source: source,
    );
    final received = inbox.status(transfer.id).files.single;
    if (received.state != FileState.committed || received.finalPath == null) {
      throw StateError('Receiver did not report verified commit');
    }
    final sink = File(received.finalPath!);
    final sinkHash = (await sha256.bind(sink.openRead()).first).toString();
    final sinkBytes = await sink.length();
    if (sourceHash != sinkHash || totalBytes != sinkBytes) {
      throw StateError('Independent sink reread did not match source');
    }
    final result = <String, dynamic>{
      'status': 'passed',
      'mode': 'foreground HTTPS push with receiver restart and resume',
      'source_path': source.absolute.path,
      'sink_path': sink.absolute.path,
      'size': totalBytes,
      'size_bytes': totalBytes,
      'sha256': sourceHash,
      'source_sha256': sourceHash,
      'sink_sha256': sinkHash,
      'checkpoint_bytes': checkpoint,
      'resumed_from_bytes': recovered.offset,
      'host_restarted': true,
      'manual_pair_approval_checked': true,
      'receiver_consent_checked': consentChecked,
      'receiver_state': received.state.wireName,
      'elapsed_seconds': started.elapsedMilliseconds / 1000,
      'credentials': 'ephemeral memory only; not included in result',
      'report_path': reportFile.absolute.path,
    };
    await reportFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      flush: true,
    );
    return result;
  } finally {
    raw?.close(force: true);
    client?.close();
    await host?.close();
    await inbox?.close();
    await senderPeers.close();
    await receiverPeers.close();
    senderSecrets.clear();
    receiverSecrets.clear();
  }
}

Future<void> _until(bool Function() predicate) async {
  final timer = Stopwatch()..start();
  while (!predicate()) {
    if (timer.elapsed > const Duration(seconds: 15)) {
      throw TimeoutException('Expected durable state did not arrive');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
