import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:transfer_core/transfer_core.dart'
    show stripInvisibleNameCharacters;

/// A file offered to the browser (a prepared, immutable outbox copy).
class WebSharedFile {
  const WebSharedFile({
    required this.name,
    required this.path,
    required this.bytes,
  });
  final String name;
  final String path;
  final int bytes;
}

/// A browser asks to upload files; the app must accept it explicitly.
class WebUploadAsk {
  WebUploadAsk({
    required this.id,
    required this.client,
    required this.names,
    required this.sizes,
  });
  final String id;

  /// The browser's LAN address, shown so the user can tell who is asking.
  final String client;
  final List<String> names;
  final List<int> sizes;
  int get totalBytes => sizes.fold(0, (sum, size) => sum + size);
}

/// Localized texts of the browser page.
class WebPageTexts {
  const WebPageTexts({
    required this.title,
    required this.download,
    required this.noFiles,
    required this.upload,
    required this.chooseFiles,
    required this.waiting,
    required this.uploading,
    required this.done,
    required this.rejected,
    required this.failed,
    required this.expires,
  });
  final String title;
  final String download;
  final String noFiles;
  final String upload;
  final String chooseFiles;
  final String waiting;
  final String uploading;
  final String done;
  final String rejected;
  final String failed;
  final String expires;
}

/// Opt-in, time-limited plain-HTTP share for devices without the app.
///
/// Plain HTTP is deliberate (browsers would reject the app's self-signed
/// certificate) and therefore constrained: an explicit user action starts
/// it, it stops by itself after [ttl], the URL carries a random 128-bit token,
/// only the files chosen for sharing are served (no listing, no paths), and
/// every browser upload batch needs consent in the app, with declared sizes
/// enforced. Per-address request limits bound abuse on the local network.
class WebShareServer {
  WebShareServer({
    required this.files,
    required this.allowUpload,
    required this.uploadDirectory,
    required this.texts,
    required this.onUploadAsk,
    required this.onFileStored,
    this.onChanged,
    this.ttl = const Duration(minutes: 10),
    this.maxUploadFiles = 20,
    this.maxUploadFileBytes = 4 * 1024 * 1024 * 1024,
    this.consentTimeout = const Duration(seconds: 120),
  });

  final List<WebSharedFile> files;
  final bool allowUpload;
  final Directory uploadDirectory;
  final WebPageTexts texts;

  /// Resolves to true when the user accepts the batch in the app.
  final Future<bool> Function(WebUploadAsk ask) onUploadAsk;

  /// Called for every completely received and verified browser upload.
  final void Function(String askId, String name, File file) onFileStored;
  final void Function()? onChanged;
  final Duration ttl;
  final int maxUploadFiles;
  final int maxUploadFileBytes;
  final Duration consentTimeout;

  HttpServer? _server;
  late final String token = _randomToken();
  DateTime? _expiresAt;
  Timer? _expiry;
  final _hits = <String, List<int>>{};
  final _recentClients = <String, int>{};
  final _approved = <String, WebUploadAsk>{};
  final _clock = Stopwatch()..start();
  int downloads = 0;
  int uploads = 0;

  DateTime? get expiresAt => _expiresAt;
  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  /// Distinct browser addresses seen in the last minute.
  int get connectedClients {
    final now = _clock.elapsedMilliseconds;
    _recentClients.removeWhere((_, at) => now - at > 60000);
    return _recentClients.length;
  }

  Uri urlFor(String host) =>
      Uri(scheme: 'http', host: host, port: port, path: '/$token/');

  Future<void> start({
    InternetAddress? address,
    int preferredPort = 53320,
  }) async {
    if (_server != null) return;
    final bind = address ?? InternetAddress.anyIPv4;
    HttpServer server;
    try {
      server = await HttpServer.bind(bind, preferredPort);
    } on SocketException {
      server = await HttpServer.bind(bind, 0);
    }
    server.autoCompress = false;
    server.idleTimeout = const Duration(seconds: 20);
    _server = server;
    _expiresAt = DateTime.now().add(ttl);
    _expiry = Timer(ttl, () => unawaited(stop()));
    server.listen((request) {
      unawaited(_handle(request).catchError((Object _) {}));
    }, onError: (Object _) {});
  }

