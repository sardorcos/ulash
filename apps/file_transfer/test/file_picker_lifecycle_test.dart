import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_transfer/services/app_runtime.dart';
import 'package:file_transfer/services/transfer_app_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:transfer_core/transfer_core.dart' as core;

// file_picker 13.4.0 delegates its static pickFiles API to this exported
// platform interface. Its actual contract is List<PlatformFile>; [] is cancel.
// Exercise that boundary without inventing an older MethodChannel shape.
class _DeferredFilePicker extends FilePickerPlatform {
  final requests = <Completer<List<PlatformFile>>>[];
  final busyAtRequest = <bool>[];
  bool Function()? controllerBusy;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    busyAtRequest.add(controllerBusy?.call() ?? false);
    final response = Completer<List<PlatformFile>>();
    requests.add(response);
    return response.future;
  }

  void releasePending() {
    for (final request in requests) {
      if (!request.isCompleted) request.complete(const []);
    }
  }
}

final class _PickedLocalFile extends PlatformFile {
  _PickedLocalFile(this.file);
  final File file;
  int metadataReads = 0;
  int contentReads = 0;

  @override
  String get name => p.basename(file.path);
  @override
  Uri get uri => file.uri;
  @override
  Never get xFile =>
      throw StateError('The controller must use the staged path.');
  @override
  int lengthSync() {
    metadataReads++;
    return file.lengthSync();
  }

  @override
  Future<int> length() => file.length();
  @override
  Future<Uint8List> readAsBytes() {
    contentReads++;
    return file.readAsBytes();
  }

  @override
  Stream<Uint8List> readAsByteStream() {
    contentReads++;
    return file.openRead().map(Uint8List.fromList);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('picker owns busy state, resets after cancel/error, ignores result after shutdown', () async {
    final root = await Directory.systemTemp.createTemp('picker-lifecycle-');
    final secrets = core.MemorySecretStore();
    final previousPicker = FilePickerPlatform.instance;
    final picker = _DeferredFilePicker();
    FilePickerPlatform.instance = picker;
    TransferAppController? controller;
    const gib = 1024 * 1024 * 1024;
    try {
      // A recovered, unreferenced staged file makes cleanup observable.
      // The original survives both the blocked and later allowed cleanup.
      final original = File(p.join(root.path, 'existing.txt'));
      await original.writeAsString('Keep the original document.', flush: true);
      final outboxRoot = Directory(
        p.join(root.path, 'file-transfer-v1', 'outbox'),
      );
      final seed = await core.DurableOutbox.open(outboxRoot);
      late core.PreparedFile prepared;
      try {
        prepared = await seed.stageFile(original);
      } finally {
        await seed.close();
      }
      final stagedCopy = File(prepared.path);
      final app = TransferAppController(
        runtime: AppRuntime(
          secrets: secrets,
          storageDirectory: () async => root,
          ensurePermission: () async => true,
          addresses: () async => ['127.0.0.1'],
          listenAddress: InternetAddress.loopbackIPv4,
          availableBytes: (_) async => 100 * gib,
          initialDeviceName: 'Picker lifecycle test',
        ),
      );
      controller = app;
      picker.controllerBusy = () => app.isBusy;
      await app.initialize();
      expect(app.errorMessage, isNull);
      expect(app.isBusy, isFalse);
      expect(app.storageOverview!.temporaryQuotaBytes, 20 * gib);
      expect(app.storageOverview!.unusedFiles.map((file) => file.id), [
        prepared.manifest.fileId,
      ]);

      final firstPick = app.chooseFiles();
      expect(picker.requests, hasLength(1));
      expect(picker.busyAtRequest, [true]);
      expect(app.isBusy, isTrue);
      expect(app.busyLabel, 'Выбор файлов');

      await app.setTemporaryQuota(5 * gib);
      await app.clearUnusedTemporary([prepared.manifest.fileId]);
      await app.chooseFiles();
      expect(picker.requests, hasLength(1), reason: 'No overlapping picker.');
      expect(app.storageOverview!.temporaryQuotaBytes, 20 * gib);
      expect(
        await secrets.read('transfer.settings.temporaryQuotaBytes'),
        isNull,
      );
      expect(
        await stagedCopy.exists(),
        isTrue,
        reason: 'Cleanup cannot interleave with selection.',
      );
      expect(app.isBusy, isTrue);

      // The plugin cancellation value is an empty list, not null.
      picker.requests[0].complete(const []);
      await firstPick;
      expect(app.isBusy, isFalse);
      expect(app.busyLabel, isNull);
      expect(app.errorMessage, isNull);
      expect(app.selectedSources, isEmpty);
      await app.setTemporaryQuota(5 * gib);
      expect(app.storageOverview!.temporaryQuotaBytes, 5 * gib);
      expect(
        await secrets.read('transfer.settings.temporaryQuotaBytes'),
        '${5 * gib}',
      );
      await app.clearUnusedTemporary([prepared.manifest.fileId]);
      expect(await stagedCopy.exists(), isFalse);
      expect(await original.readAsString(), 'Keep the original document.');

      final failedPick = app.chooseFiles();
      expect(picker.requests, hasLength(2));
      expect(app.isBusy, isTrue);
      picker.requests[1].completeError(
        PlatformException(
          code: 'PICKER_FAILED',
          message: 'Provider unavailable',
        ),
      );
      await failedPick;
      expect(app.isBusy, isFalse);
      expect(app.busyLabel, isNull);
      expect(app.errorMessage, isNotNull);
      expect(app.selectedSources, isEmpty);
      await app.setTemporaryQuota(10 * gib);
      expect(app.storageOverview!.temporaryQuotaBytes, 10 * gib);

      // Return a readable source after shutdown has set its closing flag.
      // No metadata or bytes may enter source preparation afterwards.
      final lateOriginal = File(p.join(root.path, 'late-result.bin'));
      await lateOriginal.writeAsBytes([17, 29, 43, 71], flush: true);
      final lateFile = _PickedLocalFile(lateOriginal);
      final latePick = app.chooseFiles();
      expect(picker.requests, hasLength(3));
      final shuttingDown = app.shutdown();
      await app.chooseFiles();
      expect(picker.requests, hasLength(3));
      picker.requests[2].complete([lateFile]);
      await latePick;
      await shuttingDown;
      expect(picker.busyAtRequest, [true, true, true]);
      expect(app.isBusy, isFalse);
      expect(app.busyLabel, isNull);
      expect(app.selectedSources, isEmpty);
      expect(lateFile.metadataReads, 0);
      expect(lateFile.contentReads, 0);
      expect(await lateOriginal.readAsBytes(), [17, 29, 43, 71]);
      expect(
        await Directory(p.join(outboxRoot.path, 'files')).list().toList(),
        isEmpty,
        reason: 'A late result must not publish a staged copy.',
      );
    } finally {
      picker.releasePending();
      if (controller != null) {
        await controller.shutdown();
        controller.dispose();
      }
      FilePickerPlatform.instance = previousPicker;
      secrets.clear();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
