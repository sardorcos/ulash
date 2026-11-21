import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_transfer/services/app_runtime.dart';
import 'package:file_transfer/services/transfer_app_controller.dart';
import 'package:file_transfer/ui/app_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:transfer_core/transfer_core.dart' as core;

/// Preserve the real transport and its TLS pin checks inside Flutter tests.
/// Flutter's widget binding otherwise substitutes a client returning HTTP 400.
class _RealHttpOverrides extends HttpOverrides {}

Future<void> _realNetwork(Future<void> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

Future<void> _waitUntil(
  bool Function() ready, {
  required String reason,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > timeout) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<void> _expectPortClosed(int port) async {
  Socket? socket;
  try {
    socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(milliseconds: 500),
    );
  } on SocketException {
    return;
  } finally {
    socket?.destroy();
  }
  fail('TCP listener $port remained open after shutdown.');
}

class _Harness {
  _Harness(this.root, this.secrets);

  final Directory root;
  final core.MemorySecretStore secrets;
  late final TransferAppController controller;
  int addressLookups = 0;
  bool closed = false;

  static Future<_Harness> create(String name) async {
    final root = await Directory.systemTemp.createTemp('transfer-app-');
    final result = _Harness(root, core.MemorySecretStore());
    result.controller = TransferAppController(
      runtime: AppRuntime(
        secrets: result.secrets,
        storageDirectory: () async => root,
        ensurePermission: () async => true,
        addresses: () async {
          result.addressLookups++;
          // Makes overlapping lifecycle starts observable without mocking TLS.
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return ['127.0.0.1'];
        },
        listenAddress: InternetAddress.loopbackIPv4,
        listenPort: 0,
        initialDeviceName: name,
        mobileLifecycle: true,
        discoveryEnabled: false,
      ),
    );
    try {
      await result.controller.initialize();
      expect(result.controller.errorMessage, isNull);
      expect(result.controller.receivingEnabled, isTrue);
      return result;
    } catch (_) {
      await result.close();
      rethrow;
    }
  }

  Future<int> invitationPort() async {
    await controller.createInvitation();
    expect(controller.errorMessage, isNull);
    return core.PairingInvite.parse(controller.invitation!.payload)
        .endpoint
        .port;
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    await controller.shutdown();
    controller.dispose();
    secrets.clear();
    await root.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'two real controllers pair, require consent and commit exact file bytes',
    () => _realNetwork(() async {
      final sender = await _Harness.create('Controller A');
      final receiver = await _Harness.create('Controller B');
      final a = sender.controller;
      final b = receiver.controller;
      try {
        expect(a.peers, isEmpty);
        expect(b.peers, isEmpty);
        expect(a.transfers, isEmpty);
        expect(b.transfers, isEmpty);
        await b.createInvitation();
        expect(b.errorMessage, isNull);
        final pairing = a.pairFromText(b.invitation!.payload);
        await _waitUntil(
          () => b.pendingPairings.isNotEmpty,
          reason: 'real peer pairing request reaches the receiver',
        );
        expect(a.peers.where((peer) => peer.isTrusted), isEmpty);
        expect(b.peers.where((peer) => peer.isTrusted), isEmpty);
        await b.respondToPairing(b.pendingPairings.single.id, true);
        await pairing;
        expect(a.errorMessage, isNull);
        await _waitUntil(
          () =>
              a.peers.any((peer) => peer.isTrusted && peer.isOnline) &&
              b.peers.any((peer) => peer.isTrusted),
          reason: 'explicit approval completes mutual pairing',
        );
        final peer = a.peers.singleWhere((peer) => peer.isTrusted);

        final payload = Uint8List(2 * 1024 * 1024 + 37);
        for (var index = 0; index < payload.length; index++) {
          payload[index] = (index * 31 + 7) & 255;
        }
        final contents = <String, List<int>>{
          'binary.dat': payload,
          'Документ.txt': utf8.encode('Реальная передача файла через TLS.\n'),
        };
        final sources = <File>[];
        for (final entry in contents.entries) {
          final source = File(p.join(sender.root.path, entry.key));
          await source.writeAsBytes(entry.value, flush: true);
          sources.add(source);
        }
        await a.addSourcePaths(sources.map((source) => source.path).toList());
        expect(a.errorMessage, isNull);
        expect(a.selectedSources, hasLength(2));
        expect(
          a.selectedSources.every(
            (source) => source.status == SourceStatus.ready,
          ),
          isTrue,
        );
        // Preparation owns durable copies; later selection changes cannot alter bytes.
        for (final source in sources) {
          await source.delete();
        }
        await a.sendTo(peer.id);
        expect(a.errorMessage, isNull);
        await _waitUntil(
          () => b.pendingTransfers.isNotEmpty,
          reason: 'offer reaches the receiver before any accepted file',
        );
        expect(b.transfers.single.phase, TransferPhase.waitingForConsent);
        expect(b.transfers.single.transferredBytes, 0);
        expect(b.transfers.single.canOpen, isFalse);
        expect(
          await Directory(b.saveLocationLabel)
              .list(recursive: true)
              .where((entry) => entry is File)
              .toList(),
          isEmpty,
        );
        await b.respondToTransfer(b.pendingTransfers.single.id, true);
        await _waitUntil(
          () =>
              a.transfers.single.phase == TransferPhase.completed &&
              b.transfers.single.phase == TransferPhase.completed,
          reason: 'both controllers receive a committed and verified receipt',
        );
        final total = contents.values.fold<int>(
          0,
          (sum, bytes) => sum + bytes.length,
        );
        expect(a.transfers.single.transferredBytes, total);
        expect(b.transfers.single.transferredBytes, total);
        expect(b.transfers.single.canOpen, isTrue);
        expect(b.pendingTransfers, isEmpty);
        final files = await Directory(b.saveLocationLabel)
            .list(recursive: true, followLinks: false)
            .where((entry) => entry is File)
            .cast<File>()
            .toList();
        expect(files, hasLength(contents.length));
        for (final saved in files) {
          final original = contents[p.basename(saved.path)];
          expect(original, isNotNull);
          final diskHash = await sha256.bind(saved.openRead()).first;
          expect(diskHash.toString(), sha256.convert(original!).toString());
        }
        expect(b.transfers.single.receivedFiles, hasLength(2));
      } finally {
        await sender.close();
        await receiver.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'receive-off survives refresh and resume; parallel starts share one listener',
    () => _realNetwork(() async {
      final harness = await _Harness.create('Lifecycle controller');
      final controller = harness.controller;
      try {
        final initialPort = await harness.invitationPort();
        await controller.setReceiving(false);
        expect(controller.receivingEnabled, isFalse);
        await _expectPortClosed(initialPort);
        await controller.refreshPeers();
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await controller.refreshPeers();
        expect(controller.receivingEnabled, isFalse);
        expect(controller.invitation, isNull);
        await _expectPortClosed(initialPort);

        final lookupsBeforeStart = harness.addressLookups;
        await Future.wait([
          controller.setReceiving(true),
          controller.refreshPeers(),
          controller.setReceiving(true),
          controller.refreshPeers(),
          controller.setReceiving(true),
        ]);
        expect(controller.errorMessage, isNull);
        expect(controller.receivingEnabled, isTrue);
        expect(
          harness.addressLookups - lookupsBeforeStart,
          1,
          reason: 'one serialized start acquires one real listener',
        );
        final activePort = await harness.invitationPort();
        final samePort = await harness.invitationPort();
        expect(samePort, activePort);

        var notifications = 0;
        controller.addListener(() => notifications++);
        final refresh = controller.refreshPeers();
        final stopping = controller.shutdown();
        final countAtShutdown = notifications;
        await Future.wait([refresh, stopping]);
        await _expectPortClosed(activePort);
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await controller.setReceiving(true);
        await controller.refreshPeers();
        expect(notifications, countAtShutdown);
        expect(controller.receivingEnabled, isFalse);
        await _expectPortClosed(activePort);
      } finally {
        await harness.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'shutdown during initialization waits for storage and never opens a host',
    () => _realNetwork(() async {
      final root = await Directory.systemTemp.createTemp(
        'transfer-start-close-',
      );
      final secrets = core.MemorySecretStore();
      final directoryReady = Completer<Directory>();
      var addressLookups = 0;
      final controller = TransferAppController(
        runtime: AppRuntime(
          secrets: secrets,
          storageDirectory: () => directoryReady.future,
          ensurePermission: () async => true,
          addresses: () async {
            addressLookups++;
            return ['127.0.0.1'];
          },
          listenAddress: InternetAddress.loopbackIPv4,
          initialDeviceName: 'Closing controller',
        ),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      final initializing = controller.initialize();
      final stopping = controller.shutdown();
      final countAtShutdown = notifications;
      directoryReady.complete(root);
      try {
        await Future.wait([initializing, stopping]);
        expect(controller.receivingEnabled, isFalse);
        expect(addressLookups, 0);
        expect(notifications, countAtShutdown);
        // Reopening confirms the initialization/shutdown race released store leases.
        final inbox = await core.DurableInbox.open(
          Directory(p.join(root.path, 'file-transfer-v1', 'inbox')),
        );
        await inbox.close();
        final outbox = await core.DurableOutbox.open(
          Directory(p.join(root.path, 'file-transfer-v1', 'outbox')),
        );
        await outbox.close();
      } finally {
        await controller.shutdown();
        controller.dispose();
        secrets.clear();
        await root.delete(recursive: true);
      }
    }),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
