import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_transfer/services/app_runtime.dart';
import 'package:file_transfer/services/network_retry_policy.dart';
import 'package:file_transfer/services/outgoing_journal.dart';
import 'package:file_transfer/services/transfer_app_controller.dart';
import 'package:file_transfer/services/web_share_server.dart';
import 'package:file_transfer/ui/app_controller.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart' show Locale, ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:transfer_core/transfer_core.dart' as core;

class _RealHttpOverrides extends HttpOverrides {}

Future<void> _realNetwork(Future<void> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

Future<void> _waitUntil(
  bool Function() ready, {
  required String reason,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > timeout) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

class _Node {
  _Node(this.root, this.secrets, this.controller, this.reviews, this.urls);
  final Directory root;
  final core.MemorySecretStore secrets;
  final TransferAppController controller;
  final List<int> reviews;
  final List<Uri> urls;
  bool closed = false;

  static Future<_Node> create(
    String name, {
    Directory? root,
    core.MemorySecretStore? secrets,
    Directory? temporary,
    bool pickerCopies = false,
  }) async {
    final dir = root ?? await Directory.systemTemp.createTemp('ulash-a-');
    final store = secrets ?? core.MemorySecretStore();
    final reviews = <int>[];
    final urls = <Uri>[];
    final controller = TransferAppController(
      runtime: AppRuntime(
        secrets: store,
        storageDirectory: () async => dir,
        ensurePermission: () async => true,
        addresses: () async => ['127.0.0.1'],
        listenAddress: InternetAddress.loopbackIPv4,
        listenPort: 0,
        initialDeviceName: name,
        mobileLifecycle: true,
        discoveryEnabled: false,
        temporaryDirectory: temporary == null ? null : () async => temporary,
        pickerCopiesToCache: pickerCopies,
        requestReview: () async => reviews.add(1),
        openUrl: (url) async {
          urls.add(url);
          return true;
        },
        webShareAddress: InternetAddress.loopbackIPv4,
        webSharePort: 0,
      ),
    );
    await controller.initialize();
    return _Node(dir, store, controller, reviews, urls);
  }

  Future<void> close({bool deleteRoot = true}) async {
    if (closed) return;
    closed = true;
    await controller.shutdown();
    controller.dispose();
    if (deleteRoot && await root.exists()) await root.delete(recursive: true);
  }
}

Future<void> _pair(TransferAppController a, TransferAppController b) async {
  await b.createInvitation();
  final pairing = a.pairFromText(b.invitation!.payload);
  await _waitUntil(() => b.pendingPairings.isNotEmpty, reason: 'pairing ask');
  await b.respondToPairing(b.pendingPairings.single.id, true);
  await pairing;
  await _waitUntil(
    () => a.peers.any((peer) => peer.isTrusted && peer.isOnline),
    reason: 'pairing completes',
  );
}

class _ImmediatePicker extends FilePickerPlatform {
  _ImmediatePicker(this.files);
  final List<PlatformFile> files;
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
  }) async => files;

  @override
  Future<void> clearTemporaryFiles() async {}
}

final class _PathFile extends PlatformFile {
  _PathFile(this.file);
  final File file;
  @override
  String get name => p.basename(file.path);
  @override
  Uri get uri => file.uri;
  @override
  Never get xFile => throw StateError('unused');
  @override
  int lengthSync() => file.lengthSync();
  @override
  Future<int> length() => file.length();
  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();
  @override
  Stream<Uint8List> readAsByteStream() =>
      file.openRead().map(Uint8List.fromList);
}

