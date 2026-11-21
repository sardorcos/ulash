import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:transfer_core/src/network/pinned_http_client.dart';
import 'package:transfer_core/src/security/pairing_service.dart';
import 'package:transfer_core/src/storage/storage_support.dart';
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

FileManifest fileManifest(
  List<int> bytes, {
  String id = 'file-a',
  String? name,
}) => FileManifest(
  fileId: id,
  displayName: name ?? '$id.bin',
  sizeBytes: bytes.length,
  sha256: sha256.convert(bytes).toString(),
);

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition not reached');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory temp;
  late TestClock clock;
  DurableInbox? inbox;
  DurableOutbox? outbox;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('transfer-hardening-');
    clock = TestClock();
  });

  tearDown(() async {
    await inbox?.close();
    await outbox?.close();
    inbox = null;
    outbox = null;
    await temp.delete(recursive: true);
  });

  Future<DurableInbox> openInbox(
    Directory directory, {
    StorageBudget? budget,
    int maxOffersPerWindow = 20,
    int maxRetainedUnaccepted = 50,
  }) async => inbox = await DurableInbox.open(
    directory,
    budget: budget,
    checkpointBytes: 2,
    wallClock: () => clock.wall,
    monotonicClock: () => clock.mono,
    maxOffersPerWindow: maxOffersPerWindow,
    maxRetainedUnacceptedOffersPerPeer: maxRetainedUnaccepted,
  );

  Future<TransferSnapshot> offer(
    List<List<int>> payloads, {
    String request = 'request-1',
    String peer = 'peer-a',
  }) => inbox!.createOffer(
    TransferManifest(
      requestId: request,
      files: [
        for (var i = 0; i < payloads.length; i++)
          fileManifest(payloads[i], id: 'file-$i'),
      ],
    ),
    peerId: peer,
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

  group('store-relative paths (container moves)', () {
    test('journals persist only relative paths', () async {
      final directory = Directory(p.join(temp.path, 'a', 'inbox'));
      await openInbox(directory);
      final transfer = await inbox!.accept(
        (await offer([
          [1, 2, 3],
        ])).transferId,
      );
      await write(transfer, [1, 2, 3]);
      await inbox!.close();
      inbox = null;
      final db = sqlite3.open(p.join(directory.path, 'inbox.sqlite'));
      final row = db.select('SELECT * FROM inbox_files').single;
      db.close();
      expect(row['temporary_path'], startsWith('.staging/'));
      expect(row['final_path'], startsWith('received/'));
      expect(p.isRelative(row['final_path'] as String), isTrue);
    });

    test(
      'moving the whole data tree keeps results, resume, cleanup and budget',
      () async {
        final oldRoot = Directory(p.join(temp.path, 'container-A'));
        final budget = StorageBudget(
          availableBytes: () async => 1 << 30,
          safetyReserveBytes: 0,
        );
        await openInbox(
          Directory(p.join(oldRoot.path, 'inbox')),
          budget: budget,
        );
        outbox = await DurableOutbox.open(
          Directory(p.join(oldRoot.path, 'outbox')),
          budget: budget,
        );
        final staged = await outbox!.stageStream(
          Stream.value([5, 6, 7]),
          displayName: 'send.bin',
          expectedSizeBytes: 3,
        );
        final done = await inbox!.accept(
          (await offer([
            [1, 2, 3],
          ], request: 'done')).transferId,
        );
        await write(done, [1, 2, 3]);
        final partial = await inbox!.accept(
          (await offer([
            [9, 8, 7, 6],
          ], request: 'partial')).transferId,
        );
        await write(partial, [9, 8]);
        await inbox!.close();
        await outbox!.close();
        inbox = null;
        outbox = null;

        // Simulate an iOS container UUID change: everything moves at once.
        final newRoot = Directory(p.join(temp.path, 'container-B'));
        await oldRoot.rename(newRoot.path);
        final movedBudget = StorageBudget(
          availableBytes: () async => 1 << 30,
          safetyReserveBytes: 0,
        );
        await openInbox(
          Directory(p.join(newRoot.path, 'inbox')),
          budget: movedBudget,
        );
        outbox = await DurableOutbox.open(
          Directory(p.join(newRoot.path, 'outbox')),
          budget: movedBudget,
        );

        final completed = inbox!.status(done.transferId).files.single;
        expect(completed.state, FileState.committed);
        expect(completed.errorCode, isNull);
        expect(p.isWithin(newRoot.path, completed.finalPath!), isTrue);
        expect(await File(completed.finalPath!).readAsBytes(), [1, 2, 3]);

        final resumed = inbox!.status(partial.transferId);
        expect(resumed.state, TransferState.paused);
        expect(resumed.files.single.offset, 2);
        expect((await movedBudget.inspect()).temporaryBytes, 2 + 3);
        final preview = await inbox!.previewIncompleteCleanup();
        expect(preview.single.temporaryBytes, 2);
        await inbox!.resume(partial.transferId);
        await write(resumed, [7, 6]);
        expect(
          inbox!.status(partial.transferId).state,
          TransferState.completed,
        );

        final prepared = outbox!.get(staged.manifest.fileId);
        expect(p.isWithin(newRoot.path, prepared.path), isTrue);
        expect(
          await outbox!.read(staged.manifest.fileId).expand((c) => c).toList(),
          [5, 6, 7],
        );
        await outbox!.remove(staged.manifest.fileId);
        final usage = await movedBudget.inspect();
        expect(usage.temporaryBytes, 0);
        expect(usage.reservedBytes, 0);
      },
    );

    test('legacy absolute rows from another container are migrated', () async {
      final directory = Directory(p.join(temp.path, 'inbox'));
      await openInbox(directory);
      final done = await inbox!.accept(
        (await offer([
          [1, 2, 3],
        ], request: 'done')).transferId,
      );
      final committed = await write(done, [1, 2, 3]);
      final partial = await inbox!.accept(
        (await offer([
          [4, 5, 6, 7],
        ], request: 'partial')).transferId,
      );
      await write(partial, [4, 5]);
      await inbox!.close();
      inbox = null;
      final outboxDirectory = Directory(p.join(temp.path, 'outbox'));
      outbox = await DurableOutbox.open(outboxDirectory);
      final staged = await outbox!.stageStream(
        Stream.value([1]),
        displayName: 'one.bin',
        expectedSizeBytes: 1,
      );
      await outbox!.close();
      outbox = null;

      // Rewrite rows exactly as 0.3 stored them, but under a stale container.
      const stale = '/var/mobile/Containers/Data/Application/OLD-UUID';
      final relativeFinal = p
          .split(p.relative(committed.finalPath!, from: directory.path))
          .join('/');
      final db = sqlite3.open(p.join(directory.path, 'inbox.sqlite'));
      for (final row in db.select('SELECT * FROM inbox_files')) {
        db.execute(
          'UPDATE inbox_files SET temporary_path=?,final_path=? WHERE transfer_id=? AND file_id=?',
          [
            '$stale/inbox/.staging/${row['incarnation']}.part',
            row['final_path'] == null ? null : '$stale/inbox/$relativeFinal',
            row['transfer_id'],
            row['file_id'],
          ],
        );
      }
      db.execute('PRAGMA user_version=0');
      db.close();
      final outDb = sqlite3.open(p.join(outboxDirectory.path, 'outbox.sqlite'));
      outDb.execute('UPDATE outbox_files SET path=?', [
        '$stale/outbox/files/${staged.manifest.fileId}.blob',
      ]);
      outDb.execute('PRAGMA user_version=0');
      outDb.close();

      await openInbox(directory);
      final file = inbox!.status(done.transferId).files.single;
      expect(file.state, FileState.committed);
      expect(await File(file.finalPath!).readAsBytes(), [1, 2, 3]);
      final paused = inbox!.status(partial.transferId).files.single;
      expect(paused.state, FileState.paused);
      expect(paused.offset, 2);
      outbox = await DurableOutbox.open(outboxDirectory);
      expect(
        await outbox!.read(staged.manifest.fileId).expand((c) => c).toList(),
        [1],
      );
      await inbox!.close();
      inbox = null;
      final check = sqlite3.open(p.join(directory.path, 'inbox.sqlite'));
      expect(check.select('PRAGMA user_version').single.values.single, 2);
      for (final row in check.select('SELECT * FROM inbox_files')) {
        expect(row['temporary_path'], startsWith('.staging/'));
      }
      check.close();
    });

    test('path helpers reject escapes and rebase legacy suffixes', () {
      final root = Directory(p.join(temp.path, 'r'));
      expect(
        rebaseLegacyPath(
          '/old/x/inbox/received/t/i/a.txt',
          managedTopLevel: {'received'},
        ),
        'received/t/i/a.txt',
      );
      expect(
        rebaseLegacyPath('/old/x/other/a.txt', managedTopLevel: {'received'}),
        isNull,
      );
      expect(
        () => resolveStoredPath(
          root,
          'received/../../etc/passwd',
          managedTopLevel: {'received'},
        ),
        throwsA(errorCode('UNSAFE_PATH')),
      );
      expect(
        () =>
            resolveStoredPath(root, 'outside/a', managedTopLevel: {'received'}),
        throwsA(errorCode('UNSAFE_PATH')),
      );
    });
  });

  group('journal versioning and corruption', () {
    test('records the schema version and refuses a newer journal', () async {
      final directory = Directory(p.join(temp.path, 'inbox'));
      await openInbox(directory);
      await inbox!.close();
      inbox = null;
      final db = sqlite3.open(p.join(directory.path, 'inbox.sqlite'));
      expect(
        db.select('PRAGMA user_version').single.values.single,
        DurableInbox.schemaVersion,
      );
      db.execute('PRAGMA user_version=99');
      db.close();
      await expectLater(
        openInbox(directory),
        throwsA(errorCode('JOURNAL_TOO_NEW')),
      );
    });

    test(
      'a damaged journal fails closed and can be quarantined explicitly',
      () async {
        final directory = Directory(p.join(temp.path, 'inbox'));
        await openInbox(directory);
        final done = await inbox!.accept(
          (await offer([
            [1, 2, 3],
          ], request: 'done')).transferId,
        );
        final committed = await write(done, [1, 2, 3]);
        final partial = await inbox!.accept(
          (await offer([
            [4, 5, 6],
          ], request: 'partial')).transferId,
        );
        await write(partial, [4]);
        await inbox!.close();
        inbox = null;
        final journal = File(p.join(directory.path, 'inbox.sqlite'));
        await journal.writeAsBytes(List.filled(4096, 0x42), flush: true);
        for (final side in ['-wal', '-shm']) {
          final file = File('${journal.path}$side');
          if (await file.exists()) await file.delete();
        }
        await expectLater(
          openInbox(directory),
          throwsA(errorCode('JOURNAL_CORRUPT')),
        );
        final moved = await DurableInbox.quarantineJournal(directory);
        expect(moved, isNotEmpty);
        expect(await File(moved.first).exists(), isTrue);
        await openInbox(directory);
        expect(inbox!.list(), isEmpty);
        // Received results are user data and stay; orphan parts are removed.
        expect(await File(committed.finalPath!).readAsBytes(), [1, 2, 3]);
        expect(
          await Directory(p.join(directory.path, '.staging')).list().toList(),
          isEmpty,
        );
      },
    );

    test('outbox journal corruption is reported the same way', () async {
      final directory = Directory(p.join(temp.path, 'outbox'));
      outbox = await DurableOutbox.open(directory);
      await outbox!.close();
      outbox = null;
      await File(p.join(directory.path, 'outbox.sqlite'))
          .writeAsString('not a database at all, definitely not', flush: true);
      await expectLater(
        DurableOutbox.open(directory),
        throwsA(errorCode('JOURNAL_CORRUPT')),
      );
      await DurableOutbox.quarantineJournal(directory);
      outbox = await DurableOutbox.open(directory);
      expect(outbox!.list(), isEmpty);
    });
  });

  group('cancel and pause races', () {
    for (final (stage, size, sent) in [
      ('afterFinalClose', 8, 4),
      ('beforeVerifying', 8, 8),
    ]) {
      test('cancel at $stage stays cancelled and frees its payload', () async {
        final directory = Directory(p.join(temp.path, 'inbox'));
        final budget = StorageBudget(
          availableBytes: () async => 1 << 30,
          safetyReserveBytes: 0,
        );
        await openInbox(directory, budget: budget);
        final data = List<int>.generate(size, (i) => i);
        final transfer = await inbox!.accept((await offer([data])).transferId);
        Future<TransferSnapshot>? cancelling;
        inbox!.debugStageHook = (point) async {
          if (point != stage || cancelling != null) return;
          cancelling = inbox!.cancel(transfer.transferId);
          // Let cancel persist its decision and start waiting for the writer.
          await Future<void>.delayed(const Duration(milliseconds: 20));
        };
        final file = transfer.files.single;
        await expectLater(
          inbox!.writeFile(
            transfer.transferId,
            file.fileId,
            offset: 0,
            incarnation: file.storageIncarnationId,
            bytes: Stream.value(data.sublist(0, sent)),
          ),
          throwsA(errorCode('TRANSFER_CANCELLED')),
        );
        expect(cancelling, isNotNull);
        await cancelling;
        inbox!.debugStageHook = null;
        final result = inbox!.status(transfer.transferId);
        expect(result.state, TransferState.cancelled);
        expect(result.files.single.state, FileState.cancelled);
        expect(
          await Directory(p.join(directory.path, '.staging')).list().toList(),
          isEmpty,
        );
        final usage = await budget.inspect();
        expect(usage.temporaryBytes + usage.reservedBytes, 0);
      });
    }

    test('a cancel during the final write never becomes failed', () async {
      final directory = Directory(p.join(temp.path, 'inbox'));
      final budget = StorageBudget(
        availableBytes: () async => 1 << 30,
        safetyReserveBytes: 0,
      );
      await openInbox(directory, budget: budget, maxOffersPerWindow: 1000);
      final data = List<int>.generate(64, (i) => i);
      for (var round = 0; round < 40; round++) {
        final transfer = await inbox!.accept(
          (await offer([data], request: 'race-$round')).transferId,
        );
        final file = transfer.files.single;
        final writing = inbox!
            .writeFile(
              transfer.transferId,
              file.fileId,
              offset: 0,
              incarnation: file.storageIncarnationId,
              bytes: Stream.fromIterable([
                for (var i = 0; i < data.length; i += 8) data.sublist(i, i + 8),
              ]),
            )
            .then<Object?>((value) => value, onError: (Object error) => error);
        for (var turn = 0; turn < round; turn++) {
          await Future<void>.delayed(Duration.zero);
        }
        await inbox!.cancel(transfer.transferId);
        await writing;
        final result = inbox!.status(transfer.transferId);
        expect(
          result.state,
          anyOf(TransferState.cancelled, TransferState.completed),
          reason: 'round $round',
        );
        if (result.state == TransferState.cancelled) {
          expect(result.files.single.state, FileState.cancelled);
          expect(result.files.single.errorCode, isNull);
        }
      }
      expect(
        await Directory(p.join(directory.path, '.staging')).list().toList(),
        isEmpty,
      );
      expect((await budget.inspect()).reservedBytes, 0);
    });

    test('a pause during the final write never becomes verifying', () async {
      final directory = Directory(p.join(temp.path, 'inbox'));
      await openInbox(directory, maxOffersPerWindow: 1000);
      final data = List<int>.generate(32, (i) => i);
      for (var round = 0; round < 30; round++) {
        final transfer = await inbox!.accept(
          (await offer([data], request: 'pause-$round')).transferId,
        );
        final file = transfer.files.single;
        final writing = inbox!
            .writeFile(
              transfer.transferId,
              file.fileId,
              offset: 0,
              incarnation: file.storageIncarnationId,
              bytes: Stream.fromIterable([
                for (var i = 0; i < data.length; i += 4) data.sublist(i, i + 4),
              ]),
            )
            .then<Object?>((value) => value, onError: (Object error) => error);
        for (var turn = 0; turn < round; turn++) {
          await Future<void>.delayed(Duration.zero);
        }
        await inbox!.pause(transfer.transferId);
        await writing;
        final result = inbox!.status(transfer.transferId);
        expect(
          result.state,
          anyOf(TransferState.paused, TransferState.completed),
          reason: 'round $round',
        );
        expect(
          result.files.single.state,
          isNot(anyOf(FileState.verifying, FileState.failed)),
        );
        if (result.state == TransferState.paused) {
          await inbox!.cancel(transfer.transferId);
        }
      }
    });
  });

  group('admission limits', () {
    test('offers are rate limited per peer; replays are not counted', () async {
      await openInbox(
        Directory(p.join(temp.path, 'inbox')),
        maxOffersPerWindow: 3,
      );
      final first = await offer([
        [1],
      ], request: 'r1');
      await inbox!.reject(first.transferId);
      await offer([
        [1],
      ], request: 'r2');
      await offer([
        [1],
      ], request: 'r3');
      // Idempotent replay of an existing request is still answered.
      expect(
        (await offer([
          [1],
        ], request: 'r1')).transferId,
        first.transferId,
      );
      await expectLater(
        offer([
          [1],
        ], request: 'r4'),
        throwsA(errorCode('RATE_LIMITED')),
      );
      // Another peer has its own allowance.
      await offer(
        [
          [1],
        ],
        request: 'r4',
        peer: 'peer-b',
      );
      clock.advance(const Duration(minutes: 10));
      await offer([
        [1],
      ], request: 'r4');
    });

    test('never-accepted terminal offers are capped per peer', () async {
      await openInbox(
        Directory(p.join(temp.path, 'inbox')),
        maxRetainedUnaccepted: 2,
        maxOffersPerWindow: 100,
      );
      final kept = await inbox!.accept(
        (await offer([
          [1, 2],
        ], request: 'kept')).transferId,
      );
      await write(kept, [1, 2]);
      for (var i = 0; i < 5; i++) {
        final pending = await offer([
          [1],
        ], request: 'spam-$i');
        await inbox!.reject(pending.transferId);
      }
      final spamCanceller = await offer([
        [1],
      ], request: 'cancelled');
      await inbox!.cancel(spamCanceller.transferId);
      await offer([
        [1],
      ], request: 'trigger');
      final states = inbox!.list(peerId: 'peer-a').map((t) => t.state).toList();
      expect(states.where((s) => s == TransferState.completed), hasLength(1));
      expect(
        states.where(
          (s) => s == TransferState.rejected || s == TransferState.cancelled,
        ),
        hasLength(2),
      );
      expect(states.where((s) => s == TransferState.offered), hasLength(1));
      expect(inbox!.list(peerId: 'peer-b'), isEmpty);
    });

    test('a package larger than the quota is refused at offer time', () async {
      final budget = StorageBudget(
        availableBytes: () async => 1 << 30,
        safetyReserveBytes: 0,
        temporaryQuotaBytes: 10,
      );
      await openInbox(Directory(p.join(temp.path, 'inbox')), budget: budget);
      await expectLater(
        offer([List.filled(6, 1), List.filled(6, 2)]),
        throwsA(errorCode('QUOTA_EXCEEDED')),
      );
      expect(inbox!.list(), isEmpty);
      await offer([List.filled(10, 1)], request: 'fits');
    });
  });

  group('failures, missing results and orphans', () {
    test('an oversized body fails and discards its partial payload', () async {
      final directory = Directory(p.join(temp.path, 'inbox'));
      final budget = StorageBudget(
        availableBytes: () async => 1 << 30,
        safetyReserveBytes: 0,
      );
      await openInbox(directory, budget: budget);
      final transfer = await inbox!.accept(
        (await offer([
          [1, 2, 3],
        ])).transferId,
      );
      await expectLater(
        write(transfer, [1, 2, 3, 4]),
        throwsA(errorCode('LENGTH_EXCEEDED')),
      );
      final file = inbox!.status(transfer.transferId).files.single;
      expect(file.state, FileState.failed);
      expect(file.errorCode, 'LENGTH_EXCEEDED');
      expect(
        await Directory(p.join(directory.path, '.staging')).list().toList(),
        isEmpty,
      );
      final usage = await budget.inspect();
      expect(usage.temporaryBytes + usage.reservedBytes, 0);
    });

    test('a missing committed result is flagged on open, not fatal', () async {
      final directory = Directory(p.join(temp.path, 'inbox'));
      await openInbox(directory);
      final transfer = await inbox!.accept(
        (await offer([
          [1, 2, 3],
        ])).transferId,
      );
      final committed = await write(transfer, [1, 2, 3]);
      await inbox!.close();
      inbox = null;
      final saved = await File(committed.finalPath!).readAsBytes();
      await File(committed.finalPath!).delete();
      await openInbox(directory);
      final missing = inbox!.status(transfer.transferId).files.single;
      expect(missing.state, FileState.committed);
      expect(missing.errorCode, 'FILE_MISSING');
      await inbox!.close();
      inbox = null;
      await File(committed.finalPath!).writeAsBytes(saved);
      await openInbox(directory);
      expect(inbox!.status(transfer.transferId).files.single.errorCode, isNull);
    });

    test(
      'outbox removes only its own unreferenced snapshots on open',
      () async {
        final directory = Directory(p.join(temp.path, 'outbox'));
        outbox = await DurableOutbox.open(directory);
        final kept = await outbox!.stageStream(
          Stream.value([1, 2]),
          displayName: 'kept.bin',
          expectedSizeBytes: 2,
        );
        await outbox!.close();
        outbox = null;
        final orphan = File(
          p.join(
            directory.path,
            'files',
            '0b0c0d0e-1111-4222-8333-944445555666.blob',
          ),
        );
        await orphan.writeAsBytes([9, 9, 9]);
        final foreign = File(p.join(directory.path, 'files', 'notes.txt'));
        await foreign.writeAsString('not ours');
        outbox = await DurableOutbox.open(directory);
        expect(await orphan.exists(), isFalse);
        expect(await foreign.exists(), isTrue);
        expect(
          await File(outbox!.get(kept.manifest.fileId).path).exists(),
          isTrue,
        );
      },
    );
  });

  group('retention', () {
    test('deleteTransfer removes finished transfers and their files', () async {
      final directory = Directory(p.join(temp.path, 'inbox'));
      final budget = StorageBudget(
        availableBytes: () async => 1 << 30,
        safetyReserveBytes: 0,
      );
      await openInbox(directory, budget: budget);
      final done = await inbox!.accept(
        (await offer([
          [1, 2, 3],
          [4],
        ], request: 'done')).transferId,
      );
      final committed = await write(done, [1, 2, 3]);
      await write(done, [4], index: 1);
      final active = await inbox!.accept(
        (await offer([
          [5, 6],
        ], request: 'active')).transferId,
      );
      await expectLater(
        inbox!.deleteTransfer(active.transferId),
        throwsA(errorCode('TRANSFER_ACTIVE')),
      );
      expect(await inbox!.deleteTransfer(done.transferId), 4);
      expect(
        () => inbox!.status(done.transferId),
        throwsA(errorCode('NOT_FOUND')),
      );
      expect(await File(committed.finalPath!).exists(), isFalse);
      expect(
        await Directory(p.join(directory.path, 'received', done.transferId))
            .exists(),
        isFalse,
      );
      await inbox!.cancel(active.transferId);
      await inbox!.deleteTransfer(active.transferId);
      expect(inbox!.list(), isEmpty);
      final usage = await budget.inspect();
      expect(usage.temporaryBytes + usage.reservedBytes, 0);
    });

    test('pruneTerminal keeps received files unless asked', () async {
      await openInbox(Directory(p.join(temp.path, 'inbox')));
      final done = await inbox!.accept(
        (await offer([
          [1],
        ], request: 'done')).transferId,
      );
      await write(done, [1]);
      final rejected = await offer([
        [2],
      ], request: 'rejected');
      await inbox!.reject(rejected.transferId);
      clock.advance(const Duration(days: 8));
      final recent = await offer([
        [3],
      ], request: 'recent');
      await inbox!.reject(recent.transferId);
      expect(await inbox!.pruneTerminal(olderThan: const Duration(days: 7)), 1);
      expect(
        inbox!.list().map((t) => t.transferId),
        unorderedEquals([done.transferId, recent.transferId]),
      );
      expect(
        await inbox!.pruneTerminal(
          olderThan: const Duration(days: 7),
          includeReceivedFiles: true,
        ),
        1,
      );
      expect(inbox!.list().single.transferId, recent.transferId);
    });

    test('outbox prunes terminal request records only', () async {
      outbox = await DurableOutbox.open(Directory(p.join(temp.path, 'outbox')));
      final staged = await outbox!.stageStream(
        Stream.value([1]),
        displayName: 'a.bin',
        expectedSizeBytes: 1,
      );
      final finished = await outbox!.createTransfer([
        staged.manifest.fileId,
      ], peerId: 'peer-a');
      await outbox!.updateTransfer(
        finished.manifest.requestId,
        state: 'completed',
      );
      final open = await outbox!.createTransfer([
        staged.manifest.fileId,
      ], peerId: 'peer-a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await outbox!.pruneTerminalTransfers(olderThan: Duration.zero), 1);
      expect(
        outbox!.transfers().single.manifest.requestId,
        open.manifest.requestId,
      );
      expect(outbox!.list(), hasLength(1));
    });
  });

  group('names and errors', () {
    test('invisible and reserved names are made safe', () {
      expect(safeDisplayName('invoice\u202Efdp.exe'), 'invoicefdp.exe');
      expect(safeDisplayName('a\u200Bb\uFEFF.txt'), 'ab.txt');
      expect(safeDisplayName('CON .txt'), '_CON .txt');
      expect(safeDisplayName('conin\$.log'), '_conin\$.log');
      expect(safeDisplayName('CONOUT\$'), '_CONOUT\$');
      expect(safeDisplayName('COM¹.txt'), '_COM¹.txt');
      expect(safeDisplayName('\u202E'), 'file');
      final manifest = fileManifest([1], name: 'photo\u202Egpj.exe');
      expect(manifest.visibleName, 'photogpj.exe');
      expect(manifest.displayName, contains('\u202E'));
      expect(stripInvisibleNameCharacters('\u2066x\u2069'), 'x');
    });

    test('disk-full errors are recognised per platform', () {
      expect(isDiskFullErrorCode(28, operatingSystem: 'linux'), isTrue);
      expect(isDiskFullErrorCode(122, operatingSystem: 'android'), isTrue);
      expect(isDiskFullErrorCode(69, operatingSystem: 'ios'), isTrue);
      expect(isDiskFullErrorCode(39, operatingSystem: 'windows'), isTrue);
      expect(isDiskFullErrorCode(112, operatingSystem: 'windows'), isTrue);
      expect(isDiskFullErrorCode(39, operatingSystem: 'linux'), isFalse);
      expect(isDiskFullErrorCode(null), isFalse);
      expect(
        storageIoError(SqliteException(extendedResultCode: 13, message: 'full'))
            .code,
        'DISK_FULL',
      );
      expect(
        storageIoError(SqliteException(extendedResultCode: 1, message: 'other'))
            .code,
        'STORAGE_FAILURE',
      );
    });
  });

  group('identity, pairing journal and invitations', () {
    late DeviceIdentity identity;
    setUpAll(() async {
      identity = await DeviceIdentity.generate(displayName: 'Phone');
    });

    test('rename keeps keys and persists the new name', () async {
      final store = MemorySecretStore();
      final original = await DeviceIdentity.loadOrCreate(
        store,
        displayName: 'Phone',
      );
      final renamed = await original.rename(store, '  Kitchen iPad ');
      expect(renamed.displayName, 'Kitchen iPad');
      expect(renamed.serverPin, original.serverPin);
      expect(renamed.deviceId, original.deviceId);
      final reloaded = await DeviceIdentity.loadOrCreate(
        store,
        displayName: 'ignored',
      );
      expect(reloaded.displayName, 'Kitchen iPad');
      expect(reloaded.peerId, original.peerId);
      expect(() => original.rename(store, ''), throwsA(isA<FormatException>()));
    });

    test('shortFingerprint is stable and formatted', () {
      final code = shortFingerprint(identity.peerId);
      expect(code, matches(RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}$')));
      expect(shortFingerprint(identity.peerId), code);
      expect(
        code.replaceAll('-', '').toLowerCase(),
        identity.peerId.substring(0, 8),
      );
      expect(() => shortFingerprint('zz'), throwsFormatException);
    });

    test(
      'old terminal pairing requests are pruned from the secure store',
      () async {
        final secrets = MemorySecretStore();
        final peers = TrustedPeerStore(secrets);
        final old = DateTime.now().toUtc().subtract(const Duration(hours: 1));
        Map<String, dynamic> entry(String id, String state, DateTime expires) =>
            {
              'requestId': id,
              'pairingId': 'pairing-$id',
              'state': state,
              'expiresAt': expires.toIso8601String(),
              'peerId': 'x',
              'displayName': 'x',
              'serverPin': 'x',
              'inviteDigest': 'x',
              'bodyDigest': 'x',
              'issuedToken': null,
            };
        await secrets.write(
          '${peers.storageKey}.host-pairing',
          jsonEncode({
            'version': 1,
            'requests': [
              entry('old-rejected', 'rejected', old),
              entry('old-active', 'active', old),
              entry('old-waiting', 'waiting', old),
              entry(
                'fresh-rejected',
                'rejected',
                DateTime.now().toUtc().add(const Duration(minutes: 1)),
              ),
            ],
          }),
        );
        final service = PairingService(identity: identity, peers: peers);
        await service.load();
        final stored = jsonDecode(
          (await secrets.read('${peers.storageKey}.host-pairing'))!,
        ) as Map<String, dynamic>;
        final ids = (stored['requests'] as List)
            .map((request) => (request as Map)['requestId'])
            .toList();
        expect(ids, ['fresh-rejected']);
        await peers.close();
      },
    );

    test('invitations carry up to four endpoints and parse 0.3 form', () {
      final secret = base64UrlEncode(List.filled(32, 7)).replaceAll('=', '');
      final invite = PairingInvite(
        inviteId: 'invite',
        inviteSecret: secret,
        hostPin: identity.serverPin,
        displayName: 'Phone',
        endpoint: Uri.parse('https://192.168.1.5:4000'),
        endpoints: [
          Uri.parse('https://192.168.1.5:4000'),
          Uri.parse('https://10.0.0.7:4000'),
          Uri.parse('https://172.16.0.2:4000'),
        ],
      );
      expect(invite.endpoints, hasLength(3));
      final parsed = PairingInvite.parse(invite.encode());
      expect(parsed.endpoint, Uri.parse('https://192.168.1.5:4000'));
      expect(parsed.endpoints.map((e) => e.host), [
        '192.168.1.5',
        '10.0.0.7',
        '172.16.0.2',
      ]);
      final single = PairingInvite(
        inviteId: 'invite',
        inviteSecret: secret,
        hostPin: identity.serverPin,
        displayName: 'Phone',
        endpoint: Uri.parse('https://192.168.1.5:4000'),
      );
      expect(PairingInvite.parse(single.encode()).endpoints, hasLength(1));
      expect(
        () => PairingInvite(
          inviteId: 'invite',
          inviteSecret: secret,
          hostPin: identity.serverPin,
          displayName: 'Phone',
          endpoint: Uri.parse('https://10.0.0.1:1'),
          endpoints: [
            for (var i = 2; i < 7; i++) Uri.parse('https://10.0.0.$i:1'),
          ],
        ),
        throwsFormatException,
      );
    });
  });

  group('host protections', () {
    late DeviceIdentity receiver;
    late DeviceIdentity sender;
    setUpAll(() async {
      receiver = await DeviceIdentity.generate(displayName: 'Receiver');
      sender = await DeviceIdentity.generate(displayName: 'Sender');
    });

    Future<(CoreHost, CoreClient, TrustedPeerStore, TrustedPeerStore)> paired(
      DurableInbox store, {
      Duration Function()? hostClock,
    }) async {
      final receiverPeers = TrustedPeerStore(MemorySecretStore());
      final senderPeers = TrustedPeerStore(MemorySecretStore());
      final host = CoreHost(
        identity: receiver,
        peers: receiverPeers,
        inbox: store,
        uploadGracePeriod: const Duration(seconds: 30),
        uploadThroughputWindow: const Duration(seconds: 60),
        minUploadBytesPerWindow: 64 * 1024,
        clock: hostClock,
      );
      final endpoint = await host.start();
      final client = CoreClient(
        endpoint: endpoint,
        serverPin: receiver.serverPin,
      );
      final invite = host.createInvite(
        hostAddresses: ['127.0.0.1', 'localhost'],
      );
      expect(invite.endpoints, hasLength(2));
      final pending = await client.requestPairing(
        invite,
        identity: sender,
        peers: senderPeers,
      );
      await host.approvePairing(pending.requestId);
      await client.completePairing(identity: sender, peers: senderPeers);
      return (host, client, receiverPeers, senderPeers);
    }

    test('offer flooding gets HTTP 429 RATE_LIMITED', () async {
      inbox = await DurableInbox.open(
        Directory(p.join(temp.path, 'inbox')),
        maxOffersPerWindow: 2,
      );
      final (host, client, a, b) = await paired(inbox!);
      try {
        for (var i = 0; i < 2; i++) {
          await client.offer(
            TransferManifest(
              requestId: 'o$i',
              files: [
                fileManifest([1]),
              ],
            ),
          );
        }
        await expectLater(
          client.offer(
            TransferManifest(
              requestId: 'o2',
              files: [
                fileManifest([1]),
              ],
            ),
          ),
          throwsA(
            isA<NetworkException>()
                .having((e) => e.code, 'code', 'RATE_LIMITED')
                .having((e) => e.statusCode, 'status', 429),
          ),
        );
      } finally {
        client.close();
        await host.close();
        await a.close();
        await b.close();
      }
    });

    test('a trickling upload is stopped and releases the writer', () async {
      var now = Duration.zero;
      inbox = await DurableInbox.open(
        Directory(p.join(temp.path, 'inbox')),
        checkpointBytes: 65536,
      );
      final (host, client, a, b) = await paired(inbox!, hostClock: () => now);
      final data = List<int>.generate(512 * 1024, (i) => i % 251);
      try {
        final offered = await client.offer(
          TransferManifest(requestId: 'slow', files: [fileManifest(data)]),
        );
        await host.acceptTransfer(offered.id);
        final position = await client.headFile(offered.id, 'file-a');
        final raw = createPinnedHttpClient(
          Uri.parse('https://127.0.0.1:${host.port}'),
          receiver.serverPin,
        );
        final request = await raw.openUrl(
          'PATCH',
          Uri.parse(
            'https://127.0.0.1:${host.port}/v1/transfers/${offered.id}/files/file-a/data',
          ),
        );
        request.headers.set('Authorization', 'Bearer ${client.credential}');
        request.headers.set('Tus-Resumable', '1.0.0');
        request.headers.set('Upload-Offset', '0');
        request.headers.set('X-Storage-Incarnation', position.incarnation);
        request.headers.contentType = ContentType(
          'application',
          'offset+octet-stream',
        );
        request.contentLength = data.length;
        final response = request.done.then<Object?>(
          (value) => value,
          onError: (Object error) => error,
        );
        // A healthy first burst, then (two minutes later) only a trickle.
        request.add(data.sublist(0, 256 * 1024));
        await request.flush();
        await until(
          () => inbox!.status(offered.id).files.single.offset >= 256 * 1024,
        );
        now += const Duration(seconds: 120);
        // HttpClient coalesces tiny writes; 16 KiB is still below the minimum.
        request.add(data.sublist(256 * 1024, 272 * 1024));
        await request.flush();
        // The receiver stops the upload and keeps the durable prefix.
        await until(
          () =>
              inbox!.status(offered.id).files.single.errorCode ==
              'TRANSFER_TOO_SLOW',
        );
        request.abort();
        await response;
        final file = inbox!.status(offered.id).files.single;
        expect(file.state, FileState.paused);
        expect(file.offset, greaterThanOrEqualTo(256 * 1024));
        raw.close(force: true);
        // The writer is free: a normal client resumes from the durable offset.
        final source = File(p.join(temp.path, 'slow.bin'));
        await source.writeAsBytes(data, flush: true);
        await inbox!.resume(offered.id);
        final uploaded = await client.uploadFile(
          transferId: offered.id,
          fileId: 'file-a',
          source: source,
        );
        expect(uploaded.state, FileState.committed);
      } finally {
        client.close();
        await host.close();
        await a.close();
        await b.close();
      }
    });
  });
}
