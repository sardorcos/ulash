// Manual screenshot harness for design review, not a pixel-regression test.
// Renders the real widgets with synthetic, test-only data. Run with
//   CAPTURE_OUT=/some/dir flutter test test/capture_previews_test.dart
// Nothing is written unless CAPTURE_OUT is set, and never into the repo.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_transfer/ui/app_controller.dart';
import 'package:file_transfer/ui/file_transfer_app.dart';
import 'package:flutter/foundation.dart';
// Test the bundled Material API used by the compatible application shell.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _out = Platform.environment['CAPTURE_OUT'];

/// Rich demo state; exists only in this test.
class _DemoController extends AppController {
  _DemoController(this.previews);
  final List<String> previews;

  @override
  String deviceName = 'iPhone Сардора';
  @override
  NetworkState networkState = NetworkState.ready;
  @override
  bool receivingEnabled = true;
  @override
  bool isBusy = false;
  @override
  List<SelectedSource> selectedSources = [];
  @override
  List<PeerDevice> peers = [];
  @override
  List<TransferItem> transfers = [];
  @override
  List<IncomingTransfer> pendingTransfers = [];
  @override
  List<PairingRequest> pendingPairings = [];
  @override
  PairingInvitation? invitation;
  @override
  ThemeMode themeMode = ThemeMode.light;
  @override
  Locale? locale = const Locale('ru');
  @override
  String? deviceCode = '4F2A-91C7';
  @override
  String get versionLabel => '1.2.0 (120)';
  @override
  String get saveLocationLabel => 'Файлы › Ulash';
  @override
  List<NearbyDevice> nearbyPairable = [];
  @override
  WebShareState? webShare;
  @override
  bool autoSaveToPhotos = true;
  @override
  List<WebUploadRequest> pendingWebUploads = [];
  bool onboarding = false;
  @override
  bool get needsOnboarding => onboarding;
  @override
  Future<void> completeOnboarding() async {
    onboarding = false;
    notifyListeners();
  }
  @override
  StorageOverview? storageOverview;
  @override
  AppCapabilities get capabilities => const AppCapabilities(
    mediaSelection: true,
    folderSelection: true,
    textMessages: true,
    nearbyPairing: true,
    webShare: true,
    photosSave: true,
    share: true,
    qrScanner: true,
    fileExport: true,
    storageManagement: true,
    diagnostics: true,
  );

  void seed() {
    final now = DateTime.now();
    peers = const [
      PeerDevice(
        id: 'mac',
        name: 'MacBook Air',
        platform: DevicePlatform.macos,
        isTrusted: true,
        isOnline: true,
      ),
      PeerDevice(
        id: 'pc',
        name: 'Домашний ПК',
        platform: DevicePlatform.windows,
        isTrusted: true,
        isOnline: true,
      ),
      PeerDevice(
        id: 'tab',
        name: 'Galaxy Tab',
        platform: DevicePlatform.android,
        isTrusted: true,
        isOnline: false,
      ),
    ];
    selectedSources = [
      const SelectedSource(id: '1', name: 'IMG_2041.HEIC', bytes: 3400000),
      const SelectedSource(id: '2', name: 'Отчёт за ноябрь.pdf', bytes: 1250000),
      const SelectedSource(id: '3', name: 'Видео с дня рождения.mov', bytes: 486000000),
    ];
    nearbyPairable = const [
      NearbyDevice(id: 'n1', name: 'iPad Мадины', platform: DevicePlatform.ios),
    ];
    pendingTransfers = [
      IncomingTransfer(
        id: 'offer',
        peerName: 'MacBook Air',
        fileNames: const ['Презентация.key', 'Логотип.png', 'Шрифты.zip'],
        totalBytes: 84 * 1024 * 1024,
        expiresAt: now.add(const Duration(minutes: 4)),
      ),
    ];
    transfers = [
      TransferItem(
        id: 'live',
        title: 'Видео с дня рождения.mov',
        peerName: 'Домашний ПК',
        direction: TransferDirection.outgoing,
        phase: TransferPhase.transferring,
        totalBytes: 486000000,
        transferredBytes: 301000000,
        bytesPerSecond: 38000000,
        createdAt: now.subtract(const Duration(minutes: 1)),
        canPause: true,
        canCancel: true,
      ),
      TransferItem(
        id: 'photos',
        title: '12 фото',
        peerName: 'MacBook Air',
        direction: TransferDirection.incoming,
        phase: TransferPhase.completed,
        totalBytes: 41000000,
        transferredBytes: 41000000,
        fileCount: 12,
        createdAt: now.subtract(const Duration(minutes: 25)),
        canOpen: true,
        canExport: true,
        canDelete: true,
        receivedFiles: [
          for (var i = 0; i < previews.length; i++)
            ReceivedFile(
              id: 'p$i',
              name: 'IMG_31${i}0.JPG',
              bytes: 3400000,
              isMedia: true,
              previewPath: previews[i],
            ),
        ],
      ),
      TransferItem(
        id: 'text',
        title: 'Текст',
        peerName: 'MacBook Air',
        direction: TransferDirection.incoming,
        phase: TransferPhase.completed,
        totalBytes: 40,
        transferredBytes: 40,
        createdAt: now.subtract(const Duration(hours: 2)),
        kind: TransferKind.text,
        messageText: 'Wi-Fi гостиницы: Navruz-5G, пароль 2026tash',
        canDelete: true,
      ),
      TransferItem(
        id: 'folder',
        title: 'Проект Ulash',
        peerName: 'Домашний ПК',
        direction: TransferDirection.outgoing,
        phase: TransferPhase.completed,
        kind: TransferKind.folder,
        totalBytes: 18200000,
        transferredBytes: 18200000,
        fileCount: 48,
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
        canDelete: true,
      ),
      TransferItem(
        id: 'expired',
        title: 'Договор.docx',
        peerName: 'Galaxy Tab',
        direction: TransferDirection.outgoing,
        phase: TransferPhase.expired,
        totalBytes: 220000,
        transferredBytes: 0,
        createdAt: now.subtract(const Duration(days: 1, hours: 5)),
        canRetry: true,
        canDelete: true,
      ),
    ];
    storageOverview = StorageOverview(
      availableBytes: 58 * 1024 * 1024 * 1024,
      temporaryBytes: 820 * 1024 * 1024,
      reservedBytes: 120 * 1024 * 1024,
      safetyReserveBytes: 1024 * 1024 * 1024,
      temporaryQuotaBytes: 10 * 1024 * 1024 * 1024,
      checkedAt: now,
      unusedFiles: const [
        TemporaryFileItem(id: 'u', name: 'IMG_2041.HEIC', bytes: 3400000),
      ],
    );
  }

