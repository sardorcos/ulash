import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';
import '../security/device_identity.dart';
import '../security/pairing_invite.dart';
import '../security/pairing_service.dart';
import '../security/trusted_peer_store.dart';
import '../storage/durable_inbox.dart';
import 'network_error.dart';

/// Foreground alpha host: encrypted manual pairing and consent-gated resumable
/// push. Pull/background transports are deliberately not advertised as ready.
final class CoreHost {
  CoreHost({
    required this.identity,
    required this.peers,
    required this.inbox,
    this.uploadIdleTimeout = const Duration(seconds: 30),
    this.uploadGracePeriod = const Duration(seconds: 30),
    this.uploadThroughputWindow = const Duration(seconds: 60),
    this.minUploadBytesPerWindow = 16 * 1024,
    Duration Function()? clock,
  }) : pairing = PairingService(identity: identity, peers: peers),
       _clock = clock ?? _defaultClock;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _defaultClock() => _stopwatch.elapsed;

  /// Maximum gap between two upload chunks.
  final Duration uploadIdleTimeout;

  /// No throughput requirement during the first part of an upload request.
  final Duration uploadGracePeriod;

  /// A single upload holds the receiver's only writer. A peer that keeps the
  /// connection alive with a trickle of bytes is stopped (retryably) when it
  /// delivers fewer than [minUploadBytesPerWindow] in a window.
  final Duration uploadThroughputWindow;
  final int minUploadBytesPerWindow;
  final Duration Function() _clock;

  final DeviceIdentity identity;
  final TrustedPeerStore peers;
  final DurableInbox inbox;
  final PairingService pairing;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  HttpServer? _server;
  int _activeRequests = 0;
  final Set<Future<void>> _handlers = {};
  DateTime _lastProgressEvent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _closed = false;
  StreamSubscription<TransferSnapshot>? _inboxSubscription;

  int get port => _server?.port ?? (throw StateError('Host is not started'));
  Uri get endpoint {
    final server = _server ?? (throw StateError('Host is not started'));
    final address = server.address.isLoopback
        ? server.address.address
        : (server.address.address == '0.0.0.0'
              ? '127.0.0.1'
              : server.address.address);
    return Uri(scheme: 'https', host: address, port: server.port);
  }

  Future<Uri> start({InternetAddress? address, int port = 0}) async {
    if (_server != null || _closed) {
      throw StateError('Host already started or closed');
    }
    await pairing.load();
    final server = await HttpServer.bindSecure(
      address ?? InternetAddress.loopbackIPv4,
      port,
      identity.serverContext(),
    );
    server.autoCompress = false;
    server.idleTimeout = const Duration(seconds: 30);
    _server = server;
    _inboxSubscription = inbox.changes.listen((_) => _emit());
    server.listen(
      (request) {
        final future = _handle(request);
        _handlers.add(future);
        unawaited(future.whenComplete(() => _handlers.remove(future)));
      },
      onError: (Object _) {
        _emit();
      },
    );
    return endpoint;
  }

  /// [hostAddresses] lists candidate LAN addresses, preferred first (at most
  /// [PairingInvite.maxEndpoints]); [hostAddress] is the single-address form.
  PairingInvite createInvite({
    String? hostAddress,
    List<String>? hostAddresses,
    Duration ttl = const Duration(seconds: 120),
  }) {
    final hosts = [?hostAddress, ...?hostAddresses];
    final uris = hosts.isEmpty
        ? [endpoint]
        : [
            for (final host in hosts.toSet())
              Uri(scheme: 'https', host: host, port: port),
          ];
    return pairing.createInvite(
      uris.first,
      ttl: ttl,
      additionalEndpoints: uris.skip(1).toList(),
    );
  }

  PairingInvite invite({String? hostAddress}) =>
      createInvite(hostAddress: hostAddress);
  List<PendingPairing> get pendingPairings => pairing.pending;

  Future<void> approvePairing(String requestId) async {
    await pairing.approve(requestId);
    _emit();
  }

