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
  List<String>? cleanedIncoming;
  String? retriedTransfer;
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

  final pairingResponses = <(String, bool)>[];
  @override
  Future<void> respondToPairing(String requestId, bool accept) async {
    pairingResponses.add((requestId, accept));
    pendingPairings = pendingPairings.where((p) => p.id != requestId).toList();
    notifyListeners();
  }

  String? sentText;
  @override
  Future<void> sendText(String peerId, String text) async {
    sentText = '$peerId:$text';
  }

  bool onboarding = false;
  @override
  bool get needsOnboarding => onboarding;

  @override
  List<WebUploadRequest> pendingWebUploads = [];
  final uploadResponses = <(String, bool)>[];
  @override
  Future<void> respondToWebUpload(String id, bool accept) async {
    uploadResponses.add((id, accept));
    pendingWebUploads = pendingWebUploads.where((r) => r.id != id).toList();
    notifyListeners();
  }

  @override
  bool journalWarning = false;
  @override
  bool canCancelPreparation = false;
  @override
  String? busyLabel;
  int cancelledPreparations = 0;
  @override
  Future<void> cancelPreparation() async => cancelledPreparations++;
  @override
  Future<void> completeOnboarding() async {
    onboarding = false;
    notifyListeners();
  }
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
  Future<void> retryTransfer(String transferId) async {
    retriedTransfer = transferId;
  }

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
  Future<void> clearIncompleteIncoming(List<String> transferIds) async {
    cleanedIncoming = List.of(transferIds);
  }

  void updateStorage(StorageOverview value) {
    storageOverview = value;
    notifyListeners();
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

/// Settings → Advanced (the row sits at the end of a long, lazy list).
Future<void> openAdvanced(WidgetTester tester) async {
  final row = find.byKey(const Key('settings-advanced'));
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await reveal(tester, row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// Scrolls [finder] to the middle of the viewport, clear of the pinned
/// large-title app bar and the bottom bars.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all mobile pages fit 360px and do not invent transfers', (
    tester,
  ) async {
    await setSize(tester, const Size(360, 800));
    final controller = TestController();
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Начнём с файлов'), findsOneWidget);
    expect(find.text('Подключите первое устройство'), findsOneWidget);
    expect(find.text('Передача завершена'), findsNothing);
    for (final tab in ['devices', 'history', 'send']) {
      await tester.tap(find.byKey(Key('nav-$tab')));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Mobile page $tab must not overflow.',
      );
    }
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    await openAdvanced(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The interface is Russian, so tap the back arrow instead of pageBack().
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    await reveal(tester, find.byKey(const Key('choose-files')));
    await tester.tap(find.byKey(const Key('choose-files')));
    await tester.pump();
    expect(controller.chooseCount, 1);
  });

  testWidgets('short desktop and enlarged text remain usable', (tester) async {
    await setSize(tester, const Size(1024, 600));
    final controller = TestController();
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    for (final tab in ['send', 'history', 'devices', 'settings']) {
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

  testWidgets('every phone page survives 200% text with real content', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = TestController()
      ..availableCapabilities = const AppCapabilities(
        mediaSelection: true,
        folderSelection: true,
        textMessages: true,
        nearbyPairing: true,
        webShare: true,
        photosSave: true,
        storageManagement: true,
        diagnostics: true,
      )
      ..selectedSources = [
        const SelectedSource(
          id: 's',
          name: 'Очень длинное название документа для проверки.pdf',
          bytes: 123456,
        ),
      ]
      ..peers = [
        const PeerDevice(
          id: 'p',
          name: 'Ноутбук Сардора',
          platform: DevicePlatform.windows,
          isTrusted: true,
          isOnline: true,
        ),
      ]
      ..pendingTransfers = [
        IncomingTransfer(
          id: 'offer',
          peerName: 'iPhone',
          fileNames: const ['IMG_0001.HEIC', 'IMG_0002.HEIC'],
          totalBytes: 5 * 1024 * 1024,
          expiresAt: DateTime(2026, 11, 21, 14, 30),
        ),
      ]
      ..transfers = [
        TransferItem(
          id: 't',
          title: 'Видео с отпуска.mov',
          peerName: 'iPhone',
          direction: TransferDirection.incoming,
          phase: TransferPhase.transferring,
          totalBytes: 1000000,
          transferredBytes: 420000,
          bytesPerSecond: 50000,
          createdAt: DateTime.now(),
          canPause: true,
          canCancel: true,
        ),
      ];
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'send');
    for (final tab in ['history', 'devices']) {
      await tester.tap(find.byKey(Key('nav-$tab')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'settings');
    await openAdvanced(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'advanced');
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
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('accept-incoming')));
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
    await reveal(tester, find.byKey(const Key('open-package')));
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
      await reveal(tester, find.byKey(const Key('export-received')));
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
      await openAdvanced(tester);
      await reveal(tester, find.byKey(const Key('cleanup-temporary')));
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

  testWidgets(
    'incoming cleanup confirms consequences and retains the original preview during refresh',
    (tester) async {
      await setSize(tester, const Size(360, 800));
      StorageOverview overview(List<IncomingCleanupItem> incoming) =>
          StorageOverview(
            availableBytes: null,
            temporaryBytes: 128,
            reservedBytes: 256,
            safetyReserveBytes: 128 * 1024 * 1024,
            temporaryQuotaBytes: 20 * 1024 * 1024 * 1024,
            checkedAt: DateTime(2026, 11, 21),
            unusedFiles: const [],
            incompleteIncoming: incoming,
          );
      const previewed = IncomingCleanupItem(
        id: 'previewed-incoming',
        title: 'Видео.mov',
        peerName: 'Телефон',
        temporaryBytes: 128,
        reservedBytes: 256,
        pendingFileCount: 1,
        completedFileCount: 2,
      );
      const later = IncomingCleanupItem(
        id: 'later-incoming',
        title: 'Новый документ.pdf',
        peerName: 'Ноутбук',
        temporaryBytes: 1024,
        reservedBytes: 0,
        pendingFileCount: 1,
        completedFileCount: 0,
      );
      final controller = TestController()
        ..availableCapabilities = const AppCapabilities(storageManagement: true)
        ..storageOverview = overview([previewed]);
      await tester.pumpWidget(FileTransferApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-settings')));
      await tester.pumpAndSettle();
      await openAdvanced(tester);
      await reveal(tester, find.byKey(const Key('cleanup-incoming')));
      await tester.tap(find.byKey(const Key('cleanup-incoming')));
      await tester.pumpAndSettle();
      expect(controller.cleanedIncoming, isNull);
      expect(
        find.textContaining('Готовых файлов останется: 2'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Продолжить эти передачи после очистки нельзя'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Оставить'));
      await tester.pumpAndSettle();
      expect(controller.cleanedIncoming, isNull);
      await tester.tap(find.byKey(const Key('cleanup-incoming')));
      await tester.pumpAndSettle();
      controller.updateStorage(overview([previewed, later]));
      await tester.pumpAndSettle();
      expect(find.textContaining('Новый документ.pdf'), findsNothing);
      await tester.tap(find.byKey(const Key('confirm-cleanup-incoming')));
      await tester.pumpAndSettle();
      expect(controller.cleanedIncoming, ['previewed-incoming']);
      expect(controller.cleanedFiles, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offer deadline is visible without implied acceptance', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final controller = TestController()
      ..pendingTransfers = [
        IncomingTransfer(
          id: 'deadline',
          peerName: 'Отправитель',
          fileNames: const ['Документ.pdf'],
          totalBytes: 1024,
          expiresAt: DateTime(2026, 11, 21, 14, 30, 47),
        ),
      ];
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('offer-deadline-deadline')),
    );
    expect(find.textContaining('14:30:47'), findsOneWidget);
    expect(controller.responses, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry and expiry are distinct from verified completion', (
    tester,
  ) async {
    await setSize(tester, const Size(1280, 1000));
    final controller = TestController()
      ..transfers = [
        TransferItem(
          id: 'retry',
          title: 'Передача с обрывом',
          peerName: 'Отправитель',
          direction: TransferDirection.outgoing,
          phase: TransferPhase.retrying,
          totalBytes: 1024,
          transferredBytes: 512,
          createdAt: DateTime(2026, 11, 21),
          canPause: true,
          canCancel: true,
          detail: 'Повтор 2 из 5 через 2 секунды.',
        ),
        TransferItem(
          id: 'expired',
          title: 'Предложение без ответа',
          peerName: 'Отправитель',
          direction: TransferDirection.incoming,
          phase: TransferPhase.expired,
          totalBytes: 2048,
          transferredBytes: 0,
          createdAt: DateTime(2026, 11, 21),
        ),
      ];
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    expect(find.text('Повторяем подключение'), findsOneWidget);
    expect(find.text('Время ожидания истекло'), findsOneWidget);
    expect(find.text('Передача завершена'), findsNothing);
    expect(find.byKey(const Key('pause-retry')), findsOneWidget);
    expect(find.byKey(const Key('resume-expired')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending retained copies again requires an explicit new offer', (
    tester,
  ) async {
    await setSize(tester, const Size(360, 640));
    final controller = TestController()
      ..transfers = [
        TransferItem(
          id: 'expired-outgoing',
          title: 'Сохранённая копия.pdf',
          peerName: 'Ноутбук',
          direction: TransferDirection.outgoing,
          phase: TransferPhase.expired,
          totalBytes: 1024,
          transferredBytes: 0,
          createdAt: DateTime(2026, 11, 21),
          canRetry: true,
        ),
      ];
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    final retry = find.byKey(const Key('retry-expired-outgoing'));
    await reveal(tester, retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(controller.retriedTransfer, isNull);
    expect(find.textContaining('нужно подтвердить'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Оставить'));
    await tester.pumpAndSettle();
    expect(controller.retriedTransfer, isNull);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-retry-expired-outgoing')));
    await tester.pumpAndSettle();
    expect(controller.retriedTransfer, 'expired-outgoing');
    expect(controller.sentPeer, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pairing asks whether both codes match, like Bluetooth', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final controller = TestController();
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    controller.pendingPairings = [
      const PairingRequest(
        id: 'pair',
        deviceName: 'Ноутбук',
        platform: DevicePlatform.windows,
        code: '123456',
      ),
    ];
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Коды совпадают?'), findsOneWidget);
    expect(find.text('123 456'), findsWidgets);
    expect(controller.pairingResponses, isEmpty);
    await tester.tap(find.byKey(const Key('dialog-approve-pair-pair')));
    await tester.pumpAndSettle();
    expect(controller.pairingResponses, [('pair', true)]);
    expect(find.text('Коды совпадают?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history search and filters narrow the list', (tester) async {
    await setSize(tester, const Size(390, 844));
    final now = DateTime.now();
    final controller = TestController()
      ..transfers = [
        TransferItem(
          id: 'a',
          title: 'Отчёт.pdf',
          peerName: 'Ноутбук',
          direction: TransferDirection.outgoing,
          phase: TransferPhase.completed,
          totalBytes: 10,
          transferredBytes: 10,
          createdAt: now,
        ),
        TransferItem(
          id: 'b',
          title: 'Фото.heic',
          peerName: 'iPhone',
          direction: TransferDirection.incoming,
          phase: TransferPhase.completed,
          totalBytes: 10,
          transferredBytes: 10,
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      ];
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('Вчера'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('history-search')), 'фото');
    await tester.pumpAndSettle();
    expect(find.text('Отчёт.pdf'), findsNothing);
    expect(find.text('Фото.heic'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('history-search')), '');
    await tester.tap(find.byKey(const Key('filter-sent')));
    await tester.pumpAndSettle();
    expect(find.text('Отчёт.pdf'), findsOneWidget);
    expect(find.text('Фото.heic'), findsNothing);
  });

  testWidgets('text messages are composed in a sheet and shown as bubbles', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final controller = TestController()
      ..availableCapabilities = const AppCapabilities(textMessages: true)
      ..peers = [
        const PeerDevice(
          id: 'laptop',
          name: 'Ноутбук',
          platform: DevicePlatform.macos,
          isTrusted: true,
          isOnline: true,
        ),
      ]
      ..transfers = [
        TransferItem(
          id: 'msg',
          title: 'Текст',
          peerName: 'Ноутбук',
          direction: TransferDirection.incoming,
          phase: TransferPhase.completed,
          totalBytes: 12,
          transferredBytes: 12,
          createdAt: DateTime.now(),
          kind: TransferKind.text,
          messageText: 'https://example.org',
        ),
      ];
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('compose-text')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('message-input')), ' Привет ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-message')));
    await tester.pumpAndSettle();
    expect(controller.sentText, 'laptop:Привет');
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    expect(find.text('https://example.org'), findsOneWidget);
    expect(find.byKey(const Key('copy-text-msg')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding is two steps and ends by asking for access', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final controller = TestController()..onboarding = true;
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Разрешить доступ'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(controller.needsOnboarding, isFalse);
    expect(find.text('Подключите первое устройство'), findsOneWidget);
  });

  testWidgets('executable files need a second confirmation to open', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final controller = TestController()
      ..transfers = [
        TransferItem(
          id: 'exe',
          title: 'setup.exe',
          peerName: 'Ноутбук',
          direction: TransferDirection.incoming,
          phase: TransferPhase.completed,
          totalBytes: 10,
          transferredBytes: 10,
          createdAt: DateTime.now(),
          canOpen: true,
          receivedFiles: const [
            ReceivedFile(
              id: 'bin',
              name: 'setup.exe',
              bytes: 10,
              potentiallyExecutable: true,
            ),
          ],
        ),
      ];
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-exe')));
    await tester.pumpAndSettle();
    expect(controller.openedFile, isNull);
    await tester.tap(find.byKey(const Key('confirm-open-bin')));
    await tester.pumpAndSettle();
    expect(controller.openedFile, ('exe', 'bin'));
  });

  testWidgets('browser uploads ask for consent like an incoming offer', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final controller = TestController();
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pumpAndSettle();
    controller.pendingWebUploads = [
      const WebUploadRequest(
        id: 'up',
        client: '192.168.1.5',
        fileNames: ['Скан.pdf'],
        totalBytes: 2048,
      ),
    ];
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Скан.pdf'), findsOneWidget);
    expect(controller.uploadResponses, isEmpty);
    await tester.tap(find.byKey(const Key('web-upload-allow-up')));
    await tester.pumpAndSettle();
    expect(controller.uploadResponses, [('up', true)]);
    expect(find.text('Скан.pdf'), findsNothing);
  });

  testWidgets('preparation can be cancelled and journal problems are shown', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final controller = TestController()
      ..isBusy = true
      ..busyLabel = 'Готовим «Видео.mov»'
      ..canCancelPreparation = true
      ..journalWarning = true;
    await tester.pumpWidget(FileTransferApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('journal-warning')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-preparation')));
    await tester.pump();
    expect(controller.cancelledPreparations, 1);
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('journal-warning')), findsOneWidget);
  });
}
