import 'package:file_transfer/ui/app_controller.dart';
import 'package:file_transfer/ui/file_transfer_app.dart';
// Test the bundled Material API used by the compatible application shell.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic data is confined to tests. Production UI never seeds a controller.
class TestController extends AppController {
  @override
  String deviceName = 'Тестовое устройство';
  @override
  NetworkState networkState = NetworkState.ready;
  @override
  bool receivingEnabled = false;
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
  String? errorMessage;
  AppCapabilities availableCapabilities = const AppCapabilities();
  @override
  AppCapabilities get capabilities => availableCapabilities;
  @override
  StorageOverview? storageOverview;

  int chooseCount = 0;
  String? sentPeer;
  String? pairedText;
  (String, String)? openedFile;
  (String, String)? exportedFile;
  List<String>? cleanedFiles;
  final responses = <(String, bool)>[];

  @override
  Future<void> chooseFiles() async {
    chooseCount++;
  }

  @override
  Future<void> removeSource(String sourceId) async {
    selectedSources = selectedSources.where((s) => s.id != sourceId).toList();
    notifyListeners();
  }

  @override
  Future<void> clearSources() async {
    selectedSources = [];
    notifyListeners();
  }

  @override
  Future<void> sendTo(String peerId) async {
    sentPeer = peerId;
  }

  @override
  Future<void> refreshPeers() async {}
  @override
  Future<void> setReceiving(bool enabled) async {
    receivingEnabled = enabled;
    notifyListeners();
  }

  @override
  Future<void> createInvitation() async {
    invitation = PairingInvitation(
      payload: 'test-only-invitation',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    notifyListeners();
  }

  @override
  Future<void> pairFromText(String payload) async {
    pairedText = payload;
  }

  @override
  Future<void> respondToPairing(String requestId, bool accept) async {}
  @override
  Future<void> respondToTransfer(String transferId, bool accept) async {
    responses.add((transferId, accept));
    pendingTransfers = pendingTransfers
        .where((t) => t.id != transferId)
        .toList();
    notifyListeners();
  }

  @override
  Future<void> pauseTransfer(String transferId) async {}
  @override
  Future<void> resumeTransfer(String transferId) async {}
  @override
  Future<void> cancelTransfer(String transferId) async {}
  @override
  Future<void> openReceivedFile(String transferId, String fileId) async {
    openedFile = (transferId, fileId);
  }

  @override
  Future<void> exportReceivedFile(String transferId, String fileId) async {
    exportedFile = (transferId, fileId);
  }

  @override
  Future<void> clearUnusedTemporary(List<String> fileIds) async {
    cleanedFiles = List.of(fileIds);
  }

  @override
  Future<void> revokePeer(String peerId) async {}
  @override
  Future<void> renameDevice(String name) async {
    deviceName = name;
    notifyListeners();
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
  }
}

Future<void> setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.binding.setSurfaceSize(null);
  });
}