  Future<void> rejectPairing(String requestId) async {
    await pairing.reject(requestId);
    _emit();
  }

  Future<void> revoke(String peerId) async {
    await pairing.revoke(peerId);
    for (final transfer in inbox.list(peerId: peerId)) {
      if (transfer.state != TransferState.completed &&
          transfer.state != TransferState.cancelled &&
          transfer.state != TransferState.rejected) {
        await inbox.cancel(transfer.transferId);
      }
    }
    _emit();
  }

  Future<TransferSnapshot> acceptTransfer(String transferId) async {
    final result = await inbox.accept(transferId);
    _emit();
    return result;
  }

  Future<TransferSnapshot> rejectTransfer(String transferId) async {
    final result = await inbox.reject(transferId);
    _emit();
    return result;
  }

  Map<String, dynamic> get capabilities => {
    'protocolMajor': 1,
    'protocolMinor': 0,
    // Authenticated, pinned response: lets paired peers pick up a rename.
    'displayName': identity.displayName,
    'canHostForeground': true,
    'canPushClient': true,
    'canPullClient': false,
    'supportsResume': true,
    'supportsNativeBackgroundUpload': false,
    'supportsNativeBackgroundDownload': false,
    'maxFileSizeBytes': TransferLimits.maxFileBytes.toString(),
    'maxTransferSizeBytes': TransferLimits.maxTransferBytes.toString(),
    'maxFileCount': TransferLimits.maxFiles,
    'maxConcurrentFileWriters': 1,
    'supportedChecksums': ['sha256'],
    'uploadCore': 'tus/1.0.0',
  };

  Future<void> _handle(HttpRequest request) async {
    // A local cancel/revoke can close the request stream before the route has
    // reached response.close(). Observe response.done immediately so that an
    // intentional disconnect never becomes an unhandled isolate error.
    unawaited(request.response.done.then<void>((_) {}, onError: (Object _) {}));
    _activeRequests++;
    try {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.headers.set('X-Content-Type-Options', 'nosniff');
      if (_closed || _activeRequests > 32) {
        throw const NetworkException('BUSY', 'Host is busy', statusCode: 503);
      }
      await _route(request);
    } on PairingException catch (error) {
      await _error(request, error.code, error.message);
    } on StorageException catch (error) {
      await _error(request, error.code, error.message, offset: error.offset);
    } on NetworkException catch (error) {
      await _error(
        request,
        error.code,
        error.message,
        status: error.statusCode,
        offset: error.offset,
      );
    } on FormatException {
      await _error(request, 'INVALID_REQUEST', 'Malformed request');
    } on TypeError {
      await _error(request, 'INVALID_REQUEST', 'Invalid request field types');
    } catch (_) {
      // Do not disclose local filesystem paths, credentials or exception bodies.
      await _error(
        request,
        'INTERNAL_ERROR',
        'Operation could not be completed',
      );
    } finally {
      _activeRequests--;
    }
  }

