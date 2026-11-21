import 'dart:io';
import 'dart:typed_data';

import 'package:file_transfer/services/app_runtime.dart';
import 'package:file_transfer/services/diagnostics_log.dart';
import 'package:file_transfer/services/lan_discovery.dart';
import 'package:file_transfer/services/transfer_app_controller.dart';
import 'package:file_transfer/ui/app_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:transfer_core/transfer_core.dart' as core;

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

/// A secret store whose reads fail until it is "repaired", like a Keystore
/// whose key was lost after a device-to-device migration.
class _BrokenSecretStore implements core.SecretStore {
  final inner = core.MemorySecretStore();
  bool broken = true;

  @override
  Future<String?> read(String key) async {
    if (broken) throw const FormatException('cannot decrypt');
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => inner.write(key, value);

  @override
  Future<void> delete(String key) => inner.delete(key);
}

class _Node {
  _Node(this.root, this.secrets, this.controller);
  final Directory root;
  final core.SecretStore secrets;
  final TransferAppController controller;
  final keepAwake = <bool>[];
  bool closed = false;

  static Future<_Node> create(
    String name, {
    Directory? root,
    core.SecretStore? secrets,
    bool requireOnboarding = false,
    Duration backgroundGrace = Duration.zero,
    Future<void> Function()? resetSecrets,
    bool initialize = true,
  }) async {
    final dir = root ?? await Directory.systemTemp.createTemp('ulash-prod-');
    final store = secrets ?? core.MemorySecretStore();
    late final _Node node;
    final controller = TransferAppController(
      runtime: AppRuntime(
        secrets: store,
        storageDirectory: () async => dir,
        ensurePermission: () async => true,
        addresses: () async => ['127.0.0.1'],
        listenAddress: InternetAddress.loopbackIPv4,
        listenPort: 0,
        initialDeviceName: name,
        mobileLifecycle: true,
        discoveryEnabled: false,
        requireOnboarding: requireOnboarding,
        backgroundGrace: backgroundGrace,
        resetSecrets: resetSecrets,
        setKeepAwake: (enabled) async => node.keepAwake.add(enabled),
      ),
    );
    node = _Node(dir, store, controller);
    if (initialize) await controller.initialize();
    return node;
  }

