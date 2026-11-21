import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:transfer_core/transfer_core.dart';

Matcher storageCode(String value) => isA<StorageException>().having(
  (error) => error.code,
  'storage code',
  value,
);

FileManifest manifest(List<int> bytes, {String id = 'file-a'}) => FileManifest(
  fileId: id,
  displayName: '$id.bin',
  sizeBytes: bytes.length,
  sha256: sha256.convert(bytes).toString(),
);

void main() {
  late Directory root;
  late Directory incomingRoot;
  late Directory outgoingRoot;
  DurableInbox? inbox;
  DurableOutbox? outbox;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('transfer-budget-test-');
    incomingRoot = Directory(p.join(root.path, 'inbox'));
    outgoingRoot = Directory(p.join(root.path, 'outbox'));
  });

  tearDown(() async {
    await inbox?.close();
    await outbox?.close();
    inbox = null;
    outbox = null;
    await root.delete(recursive: true);
  });

  Future<TransferSnapshot> offer(
    List<List<int>> contents, {
    String id = 'offer',
  }) => inbox!.createOffer(
    TransferManifest(
      requestId: id,
      files: [
        for (var i = 0; i < contents.length; i++)
          manifest(contents[i], id: 'file-$i'),
      ],
    ),
    peerId: 'verified-peer',
  );

  Future<FileSnapshot> write(TransferSnapshot transfer, List<int> bytes) {
    final file = inbox!.status(transfer.transferId).files.first;
    return inbox!.writeFile(
      transfer.transferId,
      file.fileId,
      offset: file.offset,
      incarnation: file.storageIncarnationId,
      bytes: Stream.value(bytes),
    );
  }

  Future<int> physicalPayloadBytes() async {
    var bytes = 0;
    for (final path in [
      p.join(incomingRoot.path, '.staging'),
      p.join(incomingRoot.path, 'received'),
      p.join(outgoingRoot.path, '.preparing'),
      p.join(outgoingRoot.path, 'files'),
    ]) {
      final directory = Directory(path);
      if (!await directory.exists()) continue;
      await for (final item in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (item is File) bytes += await item.length();
      }
    }
    return bytes;
  }

  test(
    'low disk rejects consent before creating payloads or accepting offer',
    () async {
      final budget = StorageBudget(
        availableBytes: () async => 15,
        safetyReserveBytes: 10,
        temporaryQuotaBytes: 100,
      );
      inbox = await DurableInbox.open(incomingRoot, budget: budget);
      final pending = await offer([List.filled(6, 1)]);
      await expectLater(
        inbox!.accept(pending.transferId),
        throwsA(storageCode('DISK_FULL')),
      );
      expect(inbox!.status(pending.transferId).state, TransferState.offered);
      expect(
        await Directory(p.join(incomingRoot.path, '.staging')).list().toList(),
        isEmpty,
      );
      final usage = await budget.inspect();
      expect(usage.temporaryBytes, 0);
      expect(usage.reservedBytes, 0);
    },
  );

  test(
    'batch quota admission is atomic and leaves other preparation possible',
    () async {
      final budget = StorageBudget(
        availableBytes: () async => 100,
        safetyReserveBytes: 0,
        temporaryQuotaBytes: 12,
      );
      inbox = await DurableInbox.open(incomingRoot, budget: budget);
      outbox = await DurableOutbox.open(outgoingRoot, budget: budget);
      await outbox!.stageStream(
        Stream.value(List.filled(2, 3)),
        displayName: 'small.bin',
        expectedSizeBytes: 2,
      );
      final pending = await offer([List.filled(6, 1), List.filled(6, 2)]);
      await expectLater(
        inbox!.accept(pending.transferId),
        throwsA(storageCode('TEMP_QUOTA_EXCEEDED')),
      );
      final prepared = await outbox!.stageStream(
        Stream.value(List.filled(10, 7)),
        displayName: 'fits.bin',
        expectedSizeBytes: 10,
      );
      expect(await File(prepared.path).length(), 10);
      expect((await budget.inspect()).reservedBytes, 0);
    },
  );

  test(
    'concurrent incoming and outgoing admissions share one disk reservation',
    () async {
      final budget = StorageBudget(
        availableBytes: () async => 10,
        safetyReserveBytes: 0,
        temporaryQuotaBytes: 100,
      );
      inbox = await DurableInbox.open(incomingRoot, budget: budget);
      outbox = await DurableOutbox.open(outgoingRoot, budget: budget);
      final pending = await offer([List.filled(6, 1)]);
      final proceed = Completer<void>();
      Stream<List<int>> source() async* {
        await proceed.future;
        yield List.filled(6, 9);
      }

      final preparing = outbox!
          .stageStream(
            source(),
            displayName: 'parallel.bin',
            expectedSizeBytes: 6,
          )
          .then<Object>((value) => value, onError: (Object error) => error);
      final accepting = inbox!
          .accept(pending.transferId)
          .then<Object>((value) => value, onError: (Object error) => error);
      for (var i = 0; i < 100; i++) {
        if ((await budget.inspect()).reservedBytes == 6) break;
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect((await budget.inspect()).reservedBytes, 6);
      proceed.complete();
      final outcomes = await Future.wait([preparing, accepting]);
      expect(outcomes.whereType<StorageException>(), hasLength(1));
      expect(outcomes.whereType<StorageException>().single.code, 'DISK_FULL');
      final usage = await budget.inspect();
      expect(usage.temporaryBytes + usage.reservedBytes, 6);
    },
  );

  test('written bytes are not charged twice and committed results remain intact', () async {
    // This test capability simulates a tiny payload volume. SQLite metadata is
    // deliberately outside that synthetic volume; each payload is a real file.
    final budget = StorageBudget(
      availableBytes: () async => 16 - await physicalPayloadBytes(),
      safetyReserveBytes: 4,
      temporaryQuotaBytes: 12,
      recheckBytes: 1,
    );
    inbox = await DurableInbox.open(
      incomingRoot,
      budget: budget,
      checkpointBytes: 4,
    );
    outbox = await DurableOutbox.open(outgoingRoot, budget: budget);
    final bytes = List.generate(12, (i) => i);
    final accepted = await inbox!.accept((await offer([bytes])).transferId);
    await write(accepted, bytes.sublist(0, 4));
    var usage = await budget.inspect();
    expect(usage.availableBytes, 12);
    expect(usage.temporaryBytes, 4);
    expect(usage.reservedBytes, 8);
    final result = await write(accepted, bytes.sublist(4));
    expect(result.state, FileState.committed);
    usage = await budget.inspect();
    expect(usage.availableBytes, 4);
    expect(usage.temporaryBytes, 0);
    expect(usage.reservedBytes, 0);
    await expectLater(
      outbox!.stageStream(
        Stream.value([1]),
        displayName: 'extra.bin',
        expectedSizeBytes: 1,
      ),
      throwsA(storageCode('DISK_FULL')),
    );
    expect(await File(result.finalPath!).readAsBytes(), bytes);
  });

  test(
    'late capacity loss pauses on a durable prefix and survives restart',
    () async {
      var free = 100;
      StorageBudget newBudget() => StorageBudget(
        availableBytes: () async => free,
        safetyReserveBytes: 10,
        temporaryQuotaBytes: 100,
        recheckBytes: 4,
      );
      var budget = newBudget();
      inbox = await DurableInbox.open(
        incomingRoot,
        budget: budget,
        checkpointBytes: 4,
      );
      final bytes = List.generate(12, (i) => i + 1);
      final accepted = await inbox!.accept((await offer([bytes])).transferId);
      final first = accepted.files.first;
      Stream<List<int>> shrinkingDisk() async* {
        yield bytes.sublist(0, 4);
        free = 11;
        yield bytes.sublist(4, 8);
        yield bytes.sublist(8);
      }

      await expectLater(
        inbox!.writeFile(
          accepted.transferId,
          first.fileId,
          offset: 0,
          incarnation: first.storageIncarnationId,
          bytes: shrinkingDisk(),
        ),
        throwsA(storageCode('DISK_FULL')),
      );
      expect(inbox!.status(accepted.transferId).files.first.offset, 4);
      expect(inbox!.status(accepted.transferId).state, TransferState.paused);
      expect(
        inbox!.status(accepted.transferId).files.first.errorCode,
        'DISK_FULL',
      );
      await inbox!.close();
      budget = newBudget();
      inbox = await DurableInbox.open(
        incomingRoot,
        budget: budget,
        checkpointBytes: 4,
      );
      final recovered = await budget.inspect();
      expect(recovered.temporaryBytes, 4);
      expect(recovered.reservedBytes, 8);
      expect(
        inbox!.status(accepted.transferId).files.first.errorCode,
        'DISK_FULL',
      );
      free = 100;
      final finished = await write(accepted, bytes.sublist(4));
      expect(finished.state, FileState.committed);
      expect(finished.errorCode, isNull);
      expect(await File(finished.finalPath!).readAsBytes(), bytes);
    },
  );

  test('unknown provider length cannot grow beyond quota or publish a partial source', () async {
    final budget = StorageBudget(
      availableBytes: () async => null,
      safetyReserveBytes: 10,
      temporaryQuotaBytes: 6,
    );
    outbox = await DurableOutbox.open(outgoingRoot, budget: budget);
    await expectLater(
      outbox!.stageStream(
        Stream.fromIterable([
          [1, 2, 3, 4],
          [5, 6, 7, 8],
        ]),
        displayName: 'unknown-size.bin',
      ),
      throwsA(storageCode('TEMP_QUOTA_EXCEEDED')),
    );
    expect(outbox!.list(), isEmpty);
    expect(await physicalPayloadBytes(), 0);
    final usage = await budget.inspect();
    expect(usage.availableBytes, isNull);
    expect(usage.temporaryBytes + usage.reservedBytes, 0);
  });

  test(
    'restart rebuilds both stores and quota cannot shrink below obligations',
    () async {
      StorageBudget newBudget() => StorageBudget(
        availableBytes: () async => 100,
        safetyReserveBytes: 0,
        temporaryQuotaBytes: 9,
      );
      var budget = newBudget();
      inbox = await DurableInbox.open(incomingRoot, budget: budget);
      outbox = await DurableOutbox.open(outgoingRoot, budget: budget);
      final original = File(p.join(root.path, 'user-original.bin'));
      await original.writeAsBytes([1, 2, 3]);
      final prepared = await outbox!.stageFile(original);
      final accepted = await inbox!.accept(
        (await offer([List.filled(6, 8)])).transferId,
      );
      await write(accepted, [8, 8]);
      await inbox!.close();
      await outbox!.close();
      budget = newBudget();
      inbox = await DurableInbox.open(incomingRoot, budget: budget);
      outbox = await DurableOutbox.open(outgoingRoot, budget: budget);
      var usage = await budget.inspect();
      expect(usage.temporaryBytes, 5);
      expect(usage.reservedBytes, 4);
      await expectLater(
        budget.setTemporaryQuotaBytes(8),
        throwsA(storageCode('TEMP_QUOTA_BELOW_USAGE')),
      );
      expect((await budget.inspect()).temporaryQuotaBytes, 9);
      await budget.setTemporaryQuotaBytes(10);
      await outbox!.remove(prepared.manifest.fileId);
      await inbox!.cancel(accepted.transferId);
      usage = await budget.inspect();
      expect(usage.temporaryBytes + usage.reservedBytes, 0);
      expect(await original.readAsBytes(), [1, 2, 3]);
    },
  );

  test('zero-length send and receive honor the reserve and succeed exactly at margin', () async {
    var free = 9;
    final budget = StorageBudget(
      availableBytes: () async => free,
      safetyReserveBytes: 10,
      temporaryQuotaBytes: 0,
    );
    outbox = await DurableOutbox.open(outgoingRoot, budget: budget);
    inbox = await DurableInbox.open(incomingRoot, budget: budget);
    final pending = await offer([<int>[]]);
    await expectLater(
      inbox!.accept(pending.transferId),
      throwsA(storageCode('DISK_FULL')),
    );
    await expectLater(
      outbox!.stageStream(
        const Stream.empty(),
        displayName: 'empty',
        expectedSizeBytes: 0,
      ),
      throwsA(storageCode('DISK_FULL')),
    );
    free = 10;
    final empty = await outbox!.stageStream(
      const Stream.empty(),
      displayName: 'empty',
      expectedSizeBytes: 0,
    );
    expect(empty.manifest.sizeBytes, 0);
    expect(await File(empty.path).length(), 0);
    final accepted = await inbox!.accept(pending.transferId);
    final received = await write(accepted, []);
    expect(received.state, FileState.committed);
    expect(await File(received.finalPath!).length(), 0);
    expect((await budget.inspect()).temporaryBytes, 0);
  });

  test(
    'failed preparation releases reservation without removing the original',
    () async {
      final budget = StorageBudget(
        availableBytes: () async => 100,
        safetyReserveBytes: 0,
        temporaryQuotaBytes: 4,
      );
      outbox = await DurableOutbox.open(outgoingRoot, budget: budget);
      final original = File(p.join(root.path, 'kept.bin'));
      await original.writeAsBytes([1, 2, 3, 4]);
      var cancel = false;
      await expectLater(
        outbox!.stageFile(
          original,
          onProgress: (_) => cancel = true,
          isCancelled: () => cancel,
        ),
        throwsA(storageCode('PREPARATION_CANCELLED')),
      );
      expect(await original.readAsBytes(), [1, 2, 3, 4]);
      expect((await budget.inspect()).reservedBytes, 0);
      expect((await budget.inspect()).temporaryBytes, 0);
      expect(await physicalPayloadBytes(), 0);
    },
  );

  test(
    'recovery accounts orphaned prepared payloads without deleting them',
    () async {
      outbox = await DurableOutbox.open(outgoingRoot);
      await outbox!.close();
      final orphan = File(p.join(outgoingRoot.path, 'files', 'orphan.blob'));
      await orphan.writeAsBytes([1, 2, 3, 4, 5]);
      final budget = StorageBudget(
        availableBytes: () async => null,
        safetyReserveBytes: 0,
        temporaryQuotaBytes: 4,
      );
      outbox = await DurableOutbox.open(outgoingRoot, budget: budget);
      expect((await budget.inspect()).temporaryBytes, 5);
      await expectLater(
        outbox!.stageStream(
          Stream.value([6]),
          displayName: 'over.bin',
          expectedSizeBytes: 1,
        ),
        throwsA(storageCode('TEMP_QUOTA_EXCEEDED')),
      );
      expect(await orphan.readAsBytes(), [1, 2, 3, 4, 5]);
    },
  );

  test(
    'removal rejects a symlinked payload parent and preserves external bytes',
    () async {
      outbox = await DurableOutbox.open(outgoingRoot);
      final prepared = await outbox!.stageStream(
        Stream.value([1, 2, 3]),
        displayName: 'source.bin',
        expectedSizeBytes: 3,
      );
      final files = Directory(p.join(outgoingRoot.path, 'files'));
      final moved = await files.rename(p.join(root.path, 'outside'));
      await Link(files.path).create(moved.path);
      await expectLater(
        outbox!.remove(prepared.manifest.fileId),
        throwsA(storageCode('UNSAFE_PATH')),
      );
      expect(
        await File(p.join(moved.path, p.basename(prepared.path))).readAsBytes(),
        [1, 2, 3],
      );
      expect(outbox!.list(), hasLength(1));
    },
    skip: Platform.isWindows
        ? 'Symlink creation requires privileges on Windows.'
        : false,
  );
}