  Future<void> _route(HttpRequest request) async {
    final parts = request.uri.pathSegments;
    if (parts.isEmpty || parts.first != 'v1' || request.uri.hasFragment) {
      throw const NetworkException('NOT_FOUND', 'Unknown endpoint');
    }
    final path = request.uri.path;
    var method = request.method;
    final override = request.headers.value('X-HTTP-Method-Override');
    if (override != null) {
      if (parts.length != 6 ||
          parts[1] != 'transfers' ||
          parts[3] != 'files' ||
          parts[5] != 'data' ||
          method != 'POST' ||
          !{'HEAD', 'PATCH', 'OPTIONS'}.contains(override)) {
        throw const NetworkException(
          'METHOD_NOT_ALLOWED',
          'Method override rejected',
        );
      }
      method = override;
    }
    if (path == '/v1/hello' && method == 'GET') {
      return _json(request, {
        'protocolMajor': 1,
        'protocolMinor': 0,
        'displayName': identity.displayName,
        'peerId': identity.peerId,
      });
    }
    if (path == '/v1/pairing/requests' && method == 'POST') {
      final body = await _body(request, maxBytes: 16384);
      final result = await pairing.request(body, _auth(request, 'Invite'));
      _emit();
      return _json(request, result, status: 202);
    }
    if (parts.length == 4 &&
        parts[1] == 'pairing' &&
        parts[2] == 'requests' &&
        method == 'GET') {
      return _json(request, pairing.poll(parts[3], _auth(request, 'Invite')));
    }
    if (parts.length == 4 &&
        parts[1] == 'pairing' &&
        parts[3] == 'commit' &&
        method == 'POST') {
      await _body(request, maxBytes: 1024, allowEmpty: true);
      final result = await pairing.commit(parts[2], _auth(request, 'Bearer'));
      _emit();
      return _json(request, result);
    }
    if (parts.length == 3 && parts[1] == 'pairing' && method == 'GET') {
      return _json(request, pairing.state(parts[2], _auth(request, 'Bearer')));
    }
    final token = _auth(request, 'Bearer');
    final peer = peers.authenticate(token);
    if (peer == null) {
      throw const NetworkException('UNAUTHORIZED', 'Active pairing required');
    }
    if (path == '/v1/capabilities' && method == 'GET') {
      return _json(request, capabilities);
    }
    if (path == '/v1/transfers' && method == 'GET') {
      return _json(request, {
        'transfers': inbox
            .list(peerId: peer.peerId)
            .map((value) => value.toJson())
            .toList(),
      });
    }
    if (path == '/v1/transfers' && method == 'POST') {
      final body = await _body(
        request,
        maxBytes: TransferLimits.maxManifestBytes,
      );
      final manifest = TransferManifest.fromJson(body);
      final result = await inbox.createOffer(manifest, peerId: peer.peerId);
      _emit();
      return _json(request, result.toJson(), status: 201);
    }
    if (parts.length < 3 || parts[1] != 'transfers') {
      throw const NetworkException('NOT_FOUND', 'Unknown endpoint');
    }
    final transfer = inbox.status(parts[2]);
    if (transfer.peerId != peer.peerId) {
      throw const NetworkException('NOT_FOUND', 'Transfer not found');
    }
    if (parts.length == 3 && method == 'GET') {
      return _json(request, transfer.toJson());
    }
    if (parts.length == 4 && method == 'POST') {
      await _body(request, maxBytes: 1024, allowEmpty: true);
      if (parts[3] == 'accept' || parts[3] == 'reject') {
        throw const NetworkException(
          'FORBIDDEN',
          'Only the receiving device can decide',
        );
      }
      if (parts[3] == 'cancel') {
        final result = await inbox.cancel(transfer.transferId);
        _emit();
        return _json(request, result.toJson());
      }
      if (parts[3] == 'pause' || parts[3] == 'resume') {
        final result = parts[3] == 'pause'
            ? await inbox.pause(transfer.transferId, bySource: true)
            : await inbox.resume(transfer.transferId, bySource: true);
        _emit();
        return _json(request, result.toJson());
      }
    }
    if (parts.length != 6 || parts[3] != 'files' || parts[5] != 'data') {
      throw const NetworkException('NOT_FOUND', 'Unknown endpoint');
    }
    if (!{'HEAD', 'PATCH', 'OPTIONS'}.contains(method)) {
      throw const NetworkException(
        'METHOD_NOT_ALLOWED',
        'Use HEAD or PATCH for push',
      );
    }
    if (method == 'OPTIONS') {
      request.response.headers.set('Tus-Version', '1.0.0');
      request.response.headers.set(
        'Tus-Max-Size',
        TransferLimits.maxFileBytes.toString(),
      );
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }
    request.response.headers.set('Tus-Resumable', '1.0.0');
    if (request.headers.value('Tus-Resumable') != '1.0.0') {
      request.response.headers.set('Tus-Version', '1.0.0');
      throw const NetworkException(
        'UNSUPPORTED_PROTOCOL',
        'Tus-Resumable must be 1.0.0',
        statusCode: 412,
      );
    }
    final file = transfer.files.firstWhere(
      (f) => f.manifest.fileId == parts[4],
      orElse: () => throw const NetworkException('NOT_FOUND', 'File not found'),
    );
    if ({
      FileState.offered,
      FileState.rejected,
      FileState.cancelled,
      FileState.failed,
      FileState.expired,
    }.contains(file.state)) {
      throw const NetworkException(
        'CONSENT_REQUIRED',
        'File has not been accepted',
        statusCode: 403,
      );
    }
    request.response.headers.set(
      'Upload-Length',
      file.manifest.sizeBytes.toString(),
    );
    request.response.headers.set(
      'X-Storage-Incarnation',
      file.storageIncarnationId,
    );
    if (method == 'HEAD') {
      request.response.headers.set('Upload-Offset', file.offset.toString());
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }
    if (request.headers.contentType?.mimeType !=
            'application/offset+octet-stream' ||
        !_identityEncoding(request)) {
      throw const NetworkException(
        'UNSUPPORTED_MEDIA_TYPE',
        'Expected unencoded upload bytes',
      );
    }
    final offsetText = request.headers.value('Upload-Offset');
    if (offsetText == null ||
        !RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(offsetText)) {
      throw const NetworkException('INVALID_REQUEST', 'Invalid upload offset');
    }
    final offset = int.tryParse(offsetText);
    if (offset == null || offset != file.offset) {
      throw NetworkException(
        'OFFSET_MISMATCH',
        'Upload offset changed',
        offset: file.offset,
        statusCode: 409,
      );
    }
    final remaining = file.manifest.sizeBytes - offset;
    if (request.contentLength > remaining) {
      throw const NetworkException(
        'BODY_TOO_LARGE',
        'Upload exceeds declared file size',
      );
    }
    if (request.headers.value('X-Storage-Incarnation') !=
        file.storageIncarnationId) {
      throw const NetworkException(
        'STALE_INCARNATION',
        'Storage incarnation changed',
        statusCode: 409,
      );
    }
    final result = await inbox.writeFile(
      transfer.transferId,
      file.manifest.fileId,
      offset: offset,
      incarnation: file.storageIncarnationId,
      bytes: _uploadBytes(request, token!, peer.peerId, remaining),
    );
    _emit();
    request.response.headers.set('Upload-Offset', result.offset.toString());
    request.response.statusCode = 204;
    await request.response.close();
  }

