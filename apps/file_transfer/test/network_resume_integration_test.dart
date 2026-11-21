import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_transfer/services/app_runtime.dart';
import 'package:file_transfer/services/network_retry_policy.dart';
import 'package:file_transfer/services/transfer_app_controller.dart';
import 'package:file_transfer/ui/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:transfer_core/transfer_core.dart' as core;

class _RealHttp extends HttpOverrides {}

Future<void> _until(
  bool Function() predicate,
  String reason, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > timeout) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// An opaque TCP relay: TLS, the certificate, pin checks, credentials, requests
/// and file data remain between the two real app controllers. Only sockets are
/// interrupted, without replacing the client or synthesizing a response.
class _Relay {
  _Relay(this.listener, this.target);

  final ServerSocket listener;
  final int target;
  final Set<Socket> _sockets = {};
  final Set<Future<void>> _connections = {};
  bool _closed = false;
  int cuts = 0;
  int outgoingBytesAfterCut = 0;

  int get port => listener.port;

  static Future<_Relay> open(int target) async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _Relay(listener, target);
    listener.listen((downstream) {
      late final Future<void> connection;
      connection = relay._connect(downstream).whenComplete(() {
        relay._connections.remove(connection);
      });
      relay._connections.add(connection);
    });
    return relay;
  }

  Future<void> _connect(Socket downstream) async {
    _sockets.add(downstream);
    Socket? upstream;
    try {
      upstream = await Socket.connect(InternetAddress.loopbackIPv4, target);
      if (_closed) return;
      _sockets.add(upstream);
      Future<void> forward(
        Socket from,
        Socket to, {
        bool outgoing = false,
      }) async {
        try {
          await to.addStream(
            from.map((bytes) {
              if (outgoing && cuts > 0) outgoingBytesAfterCut += bytes.length;
              return bytes;
            }),
          );
        } catch (_) {
          // A deliberate socket reset or peer shutdown ends this direction.
        } finally {
          from.destroy();
          to.destroy();
        }
      }

      await Future.wait([
        forward(downstream, upstream, outgoing: true),
        forward(upstream, downstream),
      ]);
    } on SocketException {
      // A target stopping during the test is a real unavailable connection.
    } finally {
      downstream.destroy();
      upstream?.destroy();
      _sockets.remove(downstream);
      _sockets.remove(upstream);
    }
  }

  void interruptConnections() {
    cuts++;
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
  }

  Future<void> close() async {
    _closed = true;
    await listener.close();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    await Future.wait(_connections.toList());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a real TLS socket interruption automatically resumes the same transfer and exact bytes',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final root = await Directory.systemTemp.createTemp('transfer-retry-tls-');
      final senderRoot = Directory(p.join(root.path, 'sender'));
      final receiverRoot = Directory(p.join(root.path, 'receiver'));
      final senderSecrets = core.MemorySecretStore();
      final receiverSecrets = core.MemorySecretStore();
      final retryGate = Completer<void>();
      final retryDelays = <Duration>[];
      final watch = Stopwatch()..start();
      TransferAppController? sender;
      TransferAppController? receiver;
      _Relay? relay;
      void Function()? observe;

      AppRuntime runtime(
        Directory directory,
        core.MemorySecretStore secrets,
        String name, {
        Future<void> Function(Duration)? retryDelay,
      }) => AppRuntime(
        secrets: secrets,
        storageDirectory: () async => directory,
        ensurePermission: () async => true,
        addresses: () async => ['127.0.0.1'],
        listenAddress: InternetAddress.loopbackIPv4,
        initialDeviceName: name,
        retryPolicy: NetworkRetryPolicy(randomUnit: () => 0),
        retryDelay: retryDelay,
      );

      try {
        final b = receiver = TransferAppController(
          runtime: runtime(receiverRoot, receiverSecrets, 'Retry receiver'),
        );
        await b.initialize();
        expect(b.errorMessage, isNull);
        await b.createInvitation();
        final original = core.PairingInvite.parse(b.invitation!.payload);
        final bridge = relay = await _Relay.open(original.endpoint.port);
        final invite = core.PairingInvite(
          inviteId: original.inviteId,
          inviteSecret: original.inviteSecret,
          hostPin: original.hostPin,
          displayName: original.displayName,
          endpoint: original.endpoint.replace(port: bridge.port),
        );
        final a = sender = TransferAppController(
          runtime: runtime(
            senderRoot,
            senderSecrets,
            'Retry sender',
            retryDelay: (delay) async {
              retryDelays.add(delay);
              await retryGate.future;
            },
          ),
        );
        await a.initialize();
        final pairing = a.pairFromText(invite.encode());
        await _until(() => b.pendingPairings.isNotEmpty, 'pairing request');
        await b.respondToPairing(b.pendingPairings.single.id, true);
        await pairing;
        expect(a.errorMessage, isNull);
        await _until(
          () => a.peers.any((peer) => peer.isTrusted && peer.isOnline),
          'pinned peer is reachable through the relay',
        );

        const totalBytes = 16 * 1024 * 1024 + 137;
        final payload = Uint8List(totalBytes);
        for (var index = 0; index < payload.length; index++) {
          payload[index] = (index * 29 + index ~/ 251 + 11) & 255;
        }
        final expectedHash = sha256.convert(payload).toString();
        final source = File(p.join(senderRoot.path, 'socket-resume.bin'));
        await source.writeAsBytes(payload, flush: true);
        await a.addSourcePaths([source.path]);
        expect(a.errorMessage, isNull);
        // The original may disappear: only the durable staged copy is sent.
        await source.delete();
        await a.sendTo(a.peers.singleWhere((peer) => peer.isTrusted).id);
        await _until(() => b.pendingTransfers.isNotEmpty, 'offer');
        final requestId = a.transfers.single.id;
        final transferId = b.transfers.single.id;
        expect(b.transfers.single.transferredBytes, 0);
        var checkpointBeforeCut = 0;
        observe = () {
          if (bridge.cuts != 0 || b.transfers.isEmpty) return;
          final current = b.transfers.single.transferredBytes;
          if (current >= 4 * 1024 * 1024 && current < totalBytes) {
            checkpointBeforeCut = current;
            bridge.interruptConnections();
          }
        };
        b.addListener(observe);
        await b.respondToTransfer(b.pendingTransfers.single.id, true);
        await _until(
          () => retryDelays.isNotEmpty,
          'automatic retry is scheduled',
        );
        expect(bridge.cuts, 1);
        expect(checkpointBeforeCut, greaterThan(0));
        expect(checkpointBeforeCut, lessThan(totalBytes));
        expect(retryDelays.first, const Duration(seconds: 1));
        await _until(
          () => b.transfers.single.phase == TransferPhase.paused,
          'receiver stores the durable interrupted prefix',
        );
        final durableOffset = b.transfers.single.transferredBytes;
        expect(durableOffset, greaterThanOrEqualTo(checkpointBeforeCut));
        expect(durableOffset, lessThan(totalBytes));
        expect(a.transfers.single.phase, isNot(TransferPhase.completed));
        expect(b.transfers.single.canOpen, isFalse);

        // No call to source resumeTransfer: the bounded scheduler reconnects.
        retryGate.complete();
        await _until(
          () =>
              a.transfers.single.phase == TransferPhase.completed &&
              b.transfers.single.phase == TransferPhase.completed,
          'automatic resume receives a validated committed receipt',
        );
        expect(a.transfers.single.id, requestId);
        expect(b.transfers.single.id, transferId);
        expect(a.transfers, hasLength(1));
        expect(b.transfers, hasLength(1));
        expect(b.pendingTransfers, isEmpty);
        expect(retryDelays, hasLength(1));
        final files = await Directory(b.saveLocationLabel)
            .list(recursive: true, followLinks: false)
            .where((entry) => entry is File)
            .cast<File>()
            .toList();
        expect(files, hasLength(1));
        expect(await files.single.length(), totalBytes);
        final actualHash = (await sha256.bind(files.single.openRead()).first)
            .toString();
        expect(actualHash, expectedHash);
        expect(a.transfers.single.transferredBytes, totalBytes);
        expect(b.transfers.single.transferredBytes, totalBytes);
        expect(
          bridge.outgoingBytesAfterCut,
          lessThan(totalBytes - 1024 * 1024),
          reason:
              'Wire data after reconnect (including TLS and metadata) must be '
              'smaller than a fresh full-file upload; the durable prefix is reused.',
        );
        // Bounded test report: no invitations, credentials or file paths.
        // ignore: avoid_print
        print(
          'NETWORK_RETRY_PROBE ${jsonEncode({'bytes': totalBytes, 'durableOffsetAtRetry': durableOffset, 'socketInterruptions': bridge.cuts, 'automaticRetries': retryDelays.length, 'outgoingWireBytesAfterCut': bridge.outgoingBytesAfterCut, 'retryDelaysMs': retryDelays.map((delay) => delay.inMilliseconds).toList(), 'sha256': actualHash, 'elapsedMilliseconds': watch.elapsedMilliseconds, 'requestIdPreserved': true, 'transferIdPreserved': true})}',
        );
      } finally {
        if (!retryGate.isCompleted) retryGate.complete();
        if (observe != null) receiver?.removeListener(observe);
        await sender?.shutdown();
        await receiver?.shutdown();
        sender?.dispose();
        receiver?.dispose();
        await relay?.close();
        senderSecrets.clear();
        receiverSecrets.clear();
        await root.delete(recursive: true);
      }
    }, _RealHttp()),
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
