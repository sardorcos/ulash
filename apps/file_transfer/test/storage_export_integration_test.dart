import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_transfer/services/app_runtime.dart';
import 'package:file_transfer/services/export_journal.dart';
import 'package:file_transfer/services/outgoing_journal.dart';
import 'package:file_transfer/services/platform_storage.dart';
import 'package:file_transfer/services/transfer_app_controller.dart';
import 'package:file_transfer/ui/app_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:transfer_core/transfer_core.dart' as core;

const _gib = 1024 * 1024 * 1024;
const _mib = 1024 * 1024;

Future<void> _until(bool Function() predicate) async {
  final timer = Stopwatch()..start();
  while (!predicate()) {
    if (timer.elapsed > const Duration(seconds: 10)) fail('Timed out.');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Fixture {
  _Fixture(this.root);
  final Directory root;
  final core.MemorySecretStore secrets = core.MemorySecretStore();
  final List<TransferAppController> controllers = [];
  Directory get data => Directory(p.join(root.path, 'file-transfer-v1'));
  int? available = 100 * _gib;

  static Future<_Fixture> create() async => _Fixture(
    await Directory.systemTemp.createTemp('transfer-storage-export-'),
  );

  Future<core.TransferSnapshot> receive(List<int> bytes) async {
    final inbox = await core.DurableInbox.open(
      Directory(p.join(data.path, 'inbox')),
    );
    try {
      final manifest = core.TransferManifest(
        requestId: 'fixture-receive',
        files: [
          core.FileManifest(
            fileId: 'fixture-file',
            displayName: 'Документ.bin',
            sizeBytes: bytes.length,
            sha256: sha256.convert(bytes).toString(),
            mimeType: 'application/octet-stream',
          ),
        ],
      );
      final offered = await inbox.createOffer(manifest, peerId: 'fixture-peer');
      final accepted = await inbox.accept(offered.transferId);
      await inbox.writeFile(
        accepted.transferId,
        'fixture-file',
        offset: 0,
        incarnation: accepted.files.single.storageIncarnationId,
        bytes: Stream.value(bytes),
      );
      await inbox.finishFile(
        accepted.transferId,
        'fixture-file',
        incarnation: accepted.files.single.storageIncarnationId,
      );
      return inbox.status(accepted.transferId);
    } finally {
      await inbox.close();
    }
  }

  Future<TransferAppController> start({ExportFileCallback? export}) async {
    final controller = TransferAppController(
      runtime: AppRuntime(
        secrets: secrets,
        storageDirectory: () async => root,
        ensurePermission: () async => false,
        addresses: () async => const [],
        listenAddress: InternetAddress.loopbackIPv4,
        availableBytes: (_) async => available,
        exportSupported: export != null,
        exportFile: export,
      ),
    );
    controllers.add(controller);
    await controller.initialize();
    expect(controller.storageOverview, isNotNull);
    return controller;
  }

  Future<void> closeController(TransferAppController controller) async {
    await controller.shutdown();
    controller.dispose();
    controllers.remove(controller);
  }

  Future<void> close() async {
    for (final controller in controllers.toList()) {
      await closeController(controller);
    }
    secrets.clear();
    await root.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export keeps network receipt independent, bounds native calls, and remembers success after cancellation', () async {
    final fixture = await _Fixture.create();
    try {
      final bytes = List<int>.generate(256 * 1024 + 17, (i) => i % 251);
      final received = await fixture.receive(bytes);
      final destination = File(p.join(fixture.root.path, 'user-export.bin'));
      var calls = 0;
      var response = Completer<NativeExportResult?>();
      final controller = await fixture.start(
        export: ({required source, required displayName, mimeType}) async {
          calls++;
          expect(displayName, 'Документ.bin');
          expect(mimeType, 'application/octet-stream');
          await source.copy(destination.path);
          return response.future;
        },
      );
      final id = 'in:${received.transferId}';
      final exporting = controller.exportReceivedFile(id, 'fixture-file');
      await _until(() => calls == 1);
      expect(controller.transfers.single.phase, TransferPhase.completed);
      expect(
        controller.transfers.single.receivedFiles.single.exportPhase,
        ExportPhase.exporting,
      );
      expect(controller.transfers.single.canExport, isFalse);
      await controller.exportReceivedFile(id, 'fixture-file');
      expect(
        calls,
        1,
        reason: 'A second native picker cannot run concurrently.',
      );
      response.complete(
        const NativeExportResult(
          destinationLabel: 'Выбранная папка/user-export.bin',
          platformReference: 'test-destination',
        ),
      );
      await exporting;
      expect(controller.errorMessage, isNull);
      expect(
        controller.transfers.single.receivedFiles.single.exportPhase,
        ExportPhase.exported,
      );
      expect(
        await sha256.bind(destination.openRead()).first,
        sha256.convert(bytes),
      );
      expect(await File(received.files.single.finalPath!).readAsBytes(), bytes);

      response = Completer<NativeExportResult?>();
      final cancelled = controller.exportReceivedFile(id, 'fixture-file');
      await _until(() => calls == 2);
      response.complete(null);
      await cancelled;
      expect(controller.errorMessage, isNull);
      final file = controller.transfers.single.receivedFiles.single;
      expect(file.exportPhase, ExportPhase.cancelled);
      expect(file.exportDestination, contains('user-export.bin'));
      expect(controller.transfers.single.phase, TransferPhase.completed);

      await fixture.closeController(controller);
      final recovered = await fixture.start(
        export: ({required source, required displayName, mimeType}) async {
          fail('Restart must never automatically export a file.');
        },
      );
      expect(
        recovered.transfers.single.receivedFiles.single.exportPhase,
        ExportPhase.cancelled,
      );
      expect(
        recovered.transfers.single.receivedFiles.single.exportDestination,
        contains('user-export.bin'),
      );
    } finally {
      await fixture.close();
    }
  });

  test('failed or interrupted native export preserves committed file and reports exact uncertainty', () async {
    final fixture = await _Fixture.create();
    try {
      final received = await fixture.receive([1, 2, 3, 4]);
      var code = 'EXPORT_FAILED';
      final controller = await fixture.start(
        export: ({required source, required displayName, mimeType}) async {
          throw PlatformException(code: code);
        },
      );
      final id = 'in:${received.transferId}';
      await controller.exportReceivedFile(id, 'fixture-file');
      expect(
        controller.transfers.single.receivedFiles.single.exportPhase,
        ExportPhase.failed,
      );
      expect(controller.errorMessage, contains('Полученный файл остаётся'));
      code = 'EXPORT_INTERRUPTED';
      await controller.exportReceivedFile(id, 'fixture-file');
      expect(
        controller.transfers.single.receivedFiles.single.exportPhase,
        ExportPhase.unknown,
      );
      expect(controller.errorMessage, contains('Проверьте выбранную папку'));
      expect(controller.transfers.single.phase, TransferPhase.completed);
      expect(await File(received.files.single.finalPath!).readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
    } finally {
      await fixture.close();
    }
  });

  test(
    'a same-length changed received file never reaches native export',
    () async {
      final fixture = await _Fixture.create();
      try {
        final received = await fixture.receive([1, 2, 3, 4]);
        final controller = await fixture.start(
          export: ({required source, required displayName, mimeType}) async {
            fail('Changed bytes must not reach the native exporter.');
          },
        );
        await File(received.files.single.finalPath!)
            .writeAsBytes([4, 3, 2, 1], flush: true);
        await controller.exportReceivedFile(
          'in:${received.transferId}',
          'fixture-file',
        );
        expect(
          controller.transfers.single.receivedFiles.single.exportPhase,
          ExportPhase.failed,
        );
        expect(controller.errorMessage, contains('изменён'));
        expect(
          controller.transfers.single.phase,
          TransferPhase.completed,
          reason: 'The historical received receipt is not an export receipt.',
        );
      } finally {
        await fixture.close();
      }
    },
  );

  test('a pending export recovers unknown without retrying or rewriting received bytes', () async {
    final fixture = await _Fixture.create();
    try {
      final received = await fixture.receive([9, 8, 7]);
      final journal = ExportJournal(
        Directory(p.join(fixture.data.path, 'journal')),
      );
      journal.begin(received.transferId, 'fixture-file');
      journal.close();
      final controller = await fixture.start(
        export: ({required source, required displayName, mimeType}) async {
          fail('Unknown result must require another explicit user action.');
        },
      );
      expect(
        controller.transfers.single.receivedFiles.single.exportPhase,
        ExportPhase.unknown,
      );
      expect(await File(received.files.single.finalPath!).readAsBytes(), [
        9,
        8,
        7,
      ]);
      expect(controller.transfers.single.phase, TransferPhase.completed);
    } finally {
      await fixture.close();
    }
  });

  test('cleanup rechecks source/job ownership and only removes the explicitly previewed orphan', () async {
    final fixture = await _Fixture.create();
    try {
      final received = await fixture.receive([5, 4, 3]);
      final original = File(p.join(fixture.root.path, 'original.bin'));
      await original.writeAsBytes(List.filled(4096, 3), flush: true);
      final outbox = await core.DurableOutbox.open(
        Directory(p.join(fixture.data.path, 'outbox')),
      );
      final orphan = await outbox.stageFile(original);
      final active = await outbox.stageFile(original);
      final newOrphan = await outbox.stageFile(original);
      await outbox.close();
      final journal = OutgoingJournal(
        Directory(p.join(fixture.data.path, 'journal')),
      );
      journal.save(
        OutgoingJob(
          id: 'active-job',
          peerId: 'other-peer',
          peerName: 'Другой',
          manifest: core.TransferManifest(
            requestId: 'active-job',
            files: [active.manifest],
          ),
          createdAt: DateTime.now().toUtc(),
          localState: 'paused',
        ),
      );
      journal.close();
      final controller = await fixture.start();
      await controller.addSourcePaths([original.path]);
      final selected = controller.selectedSources.single.id;
      await controller.refreshStorage();
      final unused = controller.storageOverview!.unusedFiles
          .map((f) => f.id)
          .toSet();
      expect(
        unused,
        containsAll([orphan.manifest.fileId, newOrphan.manifest.fileId]),
      );
      expect(unused, isNot(contains(active.manifest.fileId)));
      expect(unused, isNot(contains(selected)));
      await controller.clearUnusedTemporary([
        orphan.manifest.fileId,
        active.manifest.fileId,
        selected,
      ]);
      expect(controller.errorMessage, isNull);
      expect(await File(orphan.path).exists(), isFalse);
      expect(await File(active.path).exists(), isTrue);
      expect(
        await File(newOrphan.path).exists(),
        isTrue,
        reason: 'Unpreviewed files cannot be swept.',
      );
      expect(controller.selectedSources.single.id, selected);
      expect(await original.exists(), isTrue);
      expect(await File(received.files.single.finalPath!).readAsBytes(), [
        5,
        4,
        3,
      ]);
      expect(controller.storageOverview!.temporaryBytes, 3 * 4096);
    } finally {
      await fixture.close();
    }
  });

  test(
    'space preflight and quota persistence surface truthful settings',
    () async {
      final fixture = await _Fixture.create();
      try {
        final source = File(p.join(fixture.root.path, 'source.bin'));
        await source.writeAsBytes(List.filled(1024, 1), flush: true);
        fixture.available = 128 * _mib + 1023;
        final controller = await fixture.start();
        await controller.addSourcePaths([source.path]);
        expect(
          controller.errorMessage,
          contains('Недостаточно свободного места'),
        );
        expect(controller.selectedSources, isEmpty);
        expect(await source.length(), 1024);
        fixture.available = 100 * _gib;
        await controller.setTemporaryQuota(5 * _gib);
        expect(controller.errorMessage, isNull);
        expect(controller.storageOverview!.temporaryQuotaBytes, 5 * _gib);
        await fixture.closeController(controller);
        fixture.available = null;
        final recovered = await fixture.start();
        expect(recovered.storageOverview!.temporaryQuotaBytes, 5 * _gib);
        expect(recovered.storageOverview!.availableBytes, isNull);
      } finally {
        await fixture.close();
      }
    },
  );

  test(
    'receiver explains a disk-full pause and retains its durable prefix',
    () async {
      final fixture = await _Fixture.create();
      try {
        var free = 100;
        final budget = core.StorageBudget(
          availableBytes: () async => free,
          safetyReserveBytes: 1,
          temporaryQuotaBytes: 100,
          recheckBytes: 1,
        );
        final inbox = await core.DurableInbox.open(
          Directory(p.join(fixture.data.path, 'inbox')),
          budget: budget,
          checkpointBytes: 1,
        );
        final offered = await inbox.createOffer(
          core.TransferManifest(
            requestId: 'full-disk',
            files: [
              core.FileManifest(
                fileId: 'prefix',
                displayName: 'Файл.bin',
                sizeBytes: 4,
                sha256: sha256.convert([1, 2, 3, 4]).toString(),
              ),
            ],
          ),
          peerId: 'disk-peer',
        );
        final accepted = await inbox.accept(offered.transferId);
        final incarnation = accepted.files.single.storageIncarnationId;
        await inbox.writeFile(
          offered.transferId,
          'prefix',
          offset: 0,
          incarnation: incarnation,
          bytes: Stream.value([1, 2]),
        );
        free = 1;
        await expectLater(
          inbox.writeFile(
            offered.transferId,
            'prefix',
            offset: 2,
            incarnation: incarnation,
            bytes: Stream.value([3, 4]),
          ),
          throwsA(isA<core.StorageException>()),
        );
        expect(inbox.status(offered.transferId).files.single.offset, 2);
        await inbox.close();
        final controller = await fixture.start();
        final transfer = controller.transfers.single;
        expect(transfer.phase, TransferPhase.paused);
        expect(transfer.transferredBytes, 2);
        expect(transfer.detail, contains('Недостаточно свободного места'));
        expect(
          transfer.detail,
          contains('Подтверждённая часть файла сохранена'),
        );
        expect(transfer.canResume, isTrue);
      } finally {
        await fixture.close();
      }
    },
  );
}
