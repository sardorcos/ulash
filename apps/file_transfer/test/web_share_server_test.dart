import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_transfer/services/web_share_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _RealHttpOverrides extends HttpOverrides {}

Future<void> _realNetwork(Future<void> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

const _texts = WebPageTexts(
  title: 't',
  download: 'd',
  noFiles: 'n',
  upload: 'u',
  chooseFiles: 'c',
  waiting: 'w',
  uploading: 'up',
  done: 'ok',
  rejected: 'r',
  failed: 'f',
  expires: 'e',
);

class _Harness {
  _Harness(this.dir, this.server);
  final Directory dir;
  final WebShareServer server;
  final stored = <String>[];
  int asks = 0;

  static Future<_Harness> start({
    Duration approvalLifetime = const Duration(minutes: 10),
    Future<int?> Function()? availableBytes,
    Duration ttl = const Duration(minutes: 10),
    void Function()? onStopped,
    InternetAddress? address,
  }) async {
    final dir = await Directory.systemTemp.createTemp('ulash-web-');
    late _Harness harness;
    final server = WebShareServer(
      files: const [],
      allowUpload: true,
      uploadDirectory: Directory(p.join(dir.path, 'up')),
      texts: _texts,
      onUploadAsk: (_) async {
        harness.asks++;
        return true;
      },
      onFileStored: (_, name, _) => harness.stored.add(name),
      approvalLifetime: approvalLifetime,
      availableBytes: availableBytes,
      ttl: ttl,
      onStopped: onStopped,
    );
    harness = _Harness(dir, server);
    await server.start(
      address: address ?? InternetAddress.anyIPv4,
      preferredPort: 0,
    );
    return harness;
  }

  Uri get base => Uri.parse('http://127.0.0.1:${server.port}/${server.token}/');

  Directory get staging => Directory(p.join(dir.path, 'up', '.staging'));

  Future<(int, String)> ask(List<(String, int)> files) async {
    final http = HttpClient();
    try {
      final request = await http.postUrl(base.resolve('ask'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'files': [
            for (final (name, size) in files) {'name': name, 'size': size},
          ],
        }),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      final id = response.statusCode == 200
          ? (jsonDecode(body) as Map)['upload'] as String
          : '';
      return (response.statusCode, id);
    } finally {
      http.close(force: true);
    }
  }

  Future<int> put(String id, int index, List<int> bytes) async {
    final http = HttpClient();
    try {
      final request = await http.putUrl(base.resolve('u/$id/$index'));
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      http.close(force: true);
    }
  }

  /// A raw request from [source], optionally cut off after [sendBytes].
  Future<int?> raw(
    String path, {
    String method = 'PUT',
    String source = '127.0.0.1',
    int contentLength = 0,
    List<int> body = const [],
    bool abort = false,
  }) async {
    final socket = await Socket.connect(
      '127.0.0.1',
      server.port,
      sourceAddress: source,
    );
    socket.write(
      '$method ${base.resolve(path).path} HTTP/1.1\r\n'
      'Host: 127.0.0.1\r\nContent-Length: $contentLength\r\n'
      'Connection: close\r\n\r\n',
    );
    socket.add(body);
    await socket.flush();
    if (abort) {
      socket.destroy();
      return null;
    }
    final reply = await utf8.decodeStream(socket);
    socket.destroy();
    return int.tryParse(reply.split(' ').elementAtOrNull(1) ?? '');
  }

  Future<void> close() async {
    await server.stop();
    await dir.delete(recursive: true);
  }
}

Future<void> _waitUntil(bool Function() ready, String reason) async {
  final clock = Stopwatch()..start();
  while (!ready()) {
    if (clock.elapsed > const Duration(seconds: 10)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

bool _empty(Directory dir) => !dir.existsSync() || dir.listSync().isEmpty;

void main() {
  test(
    'an approval is bound to the asking browser and each file is used once',
    () => _realNetwork(() async {
      final h = await _Harness.start();
      try {
        final (status, id) = await h.ask([('a.txt', 3), ('a.txt', 2)]);
        expect(status, 200);
        // Another address on the LAN that learned the id cannot use it.
        expect(
          await h.raw(
            'u/$id/0',
            source: '127.0.0.2',
            contentLength: 3,
            body: [1, 2, 3],
          ),
          403,
        );
        expect(await h.put(id, 0, [1, 2, 3]), 200);
        expect(await h.put(id, 0, [1, 2, 3]), 403, reason: 'used once');
        expect(await h.put(id, 2, [1]), 403, reason: 'not declared');
        expect(await h.put(id, 1, [1, 2]), 200);
        expect(await h.put(id, 1, [1, 2]), 403);
        // Same name twice: the final names are reserved atomically.
        expect(h.stored, ['a.txt', 'a.txt']);
        expect(
          Directory(p.join(h.dir.path, 'up'))
              .listSync()
              .whereType<File>()
              .map((f) => p.basename(f.path))
              .toSet(),
          {'a.txt', 'a (2).txt'},
        );
        expect(_empty(h.staging), isTrue);
      } finally {
        await h.close();
      }
    }),
  );

  test(
    'expired approvals, aborted and oversized uploads leave nothing behind',
    () => _realNetwork(() async {
      final expired = await _Harness.start(approvalLifetime: Duration.zero);
      try {
        final (_, id) = await expired.ask([('x.bin', 3)]);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(await expired.put(id, 0, [1, 2, 3]), 403);
      } finally {
        await expired.close();
      }

      final h = await _Harness.start();
      try {
        final (_, id) = await h.ask([('big.bin', 100), ('small.bin', 2)]);
        // The connection drops halfway: the part file is removed.
        await h.raw(
          'u/$id/0',
          contentLength: 100,
          body: [1, 2, 3],
          abort: true,
        );
        await _waitUntil(() => _empty(h.staging), 'aborted part removed');
        expect(await h.put(id, 0, List.filled(100, 1)), 403, reason: 'used');
        // Declared 2 bytes, sent 5 without a length (chunked).
        final http = HttpClient();
        final request = await http.putUrl(h.base.resolve('u/$id/1'));
        request.add([1, 2, 3, 4, 5]);
        final response = await request.close();
        await response.drain<void>();
        http.close(force: true);
        expect(response.statusCode, 400);
        expect(_empty(h.staging), isTrue);
        expect(h.stored, isEmpty);
        final visible = Directory(p.join(h.dir.path, 'up'))
            .listSync()
            .whereType<File>();
        expect(visible, isEmpty, reason: 'no reserved placeholders remain');
      } finally {
        await h.close();
      }
    }),
  );

  test(
    'a batch that cannot fit is refused before the user is asked',
    () => _realNetwork(() async {
      var free = 1000;
      final h = await _Harness.start(availableBytes: () async => free);
      try {
        expect((await h.ask([('a', 2000)])).$1, 507);
        expect(h.asks, 0);
        final (ok, _) = await h.ask([('a', 600)]);
        expect(ok, 200);
        // 600 bytes are reserved by the approved batch.
        expect((await h.ask([('b', 600)])).$1, 507);
        free = 5000;
        expect((await h.ask([('b', 600)])).$1, 200);
      } finally {
        await h.close();
      }
    }),
  );

  test('the ask body is counted while reading and has one deadline', () async {
    final big = StreamController<List<int>>();
    final over = WebShareServer.readLimited(
      big.stream,
      10,
      const Duration(seconds: 5),
    );
    big.add(List.filled(6, 1));
    big.add(List.filled(6, 1));
    expect(await over, isNull);
    await big.close();

    final slow = StreamController<List<int>>();
    final late = WebShareServer.readLimited(
      slow.stream,
      100,
      const Duration(milliseconds: 200),
    );
    final timer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => slow.add([1]),
    );
    await expectLater(late, throwsA(isA<TimeoutException>()));
    timer.cancel();
    await slow.close();

    final fine = StreamController<List<int>>();
    final ok = WebShareServer.readLimited(
      fine.stream,
      10,
      const Duration(seconds: 1),
    );
    fine.add([1, 2]);
    await fine.close();
    expect(await ok, [1, 2]);
  });

  test(
    'oversized chunked ask is rejected; binds to the given address; '
    'reports its own expiry',
    () => _realNetwork(() async {
      var stopped = 0;
      final h = await _Harness.start(
        address: InternetAddress.loopbackIPv4,
        ttl: const Duration(milliseconds: 400),
        onStopped: () => stopped++,
      );
      try {
        expect(h.server.boundAddress, InternetAddress.loopbackIPv4);
        final http = HttpClient();
        final request = await http.postUrl(h.base.resolve('ask'));
        request.add(utf8.encode('{"files":[${'1,' * 40000}1]}'));
        final response = await request.close();
        await response.drain<void>();
        http.close(force: true);
        expect(response.statusCode, 413);
        expect(h.asks, 0);
        await _waitUntil(() => stopped == 1, 'expiry reported');
        expect(h.server.running, isFalse);
      } finally {
        await h.close();
      }
      expect(stopped, 1, reason: 'stop after expiry does not report again');
    }),
  );
}