/// A picked file without a path whose bytes trickle in, so preparation can
/// be cancelled mid-file deterministically.
final class _SlowStreamFile extends PlatformFile {
  _SlowStreamFile(this.label, this.size, this.firstChunk);
  final String label;
  final int size;
  final Completer<void> firstChunk;
  @override
  String get name => label;
  @override
  Uri get uri => Uri.parse('content://test/$label');
  @override
  Never get xFile => throw StateError('unused');
  @override
  int lengthSync() => size;
  @override
  Future<int> length() async => size;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List(size);
  @override
  Stream<Uint8List> readAsByteStream() async* {
    const chunk = 64 * 1024;
    var sent = 0;
    while (sent < size) {
      final n = (size - sent) < chunk ? size - sent : chunk;
      yield Uint8List(n);
      sent += n;
      if (!firstChunk.isCompleted) firstChunk.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

core.TransferManifest _manifest(String id) => core.TransferManifest(
  requestId: id,
  files: [
    core.FileManifest(
      fileId: 'f-$id',
      displayName: 'file-$id.bin',
      sizeBytes: 3,
      sha256: List.filled(64, 'a').join(),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retry budget restarts after durable progress', () {
    final counter = StallRetryCounter(0);
    expect(counter.next(0), 1);
    expect(counter.next(0), 2);
    expect(counter.next(1024), 1, reason: 'progress since last failure');
    expect(counter.next(1024), 2);
    expect(counter.next(512), 3, reason: 'a lower offset is not progress');
  });

  test('journal keys ignore byte progress but track durable state', () {
    final job = OutgoingJob(
      id: 'a',
      peerId: 'p',
      peerName: 'Peer',
      manifest: _manifest('a'),
      createdAt: DateTime.now(),
    );
    final first = TransferAppController.persistKeyForTest(job);
    expect(TransferAppController.persistKeyForTest(job), first);
    job.localState = 'sending';
    final sending = TransferAppController.persistKeyForTest(job);
    expect(sending, isNot(first));
    job.setDetail('connectionRetrying', [1, 5, '1.0']);
    expect(TransferAppController.persistKeyForTest(job), isNot(sending));
  });

  test('job details are stored as codes and legacy text still loads', () {
    final job = OutgoingJob(
      id: 'b',
      peerId: 'p',
      peerName: 'Peer',
      manifest: _manifest('b'),
      createdAt: DateTime.now(),
    )..setDetail('partiallySaved', [1, 2]);
    final json = job.toJson();
    expect(json['detailCode'], 'partiallySaved');
    expect(json['detailArgs'], ['1', '2']);
    expect(json.containsKey('detail'), isFalse);
    final legacy = OutgoingJob.fromJson(
      {...json, 'detail': 'Старый текст'}..remove('detailCode'),
    );
    expect(legacy.detail, 'Старый текст');
    expect(legacy.detailCode, isNull);
  });

  test(
    'a journal from a newer app version is refused, not rewritten',
    () async {
      final dir = await Directory.systemTemp.createTemp('ulash-journal-new-');
      try {
        OutgoingJournal(dir).close();
        final db = sqlite3.open(p.join(dir.path, 'outgoing.sqlite3'));
        db.execute('PRAGMA user_version=99');
        db.close();
        expect(
          () => OutgoingJournal(dir),
          throwsA(
            isA<core.StorageException>().having(
              (e) => e.code,
              'code',
              'JOURNAL_TOO_NEW',
            ),
          ),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'details follow the current language; unreadable rows protect copies',
    () => _realNetwork(() async {
      final dir = await Directory.systemTemp.createTemp('ulash-detail-');
      final data = Directory(p.join(dir.path, 'file-transfer-v1'));
      final journal = OutgoingJournal(Directory(p.join(data.path, 'journal')));
      journal.save(
        OutgoingJob(
          id: 'c1',
          peerId: 'p',
          peerName: 'Peer',
          manifest: _manifest('c1'),
          createdAt: DateTime.now(),
          localState: 'sending',
        ),
      );
      // One unreadable row (e.g. written by a future/broken version).
      final db = sqlite3.open(p.join(data.path, 'journal', 'outgoing.sqlite3'));
      db.execute(
        "INSERT INTO jobs(id,payload,created) VALUES('bad','{not json',?)",
        [DateTime.now().toUtc().toIso8601String()],
      );
      db.close();
      journal.close();
      // A prepared copy that no visible job references.
      final source = File(p.join(dir.path, 'orphan.txt'))
        ..writeAsStringSync('payload');
      final outbox = await core.DurableOutbox.open(
        Directory(p.join(data.path, 'outbox')),
      );
      await outbox.stageFile(source);
      await outbox.close();

      final node = await _Node.create('Detail', root: dir);
      try {
        final item = node.controller.transfers.single;
        expect(item.detail, contains('закрытии приложения'));
        await node.controller.setLocale(const Locale('en'));
        await _waitUntil(
          () => !(node.controller.transfers.single.detail ?? '').contains(
            'закрытии',
          ),
          reason: 'detail re-translated',
        );
        expect(node.controller.journalWarning, isTrue);
        await node.controller.refreshStorage();
        expect(
          node.controller.storageOverview!.unusedFiles,
          isEmpty,
          reason: 'a hidden job may still need the copy',
        );
      } finally {
        await node.close();
      }
    }),
  );

  test(
    'finished outgoing history is capped at 500 journal records',
    () => _realNetwork(() async {
      final dir = await Directory.systemTemp.createTemp('ulash-retention-');
      final journal = OutgoingJournal(
        Directory(p.join(dir.path, 'file-transfer-v1', 'journal')),
      );
      final now = DateTime.now();
      for (var i = 0; i < 505; i++) {
        journal.save(
          OutgoingJob(
            id: 'r$i',
            peerId: 'p',
            peerName: 'Peer',
            manifest: _manifest('r$i'),
            createdAt: now.subtract(Duration(minutes: i)),
            localState: 'completed',
          ),
        );
      }
      journal.close();
      final node = await _Node.create('Retention', root: dir);
      try {
        final outgoing = node.controller.transfers
            .where((t) => t.direction == TransferDirection.outgoing)
            .toList();
        expect(outgoing, hasLength(TransferAppController.historyLimit));
        expect(outgoing.any((t) => t.id == 'out:r0'), isTrue);
        expect(outgoing.any((t) => t.id == 'out:r504'), isFalse);
      } finally {
        await node.close();
      }
    }),
  );

  test(
    'picker cache copies are deleted per file; originals elsewhere are kept',
    () => _realNetwork(() async {
      final temp = await Directory.systemTemp.createTemp('ulash-picker-tmp-');
      final elsewhere = await Directory.systemTemp.createTemp('ulash-orig-');
      final inside1 = File(p.join(temp.path, 'one.txt'))
        ..writeAsStringSync('1');
      final inside2 = File(p.join(temp.path, 'two.txt'))
        ..writeAsStringSync('2');
      final outside = File(p.join(elsewhere.path, 'three.txt'))
        ..writeAsStringSync('3');
      final previous = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _ImmediatePicker([
        _PathFile(inside1),
        _PathFile(inside2),
        _PathFile(outside),
      ]);
      final node = await _Node.create(
        'Picker',
        temporary: temp,
        pickerCopies: true,
      );
      try {
        await node.controller.chooseFiles();
        expect(node.controller.errorMessage, isNull);
        expect(node.controller.selectedSources, hasLength(3));
        expect(inside1.existsSync(), isFalse);
        expect(inside2.existsSync(), isFalse);
        expect(outside.existsSync(), isTrue, reason: 'never delete originals');
      } finally {
        FilePickerPlatform.instance = previous;
        await node.close();
        await temp.delete(recursive: true);
        await elsewhere.delete(recursive: true);
      }
    }),
  );

  test(
    'preparation can be cancelled in the middle of a file',
    () => _realNetwork(() async {
      final first = Completer<void>();
      final previous = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _ImmediatePicker([
        _SlowStreamFile('slow-1.bin', 4 * 1024 * 1024, first),
        _SlowStreamFile('slow-2.bin', 4 * 1024 * 1024, Completer<void>()),
      ]);
      final node = await _Node.create('Cancel');
      try {
        final picking = node.controller.chooseFiles();
        await first.future;
        expect(node.controller.canCancelPreparation, isTrue);
        await node.controller.cancelPreparation();
        await picking;
        expect(node.controller.selectedSources, isEmpty);
        expect(node.controller.errorMessage, isNull);
        expect(node.controller.isBusy, isFalse);
      } finally {
        FilePickerPlatform.instance = previous;
        await node.close();
      }
    }),
  );

  test(
    'change notifications are limited to about 4 per second',
    () => _realNetwork(() async {
      final node = await _Node.create('Throttle');
      try {
        var notified = 0;
        void listener() => notified++;
        node.controller.addListener(listener);
        final clock = Stopwatch()..start();
        for (var i = 0; i < 30; i++) {
          await node.controller.setThemeMode(
            i.isEven ? ThemeMode.dark : ThemeMode.light,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        node.controller.removeListener(listener);
        final seconds = clock.elapsedMilliseconds / 1000;
        expect(notified, lessThanOrEqualTo((seconds * 4).ceil() + 2));
      } finally {
        await node.close();
      }
    }),
  );

  test(
    'text messages travel as messages; ratings asked once after 3 successes',
    () => _realNetwork(() async {
      final a = await _Node.create('Sender');
      final b = await _Node.create('Receiver');
      try {
        await _pair(a.controller, b.controller);
        final peer = a.controller.peers.singleWhere((x) => x.isTrusted);
        expect(a.controller.capabilities.textMessages, isTrue);
        for (var i = 1; i <= 3; i++) {
          await a.controller.sendText(
            peer.id,
            'Привет №$i https://example.org',
          );
          expect(a.controller.errorMessage, isNull);
          await _waitUntil(
            () => b.controller.pendingTransfers.isNotEmpty,
            reason: 'message $i offered',
          );
          await b.controller.respondToTransfer(
            b.controller.pendingTransfers.single.id,
            true,
          );
          await _waitUntil(
            () => a.controller.transfers.every(
              (t) => t.phase == TransferPhase.completed,
            ),
            reason: 'message $i delivered',
          );
        }
        final received = b.controller.transfers
            .where((t) => t.kind == TransferKind.text)
            .toList();
        expect(received, hasLength(3));
        expect(
          received.map((t) => t.messageText),
          contains('Привет №2 https://example.org'),
        );
        expect(
          a.controller.transfers.every((t) => t.kind == TransferKind.text),
          isTrue,
        );
        expect(
          a.controller.transfers.first.messageText,
          startsWith('Привет №'),
        );
        await _waitUntil(() => a.reviews.isNotEmpty, reason: 'review ask');
        expect(a.reviews, hasLength(1), reason: 'once per version');
        await a.controller.sendText(peer.id, 'x' * (64 * 1024 + 1));
        expect(a.controller.errorMessage, isNotNull);
      } finally {
        await a.close();
        await b.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'external links use the runtime opener',
    () => _realNetwork(() async {
      final node = await _Node.create('Links');
      try {
        await node.controller.openExternalUrl(node.controller.privacyPolicyUrl);
        expect(node.urls.single.path, endsWith('privacy.html'));
      } finally {
        await node.close();
      }
    }),
  );

  test(
    'web share serves only shared files and uploads need consent',
    () => _realNetwork(() async {
      final node = await _Node.create('Web');
      final http = HttpClient();
      try {
        final source = File(p.join(node.root.path, 'Отчёт 1.txt'))
          ..writeAsStringSync('web share bytes');
        await node.controller.addSourcePaths([source.path]);
        await node.controller.startWebShare(allowUpload: true);
        final share = node.controller.webShare!;
        expect(share.sharedFileCount, 1);
        final base = share.url;

        Future<(int, String)> get(Uri uri) async {
          final request = await http.getUrl(uri);
          final response = await request.close();
          return (response.statusCode, await utf8.decodeStream(response));
        }

        final page = await get(base);
        expect(page.$1, 200);
        expect(page.$2, contains('Отчёт 1.txt'));
        final file = await get(base.resolve('f/0'));
        expect(file.$2, 'web share bytes');
        final wrong = await get(base.replace(path: '/wrongtoken/'));
        expect(wrong.$1, 404);
        expect((await get(base.resolve('f/1'))).$1, 404);

        Future<int> ask(List<Map<String, Object>> files) async {
          final request = await http.postUrl(base.resolve('ask'));
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode({'files': files}));
          final response = await request.close();
          final body = await utf8.decodeStream(response);
          if (response.statusCode == 200) {
            final id = (jsonDecode(body) as Map)['upload'] as String;
            final put = await http.putUrl(base.resolve('u/$id/0'));
            put.add(utf8.encode('hello'));
            return (await put.close()).statusCode;
          }
          return response.statusCode;
        }

        // Declined batch.
        final declined = ask([
          {'name': 'a.txt', 'size': 5},
        ]);
        await _waitUntil(
          () => node.controller.pendingWebUploads.isNotEmpty,
          reason: 'upload consent asked',
        );
        // A countdown for the interface: the request expires with the
        // server's consent timeout and is then declined automatically.
        final expiresAt = node.controller.pendingWebUploads.single.expiresAt!;
        final left = expiresAt.difference(DateTime.now());
        expect(left.inSeconds, inInclusiveRange(100, 120));
        await node.controller.respondToWebUpload(
          node.controller.pendingWebUploads.single.id,
          false,
        );
        expect(await declined, 403);

        // Accepted batch lands in history as a browser item.
        final accepted = ask([
          {'name': '../evil<name>.txt', 'size': 5},
        ]);
        await _waitUntil(
          () => node.controller.pendingWebUploads.isNotEmpty,
          reason: 'second consent',
        );
        await node.controller.respondToWebUpload(
          node.controller.pendingWebUploads.single.id,
          true,
        );
        expect(await accepted, 200);
        final item = node.controller.transfers.firstWhere(
          (t) => t.id.startsWith('web:'),
        );
        expect(item.receivedFiles.single.name, isNot(contains('/')));
        expect(item.receivedFiles.single.name, isNot(contains('<')));
        await node.controller.deleteTransfer(item.id);
        expect(
          node.controller.transfers.where((t) => t.id.startsWith('web:')),
          isEmpty,
        );
        await node.controller.stopWebShare();
        expect(node.controller.webShare, isNull);
      } finally {
        http.close(force: true);
        await node.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('upload names are made safe', () {
    expect(
      WebShareServer.safeUploadName('../../etc/passwd'),
      isNot(contains('/')),
    );
    expect(WebShareServer.safeUploadName('CON.txt'), '_CON.txt');
    expect(WebShareServer.safeUploadName('a&calc.jpg'), 'a_calc.jpg');
    expect(
      WebShareServer.contentDisposition('Отчёт "1".pdf'),
      contains("filename*=UTF-8''"),
    );
  });
}
