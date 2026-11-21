import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:transfer_core/src/models.dart';
import 'package:transfer_core/src/storage/durable_inbox.dart';
import 'package:transfer_core/src/storage/durable_outbox.dart';

Matcher code(String code) =>
    isA<StorageException>().having((error) => error.code, 'code', code);

FileManifest manifestFor(
  List<int> bytes, {
  String id = 'file-1',
  String name = 'example.bin',
}) => FileManifest(
  fileId: id,
  displayName: name,
  sizeBytes: bytes.length,
  sha256: sha256.convert(bytes).toString(),
);

void main() {
  late Directory temporary;
  late Directory inboxDirectory;
  late DurableInbox inbox;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('transfer-storage-test-');
    inboxDirectory = Directory(p.join(temporary.path, 'inbox'));
    inbox = await DurableInbox.open(inboxDirectory, checkpointBytes: 4);
  });

  tearDown(() async {
    await inbox.close();
    await temporary.delete(recursive: true);
  });

  Future<TransferSnapshot> accepted(
    List<FileManifest> files, {
    String request = 'request-1',
  }) async {
    final offer = await inbox.createOffer(
      TransferManifest(requestId: request, files: files),
      peerId: 'verified-peer',
    );
    return inbox.accept(offer.transferId);
  }

  Future<FileSnapshot> write(
    TransferSnapshot transfer,
    List<int> bytes, {
    int index = 0,
    int? offset,
  }) {
    final file = inbox.status(transfer.transferId).files[index];
    return inbox.writeFile(
      transfer.transferId,
      file.fileId,
      offset: offset ?? file.offset,
      incarnation: file.storageIncarnationId,
      bytes: Stream.value(bytes),
    );
  }

  test('only one store instance may own an inbox directory', () async {
    await expectLater(
      DurableInbox.open(inboxDirectory),
      throwsA(code('STORE_IN_USE')),
    );
    await inbox.close();
    inbox = await DurableInbox.open(inboxDirectory);
    expect(inbox.list(), isEmpty);
  });

  test('wire uint64 parser preserves >4GiB and rejects numeric/coerced/overflow values', () {
    expect(parseWireUint64('5368709120', 'size'), 5 * 1024 * 1024 * 1024);
    expect(
      parseWireUint64('9223372036854775807', 'size'),
      TransferLimits.maxSignedInt64,
    );
    for (final invalid in <Object?>[
      1,
      -1,
      '-1',
      '01',
      ' 1',
      '1.0',
      '9223372036854775808',
      null,
    ]) {
      expect(
        () => parseWireUint64(invalid, 'size'),
        throwsA(code('INVALID_MANIFEST')),
      );
    }
    final input = manifestFor([1, 2]).toJson();
    expect(input['sizeBytes'], '2');
    expect(
      () => FileManifest.fromJson({...input, 'sizeBytes': 2}),
      throwsA(code('INVALID_MANIFEST')),
    );
    expect(
      () => FileManifest.fromJson({...input, 'displayName': '../file'}),
      throwsA(code('INVALID_MANIFEST')),
    );
  });

  test(
    'offers are durable and idempotent only for same peer/request/content',
    () async {
      final manifest = TransferManifest(
        requestId: 'same-request',
        files: [
          manifestFor([1, 2, 3]),
        ],
      );
      final first = await inbox.createOffer(manifest, peerId: 'peer-a');
      expect(
        (await inbox.createOffer(manifest, peerId: 'peer-a')).transferId,
        first.transferId,
      );
      final otherPeer = await inbox.createOffer(manifest, peerId: 'peer-b');
      expect(otherPeer.transferId, isNot(first.transferId));
      await expectLater(
        inbox.createOffer(
          TransferManifest(
            requestId: 'same-request',
            files: [
              manifestFor([9, 9, 9]),
            ],
          ),
          peerId: 'peer-a',
        ),
        throwsA(code('REQUEST_CONFLICT')),
      );
      await inbox.close();
      inbox = await DurableInbox.open(inboxDirectory);
      expect(inbox.list(), hasLength(2));
      expect(
        (await inbox.createOffer(manifest, peerId: 'peer-a')).transferId,
        first.transferId,
      );
    },
  );

  test(
    'data before consent is rejected and creates no received file',
    () async {
      final manifest = TransferManifest(
        requestId: 'request-1',
        files: [
          manifestFor([1]),
        ],
      );
      final offer = await inbox.createOffer(manifest, peerId: 'verified-peer');
      await expectLater(write(offer, [1]), throwsA(code('NOT_ACCEPTED')));
      expect(
        await Directory(p.join(inboxDirectory.path, 'received'))
            .list()
            .toList(),
        isEmpty,
      );
      await inbox.reject(offer.transferId);
      expect(inbox.status(offer.transferId).state, TransferState.rejected);
    },
  );

  test(
    'partial upload, restart and resume produce exactly one verified original',
    () async {
      final data = utf8.encode('A real transfer survives reconnection.');
      final transfer = await accepted([manifestFor(data)]);
      final partial = await write(transfer, data.sublist(0, 9));
      expect(partial.offset, 9);
      expect(partial.state, FileState.paused);
      await inbox.close();
      inbox = await DurableInbox.open(inboxDirectory, checkpointBytes: 4);
      final before = inbox.status(transfer.transferId);
      expect(before.files.single.offset, 9);
      final finalFile = await write(before, data.sublist(9));
      expect(finalFile.state, FileState.committed);
      expect(await File(finalFile.finalPath!).readAsBytes(), data);
      expect(inbox.status(transfer.transferId).state, TransferState.completed);
      final repeated = await inbox.finishFile(
        transfer.transferId,
        finalFile.fileId,
        incarnation: finalFile.storageIncarnationId,
      );
      expect(repeated.finalPath, finalFile.finalPath);
      expect(
        inbox.status(transfer.transferId).toJson().toString(),
        isNot(contains(inboxDirectory.path)),
      );
    },
  );

  test(
    'wrong offset and stale incarnation do not mutate durable data',
    () async {
      final transfer = await accepted([
        manifestFor([1, 2, 3, 4, 5, 6]),
      ]);
      await write(transfer, [1, 2]);
      final snapshot = inbox.status(transfer.transferId).files.single;
      await expectLater(
        write(transfer, [9], offset: 0),
        throwsA(code('OFFSET_MISMATCH')),
      );
      await expectLater(
        inbox.writeFile(
          transfer.transferId,
          snapshot.fileId,
          offset: 2,
          incarnation: 'old-incarnation',
          bytes: Stream.value([3]),
        ),
        throwsA(code('INCARNATION_MISMATCH')),
      );
      expect(inbox.status(transfer.transferId).files.single.offset, 2);
      final result = await write(transfer, [3, 4, 5, 6]);
      expect(await File(result.finalPath!).readAsBytes(), [1, 2, 3, 4, 5, 6]);
    },
  );

  test(
    'stream failure checkpoints valid prefix and allows continuation',
    () async {
      final transfer = await accepted([
        manifestFor([1, 2, 3, 4, 5, 6, 7, 8]),
      ]);
      final initial = transfer.files.single;
      Stream<List<int>> broken() async* {
        yield [1, 2, 3, 4, 5];
        throw const SocketException('simulated disconnect');
      }

      await expectLater(
        inbox.writeFile(
          transfer.transferId,
          initial.fileId,
          offset: 0,
          incarnation: initial.storageIncarnationId,
          bytes: broken(),
        ),
        throwsA(code('TRANSFER_INTERRUPTED')),
      );
      expect(inbox.status(transfer.transferId).files.single.offset, 5);
      final result = await write(transfer, [6, 7, 8]);
      expect(await File(result.finalPath!).readAsBytes(), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]);
    },
  );

  test('hash mismatch never produces a committed or exported file', () async {
    final transfer = await accepted([
      manifestFor([1, 2, 3, 4]),
    ]);
    await expectLater(
      write(transfer, [4, 3, 2, 1]),
      throwsA(code('INTEGRITY_MISMATCH')),
    );
    final result = inbox.status(transfer.transferId);
    expect(result.state, TransferState.failed);
    expect(result.files.single.finalPath, isNull);
    expect(
      await Directory(p.join(inboxDirectory.path, 'received'))
          .list(recursive: true)
          .toList(),
      isEmpty,
    );
  });

  test(
    'empty file still requires consent and receives verified commit',
    () async {
      final transfer = await accepted([manifestFor([])]);
      final file = transfer.files.single;
      expect(file.state, FileState.accepted);
      final result = await inbox.finishFile(
        transfer.transferId,
        file.fileId,
        incarnation: file.storageIncarnationId,
      );
      expect(await File(result.finalPath!).length(), 0);
      expect(result.state, FileState.committed);
    },
  );

  test('body longer than manifest is rejected without committing', () async {
    final transfer = await accepted([
      manifestFor([1, 2]),
    ]);
    await expectLater(
      write(transfer, [1, 2, 3]),
      throwsA(code('LENGTH_EXCEEDED')),
    );
    expect(inbox.status(transfer.transferId).files.single.offset, 0);
    expect(
      inbox.status(transfer.transferId).files.single.state,
      FileState.failed,
    );
  });

  test('recovery truncates unacknowledged tail but rejects a missing durable prefix', () async {
    final data = List<int>.generate(20, (i) => i);
    final transfer = await accepted([manifestFor(data)]);
    await write(transfer, data.sublist(0, 8));
    await inbox.close();
    var db = sqlite3.open(p.join(inboxDirectory.path, 'inbox.sqlite'));
    final path =
        db
                .select('SELECT temporary_path FROM inbox_files')
                .single['temporary_path']
            as String;
    db.execute("UPDATE inbox_files SET state='transferring'");
    db.close();
    await File(path).writeAsBytes([90, 91, 92], mode: FileMode.append);
    inbox = await DurableInbox.open(inboxDirectory);
    expect(await File(path).length(), 8);
    expect(inbox.status(transfer.transferId).files.single.offset, 8);
    await inbox.close();
    final handle = await File(path).open(mode: FileMode.append);
    await handle.truncate(3);
    await handle.close();
    inbox = await DurableInbox.open(inboxDirectory);
    final recovered = inbox.status(transfer.transferId).files.single;
    expect(recovered.state, FileState.failed);
    expect(recovered.errorCode, 'RECOVERY_INCONSISTENT');
    expect(
      recovered.storageIncarnationId,
      transfer.files.single.storageIncarnationId,
    );
  });

  test('commit intent after rename recovers idempotently', () async {
    final data = utf8.encode('committed once');
    final transfer = await accepted([manifestFor(data)]);
    final committed = await write(transfer, data);
    await inbox.close();
    final db = sqlite3.open(p.join(inboxDirectory.path, 'inbox.sqlite'));
    db.execute("UPDATE inbox_files SET state='committing'");
    db.execute("UPDATE inbox_transfers SET state='transferring'");
    db.close();
    inbox = await DurableInbox.open(inboxDirectory);
    expect(inbox.status(transfer.transferId).state, TransferState.completed);
    expect(
      inbox.status(transfer.transferId).files.single.finalPath,
      committed.finalPath,
    );
    expect(await File(committed.finalPath!).readAsBytes(), data);
    final receivedFiles = await Directory(
      p.join(inboxDirectory.path, 'received'),
    ).list(recursive: true).where((entity) => entity is File).toList();
    expect(receivedFiles, hasLength(1));
  });

  test(
    'commit recovery never overwrites an unexpected existing result',
    () async {
      final data = utf8.encode('expected original');
      final transfer = await accepted([manifestFor(data)]);
      final committed = await write(transfer, data);
      await inbox.close();
      final db = sqlite3.open(p.join(inboxDirectory.path, 'inbox.sqlite'));
      final temporaryPath =
          db
                  .select('SELECT temporary_path FROM inbox_files')
                  .single['temporary_path']
              as String;
      db.execute("UPDATE inbox_files SET state='committing'");
      db.close();
      await File(committed.finalPath!).rename(temporaryPath);
      await File(committed.finalPath!).writeAsString('existing user data');
      inbox = await DurableInbox.open(inboxDirectory);
      expect(
        inbox.status(transfer.transferId).files.single.state,
        FileState.failed,
      );
      expect(
        await File(committed.finalPath!).readAsString(),
        'existing user data',
      );
      expect(await File(temporaryPath).readAsBytes(), data);
    },
  );

  test('pause interrupts a stalled writer and source resume cannot clear sink pause', () async {
    final transfer = await accepted([
      manifestFor([1, 2, 3, 4, 5, 6]),
    ]);
    final controller = StreamController<List<int>>();
    final ready = inbox.changes.firstWhere(
      (event) =>
          event.transferId == transfer.transferId &&
          event.files.single.offset >= 4,
    );
    final writing = inbox.writeFile(
      transfer.transferId,
      transfer.files.single.fileId,
      offset: 0,
      incarnation: transfer.files.single.storageIncarnationId,
      bytes: controller.stream,
    );
    final failure = expectLater(writing, throwsA(code('TRANSFER_PAUSED')));
    controller.add([1, 2, 3, 4]);
    await ready.timeout(const Duration(seconds: 5));
    await inbox.pause(transfer.transferId).timeout(const Duration(seconds: 5));
    await failure;
    await controller.close();
    await inbox.resume(transfer.transferId, bySource: true);
    expect(inbox.status(transfer.transferId).pausedBySink, isTrue);
    await expectLater(
      write(transfer, [5, 6]),
      throwsA(code('TRANSFER_PAUSED')),
    );
    await inbox.resume(transfer.transferId);
    expect((await write(transfer, [5, 6])).state, FileState.committed);
  });

  test(
    'cancel keeps already committed files in a partially completed package',
    () async {
      final transfer = await accepted([
        manifestFor([1, 2], id: 'one', name: 'same.txt'),
        manifestFor([3, 4], id: 'two', name: 'same.txt'),
      ]);
      final first = await write(transfer, [1, 2]);
      await write(transfer, [3], index: 1);
      final result = await inbox.cancel(transfer.transferId);
      expect(result.state, TransferState.partiallyCompleted);
      expect(result.files[0].state, FileState.committed);
      expect(result.files[1].state, FileState.cancelled);
      expect(await File(first.finalPath!).readAsBytes(), [1, 2]);
    },
  );

  test(
    'safe names preserve display metadata and never use sender paths',
    () async {
      final transfer = await accepted([
        manifestFor([1], id: 'one', name: 'CON.txt'),
        manifestFor([2], id: 'two', name: 'report:photo?.txt'),
      ]);
      final first = await write(transfer, [1]);
      final second = await write(transfer, [2], index: 1);
      expect(p.basename(first.finalPath!), '_CON.txt');
      expect(p.basename(second.finalPath!), 'report_photo_.txt');
      expect(second.manifest.displayName, 'report:photo?.txt');
      expect(p.isWithin(inboxDirectory.path, first.finalPath!), isTrue);
    },
  );

  test('an injected staging symlink cannot redirect incoming bytes', () async {
    if (Platform.isWindows) {
      return; // Windows symlink creation needs privileges.
    }
    final outside = await Directory(p.join(temporary.path, 'outside')).create();
    final staging = Directory(p.join(inboxDirectory.path, '.staging'));
    await staging.delete();
    await Link(staging.path).create(outside.path);
    final offer = await inbox.createOffer(
      TransferManifest(
        requestId: 'link-test',
        files: [
          manifestFor([1]),
        ],
      ),
      peerId: 'peer',
    );
    await expectLater(
      inbox.accept(offer.transferId),
      throwsA(code('UNSAFE_PATH')),
    );
    expect(await outside.list().toList(), isEmpty);
  });

  test(
    'outbox copies remain stable after user source changes and survive restart',
    () async {
      final source = await File(p.join(temporary.path, 'original.txt'))
          .writeAsString('original content');
      final root = Directory(p.join(temporary.path, 'outbox'));
      var outbox = await DurableOutbox.open(root);
      final staged = await outbox.stageFile(source);
      await source.writeAsString('changed user content');
      expect(
        utf8.decode(
          await outbox
              .read(staged.manifest.fileId)
              .expand((bytes) => bytes)
              .toList(),
        ),
        'original content',
      );
      expect(
        staged.manifest.sha256,
        sha256.convert(utf8.encode('original content')).toString(),
      );
      await outbox.close();
      outbox = await DurableOutbox.open(root);
      expect(outbox.list(), hasLength(1));
      expect(outbox.get(staged.manifest.fileId).path, staged.path);
      await outbox.remove(staged.manifest.fileId);
      expect(await source.readAsString(), 'changed user content');
      await outbox.close();
    },
  );

  test('outbox rejects source edits during preparation without publishing a manifest', () async {
    final source = await File(p.join(temporary.path, 'changing.bin'))
        .writeAsBytes(List.filled(200000, 7));
    final outbox = await DurableOutbox.open(
      Directory(p.join(temporary.path, 'outbox')),
    );
    var changed = false;
    await expectLater(
      outbox.stageFile(
        source,
        onProgress: (_) {
          if (!changed) {
            changed = true;
            source.writeAsBytesSync([8], mode: FileMode.append);
          }
        },
      ),
      throwsA(code('SOURCE_CHANGED')),
    );
    expect(outbox.list(), isEmpty);
    await outbox.close();
  });

  test(
    'provider stream is staged without a path, short source is rejected',
    () async {
      final outbox = await DurableOutbox.open(
        Directory(p.join(temporary.path, 'outbox')),
      );
      final staged = await outbox.stageStream(
        Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
        displayName: 'Документ.bin',
        expectedSizeBytes: 4,
      );
      expect(await File(staged.path).readAsBytes(), [1, 2, 3, 4]);
      expect(staged.manifest.sha256, sha256.convert([1, 2, 3, 4]).toString());
      await expectLater(
        outbox.stageStream(
          Stream.value([1, 2]),
          displayName: 'incomplete.bin',
          expectedSizeBytes: 4,
        ),
        throwsA(code('SOURCE_CHANGED')),
      );
      expect(outbox.list(), hasLength(1));
      await outbox.close();
    },
  );
}