  Future<void> close({bool deleteRoot = true}) async {
    if (closed) return;
    closed = true;
    await controller.shutdown();
    controller.dispose();
    if (deleteRoot && await root.exists()) await root.delete(recursive: true);
  }
}

Future<void> _pair(TransferAppController a, TransferAppController b) async {
  await b.createInvitation();
  expect(b.errorMessage, isNull);
  final pairing = a.pairFromText(b.invitation!.payload);
  await _waitUntil(
    () => b.pendingPairings.isNotEmpty,
    reason: 'pairing request arrives',
  );
  // The code the receiver shows must be the requesting device's own code.
  expect(b.pendingPairings.single.code, a.deviceCode);
  expect(a.deviceCode, matches(RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}$')));
  await b.respondToPairing(b.pendingPairings.single.id, true);
  await pairing;
  await _waitUntil(
    () => a.peers.any((peer) => peer.isTrusted && peer.isOnline),
    reason: 'pairing completes',
  );
}

Future<void> _select(_Node node, int bytes) async {
  final file = File(p.join(node.root.path, 'payload-$bytes.bin'));
  final data = Uint8List(bytes);
  for (var i = 0; i < bytes; i++) {
    data[i] = (i * 13 + 5) & 255;
  }
  await file.writeAsBytes(data, flush: true);
  await node.controller.addSourcePaths([file.path]);
  expect(node.controller.errorMessage, isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rankLanAddresses prefers Wi-Fi/Ethernet and drops virtual adapters', () {
    final ranked = rankLanAddresses([
      ('vEthernet (WSL)', '172.24.16.1'),
      ('docker0', '172.17.0.1'),
      ('utun3', '10.8.0.2'),
      ('rmnet_data0', '100.70.1.2'),
      ('en0', '192.168.1.23'),
      ('eth1', '10.0.0.5'),
      ('lo', '127.0.0.1'),
      ('en5', '169.254.10.1'),
    ]);
    expect(ranked.first, '192.168.1.23');
    expect(ranked, contains('10.0.0.5'));
    expect(ranked, isNot(contains('172.24.16.1')));
    expect(ranked, isNot(contains('172.17.0.1')));
    expect(ranked, isNot(contains('10.8.0.2')));
    expect(ranked, isNot(contains('100.70.1.2')));
    expect(ranked, isNot(contains('127.0.0.1')));
    expect(ranked, isNot(contains('169.254.10.1')));
  });

  test('diagnostics never record paths, addresses or tokens', () async {
    final dir = await Directory.systemTemp.createTemp('ulash-diag-');
    try {
      final log = DiagnosticsLog.instance;
      await log.attach(dir);
      log.error(
        'probe',
        FileSystemException(
          'open failed',
          '/var/mobile/Containers/Data/secret-name.mov',
        ),
      );
      log.info(
        'endpoint https://192.168.1.4:53318 token '
        'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcdef',
      );
      final out = await log.exportSnapshot(Directory(p.join(dir.path, 'x')));
      final text = await out!.readAsString();
      expect(text, contains('FileSystemException'));
      expect(text, isNot(contains('secret-name')));
      expect(text, isNot(contains('192.168.1.4')));
      expect(text, isNot(contains('AbCdEfGhIjKlMnOpQrStUvWxYz')));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test(
    'first launch waits for onboarding before any network listener starts',
    () => _realNetwork(() async {
      final dir = await Directory.systemTemp.createTemp('ulash-onb-');
      final secrets = core.MemorySecretStore();
      final first = await _Node.create(
        'Onboarding',
        root: dir,
        secrets: secrets,
        requireOnboarding: true,
      );
      try {
        expect(first.controller.needsOnboarding, isTrue);
        expect(first.controller.receivingEnabled, isFalse);
        await first.controller.completeOnboarding();
        expect(first.controller.needsOnboarding, isFalse);
        expect(first.controller.receivingEnabled, isTrue);
        await first.close(deleteRoot: false);
        final second = await _Node.create(
          'Onboarding',
          root: dir,
          secrets: secrets,
          requireOnboarding: true,
        );
        expect(second.controller.needsOnboarding, isFalse);
        expect(second.controller.receivingEnabled, isTrue);
        await second.close();
      } finally {
        await first.close();
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    }),
  );

  test(
    'unreadable device keys offer recovery; confirmed reset starts cleanly',
    () => _realNetwork(() async {
      final secrets = _BrokenSecretStore();
      final node = await _Node.create(
        'Locked keys',
        secrets: secrets,
        resetSecrets: () async => secrets.broken = false,
      );
      try {
        expect(node.controller.startupIssue, StartupIssue.secureStorage);
        expect(node.controller.errorMessage, isNotNull);
        // Retrying without a reset keeps failing closed (no silent reset).
        await node.controller.retryStartup();
        expect(node.controller.startupIssue, StartupIssue.secureStorage);
        await node.controller.resetDeviceKeys();
        expect(node.controller.startupIssue, StartupIssue.none);
        expect(node.controller.receivingEnabled, isTrue);
        expect(node.controller.deviceCode, isNotNull);
      } finally {
        await node.close();
      }
    }),
  );

  test(
    'a damaged journal is reported and can be moved aside on request',
    () => _realNetwork(() async {
      final dir = await Directory.systemTemp.createTemp('ulash-journal-');
      final inbox = Directory(p.join(dir.path, 'file-transfer-v1', 'inbox'));
      await inbox.create(recursive: true);
      await File(
        p.join(inbox.path, 'inbox.sqlite'),
      ).writeAsString('this is not a database ' * 200);
      final node = await _Node.create('Journal', root: dir);
      try {
        expect(node.controller.startupIssue, StartupIssue.journal);
        await node.controller.repairStorage();
        expect(node.controller.startupIssue, StartupIssue.none);
        expect(node.controller.receivingEnabled, isTrue);
        final moved = await inbox
            .list()
            .where((entry) => entry.path.contains('.damaged-'))
            .toList();
        expect(moved, isNotEmpty, reason: 'damaged journal kept for support');
      } finally {
        await node.close();
      }
    }),
  );

  test(
    'device rename keeps keys, updates invitations and persists',
    () => _realNetwork(() async {
      final dir = await Directory.systemTemp.createTemp('ulash-rename-');
      final secrets = core.MemorySecretStore();
      final node = await _Node.create('Old name', root: dir, secrets: secrets);
      try {
        final code = node.controller.deviceCode;
        await node.controller.renameDevice('Kitchen iPad');
        expect(node.controller.errorMessage, isNull);
        expect(node.controller.deviceName, 'Kitchen iPad');
        expect(node.controller.deviceCode, code);
        await node.controller.createInvitation();
        final invite = core.PairingInvite.parse(
          node.controller.invitation!.payload,
        );
        expect(invite.displayName, 'Kitchen iPad');
        await node.close(deleteRoot: false);
        final reopened = await _Node.create(
          'Ignored default',
          root: dir,
          secrets: secrets,
        );
        expect(reopened.controller.deviceName, 'Kitchen iPad');
        expect(reopened.controller.deviceCode, code);
        await reopened.close();
      } finally {
        await node.close();
      }
    }),
  );

  test(
    'brief backgrounding within the grace period does not interrupt a send; '
    'a long one pauses and continues automatically on return',
    () => _realNetwork(() async {
      final sender = await _Node.create(
        'Sender',
        backgroundGrace: const Duration(milliseconds: 600),
      );
      final receiver = await _Node.create('Receiver');
      final a = sender.controller;
      final b = receiver.controller;
      try {
        await _pair(a, b);
        final peer = a.peers.singleWhere((peer) => peer.isTrusted);
        await _select(sender, 256 * 1024);
        await a.sendTo(peer.id);
        await _waitUntil(
          () => b.pendingTransfers.isNotEmpty,
          reason: 'offer arrives',
        );
        // Short trip to another app: nothing is interrupted.
        a.didChangeAppLifecycleState(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        a.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(a.transfers.single.phase, isNot(TransferPhase.paused));
        // Long trip: the run stops cleanly after the grace period...
        a.didChangeAppLifecycleState(AppLifecycleState.paused);
        await _waitUntil(
          () => a.transfers.single.phase == TransferPhase.paused,
          reason: 'grace period ends the run',
        );
        await b.respondToTransfer(b.pendingTransfers.single.id, true);
        // ...and resumes by itself when the user comes back.
        a.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await _waitUntil(
          () =>
              a.transfers.single.phase == TransferPhase.completed &&
              b.transfers.single.phase == TransferPhase.completed,
          reason: 'lifecycle-paused send continues automatically',
        );
        // The screen was kept on while bytes were moving, then released.
        expect(sender.keepAwake, isNotEmpty);
        expect(sender.keepAwake.last, isFalse);
      } finally {
        await sender.close();
        await receiver.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'deleting a received transfer removes its files; clearing history keeps '
    'completed received files',
    () => _realNetwork(() async {
      final sender = await _Node.create('Sender');
      final receiver = await _Node.create('Receiver');
      final a = sender.controller;
      final b = receiver.controller;
      try {
        await _pair(a, b);
        final peer = a.peers.singleWhere((peer) => peer.isTrusted);
        for (final size in [1000, 2000]) {
          await _select(sender, size);
          await a.sendTo(peer.id);
          await _waitUntil(
            () => b.pendingTransfers.isNotEmpty,
            reason: 'offer $size arrives',
          );
          await b.respondToTransfer(b.pendingTransfers.single.id, true);
          await _waitUntil(
            () => a.transfers.every(
              (item) => item.phase == TransferPhase.completed,
            ),
            reason: 'transfer $size completes',
          );
        }
        Future<List<File>> received() async {
          final dir = Directory(b.saveLocationLabel);
          if (!await dir.exists()) return [];
          return dir
              .list(recursive: true)
              .where((entry) => entry is File)
              .cast<File>()
              .toList();
        }

        await _waitUntil(
          () => b.transfers.where((t) => t.canDelete).length == 2,
          reason: 'receiver lists two finished transfers',
        );
        expect(await received(), hasLength(2));
        await b.clearHistory();
        expect(b.errorMessage, isNull);
        expect(await received(), hasLength(2), reason: 'bulk clear keeps files');
        final target = b.transfers.first;
        await b.deleteTransfer(target.id);
        expect(b.errorMessage, isNull);
        expect(b.transfers, hasLength(1));
        expect(await received(), hasLength(1));
        await a.clearHistory();
        expect(a.transfers, isEmpty);
      } finally {
        await sender.close();
        await receiver.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a rename reaches already paired devices over the pinned connection',
    () => _realNetwork(() async {
      final sender = await _Node.create('Sender');
      final receiver = await _Node.create('Receiver');
      try {
        await _pair(sender.controller, receiver.controller);
        await receiver.controller.renameDevice('Office PC');
        expect(receiver.controller.errorMessage, isNull);
        await _waitUntil(() => receiver.controller.receivingEnabled,
            reason: 'host restarted after rename');
        await sender.controller.refreshPeers();
        await _waitUntil(
          () => sender.controller.peers.any(
            (peer) => peer.isTrusted && peer.name == 'Office PC',
          ),
          reason: 'peer name updated from authenticated capabilities',
        );
      } finally {
        await sender.close();
        await receiver.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a confirmed key reset keeps settings and does not repeat onboarding',
    () => _realNetwork(() async {
      final secrets = core.MemorySecretStore();
      final node = await _Node.create(
        'Reset',
        secrets: secrets,
        requireOnboarding: true,
        resetSecrets: () async => secrets.clear(),
      );
      try {
        await node.controller.completeOnboarding();
        await node.controller.setLocale(const Locale('en'));
        final before = node.controller.deviceCode;
        await node.controller.resetDeviceKeys();
        expect(node.controller.startupIssue, StartupIssue.none);
        expect(node.controller.needsOnboarding, isFalse);
        expect(node.controller.locale, const Locale('en'));
        expect(node.controller.deviceCode, isNot(before));
        expect(node.controller.receivingEnabled, isTrue);
      } finally {
        await node.close();
      }
    }),
  );
}
