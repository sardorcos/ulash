import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:transfer_core/src/models.dart';
import 'package:transfer_core/src/network/core_client.dart';
import 'package:transfer_core/src/network/core_host.dart';
import 'package:transfer_core/src/network/network_error.dart';
import 'package:transfer_core/src/security/crypto.dart';
import 'package:transfer_core/src/security/device_identity.dart';
import 'package:transfer_core/src/security/secret_store.dart';
import 'package:transfer_core/src/security/trusted_peer_store.dart';
import 'package:transfer_core/src/storage/durable_inbox.dart';
import 'package:transfer_core/src/storage/durable_outbox.dart';
import 'package:transfer_core/src/storage/storage_support.dart';

Matcher storageCode(String code) =>
    isA<StorageException>().having((error) => error.code, 'code', code);

TypeMatcher<NetworkException> networkCode(String code) =>
    isA<NetworkException>().having((error) => error.code, 'code', code);

FileManifest fileFor(
  List<int> bytes, {
  String id = 'file-1',
  String name = 'photo.jpg',
  String? folder,
}) => FileManifest(
  fileId: id,
  displayName: name,
  sizeBytes: bytes.length,
  sha256: sha256.convert(bytes).toString(),
  relativeDirectory: folder,
);

/// A temp directory under its canonical name. Stores canonicalise their
/// roots (on Windows, `C:\Users\RUNNER~1` becomes `C:\Users\runneradmin`),
/// so expected paths must be built from the same form.
Future<Directory> canonicalTemp(String prefix) async {
  final created = await Directory.systemTemp.createTemp(prefix);
  return Directory(await created.resolveSymbolicLinks());
}

/// Raw HTTP/1.1 exchange over TLS that accepts any certificate: lets tests
/// speak to the host the way a hostile or minimal client would.
Future<SecureSocket> rawTls(Uri endpoint) => SecureSocket.connect(
  endpoint.host,
  endpoint.port,
  onBadCertificate: (_) => true,
  timeout: const Duration(seconds: 5),
);

/// Completes when the peer closes [socket] (or it errors). Collects bytes.
Future<String> untilClosed(Socket socket) {
  // Writes to a socket the host already dropped fail; that is expected.
  socket.done.ignore();
  final bytes = <int>[];
  final done = Completer<String>();
  socket.listen(
    bytes.addAll,
    onDone: () {
      if (!done.isCompleted) done.complete(latin1.decode(bytes));
    },
    onError: (Object _) {
      if (!done.isCompleted) done.complete(latin1.decode(bytes));
    },
    cancelOnError: true,
  );
  return done.future;
}

int statusOf(String response) =>
    int.parse(response.split('\r\n').first.split(' ')[1]);

String bodyOf(String response) {
  final body = response.substring(response.indexOf('\r\n\r\n') + 4);
  if (headerOf(response, 'transfer-encoding')?.toLowerCase() != 'chunked') {
    return body;
  }
  final out = StringBuffer();
  var rest = body;
  while (true) {
    final end = rest.indexOf('\r\n');
    if (end < 0) break;
    final size = int.parse(rest.substring(0, end).trim(), radix: 16);
    if (size == 0) break;
    out.write(rest.substring(end + 2, end + 2 + size));
    rest = rest.substring(end + 4 + size);
  }
  return out.toString();
}

String? headerOf(String response, String name) {
  for (final line in response.split('\r\n').skip(1)) {
    if (line.isEmpty) break;
    final colon = line.indexOf(':');
    if (colon > 0 &&
        line.substring(0, colon).toLowerCase() == name.toLowerCase()) {
      return line.substring(colon + 1).trim();
    }
  }
  return null;
}