  Future<void> stop() async {
    _expiry?.cancel();
    _expiry = null;
    final server = _server;
    _server = null;
    _approved.clear();
    await server?.close(force: true);
    onChanged?.call();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Cache-Control', 'no-store')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Frame-Options', 'DENY');
    try {
      final client = request.connectionInfo?.remoteAddress.address ?? '?';
      if (!_allow(client)) {
        return await _plain(
          response,
          HttpStatus.tooManyRequests,
          'Too many requests',
        );
      }
      final parts = request.uri.pathSegments;
      if (parts.isEmpty || !_sameToken(parts.first)) {
        return await _plain(response, HttpStatus.notFound, 'Not found');
      }
      _recentClients[client] = _clock.elapsedMilliseconds;
      final rest = parts.skip(1).where((part) => part.isNotEmpty).toList();
      if (rest.isEmpty && request.method == 'GET') return await _page(response);
      if (rest.length == 2 && rest[0] == 'f' && request.method == 'GET') {
        return await _download(response, int.tryParse(rest[1]));
      }
      if (allowUpload &&
          rest.length == 1 &&
          rest[0] == 'ask' &&
          request.method == 'POST') {
        return await _ask(request, client);
      }
      if (allowUpload &&
          rest.length == 3 &&
          rest[0] == 'u' &&
          request.method == 'PUT') {
        return await _upload(request, rest[1], int.tryParse(rest[2]));
      }
      return await _plain(response, HttpStatus.notFound, 'Not found');
    } catch (_) {
      try {
        await _plain(response, HttpStatus.internalServerError, 'Error');
      } catch (_) {}
    }
  }

  /// 240 requests per address per 5 minutes (downloads count once each).
  bool _allow(String client) {
    final now = _clock.elapsedMilliseconds;
    final list = _hits.putIfAbsent(client, () => <int>[])
      ..removeWhere((at) => now - at > 300000);
    if (list.length >= 240) return false;
    list.add(now);
    return true;
  }

  bool _sameToken(String candidate) {
    if (candidate.length != token.length) return false;
    var diff = 0;
    for (var i = 0; i < token.length; i++) {
      diff |= token.codeUnitAt(i) ^ candidate.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _page(HttpResponse response) async {
    response.headers
      ..contentType = ContentType.html
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; style-src 'unsafe-inline'; "
            "script-src 'unsafe-inline'; connect-src 'self'; form-action 'none'",
      );
    response.write(_html());
    await response.close();
  }

  Future<void> _download(HttpResponse response, int? index) async {
    if (index == null || index < 0 || index >= files.length) {
      return _plain(response, HttpStatus.notFound, 'Not found');
    }
    final shared = files[index];
    final file = File(shared.path);
    if (!await file.exists()) {
      return _plain(response, HttpStatus.gone, 'Gone');
    }
    response.headers
      ..contentType = ContentType.binary
      ..contentLength = await file.length()
      ..set('Content-Disposition', contentDisposition(shared.name));
    downloads++;
    onChanged?.call();
    await response.addStream(file.openRead());
    await response.close();
  }

  Future<void> _ask(HttpRequest request, String client) async {
    if (request.contentLength > 65536) {
      return _plain(
        request.response,
        HttpStatus.requestEntityTooLarge,
        'Too large',
      );
    }
    final body = await utf8.decoder
        .bind(request)
        .timeout(const Duration(seconds: 10))
        .join();
    final json = jsonDecode(body);
    final list = json is Map ? json['files'] : null;
    if (list is! List || list.isEmpty || list.length > maxUploadFiles) {
      return _plain(request.response, HttpStatus.badRequest, 'Bad request');
    }
    final names = <String>[];
    final sizes = <int>[];
    for (final item in list) {
      final name = item is Map ? item['name'] : null;
      final size = item is Map ? item['size'] : null;
      if (name is! String ||
          size is! int ||
          size < 0 ||
          size > maxUploadFileBytes) {
        return _plain(request.response, HttpStatus.badRequest, 'Bad request');
      }
      names.add(safeUploadName(name));
      sizes.add(size);
    }
    final ask = WebUploadAsk(
      id: _randomToken(),
      client: client,
      names: names,
      sizes: sizes,
    );
    bool accepted;
    try {
      accepted = await onUploadAsk(ask).timeout(consentTimeout);
    } on TimeoutException {
      accepted = false;
    }
    if (!accepted || _server == null) {
      return _plain(request.response, HttpStatus.forbidden, 'Declined');
    }
    _approved[ask.id] = ask;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'upload': ask.id}));
    await request.response.close();
  }

  Future<void> _upload(HttpRequest request, String askId, int? index) async {
    final ask = _approved[askId];
    if (ask == null ||
        index == null ||
        index < 0 ||
        index >= ask.names.length) {
      return _plain(request.response, HttpStatus.forbidden, 'Not approved');
    }
    final declared = ask.sizes[index];
    if (request.contentLength >= 0 && request.contentLength != declared) {
      return _plain(request.response, HttpStatus.badRequest, 'Size mismatch');
    }
    final staging = Directory(p.join(uploadDirectory.path, '.staging'));
    await staging.create(recursive: true);
    final part = File(p.join(staging.path, '$askId-$index.part'));
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in request.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (received > declared) throw const FormatException('too many bytes');
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received != declared) {
      await part.delete().catchError((Object _) => part);
      return _plain(request.response, HttpStatus.badRequest, 'Incomplete');
    }
    final target = await _uniqueTarget(ask.names[index]);
    await part.rename(target.path);
    uploads++;
    onFileStored(askId, ask.names[index], target);
    onChanged?.call();
    await _plain(request.response, HttpStatus.ok, 'OK');
  }

  Future<File> _uniqueTarget(String name) async {
    await uploadDirectory.create(recursive: true);
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var candidate = File(p.join(uploadDirectory.path, name));
    var n = 2;
    while (await candidate.exists()) {
      candidate = File(p.join(uploadDirectory.path, '$base ($n)$ext'));
      n++;
    }
    return candidate;
  }

  Future<void> _plain(HttpResponse response, int status, String text) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.text;
    response.write(text);
    await response.close();
  }

  String _html() {
    final esc = const HtmlEscape();
    final rows = StringBuffer();
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      rows.write(
        '<li><a href="f/$i" download>${esc.convert(f.name)}</a>'
        '<span>${_size(f.bytes)}</span></li>',
      );
    }
    final expires = _expiresAt == null
        ? ''
        : '${_expiresAt!.hour.toString().padLeft(2, '0')}:'
              '${_expiresAt!.minute.toString().padLeft(2, '0')}';
    final js = jsonEncode({
      'waiting': texts.waiting,
      'uploading': texts.uploading,
      'done': texts.done,
      'rejected': texts.rejected,
      'failed': texts.failed,
    });
    final upload = allowUpload
        ? '''
<section><h2>${esc.convert(texts.upload)}</h2>
<input id="pick" type="file" multiple aria-label="${esc.convert(texts.chooseFiles)}">
<p id="status" role="status"></p></section>
<script>
const T=$js;const st=document.getElementById('status');
document.getElementById('pick').addEventListener('change',async e=>{
 const fs=[...e.target.files].slice(0,$maxUploadFiles);if(!fs.length)return;
 st.textContent=T.waiting;
 const r=await fetch('ask',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({files:fs.map(f=>({name:f.name,size:f.size}))})});
 if(!r.ok){st.textContent=T.rejected;return;}
 const id=(await r.json()).upload;
 for(let i=0;i<fs.length;i++){st.textContent=T.uploading+' '+(i+1)+'/'+fs.length;
  const u=await fetch('u/'+id+'/'+i,{method:'PUT',body:fs[i]});
  if(!u.ok){st.textContent=T.failed;return;}}
 st.textContent=T.done;});
</script>'''
        : '';
    return '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<base href="/$token/">