  void setLocaleCode(String code) {
    locale = Locale(code);
    notifyListeners();
  }

  void refresh() => notifyListeners();

  @override
  Future<void> setLocale(Locale? value) async {
    locale = value;
    notifyListeners();
  }

  @override
  Future<void> chooseFiles() async {}
  @override
  Future<void> removeSource(String sourceId) async {}
  @override
  Future<void> clearSources() async {}
  @override
  Future<void> sendTo(String peerId) async {}
  @override
  Future<void> refreshPeers() async {}
  @override
  Future<void> setReceiving(bool enabled) async {}
  @override
  Future<void> createInvitation() async {
    invitation = PairingInvitation(
      payload: 'ulash://pair/demo-only-not-a-real-invitation',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    notifyListeners();
  }

  @override
  Future<void> pairFromText(String payload) async {}
  @override
  Future<void> respondToPairing(String requestId, bool accept) async {}
  @override
  Future<void> respondToTransfer(String transferId, bool accept) async {}
  @override
  Future<void> pauseTransfer(String transferId) async {}
  @override
  Future<void> resumeTransfer(String transferId) async {}
  @override
  Future<void> cancelTransfer(String transferId) async {}
  @override
  Future<void> revokePeer(String peerId) async {}
  @override
  Future<void> renameDevice(String name) async {}
  @override
  Future<void> setThemeMode(ThemeMode mode) async {}
  @override
  Future<void> startWebShare({bool allowUpload = false}) async {
    webShare = WebShareState(
      url: Uri.parse('http://192.168.1.24:8080/s/7Hq2'),
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      allowUpload: allowUpload,
      connectedClients: 1,
      downloadedFiles: 2,
      sharedFileCount: 3,
    );
    notifyListeners();
  }
}

String _sdkRoot() {
  final env = Platform.environment['FLUTTER_SDK'] ?? Platform.environment['FLUTTER_ROOT'];
  if (env != null) return env;
  final exe = Platform.resolvedExecutable;
  final index = exe.indexOf('/bin/cache/');
  if (index < 0) throw StateError('Set FLUTTER_SDK to the Flutter SDK.');
  return exe.substring(0, index);
}

Future<void> _loadFonts() async {
  final root = '${_sdkRoot()}/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String name) async =>
      ByteData.sublistView(await File('$root/$name').readAsBytes());
  // iOS typography asks for the system font; Roboto stands in for it here.
  for (final family in [
    'Roboto',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    '.SF Pro Text',
    '.SF Pro Display',
    '.SF UI Text',
    '.SF UI Display',
  ]) {
    final loader = FontLoader(family);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(read('Roboto-$weight.ttf'));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

/// Small gradient "photos" so thumbnails look like thumbnails.
Future<List<String>> _makePreviews(Directory dir) async {
  const palettes = [
    [Color(0xFF00A295), Color(0xFFB6F0E6)],
    [Color(0xFFFF8A65), Color(0xFFFFE0B2)],
    [Color(0xFF5C6BC0), Color(0xFFB3E5FC)],
  ];
  final paths = <String>[];
  for (var i = 0; i < palettes.length; i++) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const rect = Rect.fromLTWH(0, 0, 160, 160);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          palettes[i],
        ),
    );
    canvas.drawCircle(
      const Offset(110, 50),
      22,
      Paint()..color = Colors.white.withValues(alpha: .7),
    );
    final image = await recorder.endRecording().toImage(160, 160);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${dir.path}/preview$i.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    paths.add(file.path);
  }
  return paths;
}