void main() {
  late DeviceIdentity receiverIdentity;
  late DeviceIdentity senderIdentity;
  setUpAll(() async {
    receiverIdentity = await DeviceIdentity.generate(displayName: 'Receiver');
    senderIdentity = await DeviceIdentity.generate(displayName: 'Sender');
  });

  group('host and pairing (1.2)', () {
    late Directory temp;
    late DurableInbox inbox;
    late TrustedPeerStore receiverPeers;
    late TrustedPeerStore senderPeers;
    late CoreHost host;
    late CoreClient client;
    late Uri endpoint;

    Future<void> startHost({
      Duration handshakeTimeout = const Duration(seconds: 10),
      Duration requestHeaderTimeout = const Duration(seconds: 10),
      Duration bodyReadDeadline = const Duration(seconds: 5),
      int nearbyRequestsPerMinute = 5,
    }) async {
      host = CoreHost(
        identity: receiverIdentity,
        peers: receiverPeers,
        inbox: inbox,
        handshakeTimeout: handshakeTimeout,
        requestHeaderTimeout: requestHeaderTimeout,
        bodyReadDeadline: bodyReadDeadline,
        nearbyRequestsPerMinute: nearbyRequestsPerMinute,
      );
      endpoint = await host.start();
      client = CoreClient(
        endpoint: endpoint,
        serverPin: receiverIdentity.serverPin,
      );
    }

    Future<void> restartHost({
      Duration handshakeTimeout = const Duration(seconds: 10),
      Duration requestHeaderTimeout = const Duration(seconds: 10),
      Duration bodyReadDeadline = const Duration(seconds: 5),
      int nearbyRequestsPerMinute = 5,
    }) async {
      client.close();
      await host.close();
      await startHost(
        handshakeTimeout: handshakeTimeout,
        requestHeaderTimeout: requestHeaderTimeout,
        bodyReadDeadline: bodyReadDeadline,
        nearbyRequestsPerMinute: nearbyRequestsPerMinute,
      );
    }

    setUp(() async {
      temp = await canonicalTemp('transfer-1-2-');
      inbox = await DurableInbox.open(
        Directory(p.join(temp.path, 'inbox')),
        checkpointBytes: 65536,
      );
      receiverPeers = TrustedPeerStore(MemorySecretStore());
      senderPeers = TrustedPeerStore(MemorySecretStore());
      await startHost();
    });

    tearDown(() async {
      client.close();
      await host.close();
      await inbox.close();
      await receiverPeers.close();
      await senderPeers.close();
      await temp.delete(recursive: true);
    });

    /// Pairs the sender and returns a client authenticated as it.
    Future<CoreClient> pair() async {
      final invite = host.createInvite();
      final pending = await client.requestPairing(
        invite,
        identity: senderIdentity,
        peers: senderPeers,
      );
      await host.approvePairing(pending.requestId);
      final peer = await client.completePairing(
        identity: senderIdentity,
        peers: senderPeers,
      );
      return CoreClient(
        endpoint: endpoint,
        serverPin: receiverIdentity.serverPin,
        credential: peer!.outgoingToken,
      );
    }

    test(
      '40 slow unauthenticated connections do not block a paired peer',
      () async {
        final peer = await pair();
        final attackers = <Socket>[];
        try {
          for (var index = 0; index < 30; index++) {
            try {
              final socket = await rawTls(endpoint);
              unawaited(untilClosed(socket));
              socket.write(
                'POST /v1/pairing/requests HTTP/1.1\r\nHost: x\r\n'
                'Content-Length: 100000\r\n',
              );
              attackers.add(socket);
            } on Object {
              // An older attacker connection may already be evicted.
            }
          }
          for (var index = 0; index < 10; index++) {
            final socket = await Socket.connect(endpoint.host, endpoint.port);
            unawaited(untilClosed(socket));
            attackers.add(socket);
          }
          final elapsed = Stopwatch()..start();
          final capabilities = await peer.capabilities().timeout(
            const Duration(seconds: 5),
          );
          expect(capabilities['supportsFolders'], isTrue);
          final bytes = [1, 2, 3];
          final offer = await peer
              .offer(
                TransferManifest(
                  requestId: 'under-load',
                  files: [fileFor(bytes)],
                ),
              )
              .timeout(const Duration(seconds: 5));
          expect(offer.state, TransferState.offered);
          expect(elapsed.elapsed, lessThan(const Duration(seconds: 5)));
        } finally {
          for (final socket in attackers) {
            socket.destroy();
          }
          peer.close();
        }
      },
    );

    test(
      'a TCP connection that never starts TLS is dropped at the deadline',
      () async {
        await restartHost(handshakeTimeout: const Duration(milliseconds: 300));
        final socket = await Socket.connect(endpoint.host, endpoint.port);
        final elapsed = Stopwatch()..start();
        await untilClosed(socket).timeout(const Duration(seconds: 3));
        expect(elapsed.elapsed, lessThan(const Duration(seconds: 3)));
      },
    );

    test('incomplete request headers are dropped at the deadline', () async {
      await restartHost(
        requestHeaderTimeout: const Duration(milliseconds: 300),
      );
      final socket = await rawTls(endpoint);
      socket.write('GET /v1/hello HTTP/1.1\r\nHost: x\r\n');
      await untilClosed(socket).timeout(const Duration(seconds: 3));
    });

    test(
      'unauthenticated uploads are refused before any body byte is read',
      () async {
        final socket = await rawTls(endpoint);
        socket.write(
          'POST /v1/transfers HTTP/1.1\r\nHost: x\r\n'
          'Content-Type: application/json\r\nContent-Length: 5000\r\n\r\n',
        );
        final response = await untilClosed(socket)
            .timeout(const Duration(seconds: 3));
        expect(statusOf(response), 401);
        socket.destroy();
        expect(inbox.list(), isEmpty);
      },
    );

    test(
      'pairing requests without a live invitation are refused up front',
      () async {
        final socket = await rawTls(endpoint);
        socket.write(
          'POST /v1/pairing/requests HTTP/1.1\r\nHost: x\r\n'
          'Content-Type: application/json\r\nContent-Length: 4000\r\n\r\n',
        );
        final response = await untilClosed(socket)
            .timeout(const Duration(seconds: 3));
        expect(statusOf(response), 401);
        socket.destroy();
        expect(host.pendingPairings, isEmpty);
      },
    );

    test(
      'an authenticated body that trickles past the deadline gets 408',
      () async {
        final peer = await pair();
        peer.close();
        await restartHost(bodyReadDeadline: const Duration(milliseconds: 300));
        final token = senderPeers.byId(receiverIdentity.peerId)!.outgoingToken;
        final socket = await rawTls(endpoint);
        socket.write(
          'POST /v1/transfers HTTP/1.1\r\nHost: x\r\n'
          'Authorization: Bearer $token\r\n'
          'Content-Type: application/json\r\nContent-Length: 5000\r\n\r\n{"a"',
        );
        final response = await untilClosed(socket)
            .timeout(const Duration(seconds: 3));
        expect(statusOf(response), 408);
        expect(bodyOf(response), contains('REQUEST_TIMEOUT'));
        socket.destroy();
      },
    );

    test(
      'hello reveals only protocol versions; certificates use a constant name',
      () async {
        final socket = await rawTls(endpoint);
        expect(socket.peerCertificate!.subject, contains('Ulash'));
        expect(socket.peerCertificate!.subject, isNot(contains('Receiver')));
        socket.write('GET /v1/hello HTTP/1.1\r\nHost: x\r\n\r\n');
        final response = await untilClosed(socket)
            .timeout(const Duration(seconds: 3));
        expect(statusOf(response), 200);
        final json = jsonDecode(bodyOf(response)) as Map<String, dynamic>;
        expect(json, {'protocolMajor': 1, 'protocolMinor': 1});
        socket.destroy();
      },
    );

    test('both screens derive the same six-digit code', () async {
      final invite = host.createInvite();
      await client.requestPairing(
        invite,
        identity: senderIdentity,
        peers: senderPeers,
      );
      final pending = host.pendingPairings.single;
      expect(pending.sas, matches(RegExp(r'^[0-9]{6}$')));
      expect(invite.sasFor(senderIdentity.serverPin), pending.sas);
      // A different joining key (an interceptor) yields a different code.
      final attacker = await DeviceIdentity.generate(displayName: 'Mallory');
      expect(invite.sasFor(attacker.serverPin), isNot(pending.sas));
      expect(pending.displayName, 'Sender');
      expect(
        () => pairingSas(
          inviteDigest: 'xyz',
          hostPin: receiverIdentity.serverPin,
          joinerPin: senderIdentity.serverPin,
        ),
        throwsA(anything),
      );
    });

    test('peer names are sanitized at pairing', () async {
      final spoofer = await DeviceIdentity.generate(
        displayName: 'Ali\u202Ece\u200B   phone',
      );
      final invite = host.createInvite();
      await client.requestPairing(
        invite,
        identity: spoofer,
        peers: TrustedPeerStore(MemorySecretStore()),
      );
      expect(host.pendingPairings.single.displayName, 'Alice phone');
    });

    test(
      'nearby pairing: open window, pinned fetch, rate limit, close',
      () async {
        await restartHost(nearbyRequestsPerMinute: 3);
        await expectLater(
          CoreClient.fetchNearbyInvite(endpoint),
          throwsA(networkCode('NEARBY_UNAVAILABLE')),
        );
        expect(host.nearbyPairingOpen, isFalse);
        final opened = host.openNearbyPairing(ttl: const Duration(minutes: 1));
        expect(host.nearbyPairingOpen, isTrue);
        final fetched = await CoreClient.fetchNearbyInvite(endpoint);
        expect(fetched.inviteId, opened.inviteId);
        expect(fetched.hostPin, receiverIdentity.serverPin);
        expect(fetched.endpoint, endpoint);
        await client.requestPairing(
          fetched,
          identity: senderIdentity,
          peers: senderPeers,
        );
        expect(
          host.pendingPairings.single.sas,
          fetched.sasFor(senderIdentity.serverPin),
        );
        host.closeNearbyPairing();
        await expectLater(
          CoreClient.fetchNearbyInvite(endpoint),
          throwsA(networkCode('NEARBY_UNAVAILABLE')),
        );
        await expectLater(
          CoreClient.fetchNearbyInvite(endpoint),
          throwsA(
            networkCode('RATE_LIMITED').having(
              (error) => error.retryAfter,
              'retryAfter',
              const Duration(seconds: 60),
            ),
          ),
        );
        // The reserved request survives closing the window.
        expect(host.pendingPairings, hasLength(1));
      },
    );

    test(
      'a nearby invitation served under a different key is refused',
      () async {
        final invite = host.createInvite();
        final impostor = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          senderIdentity.serverContext(),
        );
        impostor.listen((request) {
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'invite': invite.encode()}))
            ..close();
        });
        try {
          await expectLater(
            CoreClient.fetchNearbyInvite(
              Uri(scheme: 'https', host: '127.0.0.1', port: impostor.port),
            ),
            throwsA(networkCode('IDENTITY_CHANGED')),
          );
        } finally {
          await impostor.close(force: true);
        }
      },
    );

    test(
      'a pin mismatch is IDENTITY_CHANGED; other handshake failures are not',
      () async {
        final wrong = CoreClient(
          endpoint: endpoint,
          serverPin: senderIdentity.serverPin,
        );
        await expectLater(
          wrong.capabilities(),
          throwsA(networkCode('IDENTITY_CHANGED')),
        );
        wrong.close();
        final plain = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        plain.listen((socket) {
          socket.write('HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n');
          socket.destroy();
        });
        final broken = CoreClient(
          endpoint: Uri(scheme: 'https', host: '127.0.0.1', port: plain.port),
          serverPin: receiverIdentity.serverPin,
        );
        try {
          await broken.capabilities();
          fail('A non-TLS server must not succeed.');
        } on NetworkException catch (error) {
          expect(error.code, isNot('IDENTITY_CHANGED'));
        } on Object {
          // HandshakeException / SocketException: a transport error.
        } finally {
          broken.close();
          await plain.close();
        }
      },
    );

    test(
      'BUSY carries Retry-After; one peer may hold at most 5 pending offers',
      () async {
        final peer = await pair();
        try {
          for (var index = 0; index < 5; index++) {
            await peer.offer(
              TransferManifest(
                requestId: 'pending-$index',
                files: [
                  fileFor([index]),
                ],
              ),
            );
          }
          await expectLater(
            peer.offer(
              TransferManifest(
                requestId: 'pending-6',
                files: [
                  fileFor([9]),
                ],
              ),
            ),
            throwsA(
              networkCode('BUSY')
                  .having((error) => error.statusCode, 'status', 503)
                  .having(
                    (error) => error.retryAfter,
                    'retryAfter',
                    const Duration(seconds: 2),
                  ),
            ),
          );
        } finally {
          peer.close();
        }
      },
    );

    test('folders: capabilities, transfer and on-disk structure', () async {
      final peer = await pair();
      try {
        final capabilities = await peer.capabilities();
        expect(capabilities['protocolMinor'], 1);
        expect(CoreClient.capabilitiesSupportFolders(capabilities), isTrue);
        final bytes = List<int>.generate(1000, (i) => i % 7);
        final source = File(p.join(temp.path, 'a.txt'))
          ..writeAsBytesSync(bytes);
        final manifest = TransferManifest(
          requestId: 'folders',
          files: [fileFor(bytes, name: 'a.txt', folder: 'Trip/Day 1')],
        );
        expect(manifest.toJson()['protocolMinor'], 1);
        final offer = await peer.offer(manifest);
        expect(offer.manifest.files.single.relativeDirectory, 'Trip/Day 1');
        await host.acceptTransfer(offer.id);
        final result = await peer.uploadFile(
          transferId: offer.id,
          fileId: 'file-1',
          source: source,
        );
        expect(result.state, FileState.committed);
        final local = inbox.status(offer.id).files.single.finalPath!;
        expect(local, endsWith(p.join('Trip', 'Day 1', 'a.txt')));
        expect(File(local).readAsBytesSync(), bytes);
      } finally {
        peer.close();
      }
    });

    test(
      'folder manifests are refused locally for a receiver without support',
      () async {
        var posts = 0;
        final old = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          receiverIdentity.serverContext(),
        );
        old.listen((request) async {
          if (request.method == 'POST') posts++;
          await request.drain<void>();
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'protocolMajor': 1, 'protocolMinor': 0}))
            ..close();
        });
        final legacy = CoreClient(
          endpoint: Uri(scheme: 'https', host: '127.0.0.1', port: old.port),
          serverPin: receiverIdentity.serverPin,
          credential: randomToken(),
        );
        try {
          await expectLater(
            legacy.offer(
              TransferManifest(
                requestId: 'folders-old',
                files: [
                  fileFor([1], folder: 'Docs'),
                ],
              ),
            ),
            throwsA(networkCode('FOLDERS_UNSUPPORTED')),
          );
          expect(posts, 0);
        } finally {
          legacy.close();
          await old.close(force: true);
        }
      },
    );
  });

  group('names and manifests', () {
    test(
      'display text drops invisible/bidi characters and collapses spaces',
      () {
        expect(
          sanitizeDisplayText('  a\u202Eb\u200Fc\u2066  d\u3164\u00AD '),
          'abc d',
        );
        expect(sanitizeDisplayText('x\u2028y\t\tz'), 'x y z');
      },
    );

    test('local file names replace shell metacharacters', () {
      final name = safeDisplayName('a&b^c%d!e.txt');
      expect(name, isNot(matches(RegExp(r'[&^%!]'))));
      expect(name, endsWith('.txt'));
    });

    test('isPotentiallyExecutable', () {
      for (final name in [
        'run.EXE',
        'x.bat',
        'a.ps1',
        'b.apk',
        'c.app',
        'd.sh',
      ]) {
        expect(isPotentiallyExecutable(name), isTrue, reason: name);
      }
      for (final name in ['photo.jpg', 'doc.pdf', 'noext']) {
        expect(isPotentiallyExecutable(name), isFalse, reason: name);
      }
    });

    test('relative directory validation', () {
      expect(validateRelativeDirectory(null), isNull);
      expect(validateRelativeDirectory('A/B c/D'), 'A/B c/D');
      for (final invalid in <Object?>[
        '',
        '/abs',
        'trail/',
        'a//b',
        '../up',
        'a/./b',
        r'a\b',
        'c:',
        'a/\u202Eb',
        'a/ ',
        List.filled(9, 'x').join('/'),
        'x' * 241,
        3,
      ]) {
        expect(
          () => validateRelativeDirectory(invalid),
          throwsA(storageCode('INVALID_MANIFEST')),
          reason: '$invalid',
        );
      }
      expect(
        () => FileManifest.fromJson({
          ...fileFor([1]).toJson(),
          'relativeDirectory': '../../etc',
        }),
        throwsA(anything),
      );
      final plain = TransferManifest(
        requestId: 'r',
        files: [
          fileFor([1]),
        ],
      );
      expect(plain.toJson()['protocolMinor'], 0);
      expect(
        plain.files.single.toJson().containsKey('relativeDirectory'),
        isFalse,
      );
    });
  });

  group('received directory and inbox (1.2)', () {
    late Directory temp;
    late Directory inboxDirectory;
    late Directory received;
    DurableInbox? inbox;
    var wall = DateTime(2026, 11, 26, 14, 5);

    Future<DurableInbox> open({Directory? receivedDirectory}) async =>
        inbox = await DurableInbox.open(
          inboxDirectory,
          receivedDirectory: receivedDirectory,
          checkpointBytes: 4,
          wallClock: () => wall,
        );

    setUp(() async {
      temp = await canonicalTemp('transfer-received-');
      inboxDirectory = Directory(p.join(temp.path, 'inbox'));
      received = Directory(p.join(temp.path, 'Received'));
      wall = DateTime(2026, 11, 26, 14, 5);
    });

    tearDown(() async {
      await inbox?.close();
      inbox = null;
      await temp.delete(recursive: true);
    });

    Future<TransferSnapshot> receive(
      List<FileManifest> files,
      Map<String, List<int>> contents, {
      String request = 'request-1',
      String peer = 'peer-a',
    }) async {
      final store = inbox!;
      final offer = await store.createOffer(
        TransferManifest(requestId: request, files: files),
        peerId: peer,
      );
      await store.accept(offer.transferId);
      for (final file in store.status(offer.transferId).files) {
        await store.writeFile(
          offer.transferId,
          file.fileId,
          offset: 0,
          incarnation: file.storageIncarnationId,
          bytes: Stream.value(contents[file.fileId]!),
        );
      }
      return store.status(offer.transferId);
    }

    String folderOf(TransferSnapshot transfer) {
      final short = transfer.transferId.replaceAll('-', '').substring(0, 6);
      return '2026-11-26 14.05 ($short)';
    }

    test('human-readable layout, folders and collision suffixes', () async {
      await open(receivedDirectory: received);
      final transfer = await receive(
        [
          fileFor([1], id: 'a', name: 'photo.jpg'),
          fileFor([2], id: 'b', name: 'photo.jpg'),
          fileFor([3], id: 'c', name: 'photo.jpg', folder: 'Album/Best'),
          fileFor([4], id: 'd', name: 'run&go!.txt'),
        ],
        {
          'a': [1],
          'b': [2],
          'c': [3],
          'd': [4],
        },
      );
      expect(transfer.state, TransferState.completed);
      final base = p.join(received.path, folderOf(transfer));
      final paths = [for (final f in transfer.files) f.finalPath!];
      expect(paths[0], p.join(base, 'photo.jpg'));
      expect(paths[1], p.join(base, 'photo (2).jpg'));
      expect(paths[2], p.join(base, 'Album', 'Best', 'photo.jpg'));
      expect(p.dirname(paths[3]), base);
      expect(p.basename(paths[3]), isNot(matches(RegExp(r'[&!]'))));
      for (final (index, path) in paths.indexed) {
        expect(File(path).readAsBytesSync(), [index + 1]);
      }
      // Stored values are relative to the received root ('r:' prefix).
      final db = sqlite3.open(p.join(inboxDirectory.path, 'inbox.sqlite'));
      try {
        for (final row in db.select('SELECT final_path FROM inbox_files')) {
          expect(row['final_path'], startsWith('r:'));
        }
      } finally {
        db.close();
      }
    });

    test('an existing user file is never overwritten', () async {
      await open(receivedDirectory: received);
      final offer = await inbox!.createOffer(
        TransferManifest(
          requestId: 'r',
          files: [
            fileFor([7], name: 'a.txt'),
          ],
        ),
        peerId: 'peer-a',
      );
      final folder = Directory(
        p.join(
          received.path,
          '2026-11-26 14.05 (${offer.transferId.replaceAll('-', '').substring(0, 6)})',
        ),
      )..createSync(recursive: true);
      File(p.join(folder.path, 'a.txt')).writeAsStringSync('mine');
      await inbox!.accept(offer.transferId);
      final file = inbox!.status(offer.transferId).files.single;
      final result = await inbox!.writeFile(
        offer.transferId,
        file.fileId,
        offset: 0,
        incarnation: file.storageIncarnationId,
        bytes: Stream.value([7]),
      );
      expect(result.finalPath, p.join(folder.path, 'a (2).txt'));
      expect(File(p.join(folder.path, 'a.txt')).readAsStringSync(), 'mine');
    });

    test('the received directory can move with its container', () async {
      await open(receivedDirectory: received);
      final transfer = await receive(
        [
          fileFor([5]),
        ],
        {
          'file-1': [5],
        },
      );
      await inbox!.close();
      inbox = null;
      final moved = Directory(p.join(temp.path, 'NewContainer', 'Received'))
        ..parent.createSync();
      received.renameSync(moved.path);
      await open(receivedDirectory: moved);
      final file = inbox!.status(transfer.transferId).files.single;
      expect(file.errorCode, isNull);
      expect(p.isWithin(moved.path, file.finalPath!), isTrue);
      expect(File(file.finalPath!).readAsBytesSync(), [5]);
      // Deleting removes the file and its now-empty transfer folder.
      await inbox!.deleteTransfer(transfer.transferId);
      expect(moved.listSync(), isEmpty);
    });

    test('legacy results migrate into the received directory', () async {
      await open();
      final legacy = await receive(
        [
          fileFor([1], id: 'a', name: 'one.bin'),
          fileFor([2], id: 'b', name: 'two.bin', folder: 'Sub'),
        ],
        {
          'a': [1],
          'b': [2],
        },
      );
      final legacyPath = legacy.files.first.finalPath!;
      expect(legacyPath, contains('${p.separator}received${p.separator}'));
      await inbox!.close();
      inbox = null;
      await open(receivedDirectory: received);
      final migrated = inbox!.status(legacy.transferId);
      final base = p.join(received.path, folderOf(legacy));
      expect(migrated.files[0].finalPath, p.join(base, 'one.bin'));
      expect(migrated.files[1].finalPath, p.join(base, 'Sub', 'two.bin'));
      expect(File(migrated.files[0].finalPath!).readAsBytesSync(), [1]);
      expect(File(legacyPath).existsSync(), isFalse);
      expect(
        Directory(p.join(inboxDirectory.path, 'received')).listSync(),
        isEmpty,
      );
      // Idempotent: reopening changes nothing.
      await inbox!.close();
      inbox = null;
      await open(receivedDirectory: received);
      expect(
        inbox!.status(legacy.transferId).files[0].finalPath,
        p.join(base, 'one.bin'),
      );
    });

    test(
      'migration recovers from a crash between journal update and move',
      () async {
        await open();
        final legacy = await receive(
          [
            fileFor([9], name: 'x.bin'),
          ],
          {
            'file-1': [9],
          },
        );
        final oldStored = p
            .relative(legacy.files.single.finalPath!, from: inboxDirectory.path)
            .replaceAll(r'\', '/');
        await inbox!.close();
        inbox = null;
        // Simulate: the row already points at the reserved target, the file
        // has not moved yet (crash right after the journal transaction).
        final folder = folderOf(legacy);
        Directory(p.join(received.path, folder)).createSync(recursive: true);
        File(p.join(received.path, folder, 'x.bin')).createSync();
        final db = sqlite3.open(p.join(inboxDirectory.path, 'inbox.sqlite'));
        db.execute('PRAGMA user_version=3');
        try {
          db.execute('ALTER TABLE inbox_files ADD COLUMN moved_from TEXT');
        } on SqliteException {
          // Column already present.
        }
        db.execute('UPDATE inbox_files SET final_path=?, moved_from=?', [
          'r:$folder/x.bin',
          oldStored,
        ]);
        db.close();
        await open(receivedDirectory: received);
        final file = inbox!.status(legacy.transferId).files.single;
        expect(file.finalPath, p.join(received.path, folder, 'x.bin'));
        expect(File(file.finalPath!).readAsBytesSync(), [9]);
        expect(file.errorCode, isNull);
        final check = sqlite3.open(p.join(inboxDirectory.path, 'inbox.sqlite'));
        expect(
          check
              .select('SELECT moved_from FROM inbox_files')
              .single['moved_from'],
          isNull,
        );
        check.close();
      },
    );

    final shm = Directory('/dev/shm');
    final crossDevice =
        Platform.isLinux &&
        shm.existsSync() &&
        FileStat.statSync(shm.path).type == FileSystemEntityType.directory;
    test(
      'migration and adoption fall back to copying across volumes',
      () async {
        final other = shm.createTempSync('transfer-xdev-');
        try {
          await open();
          final legacy = await receive(
            [
              fileFor([3, 3]),
            ],
            {
              'file-1': [3, 3],
            },
          );
          await inbox!.close();
          inbox = null;
          await open(receivedDirectory: Directory(p.join(other.path, 'R')));
          final file = inbox!.status(legacy.transferId).files.single;
          expect(p.isWithin(other.path, file.finalPath!), isTrue);
          expect(File(file.finalPath!).readAsBytesSync(), [3, 3]);

          final outbox = await DurableOutbox.open(
            Directory(p.join(temp.path, 'outbox')),
          );
          try {
            final source = File(p.join(other.path, 'share.tmp'))
              ..writeAsBytesSync([4, 5, 6]);
            final staged = await outbox.stageFile(source, adoptTemporary: true);
            expect(
              staged.manifest.sha256,
              sha256.convert([4, 5, 6]).toString(),
            );
            expect(File(staged.path).readAsBytesSync(), [4, 5, 6]);
          } finally {
            await outbox.close();
          }
        } finally {
          other.deleteSync(recursive: true);
        }
      },
      skip: crossDevice ? false : 'needs a second filesystem (/dev/shm)',
    );

    test(
      'per-peer pending cap, list/listRecent/count and change ids',
      () async {
        await open();
        final changed = <String>[];
        final subscription = inbox!.changedTransfers.listen(changed.add);
        final ids = <String>[];
        for (var index = 0; index < 5; index++) {
          wall = wall.add(const Duration(minutes: 1));
          ids.add(
            (await inbox!.createOffer(
              TransferManifest(
                requestId: 'a-$index',
                files: [
                  fileFor([index]),
                ],
              ),
              peerId: 'peer-a',
            )).transferId,
          );
        }
        await expectLater(
          inbox!.createOffer(
            TransferManifest(
              requestId: 'a-5',
              files: [
                fileFor([5]),
              ],
            ),
            peerId: 'peer-a',
          ),
          throwsA(storageCode('BUSY')),
        );
        wall = wall.add(const Duration(minutes: 1));
        ids.add(
          (await inbox!.createOffer(
            TransferManifest(
              requestId: 'b-0',
              files: [
                fileFor([6]),
              ],
            ),
            peerId: 'peer-b',
          )).transferId,
        );
        await Future<void>.delayed(Duration.zero);
        expect(changed, containsAll(ids));
        expect(inbox!.count(), 6);
        expect(inbox!.count(peerId: 'peer-a'), 5);
        final all = inbox!.list();
        expect(all.map((t) => t.transferId), ids.reversed);
        expect(all.first.files.single.manifest.sizeBytes, 1);
        final page = inbox!.listRecent(limit: 4);
        expect(page.map((t) => t.transferId), ids.reversed.take(4));
        final next = inbox!.listRecent(limit: 4, before: page.last.createdAt);
        expect(next.map((t) => t.transferId), ids.reversed.skip(4));
        expect(inbox!.list(peerId: 'peer-b').single.transferId, ids.last);
        await subscription.cancel();
      },
    );
  });

  group('background hashing and outbox staging', () {
    late Directory temp;
    setUp(() async {
      temp = await canonicalTemp('transfer-hash-');
    });
    tearDown(() => temp.delete(recursive: true));

    test('isolate hashing matches and honours cancellation', () async {
      final bytes = List<int>.generate(3 * 1024 * 1024 + 11, (i) => i % 253);
      final file = File(p.join(temp.path, 'big.bin'))..writeAsBytesSync(bytes);
      expect(await hashFileIsolated(file), sha256.convert(bytes).toString());
      var calls = 0;
      await expectLater(
        hashFileIsolated(
          file,
          pollInterval: const Duration(milliseconds: 1),
          check: () {
            if (++calls > 1) {
              throw const StorageException('PREPARATION_CANCELLED', 'stop');
            }
          },
        ),
        throwsA(storageCode('PREPARATION_CANCELLED')),
      );
      final copy = File(p.join(temp.path, 'copy.bin'));
      final copied = await copyAndHashIsolated(
        file,
        copy,
        maxBytes: bytes.length,
      );
      expect(copied.length, bytes.length);
      expect(copied.sha256, sha256.convert(bytes).toString());
      expect(copy.readAsBytesSync(), bytes);
      await expectLater(
        copyAndHashIsolated(file, copy, maxBytes: 10),
        throwsA(storageCode('SOURCE_CHANGED')),
      );
    });

    test('a cancelled worker closes its file handles before failing', () async {
      final source = File(p.join(temp.path, 'large.bin'));
      final sink = source.openSync(mode: FileMode.write);
      final block = List<int>.filled(1024 * 1024, 7);
      for (var index = 0; index < 48; index++) {
        sink.writeFromSync(block);
      }
      sink.closeSync();
      final destination = File(p.join(temp.path, 'large.copy'));
      List<String> openTargets() => [
        for (final entry in Directory('/proc/self/fd').listSync())
          if (entry is Link)
            () {
              try {
                return entry.targetSync();
              } on FileSystemException {
                return '';
              }
            }(),
      ];
      var calls = 0;
      void stopSoon() {
        if (++calls > 1) {
          throw const StorageException('PREPARATION_CANCELLED', 'stop');
        }
      }

      await expectLater(
        copyAndHashIsolated(
          source,
          destination,
          maxBytes: 1 << 30,
          check: stopSoon,
          pollInterval: const Duration(milliseconds: 1),
        ),
        throwsA(storageCode('PREPARATION_CANCELLED')),
      );
      // The future fails only after the worker closed both files, so the
      // caller can delete them at once (required on Windows).
      final open = openTargets();
      expect(open, isNot(contains(source.path)));
      expect(open, isNot(contains(destination.path)));
      destination.deleteSync();
      source.deleteSync();
    }, skip: Platform.isLinux ? false : 'inspects /proc/self/fd');

    test('adopting a temporary moves it; originals are copied', () async {
      final outbox = await DurableOutbox.open(
        Directory(p.join(temp.path, 'outbox')),
      );
      try {
        final original = File(p.join(temp.path, 'original.txt'))
          ..writeAsStringSync('keep me');
        final copied = await outbox.stageFile(original);
        expect(original.existsSync(), isTrue);
        expect(File(copied.path).readAsStringSync(), 'keep me');

        final temporary = File(p.join(temp.path, 'share-cache.tmp'))
          ..writeAsStringSync('hand over');
        final adopted = await outbox.stageFile(
          temporary,
          displayName: 'note.txt',
          adoptTemporary: true,
        );
        expect(temporary.existsSync(), isFalse);
        expect(adopted.manifest.displayName, 'note.txt');
        expect(
          adopted.manifest.sha256,
          sha256.convert(utf8.encode('hand over')).toString(),
        );
        expect(File(adopted.path).readAsStringSync(), 'hand over');
      } finally {
        await outbox.close();
      }
    });
  });
}
