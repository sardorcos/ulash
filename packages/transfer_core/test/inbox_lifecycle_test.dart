import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:transfer_core/transfer_core.dart';

Matcher errorCode(String value) => isA<StorageException>().having(
  (error) => error.code,
  'storage code',
  value,
);

class TestClock {
  DateTime wall = DateTime.utc(2026, 11, 21, 12);
  Duration mono = Duration.zero;
  void advance(Duration duration) {
    wall = wall.add(duration);
    mono += duration;
  }
}

FileManifest fileManifest(List<int> bytes, {String id = 'file-a'}) =>
    FileManifest(
      fileId: id,
      displayName: '$id.bin',
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );

void main() {
  late Directory root;
  late Directory incoming;
  late TestClock clock;
  DurableInbox? inbox;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('transfer-inbox-lifecycle-');
    incoming = Directory(p.join(root.path, 'inbox'));
    clock = TestClock();
  });

  tearDown(() async {
    await inbox?.close();
    inbox = null;
    await root.delete(recursive: true);
  });

  Future<void> open({StorageBudget? budget}) async {
    inbox = await DurableInbox.open(
      incoming,
      budget: budget,
      checkpointBytes: 2,
      // These scenarios exercise the global queue; one test peer fills it.
      maxPendingOffersPerPeer: 10,
      wallClock: () => clock.wall,
      monotonicClock: () => clock.mono,
    );
  }

  Future<TransferSnapshot> offer({
    String id = 'request-a',
    List<List<int>>? contents,
  }) => inbox!.createOffer(
    TransferManifest(
      requestId: id,
      files: [
        for (final (index, bytes)
            in (contents ??
                    [
                      [1, 2, 3, 4],
                    ])
                .indexed)
          fileManifest(bytes, id: 'file-$index'),
      ],
    ),
    peerId: 'verified-peer',
  );

  Future<FileSnapshot> write(
    TransferSnapshot transfer,
    List<int> bytes, {
    int index = 0,
  }) {
    final file = inbox!.status(transfer.transferId).files[index];
    return inbox!.writeFile(
      transfer.transferId,
      file.fileId,
      offset: file.offset,
      incarnation: file.storageIncarnationId,
      bytes: Stream.value(bytes),
    );
  }

  test(
    '120 second expiry is durable, terminal and request-id idempotent',
    () async {
      await open();
      final first = await offer();
      expect(
        first.offerExpiresAt,
        clock.wall.add(const Duration(seconds: 120)),
      );
      expect(
        TransferSnapshot.fromJson(first.toJson()).offerExpiresAt,
        first.offerExpiresAt,
      );
      clock.advance(const Duration(seconds: 119));
      expect(inbox!.status(first.transferId).state, TransferState.offered);
      clock.advance(const Duration(seconds: 1));
      final expired = inbox!.status(first.transferId);
      expect(expired.state, TransferState.expired);
      expect(expired.files.single.state, FileState.expired);
      expect(expired.files.single.errorCode, 'OFFER_EXPIRED');
      await expectLater(
        inbox!.accept(first.transferId),
        throwsA(errorCode('OFFER_EXPIRED')),
      );
      await expectLater(write(first, [1]), throwsA(errorCode('INVALID_STATE')));
      final repeated = await offer();
      expect(repeated.transferId, first.transferId);
      expect(repeated.state, TransferState.expired);
      await inbox!.close();
      await open();
      expect((await offer()).state, TransferState.expired);
      expect(inbox!.list(), hasLength(1));
      expect(
        await Directory(p.join(incoming.path, '.staging')).list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'running TTL follows monotonic time despite wall-clock changes',
    () async {
      await open();
      final pending = await offer();
      clock.wall = clock.wall.add(const Duration(days: 100));
      expect(inbox!.status(pending.transferId).state, TransferState.offered);
      clock.wall = clock.wall.subtract(const Duration(days: 200));
      clock.mono = const Duration(seconds: 120);
      expect(inbox!.status(pending.transferId).state, TransferState.expired);
    },
  );

  test(
    'reopening uses remaining original deadline and rollback fails closed',
    () async {
      await open();
      final pending = await offer();
      await inbox!.close();
      clock.wall = clock.wall.add(const Duration(seconds: 90));
      clock.mono = Duration.zero;
      await open();
      clock.advance(const Duration(seconds: 29));
      expect(inbox!.status(pending.transferId).state, TransferState.offered);
      clock.advance(const Duration(seconds: 1));
      expect(inbox!.status(pending.transferId).state, TransferState.expired);

      final other = await offer(id: 'rollback');
      await inbox!.close();
      clock.wall = clock.wall.subtract(const Duration(seconds: 1));
      clock.mono = Duration.zero;
      await open();
      expect(inbox!.status(other.transferId).state, TransferState.expired);
    },
  );

  test(
    '0.2 journal migration preserves accepted, paused and committed records',
    () async {
      await open();
      final pending = await offer();
      final accepted = await offer(id: 'already-consented');
      await inbox!.accept(accepted.transferId);
      final paused = await inbox!.accept(
        (await offer(id: 'paused')).transferId,
      );
      await write(paused, [1, 2]);
      await inbox!.pause(paused.transferId);
      final completed = await inbox!.accept(
        (await offer(id: 'completed')).transferId,
      );
      final saved = await write(completed, [1, 2, 3, 4]);
      await inbox!.close();
      final db = sqlite3.open(p.join(incoming.path, 'inbox.sqlite'));
      db.execute('ALTER TABLE inbox_transfers DROP COLUMN offer_expires_at');
      db.close();
      clock.advance(const Duration(seconds: 121));
      await open();
      expect(inbox!.status(pending.transferId).state, TransferState.expired);
      expect(inbox!.status(accepted.transferId).state, TransferState.accepted);
      final restoredPause = inbox!.status(paused.transferId);
      expect(restoredPause.state, TransferState.paused);
      expect(restoredPause.pausedBySink, isTrue);
      expect(restoredPause.files.single.offset, 2);
      expect(
        restoredPause.files.single.storageIncarnationId,
        paused.files.single.storageIncarnationId,
      );
      expect(
        inbox!.status(completed.transferId).state,
        TransferState.completed,
      );
      expect(await File(saved.finalPath!).readAsBytes(), [1, 2, 3, 4]);
      await inbox!.resume(paused.transferId);
      expect((await write(paused, [3, 4])).state, FileState.committed);
      expect((await write(accepted, [1, 2, 3, 4])).state, FileState.committed);
    },
  );

  test(
    'expiry recovers all pending queue slots without allowing resurrection',
    () async {
      await open();
      for (var index = 0; index < 10; index++) {
        await offer(id: 'pending-$index');
      }
      await expectLater(offer(id: 'full'), throwsA(errorCode('BUSY')));
      clock.advance(const Duration(seconds: 120));
      expect((await offer(id: 'new')).state, TransferState.offered);
      expect((await offer(id: 'pending-0')).state, TransferState.expired);
      expect(
        inbox!.list().where((item) => item.state == TransferState.expired),
        hasLength(10),
      );
    },
  );

  test(
    'deadline wins if acceptance capacity check outlives consent lifetime',
    () async {
      final capacityRequested = Completer<void>();
      final capacity = Completer<int?>();
      var block = false;
      final budget = StorageBudget(
        availableBytes: () async {
          if (!block) return 1000;
          if (!capacityRequested.isCompleted) capacityRequested.complete();
          return capacity.future;
        },
        safetyReserveBytes: 0,
        temporaryQuotaBytes: 1000,
      );
      await open(budget: budget);
      final pending = await offer();
      block = true;
      final acceptance = inbox!.accept(pending.transferId);
      final check = expectLater(
        acceptance,
        throwsA(errorCode('OFFER_EXPIRED')),
      );
      await capacityRequested.future;
      clock.advance(const Duration(seconds: 120));
      expect(inbox!.status(pending.transferId).state, TransferState.expired);
      capacity.complete(1000);
      await check;
      block = false;
      final usage = await budget.inspect();
      expect(usage.temporaryBytes, 0);
      expect(usage.reservedBytes, 0);
      expect(
        await Directory(p.join(incoming.path, '.staging')).list().toList(),
        isEmpty,
      );
    },
  );

  test('foreground timer emits expiry without a status poll', () async {
    inbox = await DurableInbox.open(
      incoming,
      offerLifetime: const Duration(milliseconds: 50),
    );
    final expired = inbox!.changes.firstWhere(
      (item) => item.state == TransferState.expired,
    );
    final pending = await offer();
    expect(
      (await expired.timeout(const Duration(seconds: 3))).transferId,
      pending.transferId,
    );
  });

  test('discard frees partial payload and reservation while preserving committed files', () async {
    final budget = StorageBudget(
      availableBytes: () async => 1000,
      safetyReserveBytes: 0,
    );
    await open(budget: budget);
    final pending = await offer(
      contents: [
        [7, 8, 9],
        [1, 2, 3, 4, 5],
      ],
    );
    final accepted = await inbox!.accept(pending.transferId);
    final committed = await write(accepted, [7, 8, 9]);
    await write(accepted, [1, 2], index: 1);
    final preview = (await inbox!.previewIncompleteCleanup()).single;
    expect(preview.transferId, accepted.transferId);
    expect(preview.temporaryBytes, 2);
    expect(preview.reservedBytes, 3);
    expect(preview.incompleteFileCount, 1);
    expect(preview.committedFileCount, 1);
    final result = await inbox!.discardIncomplete(preview.transferId);
    expect(result.removedFileCount, 1);
    expect(result.removedBytes, 2);
    expect(result.snapshot.state, TransferState.partiallyCompleted);
    expect(result.snapshot.files.first.state, FileState.committed);
    expect(result.snapshot.files.last.state, FileState.cancelled);
    expect(result.snapshot.files.last.offset, 0);
    expect(await File(committed.finalPath!).readAsBytes(), [7, 8, 9]);
    expect((await budget.inspect()).temporaryBytes, 0);
    expect((await budget.inspect()).reservedBytes, 0);
    expect(
      (await inbox!.discardIncomplete(preview.transferId)).removedFileCount,
      0,
    );
    expect(await inbox!.previewIncompleteCleanup(), isEmpty);
    await expectLater(
      write(accepted, [1, 2, 3, 4, 5], index: 1),
      throwsA(errorCode('INVALID_STATE')),
    );
    await inbox!.close();
    await open(budget: budget);
    expect(
      inbox!.status(accepted.transferId).files.first.state,
      FileState.committed,
    );
    expect(await File(committed.finalPath!).readAsBytes(), [7, 8, 9]);
  });

  test(
    'failed terminal partials are discarded and preserve failure receipt',
    () async {
      final budget = StorageBudget(
        availableBytes: () async => 1000,
        safetyReserveBytes: 0,
      );
      await open(budget: budget);
      final pending = await offer();
      final accepted = await inbox!.accept(pending.transferId);
      await expectLater(
        write(accepted, [9, 9, 9, 9]),
        throwsA(errorCode('INTEGRITY_MISMATCH')),
      );
      final failed = inbox!.status(accepted.transferId);
      expect(failed.state, TransferState.failed);
      expect(failed.files.single.errorCode, 'INTEGRITY_MISMATCH');
      expect(failed.files.single.offset, 0);
      // A non-resumable payload no longer holds temporary quota.
      expect(await inbox!.previewIncompleteCleanup(), isEmpty);
      final usage = await budget.inspect();
      expect(usage.temporaryBytes, 0);
      expect(usage.reservedBytes, 0);
      expect(
        await Directory(p.join(incoming.path, '.staging')).list().toList(),
        isEmpty,
      );
      expect((await offer()).transferId, accepted.transferId);
    },
  );

  test(
    'late cleanup confirmation never removes a newly committed result',
    () async {
      await open();
      final accepted = await inbox!.accept((await offer()).transferId);
      final preview = (await inbox!.previewIncompleteCleanup()).single;
      final committed = await write(accepted, [1, 2, 3, 4]);
      final result = await inbox!.discardIncomplete(preview.transferId);
      expect(result.removedFileCount, 0);
      expect(result.removedBytes, 0);
      expect(result.snapshot.state, TransferState.completed);
      expect(await File(committed.finalPath!).readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test(
    'discard stops an active writer before deleting its durable prefix',
    () async {
      await open();
      final accepted = await inbox!.accept((await offer()).transferId);
      final input = StreamController<List<int>>();
      final checkpoint = inbox!.changes.firstWhere(
        (item) => item.durableBytes == 2,
      );
      final writing = inbox!.writeFile(
        accepted.transferId,
        accepted.files.single.fileId,
        offset: 0,
        incarnation: accepted.files.single.storageIncarnationId,
        bytes: input.stream,
      );
      final interrupted = expectLater(
        writing,
        throwsA(errorCode('TRANSFER_CANCELLED')),
      );
      input.add([1, 2]);
      await checkpoint.timeout(const Duration(seconds: 3));
      final result = await inbox!.discardIncomplete(accepted.transferId);
      await interrupted;
      await input.close();
      expect(result.removedBytes, 2);
      expect(result.snapshot.state, TransferState.cancelled);
      expect(
        await Directory(p.join(incoming.path, '.staging')).list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'cleanup refuses a linked parent and can be retried after safe repair',
    () async {
      final budget = StorageBudget(
        availableBytes: () async => 1000,
        safetyReserveBytes: 0,
      );
      await open(budget: budget);
      final accepted = await inbox!.accept((await offer()).transferId);
      await write(accepted, [1, 2]);
      final staging = Directory(p.join(incoming.path, '.staging'));
      final original = await staging.rename(
        p.join(incoming.path, '.original-staging'),
      );
      final external = await Directory(p.join(root.path, 'external')).create();
      final name = '${accepted.files.single.storageIncarnationId}.part';
      final sentinel = await File(p.join(external.path, name))
          .writeAsBytes([9, 9, 9]);
      final link = await Link(staging.path).create(external.path);
      await expectLater(
        inbox!.discardIncomplete(accepted.transferId),
        throwsA(errorCode('UNSAFE_PATH')),
      );
      expect(await sentinel.readAsBytes(), [9, 9, 9]);
      expect(inbox!.status(accepted.transferId).state, TransferState.cancelled);
      await link.delete();
      await original.rename(staging.path);
      final result = await inbox!.discardIncomplete(accepted.transferId);
      expect(result.removedBytes, 2);
      expect((await budget.inspect()).temporaryBytes, 0);
      expect((await budget.inspect()).reservedBytes, 0);
      expect(await sentinel.readAsBytes(), [9, 9, 9]);
    },
  );

  test(
    'cleanup repairs a terminal offset after payload deletion was interrupted',
    () async {
      await open();
      final accepted = await inbox!.accept((await offer()).transferId);
      await write(accepted, [1, 2]);
      final part = File(
        p.join(
          incoming.path,
          '.staging',
          '${accepted.files.single.storageIncarnationId}.part',
        ),
      );
      final db = sqlite3.open(p.join(incoming.path, 'inbox.sqlite'));
      db.execute(
        "UPDATE inbox_files SET state='cancelled' WHERE transfer_id=?",
        [accepted.transferId],
      );
      db.execute("UPDATE inbox_transfers SET state='cancelled' WHERE id=?", [
        accepted.transferId,
      ]);
      db.close();
      await part.delete();
      expect(inbox!.status(accepted.transferId).files.single.offset, 2);
      final result = await inbox!.discardIncomplete(accepted.transferId);
      expect(result.removedFileCount, 0);
      expect(result.snapshot.files.single.offset, 0);
      expect(result.snapshot.state, TransferState.cancelled);
    },
  );

  test(
    'indeterminate commit intent is protected until verified recovery',
    () async {
      final budget = StorageBudget(
        availableBytes: () async => 1000,
        safetyReserveBytes: 0,
      );
      await open(budget: budget);
      final accepted = await inbox!.accept((await offer()).transferId);
      await write(accepted, [1, 2]);
      final incarnation = accepted.files.single.storageIncarnationId;
      final temporary = File(
        p.join(incoming.path, '.staging', '$incarnation.part'),
      );
      await temporary.writeAsBytes([1, 2, 3, 4], flush: true);
      final finalDirectory = await Directory(
        p.join(incoming.path, 'received', accepted.transferId, incarnation),
      ).create(recursive: true);
      final finalPath = p.join(finalDirectory.path, 'file-0.bin');
      // Simulate an interrupted commit after durable intent but before rename.
      final db = sqlite3.open(p.join(incoming.path, 'inbox.sqlite'));
      db.execute(
        "UPDATE inbox_files SET state='committing',durable_offset=4,final_path=? WHERE transfer_id=?",
        [finalPath, accepted.transferId],
      );
      db.execute("UPDATE inbox_transfers SET state='transferring' WHERE id=?", [
        accepted.transferId,
      ]);
      db.close();
      expect(await inbox!.previewIncompleteCleanup(), isEmpty);
      final protected = await inbox!.discardIncomplete(accepted.transferId);
      expect(protected.removedFileCount, 0);
      expect(protected.snapshot.files.single.state, FileState.committing);
      expect(await temporary.readAsBytes(), [1, 2, 3, 4]);
      await inbox!.close();
      await open(budget: budget);
      expect(inbox!.status(accepted.transferId).state, TransferState.completed);
      expect(await File(finalPath).readAsBytes(), [1, 2, 3, 4]);
      expect((await budget.inspect()).reservedBytes, 0);
    },
  );
}
