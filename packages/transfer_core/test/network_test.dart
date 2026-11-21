import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:transfer_core/src/models.dart';
import 'package:transfer_core/src/network/core_client.dart';
import 'package:transfer_core/src/network/core_host.dart';
import 'package:transfer_core/src/network/network_error.dart';
import 'package:transfer_core/src/network/pinned_http_client.dart';
import 'package:transfer_core/src/security/device_identity.dart';
import 'package:transfer_core/src/security/secret_store.dart';
import 'package:transfer_core/src/security/trusted_peer_store.dart';
import 'package:transfer_core/src/storage/durable_inbox.dart';

void main() {
  late DeviceIdentity receiverIdentity;
  late DeviceIdentity senderIdentity;
  setUpAll(() async {
    receiverIdentity = await DeviceIdentity.generate(displayName: 'Receiver');
    senderIdentity = await DeviceIdentity.generate(displayName: 'Sender');
  });

  late Directory temp;
  late DurableInbox inbox;
  late TrustedPeerStore receiverPeers;
  late TrustedPeerStore senderPeers;
  late CoreHost host;
  late CoreClient client;
  late Uri endpoint;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('transfer-network-');
    inbox = await DurableInbox.open(
      Directory('${temp.path}/inbox'),
      checkpointBytes: 65536,
    );
    receiverPeers = TrustedPeerStore(MemorySecretStore());
    senderPeers = TrustedPeerStore(MemorySecretStore());
    host = CoreHost(
      identity: receiverIdentity,
      peers: receiverPeers,
      inbox: inbox,
    );
    endpoint = await host.start();
    client = CoreClient(
      endpoint: endpoint,
      serverPin: receiverIdentity.serverPin,
    );
  });

  tearDown(() async {
    client.close();
    await host.close();
    await inbox.close();
    await receiverPeers.close();
    await senderPeers.close();
    await temp.delete(recursive: true);
  });

  Future<void> pair() async {
    final invite = host.createInvite();
    final pending = await client.requestPairing(
      invite,
      identity: senderIdentity,
      peers: senderPeers,
    );
    expect(
      await client.completePairing(
        identity: senderIdentity,
        peers: senderPeers,
      ),
      isNull,
    );
    await host.approvePairing(pending.requestId);
    final peer = await client.completePairing(
      identity: senderIdentity,
      peers: senderPeers,
    );
    expect(peer?.peerId, receiverIdentity.peerId);
    expect(
      receiverPeers.authenticate(peer!.outgoingToken)?.peerId,
      senderIdentity.peerId,
    );
    expect(
      senderPeers
          .authenticate(
            receiverPeers.byId(senderIdentity.peerId)!.outgoingToken,
          )
          ?.peerId,
      receiverIdentity.peerId,
    );
  }

  Future<(File, TransferSnapshot)> offerBytes(
    List<int> bytes, {
    String requestId = 'offer-1',
  }) async {
    final file = File('${temp.path}/source.bin');
    await file.writeAsBytes(bytes, flush: true);
    final offer = await client.offer(
      TransferManifest(
        requestId: requestId,
        files: [
          FileManifest(
            fileId: 'file-1',
            displayName: 'source.bin',
            sizeBytes: bytes.length,
            sha256: sha256.convert(bytes).toString(),
          ),
        ],
      ),
    );
    return (file, offer);
  }

  test('real TLS rejects the wrong pinned identity before any authenticated operation', () async {
    final wrong = CoreClient(
      endpoint: endpoint,
      serverPin: senderIdentity.serverPin,
    );
    await expectLater(
      wrong.capabilities(),
      throwsA(anyOf(isA<HandshakeException>(), isA<NetworkException>())),
    );
    expect(inbox.list(), isEmpty);
    wrong.close();
  });

  test(
    'pairing retry survives client restart and requires manual acceptance',
    () async {
      final invite = host.createInvite();
      final request = await client.requestPairing(
        invite,
        identity: senderIdentity,
        peers: senderPeers,
      );
      client.close();
      client = CoreClient(
        endpoint: endpoint,
        serverPin: receiverIdentity.serverPin,
      );
      final retried = await client.requestPairing(
        invite,
        identity: senderIdentity,
        peers: senderPeers,
      );
      expect(retried.requestId, request.requestId);
      expect(host.pendingPairings.length, 1);
      await expectLater(
        client.capabilities(),
        throwsA(
          isA<NetworkException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
      await host.approvePairing(request.requestId);
      final peer = await client.completePairing(
        identity: senderIdentity,
        peers: senderPeers,
      );
      expect(peer, isNotNull);
      expect((await client.capabilities())['canPullClient'], isFalse);
    },
  );

  test('expired offer survives TLS serialization and never authorizes payload bytes', () async {
    client.close();
    await host.close();
    await inbox.close();
    var mono = Duration.zero;
    inbox = await DurableInbox.open(
      Directory('${temp.path}/inbox'),
      wallClock: () => DateTime.utc(2026, 11, 21),
      monotonicClock: () => mono,
    );
    host = CoreHost(
      identity: receiverIdentity,
      peers: receiverPeers,
      inbox: inbox,
    );
    endpoint = await host.start();
    client = CoreClient(
      endpoint: endpoint,
      serverPin: receiverIdentity.serverPin,
    );
    await pair();
    final (source, offered) = await offerBytes([1, 2, 3]);
    expect(offered.offerExpiresAt, DateTime.utc(2026, 11, 21, 0, 2));
    mono = const Duration(seconds: 120);
    final expired = await client.transferStatus(offered.id);
    expect(expired.state, TransferState.expired);
    expect(expired.files.single.errorCode, 'OFFER_EXPIRED');
    final repeated = await client.offer(offered.manifest);
    expect(repeated.id, offered.id);
    expect(repeated.state, TransferState.expired);
    await expectLater(
      client.uploadFile(
        transferId: offered.id,
        fileId: 'file-1',
        source: source,
      ),
      throwsA(
        isA<NetworkException>().having(
          (error) => error.statusCode,
          'status',
          403,
        ),
      ),
    );
    expect(inbox.status(offered.id).durableBytes, 0);
    expect(await source.readAsBytes(), [1, 2, 3]);
    expect(
      await Directory('${temp.path}/inbox/.staging').list().toList(),
      isEmpty,
    );
  });

  test('consent gates streaming, full transfer is verified and retry does not duplicate files', () async {
    await pair();
    final bytes = List<int>.generate(1024 * 1024 + 137, (i) => i % 251);
    final (source, offered) = await offerBytes(bytes);
    await expectLater(
      client.uploadFile(
        transferId: offered.id,
        fileId: 'file-1',
        source: source,
      ),
      throwsA(
        isA<NetworkException>().having((e) => e.statusCode, 'status', 403),
      ),
    );
    expect(inbox.status(offered.id).files.single.offset, 0);
    await host.acceptTransfer(offered.id);
    final result = await client.uploadFile(
      transferId: offered.id,
      fileId: 'file-1',
      source: source,
    );
    expect(result.state, FileState.committed);
    expect(
      result.finalPath,
      isNull,
      reason: 'Local server paths must never leak over wire',
    );
    final local = inbox.status(offered.id).files.single;
    expect(await File(local.finalPath!).readAsBytes(), bytes);
    final repeated = await client.uploadFile(
      transferId: offered.id,
      fileId: 'file-1',
      source: source,
    );
    expect(repeated.state, FileState.committed);
    expect(inbox.list().length, 1);
  });

  test(
    'truncated HTTPS stream recovers its durable prefix across host restart',
    () async {
      await pair();
      final bytes = List<int>.generate(1024 * 1024 + 7, (i) => (i * 3) % 251);
      final (source, offered) = await offerBytes(bytes);
      await host.acceptTransfer(offered.id);
      final position = await client.headFile(offered.id, 'file-1');
      final raw = createPinnedHttpClient(endpoint, receiverIdentity.serverPin);
      final request = await raw.openUrl(
        'PATCH',
        endpoint.replace(path: '/v1/transfers/${offered.id}/files/file-1/data'),
      );
      request.headers.set('Authorization', 'Bearer ${client.credential}');
      request.headers.set('Tus-Resumable', '1.0.0');
      request.headers.set('Upload-Offset', '0');
      request.headers.set('X-Storage-Incarnation', position.incarnation);
      request.headers.contentType = ContentType(
        'application',
        'offset+octet-stream',
      );
      request.contentLength = bytes.length;
      unawaited(request.done.then<void>((_) {}, onError: (Object _) {}));
      request.add(bytes.sublist(0, 256 * 1024));
      await request.flush();
      await _until(() => inbox.status(offered.id).files.single.offset >= 65536);
      request.abort();
      raw.close(force: true);
      await _until(
        () => inbox.status(offered.id).files.single.state == FileState.paused,
      );
      final persistedOffset = inbox.status(offered.id).files.single.offset;
      expect(persistedOffset, greaterThan(0));
      expect(persistedOffset, lessThan(bytes.length));
      final oldPort = host.port;
      client.close();
      await host.close();
      await inbox.close();
      inbox = await DurableInbox.open(
        Directory('${temp.path}/inbox'),
        checkpointBytes: 65536,
      );
      host = CoreHost(
        identity: receiverIdentity,
        peers: receiverPeers,
        inbox: inbox,
      );
      endpoint = await host.start(port: oldPort);
      client = CoreClient.forPeer(
        senderPeers.byId(receiverIdentity.peerId)!,
        endpoint: endpoint,
      );
      expect(
        (await client.headFile(offered.id, 'file-1')).offset,
        persistedOffset,
      );
      await client.resume(offered.id);
      await client.uploadFile(
        transferId: offered.id,
        fileId: 'file-1',
        source: source,
      );
      expect(
        await File(inbox.status(offered.id).files.single.finalPath!)
            .readAsBytes(),
        bytes,
      );
    },
  );

  test(
    'bad offset cannot overwrite data and revoked credentials cannot resume',
    () async {
      await pair();
      final (source, offered) = await offerBytes(List.filled(1024, 42));
      await host.acceptTransfer(offered.id);
      final position = await client.headFile(offered.id, 'file-1');
      final raw = createPinnedHttpClient(endpoint, receiverIdentity.serverPin);
      final request = await raw.openUrl(
        'PATCH',
        endpoint.replace(path: '/v1/transfers/${offered.id}/files/file-1/data'),
      );
      request.headers.set('Authorization', 'Bearer ${client.credential}');
      request.headers.set('Tus-Resumable', '1.0.0');
      request.headers.set('Upload-Offset', '1');
      request.headers.set('X-Storage-Incarnation', position.incarnation);
      request.headers.contentType = ContentType(
        'application',
        'offset+octet-stream',
      );
      request.contentLength = 0;
      final response = await request.close();
      expect(response.statusCode, 409);
      await response.drain<void>();
      expect(inbox.status(offered.id).files.single.offset, 0);
      raw.close(force: true);
      await host.revoke(senderIdentity.peerId);
      await expectLater(
        client.uploadFile(
          transferId: offered.id,
          fileId: 'file-1',
          source: source,
        ),
        throwsA(
          isA<NetworkException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
    },
  );

  test(
    'source cannot clear a pause explicitly owned by the receiver',
    () async {
      await pair();
      final (source, offered) = await offerBytes(List.filled(1024, 3));
      await host.acceptTransfer(offered.id);
      await inbox.pause(offered.id);
      final status = await client.resume(offered.id);
      expect(status.pausedBySink, isTrue);
      await expectLater(
        client.uploadFile(
          transferId: offered.id,
          fileId: 'file-1',
          source: source,
        ),
        throwsA(
          isA<NetworkException>().having((e) => e.statusCode, 'status', 409),
        ),
      );
    },
  );

  test('HTTP redirect never forwards credentials to another origin', () async {
    var unwantedRequests = 0;
    final target = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      senderIdentity.serverContext(),
    );
    target.listen((req) {
      unwantedRequests++;
      req.response.close();
    });
    final redirector = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      receiverIdentity.serverContext(),
    );
    redirector.listen((req) async {
      req.response.statusCode = 302;
      req.response.headers.set(
        'Location',
        'https://127.0.0.1:${target.port}/v1/capabilities',
      );
      await req.response.close();
    });
    final redirectClient = CoreClient(
      endpoint: Uri.parse('https://127.0.0.1:${redirector.port}'),
      serverPin: receiverIdentity.serverPin,
    );
    await expectLater(
      redirectClient.capabilities(),
      throwsA(
        isA<NetworkException>().having((e) => e.statusCode, 'status', 302),
      ),
    );
    expect(unwantedRequests, 0);
    redirectClient.close();
    await redirector.close(force: true);
    await target.close(force: true);
  });

  test('oversized JSON is refused before creating pairing state', () async {
    final raw = createPinnedHttpClient(endpoint, receiverIdentity.serverPin);
    final request = await raw.postUrl(
      endpoint.replace(path: '/v1/pairing/requests'),
    );
    request.headers.contentType = ContentType.json;
    final body = utf8.encode(jsonEncode({'payload': 'x' * 20000}));
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close();
    expect(response.statusCode, 413);
    await response.drain<void>();
    expect(host.pendingPairings, isEmpty);
    raw.close(force: true);
  });

  test(
    'empty file still requires acceptance and reaches verified commit',
    () async {
      await pair();
      final (source, offered) = await offerBytes([]);
      await host.acceptTransfer(offered.id);
      final result = await client.uploadFile(
        transferId: offered.id,
        fileId: 'file-1',
        source: source,
      );
      expect(result.state, FileState.committed);
      expect(
        await File(inbox.status(offered.id).files.single.finalPath!).length(),
        0,
      );
    },
  );

  test(
    'revoking a peer stops an in-flight writer without waiting for more bytes',
    () async {
      await pair();
      final bytes = List<int>.filled(1024 * 1024, 7);
      final (_, offered) = await offerBytes(bytes);
      await host.acceptTransfer(offered.id);
      final position = await client.headFile(offered.id, 'file-1');
      final raw = createPinnedHttpClient(endpoint, receiverIdentity.serverPin);
      final request = await raw.openUrl(
        'PATCH',
        endpoint.replace(path: '/v1/transfers/${offered.id}/files/file-1/data'),
      );
      request.headers.set('Authorization', 'Bearer ${client.credential}');
      request.headers.set('Tus-Resumable', '1.0.0');
      request.headers.set('Upload-Offset', '0');
      request.headers.set('X-Storage-Incarnation', position.incarnation);
      request.headers.contentType = ContentType(
        'application',
        'offset+octet-stream',
      );
      request.contentLength = bytes.length;
      unawaited(request.done.then<void>((_) {}, onError: (Object _) {}));
      request.add(bytes.sublist(0, 131072));
      await request.flush();
      await _until(() => inbox.status(offered.id).files.single.offset >= 65536);
      await host
          .revoke(senderIdentity.peerId)
          .timeout(const Duration(seconds: 3));
      expect(inbox.status(offered.id).files.single.state, FileState.cancelled);
      expect(inbox.status(offered.id).files.single.finalPath, isNull);
      request.abort();
      raw.close(force: true);
    },
  );
}

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Expected state did not arrive');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