void main() {
  testWidgets('all five mobile pages fit 360px and do not invent transfers', (
    tester,
  ) async {
    await setSize(tester, const Size(360, 800));
    final controller = TestController();
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Начнём с файлов'), findsOneWidget);
    expect(find.text('Передача завершена'), findsNothing);
    for (final tab in ['receive', 'devices', 'history', 'settings', 'send']) {
      await tester.tap(find.byKey(Key('nav-$tab')));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Mobile page $tab must not overflow.',
      );
    }
    await tester.ensureVisible(find.byKey(const Key('choose-files')));
    await tester.tap(find.byKey(const Key('choose-files')));
    await tester.pump();
    expect(controller.chooseCount, 1);
  });

  testWidgets('short desktop and enlarged text remain usable', (tester) async {
    await setSize(tester, const Size(1024, 600));
    final controller = TestController();
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    for (final tab in ['send', 'receive', 'devices', 'history', 'settings']) {
      await tester.tap(find.byKey(Key('nav-$tab')));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Desktop page $tab must not overflow.',
      );
    }
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending needs a prepared source and a trusted available peer', (
    tester,
  ) async {
    await setSize(tester, const Size(1280, 1000));
    final controller = TestController();
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('send-selected')))
          .onPressed,
      isNull,
    );
    controller.selectedSources = [
      const SelectedSource(id: 'source', name: 'Документ.pdf', bytes: 1024),
    ];
    controller.peers = [
      const PeerDevice(
        id: 'trusted',
        name: 'Ноутбук',
        platform: DevicePlatform.windows,
        isTrusted: true,
        isOnline: true,
      ),
      const PeerDevice(
        id: 'untrusted',
        name: 'Незнакомое устройство',
        platform: DevicePlatform.android,
        isTrusted: false,
        isOnline: true,
      ),
    ];
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('peer-untrusted')), findsNothing);
    await tester.tap(find.byKey(const Key('peer-trusted')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send-selected')));
    await tester.pump();
    expect(controller.sentPeer, 'trusted');
  });

  testWidgets('incoming consent is explicit and reaches the controller', (
    tester,
  ) async {
    await setSize(tester, const Size(1280, 1000));
    final controller = TestController()
      ..pendingTransfers = [
        const IncomingTransfer(
          id: 'incoming',
          peerName: 'Отправитель',
          fileNames: ['Фото.heic'],
          totalBytes: 4000,
        ),
      ];
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.responses, isEmpty);
    await tester.tap(find.byKey(const Key('nav-receive')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('accept-incoming')));
    await tester.tap(find.byKey(const Key('accept-incoming')));
    await tester.pumpAndSettle();
    expect(controller.responses, [('incoming', true)]);
    expect(find.byKey(const Key('accept-incoming')), findsNothing);
  });

  testWidgets(
    '100 percent bytes during verification is not successful delivery',
    (tester) async {
      await setSize(tester, const Size(1280, 1000));
      final controller = TestController()
        ..transfers = [
          TransferItem(
            id: 'verify',
            title: 'Видео.mov',
            peerName: 'Ноутбук',
            direction: TransferDirection.outgoing,
            phase: TransferPhase.verifying,
            totalBytes: 100,
            transferredBytes: 100,
            createdAt: DateTime(2026, 11, 20),
          ),
        ];
      await tester.pumpWidget(FileTransferApp(controller: controller));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('nav-history')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Проверяем файл'), findsOneWidget);
      expect(find.text('Передача завершена'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
    },
  );

  testWidgets(
    'manual invitation is forwarded and unsupported scanner is disabled',
    (tester) async {
      await setSize(tester, const Size(1280, 1000));
      final controller = TestController();
      await tester.pumpWidget(FileTransferApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-devices')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('scan-invitation')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('enter-invitation')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('dialog-text-input')),
        '  invitation-from-test  ',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Подключиться'));
      await tester.pumpAndSettle();
      expect(controller.pairedText, 'invitation-from-test');
    },
  );

  testWidgets('the user can choose any committed file in a received package', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final controller = TestController()
      ..transfers = [
        TransferItem(
          id: 'package',
          title: '2 файла',
          peerName: 'Отправитель',
          direction: TransferDirection.incoming,
          phase: TransferPhase.completed,
          totalBytes: 300,
          transferredBytes: 300,
          createdAt: DateTime(2026, 11, 20),
          fileCount: 2,
          canOpen: true,
          receivedFiles: const [
            ReceivedFile(id: 'first', name: 'Первый.pdf', bytes: 100),
            ReceivedFile(id: 'second', name: 'Второй.txt', bytes: 200),
          ],
        ),
      ];
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('open-package')));
    await tester.tap(find.byKey(const Key('open-package')));
    await tester.pumpAndSettle();
    expect(controller.openedFile, isNull);
    await tester.tap(find.byKey(const Key('received-file-second')));
    await tester.pumpAndSettle();
    expect(controller.openedFile, ('package', 'second'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'export is an explicit separate action for the chosen committed file',
    (tester) async {
      await setSize(tester, const Size(390, 844));
      final controller = TestController()
        ..availableCapabilities = const AppCapabilities(fileExport: true)
        ..transfers = [
          TransferItem(
            id: 'received',
            title: '2 файла',
            peerName: 'Отправитель',
            direction: TransferDirection.incoming,
            phase: TransferPhase.completed,
            totalBytes: 300,
            transferredBytes: 300,
            createdAt: DateTime(2026, 11, 21),
            fileCount: 2,
            canOpen: true,
            canExport: true,
            receivedFiles: const [
              ReceivedFile(id: 'one', name: 'Первый.pdf', bytes: 100),
              ReceivedFile(
                id: 'two',
                name: 'Второй.txt',
                bytes: 200,
                exportPhase: ExportPhase.unknown,
                exportDetail:
                    'Результат сохранения не подтверждён. Проверьте папку.',
              ),
            ],
          ),
        ];
      await tester.pumpWidget(FileTransferApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-history')));
      await tester.pumpAndSettle();
      expect(controller.exportedFile, isNull);
      expect(find.byKey(const Key('export-status-two')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('export-received')));
      await tester.tap(find.byKey(const Key('export-received')));
      await tester.pumpAndSettle();
      expect(controller.exportedFile, isNull);
      await tester.tap(find.byKey(const Key('export-file-two')));
      await tester.pumpAndSettle();
      expect(controller.exportedFile, ('received', 'two'));
      expect(controller.openedFile, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'storage cleanup requires confirmation of the previewed IDs and fits narrow screen',
    (tester) async {
      await setSize(tester, const Size(360, 800));
      final controller = TestController()
        ..availableCapabilities = const AppCapabilities(storageManagement: true)
        ..storageOverview = StorageOverview(
          availableBytes: null,
          temporaryBytes: 128,
          reservedBytes: 64,
          safetyReserveBytes: 128 * 1024 * 1024,
          temporaryQuotaBytes: 20 * 1024 * 1024 * 1024,
          checkedAt: DateTime(2026, 11, 21),
          unusedFiles: const [
            TemporaryFileItem(id: 'previewed', name: 'Копия.txt', bytes: 128),
          ],
        );
      await tester.pumpWidget(FileTransferApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('cleanup-temporary')));
      await tester.tap(find.byKey(const Key('cleanup-temporary')));
      await tester.pumpAndSettle();
      expect(controller.cleanedFiles, isNull);
      expect(find.text('Копия.txt · 128 Б'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Оставить'));
      await tester.pumpAndSettle();
      expect(controller.cleanedFiles, isNull);
      await tester.tap(find.byKey(const Key('cleanup-temporary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-cleanup-temporary')));
      await tester.pumpAndSettle();
      expect(controller.cleanedFiles, ['previewed']);
      expect(tester.takeException(), isNull);
    },
  );
}