<title>${esc.convert(texts.title)}</title>
<style>body{font:16px -apple-system,system-ui,Segoe UI,Roboto,sans-serif;margin:0;padding:24px;max-width:640px;margin:auto;color:#10202c;background:#f4f7f8}
h1{font-size:24px}h2{font-size:18px;margin-top:32px}ul{list-style:none;padding:0}
li{display:flex;justify-content:space-between;gap:12px;background:#fff;border-radius:12px;padding:14px 16px;margin:8px 0}
a{color:#00796b;font-weight:600;word-break:break-all}span{color:#5b6b75;white-space:nowrap}
small{color:#5b6b75}@media(prefers-color-scheme:dark){body{background:#0f1a20;color:#e6eef2}li{background:#17252d}a{color:#5fd3c3}}</style>
</head><body><h1>Ulash · ${esc.convert(texts.title)}</h1>
<small>${esc.convert(texts.expires)} $expires</small>
<h2>${esc.convert(texts.download)}</h2>
${files.isEmpty ? '<p>${esc.convert(texts.noFiles)}</p>' : '<ul>$rows</ul>'}
$upload</body></html>''';
  }

  static String _size(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(i == 0 || value >= 100 ? 0 : 1)} ${units[i]}';
  }

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// RFC 6266 / RFC 5987 attachment header with an ASCII fallback.
  static String contentDisposition(String name) {
    final ascii = name
        .replaceAll(RegExp(r'[^\x20-\x7e]'), '_')
        .replaceAll(RegExp(r'["\\]'), '_');
    final encoded = Uri.encodeComponent(name).replaceAll("'", '%27');
    return "attachment; filename=\"$ascii\"; filename*=UTF-8''$encoded";
  }

  /// A browser-supplied name reduced to a safe single file name.
  static String safeUploadName(String raw) {
    var name = stripInvisibleNameCharacters(raw)
        .replaceAll(RegExp(r'[\x00-\x1f\x7f/\\:*?"<>|&^%!]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    name = name.replaceAll(RegExp(r'^\.+'), '');
    if (name.isEmpty) name = 'file';
    final reserved = RegExp(
      r'^(con|prn|aux|nul|com[0-9]|lpt[0-9]|conin\$|conout\$)(\..*)?$',
      caseSensitive: false,
    );
    if (reserved.hasMatch(name.split(' ').first)) name = '_$name';
    if (name.length > 120) {
      final ext = p.extension(name);
      name = name.substring(0, 120 - ext.length) + ext;
    }
    return name;
  }
}