void main() {
  testWidgets('capture design previews', (tester) async {
    final out = Directory(_out!)..createSync(recursive: true);
    late Directory temp;
    late List<String> previews;
    await tester.runAsync(() async {
      await _loadFonts();
      temp = await Directory.systemTemp.createTemp('ulash-previews-');
      previews = await _makePreviews(temp);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final boundary = GlobalKey();
    final controller = _DemoController(previews)..seed();

    Future<void> setSize(Size size) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = size * 2;
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
    }

    Future<void> settle() async {
      await tester.pumpAndSettle();
      // Let thumbnails decode on the real clock.
      await tester.runAsync(() async {
        for (final path in previews) {
          for (final width in [80, 96]) {
            final provider = ResizeImage.resizeIfNeeded(
              width,
              null,
              FileImage(File(path)),
            );
            final stream = provider.resolve(ImageConfiguration.empty);
            final done = Completer<void>();
            final listener = ImageStreamListener(
              (_, _) => done.isCompleted ? null : done.complete(),
              onError: (_, _) => done.isCompleted ? null : done.complete(),
            );
            stream.addListener(listener);
            await done.future.timeout(
              const Duration(seconds: 2),
              onTimeout: () {},
            );
            stream.removeListener(listener);
          }
        }
      });
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> capture(String name) async {
      await settle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${out.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull, reason: name);
    }

    Future<void> tapKey(String key) async {
      final finder = find.byKey(Key(key)).first;
      await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
    }

    Future<void> dismissSheet() async {
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    try {
      await setSize(const Size(390, 844));
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: FileTransferApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      // The first notification brings the waiting offer forward as a sheet.
      controller.refresh();
      await tester.pumpAndSettle();
      await capture('sheet-ru-incoming-offer');
      await dismissSheet();

      const sizes = {
        'iphone-390': Size(390, 844),
        'iphone-430': Size(430, 932),
        'ipad-1024': Size(1024, 1366),
      };
      for (final MapEntry(key: device, value: size) in sizes.entries) {
        await setSize(size);
        final wide = size.width >= 760;
        for (final code in ['ru', 'uz', 'en']) {
          controller.setLocaleCode(code);
          await tapKey('nav-send');
          await capture('$device-$code-1-send');
          await tapKey('nav-history');
          await capture('$device-$code-2-history');
          await tapKey('nav-devices');
          await capture('$device-$code-3-devices');
          await tapKey('nav-settings');
          await capture('$device-$code-4-settings');
          if (!wide) await back();
        }
      }

      // Large text (Dynamic Type 200%) on the smallest phone.
      await setSize(const Size(390, 844));
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      for (final code in ['ru', 'uz', 'en']) {
        controller.setLocaleCode(code);
        await tapKey('nav-send');
        await capture('large-text-$code-1-send');
        await tapKey('nav-history');
        await capture('large-text-$code-2-history');
        await tapKey('nav-devices');
        await capture('large-text-$code-3-devices');
        await tapKey('nav-settings');
        await capture('large-text-$code-4-settings');
        await back();
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();

      // Sheets and dialogs (Russian, 390pt).
      controller.setLocaleCode('ru');
      await tapKey('nav-devices');
      await tapKey('create-invitation');
      await capture('sheet-ru-qr');
      await tapKey('close-invitation');
      controller.pendingPairings = const [
        PairingRequest(
          id: 'pair',
          deviceName: 'iPad Мадины',
          platform: DevicePlatform.ios,
          code: '482915',
        ),
      ];
      controller.refresh();
      await tester.pumpAndSettle();
      await capture('dialog-ru-codes-match');
      await tapKey('dialog-decline-pair-pair');
      controller.pendingPairings = const [];
      controller.refresh();
      await tapKey('nav-send');
      await tapKey('open-web-share');
      await tapKey('web-share-start');
      await capture('sheet-ru-web-share');
      await dismissSheet();
      await tapKey('compose-text');
      await capture('sheet-ru-text');
      await dismissSheet();
      controller.pendingWebUploads = const [
        WebUploadRequest(
          id: 'up',
          client: '192.168.1.31',
          fileNames: ['Скан паспорта.pdf', 'Фото.jpg'],
          totalBytes: 5800000,
        ),
      ];
      controller.refresh();
      await tester.pumpAndSettle();
      await capture('sheet-ru-web-upload');
      await dismissSheet();

      // Fresh install: onboarding, then the first-device prompt.
      final fresh = _DemoController(previews)..onboarding = true;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: FileTransferApp(controller: fresh),
        ),
      );
      await tester.pumpAndSettle();
      await capture('first-run-ru-1-onboarding');
      await tapKey('onboarding-next');
      await capture('first-run-ru-2-allow-access');
      await tapKey('onboarding-next');
      await capture('first-run-ru-3-send-empty');
      await tapKey('nav-devices');
      await capture('first-run-ru-4-devices-empty');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => temp.delete(recursive: true));
    }
  }, skip: _out == null);
}
