import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_transfer/services/app_runtime.dart';
import 'package:file_transfer/services/transfer_app_controller.dart';
import 'package:file_transfer/ui/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:transfer_core/transfer_core.dart' as core;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit cleanup handles only confirmed incoming IDs and preserves committed files', () async {
    final root = await Directory.systemTemp.createTemp(
      'incoming-cleanup-controller-',
    );
    final secrets = core.MemorySecretStore();
    final data = Directory(p.join(root.path, 'file-transfer-v1', 'inbox'));
    final inbox = await core.DurableInbox.open(data);
    final completedBytes = [1, 2, 3, 4, 5];
    final partialBytes = List<int>.generate(4096, (i) => i & 255);
    core.FileManifest manifest(String id, List<int> bytes) => core.FileManifest(
      fileId: id,
      displayName: '$id.bin',
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
    final first = await inbox.createOffer(
      core.TransferManifest(
        requestId: 'mixed',
        files: [
          manifest('saved', completedBytes),
          manifest('unfinished', partialBytes),
        ],
      ),
      peerId: 'verified-peer',
    );
    await inbox.accept(first.id);
    final savedFile = inbox.status(first.id).files.first;
    await inbox.writeFile(
      first.id,
      savedFile.fileId,
      offset: 0,
      incarnation: savedFile.storageIncarnationId,
      bytes: Stream.value(completedBytes),
    );
    final savedPath = inbox.status(first.id).files.first.finalPath!;
    final partialFile = inbox.status(first.id).files.last;
    final partial = await inbox.writeFile(
      first.id,
      partialFile.fileId,
      offset: 0,
      incarnation: partialFile.storageIncarnationId,
      bytes: Stream.value(partialBytes.sublist(0, 1024)),
    );
    expect(partial.offset, 1024);
    final other = await inbox.createOffer(
      core.TransferManifest(
        requestId: 'not-selected',
        files: [manifest('other', partialBytes)],
      ),
      peerId: 'verified-peer',
    );
    await inbox.accept(other.id);
    await inbox.close();

    final controller = TransferAppController(
      runtime: AppRuntime(
        secrets: secrets,
        storageDirectory: () async => root,
        ensurePermission: () async => false,
        addresses: () async => [],
        listenAddress: InternetAddress.loopbackIPv4,
      ),
    );
    try {
      await controller.initialize();
      final preview = controller.storageOverview!;
      expect(preview.incompleteIncoming, hasLength(2));
      final mixed = preview.incompleteIncoming.singleWhere(
        (item) => item.id == first.id,
      );
      expect(mixed.temporaryBytes, 1024);
      expect(mixed.completedFileCount, 1);
      expect(mixed.pendingFileCount, 1);
      await controller.clearIncompleteIncoming([
        first.id,
        'not-a-previewed-id',
      ]);
      expect(controller.errorMessage, isNull);
      await controller.refreshStorage();
      expect(
        controller.storageOverview!.incompleteIncoming.map((item) => item.id),
        [other.id],
      );
      expect(controller.storageOverview!.temporaryBytes, 0);
      expect(controller.storageOverview!.reservedBytes, partialBytes.length);
      final cleaned = controller.transfers.singleWhere(
        (item) => item.id == 'in:${first.id}',
      );
      expect(cleaned.phase, TransferPhase.failed);
      expect(cleaned.receivedFiles.single.id, savedFile.fileId);
      expect(cleaned.canOpen, isTrue);
      expect(cleaned.canResume, isFalse);
      expect(await File(savedPath).readAsBytes(), completedBytes);
      // A repeated or stale confirmation is harmless and does not reach the
      // remaining batch or any already committed payload.
      await controller.clearIncompleteIncoming([first.id]);
      expect(await File(savedPath).readAsBytes(), completedBytes);
      expect(
        controller.storageOverview!.incompleteIncoming.single.id,
        other.id,
      );
    } finally {
      await controller.shutdown();
      controller.dispose();
      secrets.clear();
      await root.delete(recursive: true);
    }
  });
}