  Stream<List<int>> _uploadBytes(
    HttpRequest request,
    String token,
    String peerId,
    int maximum,
  ) {
    var count = 0;
    final started = _clock();
    var windowStart = started + uploadGracePeriod;
    var windowBytes = 0;
    // Keep cancellation directly connected to HttpRequest. An async* wrapper
    // can strand its inner moveNext future when storage cancels a live body.
    return request.timeout(uploadIdleTimeout).map((chunk) {
      if (_closed) {
        // Host restart/shutdown: resumable from the durable offset, never a
        // destructive failure of the partial file.
        throw const StorageException(
          'TRANSFER_INTERRUPTED',
          'Receiver is restarting',
        );
      }
      if (peers.authenticate(token)?.peerId != peerId) {
        throw const StorageException('PEER_REVOKED', 'Pairing was revoked');
      }
      count += chunk.length;
      if (count > maximum) {
        throw const StorageException('BODY_TOO_LARGE', 'Too many upload bytes');
      }
      final elapsedNow = _clock();
      if (elapsedNow >= windowStart) {
        windowBytes += chunk.length;
        if (elapsedNow - windowStart >= uploadThroughputWindow) {
          if (windowBytes < minUploadBytesPerWindow) {
            // Retryable: the durable offset is kept and the writer released.
            throw const StorageException(
              'TRANSFER_TOO_SLOW',
              'Upload is too slow; reconnect and resume.',
            );
          }
          windowStart = elapsedNow;
          windowBytes = 0;
        }
      }
      final now = DateTime.now();
      if (now.difference(_lastProgressEvent) >
          const Duration(milliseconds: 500)) {
        _lastProgressEvent = now;
        _emit();
      }
      return chunk;
    });
  }

