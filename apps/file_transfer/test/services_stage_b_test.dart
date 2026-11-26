import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_transfer/l10n/app_localizations.dart';
import 'package:file_transfer/services/app_runtime.dart';
import 'package:file_transfer/services/lan_discovery.dart';
import 'package:file_transfer/services/native_bridge.dart';
import 'package:file_transfer/services/outgoing_journal.dart';
import 'package:file_transfer/services/transfer_app_controller.dart';
import 'package:file_transfer/ui/app_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:transfer_core/transfer_core.dart' as core;

class _RealHttpOverrides extends HttpOverrides {}

Future<void> _realNetwork(Future<void> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

final _ru = lookupAppLocalizations(const Locale('ru'));

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

/// In-memory stand-in for Bonjour: every started instance sees the others
/// on loopback, including their nearby-pairing hint.
class _FakeDiscovery extends LanDiscovery {
  static final _bus = <_FakeDiscovery>{};
  final _out = StreamController<List<DiscoveredEndpoint>>.broadcast();
  String? _label;
  int? _listenPort;
  bool _pair = false;

  @override
  Stream<List<DiscoveredEndpoint>> get changes => _out.stream;

  @override
  List<DiscoveredEndpoint> get endpoints => [
    for (final other in _bus)
      if (!identical(other, this) && other._label != null)
        DiscoveredEndpoint(
          instanceId: other.instanceId,
          name: other._label!,
          endpoint: Uri(
            scheme: 'https',
            host: '127.0.0.1',
            port: other._listenPort,
          ),
          platform: 'linux',
          pairable: other._pair,
        ),
  ];

  static void _publish() {
    for (final member in _bus) {
      if (!member._out.isClosed) member._out.add(member.endpoints);
    }
  }

  @override
  Future<void> start({required String name, required int port}) async {
    _label = name;
    _listenPort = port;
    _bus.add(this);
    _publish();
  }

  @override
  Future<void> setPairable(bool pairable) async {
    _pair = pairable;
    _publish();
  }

  @override
  Future<void> close() async {
    _bus.remove(this);
    _publish();
    await _out.close();
  }
}

class _Hooks {
  final photos = <String>[];
  var photoResult = SaveToPhotosResult.saved;
  final marked = <String>[];
  final opened = <(String, bool)>[];
  var openResult = OpenFileResult.opened;
  final revealed = <String>[];
  final secure = <bool>[];
  final copied = <(String, int)>[];
  var nativeCopy = true;
  final intake = <IntakeItem>[];
  final intakeSignal = StreamController<void>.broadcast();
  String? folder;
}

class _Node {
  _Node(this.root, this.controller, this.hooks);
  final Directory root;
  final TransferAppController controller;
  final _Hooks hooks;

  static Future<_Node> create(
    String name, {
    Directory? root,
    Directory? received,
    Directory? legacyRoot,
    Directory? temporary,
    bool discovery = false,
    bool platformHooks = false,
    List<IntakeItem> intake = const [],
    Duration webShareTtl = const Duration(minutes: 10),
  }) async {
    final dir = root ?? await Directory.systemTemp.createTemp('ulash-b-');
    final hooks = _Hooks()..intake.addAll(intake);
    final controller = TransferAppController(
      runtime: AppRuntime(
        secrets: core.MemorySecretStore(),
        webSharePort: 0,
        webShareTtl: webShareTtl,
        storageDirectory: () async => dir,
        ensurePermission: () async => true,
        addresses: () async => ['127.0.0.1'],
        listenAddress: InternetAddress.loopbackIPv4,
        initialDeviceName: name,
        mobileLifecycle: true,
        temporaryDirectory: temporary == null ? null : () async => temporary,
        receivedDirectory: received == null ? null : () async => received,
        legacyStorageDirectory: legacyRoot == null
            ? null
            : () async => legacyRoot,
        createDiscovery: discovery ? _FakeDiscovery.new : null,
        pickDirectory: () async => hooks.folder,
        takePendingIntake: platformHooks
            ? () async {
                final items = List.of(hooks.intake);
                hooks.intake.clear();
                return items;
              }
            : null,
        intakeAvailable: platformHooks ? hooks.intakeSignal.stream : null,
        saveToPhotos: platformHooks
            ? (file, {required isVideo}) async {
                hooks.photos.add(p.basename(file.path));
                return hooks.photoResult;
              }
            : null,
        setSecureScreen: (enabled) async => hooks.secure.add(enabled),
        copySensitive: (text, seconds) async {
          if (!hooks.nativeCopy) return false;
          hooks.copied.add((text, seconds));
          return true;
        },
        openFileSafely: platformHooks
            ? (file, {required allowExecutable}) async {
                hooks.opened.add((p.basename(file.path), allowExecutable));
                return hooks.openResult;
              }
            : null,
        revealInFolder: platformHooks
            ? (file) async {
                hooks.revealed.add(file.path);
                return true;
              }
            : null,
        markFromInternet: platformHooks
            ? (file) async {
                hooks.marked.add(p.basename(file.path));
                return true;
              }
            : null,
      ),
    );
    await controller.initialize();
    return _Node(dir, controller, hooks);
  }

  Future<void> close() async {
    await controller.shutdown();
    controller.dispose();
    await hooks.intakeSignal.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<void> _pair(TransferAppController a, TransferAppController b) async {
  await b.createInvitation();
  final pairing = a.pairFromText(b.invitation!.payload);
  await _waitUntil(() => b.pendingPairings.isNotEmpty, reason: 'pairing ask');
  await b.respondToPairing(b.pendingPairings.single.id, true);
  await pairing;
  await _waitUntil(
    () => a.peers.any((peer) => peer.isTrusted && peer.isOnline),
    reason: 'pairing completes',
  );
}

Future<void> _receive(_Node sender, _Node receiver) async {
  final peer = sender.controller.peers.singleWhere((x) => x.isTrusted);
  await sender.controller.sendTo(peer.id);
  expect(sender.controller.errorMessage, isNull);
  await _waitUntil(
    () => receiver.controller.pendingTransfers.isNotEmpty,
    reason: 'offer arrives',
  );
  await receiver.controller.respondToTransfer(
    receiver.controller.pendingTransfers.single.id,
    true,
  );
  await _waitUntil(
    () => sender.controller.transfers.every(
      (t) => t.phase == TransferPhase.completed,
    ),
    reason: 'transfer completes',
    timeout: const Duration(seconds: 40),
  );
  await _waitUntil(
    () => receiver.controller.transfers.any(
      (t) => t.phase == TransferPhase.completed,
    ),
    reason: 'receiver lists the completed transfer',
  );
}

File _write(String path, int size) {
  final file = File(path)..createSync(recursive: true);
  file.writeAsBytesSync(Uint8List.fromList(List.filled(size, 7)));
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'both screens show the same six-digit code; the joiner can cancel',
    () => _realNetwork(() async {
      final a = await _Node.create('Joiner');
      final b = await _Node.create('Host');
      try {
        await b.controller.createInvitation();
        final pairing = a.controller.pairFromText(
          b.controller.invitation!.payload,
        );
        // Commit/reveal: neither side has a code until both nonces were
        // exchanged; the joiner shows "connecting" meanwhile.
        expect(a.controller.outgoingPairing?.hostName, 'Host');
        expect(a.controller.outgoingPairing?.code, isNull);
        await _waitUntil(
          () =>
              b.controller.pendingPairings.isNotEmpty &&
              a.controller.outgoingPairing?.code != null,
          reason: 'code revealed on both sides',
        );
        final outgoing = a.controller.outgoingPairing!;
        expect(outgoing.hostName, 'Host');
        expect(outgoing.legacy, isFalse);
        expect(outgoing.code, matches(RegExp(r'^[0-9]{6}$')));
        expect(b.controller.pendingPairings.single.code, outgoing.code);
        expect(b.controller.pendingPairings.single.legacy, isFalse);

        await a.controller.cancelOutgoingPairing();
        await pairing;
        expect(a.controller.outgoingPairing, isNull);
        expect(a.controller.errorMessage, isNull);
        expect(a.controller.statusMessage, _ru.pairingCancelled);
        expect(a.controller.peers.where((x) => x.isTrusted), isEmpty);
      } finally {
        await a.close();
        await b.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'nearby pairing: an open window is discoverable and still needs approval',
    () => _realNetwork(() async {
      final a = await _Node.create('Phone', discovery: true);
      final b = await _Node.create('Laptop', discovery: true);
      try {
        expect(a.controller.capabilities.nearbyPairing, isTrue);
        expect(a.controller.nearbyPairable, isEmpty);
        await b.controller.setNearbyPairing(true);
        expect(b.controller.nearbyPairingOpen, isTrue);
        await _waitUntil(
          () => a.controller.nearbyPairable.isNotEmpty,
          reason: 'pairable device listed',
        );
        final device = a.controller.nearbyPairable.single;
        expect(device.name, 'Laptop');
        expect(device.platform, DevicePlatform.linux);

        final pairing = a.controller.pairNearby(device.id);
        await _waitUntil(
          () =>
              b.controller.pendingPairings.isNotEmpty &&
              a.controller.outgoingPairing?.code != null,
          reason: 'host asked to approve',
        );
        expect(a.controller.outgoingPairing!.legacy, isFalse);
        expect(
          b.controller.pendingPairings.single.code,
          a.controller.outgoingPairing!.code,
        );
        await b.controller.respondToPairing(
          b.controller.pendingPairings.single.id,
          true,
        );
        await pairing;
        expect(a.controller.errorMessage, isNull);
        await _waitUntil(
          () => a.controller.peers.any((x) => x.isTrusted && x.isOnline),
          reason: 'paired',
        );

        await b.controller.setNearbyPairing(false);
        expect(b.controller.nearbyPairingOpen, isFalse);
        await _waitUntil(
          () => a.controller.nearbyPairable.isEmpty,
          reason: 'hint withdrawn',
        );
        await a.controller.pairNearby('nearby:gone');
        expect(a.controller.errorMessage, _ru.errNearbyUnavailable);
      } finally {
        await a.close();
        await b.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a folder keeps its structure; received files land in the visible folder '
    'and carry media/executable flags, MOTW and auto-save',
    () => _realNetwork(() async {
      final work = await Directory.systemTemp.createTemp('ulash-folder-');
      final visible = Directory(p.join(work.path, 'Downloads', 'Ulash'));
      final a = await _Node.create('Sender');
      final b = await _Node.create(
        'Receiver',
        received: visible,
        platformHooks: true,
      );
      try {
        final album = p.join(work.path, 'Album');
        _write(p.join(album, 'notes.txt'), 10);
        _write(p.join(album, 'trip', 'photo.jpg'), 2048);
        _write(p.join(album, 'trip', 'tools', 'setup.exe'), 64);
        _write(p.join(album, '.DS_Store'), 4);
        await _pair(a.controller, b.controller);

        expect(a.controller.capabilities.folderSelection, isTrue);
        a.hooks.folder = album;
        await a.controller.chooseFolder();
        expect(a.controller.errorMessage, isNull);
        final sources = a.controller.selectedSources;
        expect(sources, hasLength(3), reason: 'OS metadata is skipped');
        expect(
          {for (final s in sources) s.name: s.relativeDirectory},
          {
            'notes.txt': 'Album',
            'photo.jpg': 'Album/trip',
            'setup.exe': 'Album/trip/tools',
          },
        );

        await b.controller.setAutoSaveToPhotos(true);
        expect(b.controller.autoSaveToPhotos, isTrue);
        await _receive(a, b);

        final outgoing = a.controller.transfers.single;
        expect(outgoing.kind, TransferKind.folder);
        expect(outgoing.title, 'Album');
        final incoming = b.controller.transfers.singleWhere(
          (t) => t.direction == TransferDirection.incoming,
        );
        expect(incoming.kind, TransferKind.folder);
        final files = {for (final f in incoming.receivedFiles) f.name: f};
        expect(files['photo.jpg']!.relativeDirectory, 'Album/trip');
        expect(files['photo.jpg']!.isMedia, isTrue);
        expect(files['notes.txt']!.isMedia, isFalse);
        expect(files['setup.exe']!.potentiallyExecutable, isTrue);
        expect(files['notes.txt']!.potentiallyExecutable, isFalse);
        final preview = files['photo.jpg']!.previewPath!;
        // Windows CI temp dirs use 8.3 short names (RUNNER~1); the store
        // canonicalises its folders, so compare against the long form.
        final visibleRoot = visible.resolveSymbolicLinksSync();
        expect(p.isWithin(visibleRoot, preview), isTrue);
        expect(File(preview).existsSync(), isTrue);
        expect(
          p.split(p.relative(preview, from: visibleRoot)).skip(1).toList(),
          ['Album', 'trip', 'photo.jpg'],
        );
        expect(files['notes.txt']!.previewPath, isNull);
        expect(b.controller.saveLocationLabel, visible.path);

        // Originals are untouched.
        expect(File(p.join(album, 'trip', 'photo.jpg')).existsSync(), isTrue);

        await _waitUntil(
          () => b.hooks.marked.length == 3,
          reason: 'Mark-of-the-Web on every received file',
        );
        await _waitUntil(
          () => b.hooks.photos.isNotEmpty,
          reason: 'auto-save to Photos',
        );
        expect(b.hooks.photos, ['photo.jpg'], reason: 'media only');

        // Manual save, then a denied permission.
        await b.controller.saveToPhotos(incoming.id, files['photo.jpg']!.id);
        expect(b.controller.statusMessage, _ru.savedToPhotos);
        b.hooks.photoResult = SaveToPhotosResult.denied;
        await b.controller.saveToPhotos(incoming.id, files['photo.jpg']!.id);
        expect(b.controller.errorMessage, _ru.errPhotosDenied);

        // Windows-style opening: marked, never allowed to run executables.
        b.hooks.marked.clear();
        b.hooks.openResult = OpenFileResult.blocked;
        await b.controller.openReceivedFile(
          incoming.id,
          files['setup.exe']!.id,
        );
        expect(b.hooks.opened.single, ('setup.exe', false));
        expect(b.hooks.marked, ['setup.exe']);
        expect(b.controller.errorMessage, _ru.errOpenBlocked);
        await b.controller.revealReceivedFile(
          incoming.id,
          files['notes.txt']!.id,
        );
        expect(p.basename(b.hooks.revealed.single), 'notes.txt');
      } finally {
        await a.close();
        await b.close();
        await work.delete(recursive: true);
      }
    }),
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test('unsuitable folders are refused before anything is copied', () async {
    final work = await Directory.systemTemp.createTemp('ulash-folder-');
    final node = await _Node.create('Picker');
    try {
      final empty = Directory(p.join(work.path, 'Empty'))..createSync();
      node.hooks.folder = empty.path;
      await node.controller.chooseFolder();
      expect(node.controller.errorMessage, _ru.errFolderEmpty);

      final deep = [work.path, 'Deep', for (var i = 0; i < 9; i++) 'd$i'];
      _write(p.joinAll([...deep, 'x.txt']), 1);
      node.hooks.folder = p.join(work.path, 'Deep');
      await node.controller.chooseFolder();
      expect(node.controller.errorMessage, _ru.errFolderPath);

      final big = p.join(work.path, 'Big');
      for (var i = 0; i <= core.TransferLimits.maxFiles; i++) {
        _write(p.join(big, 'f$i.bin'), 1);
      }
      node.hooks.folder = big;
      await node.controller.chooseFolder();
      expect(node.controller.errorMessage, _ru.errFolderTooLarge);
      expect(node.controller.selectedSources, isEmpty);

      node.hooks.folder = null; // picker cancelled
      await node.controller.chooseFolder();
      expect(node.controller.selectedSources, isEmpty);
    } finally {
      await node.close();
      await work.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test(
    'shared files are adopted into the selection at start and on signal',
    () async {
      final temporary = await Directory.systemTemp.createTemp('ulash-tmp-');
      final early = _write(p.join(temporary.path, 'early.pdf'), 100);
      // A batch is already waiting when the app starts.
      final node = await _Node.create(
        'Intake',
        temporary: temporary,
        platformHooks: true,
        intake: [IntakeItem(path: early.path, name: 'Отчёт.pdf')],
      );
      try {
        await _waitUntil(
          () => node.controller.selectedSources.length == 1,
          reason: 'startup takes pending intake',
        );
        expect(node.controller.selectedSources.single.name, 'Отчёт.pdf');
        expect(early.existsSync(), isFalse, reason: 'adopted, not copied');

        final resumed = _write(p.join(temporary.path, 'resumed.txt'), 10);
        node.hooks.intake.add(IntakeItem(path: resumed.path, name: 'a.txt'));
        node.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
        node.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await _waitUntil(
          () => node.controller.selectedSources.length == 2,
          reason: 'resume takes pending intake',
        );

        final later = _write(p.join(temporary.path, 'later.png'), 50);
        node.hooks.intake.add(IntakeItem(path: later.path, name: 'later.png'));
        node.hooks.intakeSignal.add(null);
        await _waitUntil(
          () => node.controller.selectedSources.length == 3,
          reason: 'signal takes pending intake',
        );
        expect(node.controller.statusMessage, _ru.intakeAdded(1));
        expect(later.existsSync(), isFalse);
      } finally {
        await node.close();
        await temporary.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('a 1.0 data root is moved once and never deleted on conflict', () async {
    final legacy = await Directory.systemTemp.createTemp('ulash-roaming-');
    final current = await Directory.systemTemp.createTemp('ulash-local-');
    try {
      final marker = _write(
        p.join(legacy.path, 'file-transfer-v1', 'marker.txt'),
        3,
      );
      final node = await _Node.create(
        'Migrate',
        root: current,
        legacyRoot: legacy,
      );
      expect(node.controller.startupIssue, StartupIssue.none);
      expect(marker.existsSync(), isFalse);
      expect(
        File(p.join(current.path, 'file-transfer-v1', 'marker.txt'))
            .existsSync(),
        isTrue,
      );
      await node.controller.shutdown();
      node.controller.dispose();

      // Both exist: the current root wins; the legacy copy stays.
      final stale = _write(
        p.join(legacy.path, 'file-transfer-v1', 'stale.txt'),
        3,
      );
      final again = await _Node.create(
        'Migrate',
        root: current,
        legacyRoot: legacy,
      );
      expect(stale.existsSync(), isTrue);
      await again.close();
    } finally {
      if (await legacy.exists()) await legacy.delete(recursive: true);
      if (await current.exists()) await current.delete(recursive: true);
    }
  });

  test(
    'invitation copy uses the sensitive clipboard; secure screen is counted',
    () => _realNetwork(() async {
      final node = await _Node.create('Copy');
      try {
        expect(await node.controller.copyInvitation(), isFalse);
        await node.controller.createInvitation();
        expect(await node.controller.copyInvitation(), isTrue);
        expect(node.hooks.copied.single, (
          node.controller.invitation!.payload,
          120,
        ));
        expect(
          node.controller.invitation!.payload,
          startsWith('xferapp://pair?'),
          reason: 'the scanner accepts only this prefix',
        );

        final writes = <String?>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                writes.add((call.arguments as Map)['text'] as String?);
              }
              return null;
            });
        node.hooks.nativeCopy = false;
        expect(await node.controller.copyInvitation(), isTrue);
        expect(writes, [node.controller.invitation!.payload]);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);

        await node.controller.setSecureScreen(true);
        await node.controller.setSecureScreen(true);
        await node.controller.setSecureScreen(false);
        await node.controller.setSecureScreen(false);
        await node.controller.setSecureScreen(false);
        expect(node.hooks.secure, [true, false]);
        expect(node.controller.maxMessageLength, 64 * 1024);
      } finally {
        await node.close();
      }
    }),
  );

  test('journals use the shared versioned opener', () async {
    final dir = await Directory.systemTemp.createTemp('ulash-journal-');
    try {
      OutgoingJournal(dir).close();
      final db = sqlite3.open(p.join(dir.path, 'outgoing.sqlite3'));
      expect(db.select('PRAGMA user_version').first.values.first, 1);
      expect(
        db.select('PRAGMA journal_mode').first.values.first.toString(),
        'wal',
      );
      db.execute('PRAGMA user_version=9');
      db.close();
      expect(
        () => OutgoingJournal(dir),
        throwsA(
          isA<core.StorageException>().having(
            (e) => e.code,
            'code',
            'JOURNAL_TOO_NEW',
          ),
        ),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test(
    'the browser share listens on the link address; its own expiry clears '
    'pending upload requests',
    () => _realNetwork(() async {
      final node = await _Node.create(
        'Web',
        webShareTtl: const Duration(seconds: 2),
      );
      try {
        await node.controller.startWebShare(allowUpload: true);
        final share = node.controller.webShare!;
        expect(share.url.host, '127.0.0.1');
        final http = HttpClient();
        final request = await http.postUrl(share.url.resolve('ask'));
        request.write(
          jsonEncode({
            'files': [
              {'name': 'a.txt', 'size': 3},
            ],
          }),
        );
        // Refused either with 403 or by the connection closing on stop.
        final reply = request.close().then(
          (response) => response.statusCode,
          onError: (Object _) => 403,
        );
        await _waitUntil(
          () => node.controller.pendingWebUploads.isNotEmpty,
          reason: 'upload request shown',
        );
        await _waitUntil(
          () => node.controller.webShare == null,
          reason: 'share stops by itself',
        );
        expect(node.controller.pendingWebUploads, isEmpty);
        expect(await reply, 403);
        http.close(force: true);
      } finally {
        await node.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a 1.0/1.1 joiner (no commitment) is shown with its key code and a note',
    () => _realNetwork(() async {
      final host = await _Node.create('Host');
      final old = await core.DeviceIdentity.generate(displayName: 'Old phone');
      final http = HttpClient()
        // Test-only: the request below plays an old joiner; the key check is
        // not what this test is about.
        ..badCertificateCallback = (_, _, _) => true;
      try {
        await host.controller.createInvitation();
        final invite = core.PairingInvite.parse(
          host.controller.invitation!.payload,
        );
        final request = await http.postUrl(
          invite.endpoints.first.replace(path: '/v1/pairing/requests'),
        );
        request.headers
          ..contentType = ContentType.json
          ..set('Authorization', 'Invite ${invite.inviteSecret}');
        request.write(
          jsonEncode({
            'requestId': 'legacy-request-1',
            'inviteId': invite.inviteId,
            'peerId': old.peerId,
            'serverPin': old.serverPin,
            'displayName': old.displayName,
            'reverseToken': base64Url
                .encode(List.generate(32, (i) => i * 7 % 256))
                .replaceAll('=', ''),
          }),
        );
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, inInclusiveRange(200, 202));
        await _waitUntil(
          () => host.controller.pendingPairings.isNotEmpty,
          reason: 'legacy request listed',
        );
        final pending = host.controller.pendingPairings.single;
        expect(pending.legacy, isTrue);
        expect(pending.deviceName, 'Old phone');
        expect(pending.code, core.shortFingerprint(old.peerId));
        expect(pending.code, matches(RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}$')));
      } finally {
        http.close(force: true);
        await host.close();
      }
    }),
  );

  test('pairing errors from the new scheme have clear messages', () {
    expect(_ru.errUpgradeRequired, contains('Обновите Ulash'));
    expect(_ru.errCommitmentMismatch, contains('новым кодом'));
  });
}