  bool _identityEncoding(HttpRequest request) {
    final encoding = request.headers.value(HttpHeaders.contentEncodingHeader);
    return encoding == null || encoding.toLowerCase() == 'identity';
  }

  Future<Map<String, dynamic>> _body(
    HttpRequest request, {
    required int maxBytes,
    bool allowEmpty = false,
  }) async {
    if (request.contentLength > maxBytes || !_identityEncoding(request)) {
      throw const NetworkException(
        'BODY_TOO_LARGE',
        'Request body is not supported',
      );
    }
    if (request.contentLength != 0 &&
        request.headers.contentType?.mimeType != 'application/json') {
      throw const NetworkException(
        'UNSUPPORTED_MEDIA_TYPE',
        'Expected JSON metadata',
      );
    }
    final bytes = <int>[];
    await for (final chunk in request.timeout(const Duration(seconds: 10))) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const NetworkException(
          'BODY_TOO_LARGE',
          'Metadata limit exceeded',
        );
      }
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty && allowEmpty) return {};
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON object expected');
    }
    return decoded;
  }

  String? _auth(HttpRequest request, String scheme) {
    final values = request.headers[HttpHeaders.authorizationHeader];
    if (values == null || values.length != 1) return null;
    final prefix = '$scheme ';
    return values.single.startsWith(prefix)
        ? values.single.substring(prefix.length)
        : null;
  }

  Future<void> _json(
    HttpRequest request,
    Map<String, dynamic> body, {
    int status = 200,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _error(
    HttpRequest request,
    String code,
    String message, {
    int? status,
    int? offset,
  }) async {
    try {
      request.response.persistentConnection = false;
      request.response.headers.set('X-Transfer-Error', code);
      if (offset != null) {
        request.response.headers.set('Upload-Offset', offset.toString());
      }
      await _json(request, {
        'error': {
          'code': code,
          'message': message,
          if (offset != null) 'durableOffset': offset.toString(),
        },
      }, status: status ?? _errorStatus(code));
    } catch (_) {
      /* Peer may have disconnected. Never log sensitive requests. */
    }
  }

  int _errorStatus(String code) => switch (code) {
    'UNAUTHORIZED' => 401,
    'FORBIDDEN' ||
    'CONSENT_REQUIRED' ||
    'PAIRING_REJECTED' ||
    'PEER_REVOKED' => 403,
    'NOT_FOUND' => 404,
    'METHOD_NOT_ALLOWED' => 405,
    'INVITE_EXPIRED' || 'EXPIRED' => 410,
    'BODY_TOO_LARGE' ||
    'FILE_TOO_LARGE' ||
    'TRANSFER_TOO_LARGE' ||
    'QUOTA_EXCEEDED' => 413,
    'RATE_LIMITED' => 429,
    'TRANSFER_TOO_SLOW' => 408,
    'UNSUPPORTED_MEDIA_TYPE' => 415,
    'CHECKSUM_MISMATCH' || 'HASH_MISMATCH' || 'INTEGRITY_MISMATCH' => 422,
    'BUSY' => 423,
    'NOT_ACCEPTED' => 403,
    'LENGTH_EXCEEDED' => 413,
    'CONFLICT' ||
    'OFFSET_MISMATCH' ||
    'INVALID_STATE' ||
    'STALE_INCARNATION' ||
    'PAUSED' ||
    'TRANSFER_PAUSED' ||
    'TRANSFER_CANCELLED' ||
    'INCARNATION_MISMATCH' ||
    'REQUEST_CONFLICT' ||
    'INCOMPLETE_FILE' => 409,
    'INTERNAL_ERROR' => 500,
    _ => 400,
  };

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> close() async {
    _closed = true;
    await _server?.close(force: true);
    await Future.wait(_handlers.toList());
    await _inboxSubscription?.cancel();
    _server = null;
    await _changes.close();
  }
}
