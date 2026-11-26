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
import 'secure_socket_adapter.dart';

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
    this.handshakeTimeout = const Duration(seconds: 10),
    this.requestHeaderTimeout = const Duration(seconds: 10),
    this.bodyReadDeadline = const Duration(seconds: 5),
    this.maxConnections = 64,
    this.maxConnectionsPerAddress = 16,
    this.maxUnauthenticatedRequestsPerAddress = 4,
    this.maxUnauthenticatedRequests = 8,
    this.maxAuthenticatedRequests = 32,
    this.nearbyRequestsPerMinute = 5,
    Duration Function()? clock,
  }) : pairing = PairingService(identity: identity, peers: peers),
       _clock = clock ?? _defaultClock;

  /// A TLS handshake that does not finish in time is dropped.
  final Duration handshakeTimeout;

  /// A connection must deliver a complete request head this soon after the
  /// handshake, or it is closed (slow-header protection).
  final Duration requestHeaderTimeout;

  /// Whole-body deadline for JSON metadata requests (not just the gap
  /// between chunks), so a trickle of bytes cannot hold a request open.
  final Duration bodyReadDeadline;

  /// Connection caps. At a cap the oldest connection that has not yet made
  /// an authenticated request is evicted; established paired-peer
  /// connections are never evicted for a newcomer.
  final int maxConnections;
  final int maxConnectionsPerAddress;

  /// Concurrency pools: unauthenticated requests (hello, pairing, nearby)
  /// never compete with requests from paired peers.
  final int maxUnauthenticatedRequestsPerAddress;
  final int maxUnauthenticatedRequests;
  final int maxAuthenticatedRequests;

  /// Per-address rate limit for the unauthenticated nearby invitation.
  final int nearbyRequestsPerMinute;

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
  _ConnectionGuard? _guard;

  /// Requests whose body [_body] read completely.
  final _bodyRead = Expando<bool>();
  int _authenticatedRequests = 0;
  int _unauthenticatedRequests = 0;
  final _unauthenticatedByAddress = <String, int>{};
  final _nearbyRequests = <String, List<Duration>>{};
  PairingInvite? _nearbyInvite;
  Duration? _nearbyDeadline;
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
    final raw = await RawServerSocket.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    final guard = _ConnectionGuard(
      raw,
      identity.serverContext(),
      handshakeTimeout: handshakeTimeout,
      requestHeaderTimeout: requestHeaderTimeout,
      maxConnections: maxConnections,
      maxConnectionsPerAddress: maxConnectionsPerAddress,
    );
    _guard = guard;
    final server = HttpServer.listenOn(guard);
    server.autoCompress = false;
    server.idleTimeout = const Duration(seconds: 15);
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

  /// Opens a time-limited window in which an unpaired device on the LAN may
  /// fetch an invitation without scanning the QR code
  /// (`GET /v1/pairing/nearby`). Pairing still needs this device's approval
  /// after comparing the six-digit code ([PendingPairing.sas]) with the code
  /// on the joining device.
  PairingInvite openNearbyPairing({
    Duration ttl = const Duration(seconds: 120),
    List<String>? hostAddresses,
  }) {
    closeNearbyPairing();
    final invite = createInvite(hostAddresses: hostAddresses, ttl: ttl);
    _nearbyInvite = invite;
    _nearbyDeadline = _clock() + ttl;
    _emit();
    return invite;
  }

  /// Ends the nearby pairing window and invalidates its unused invitation.
  void closeNearbyPairing() {
    final invite = _nearbyInvite;
    _nearbyInvite = null;
    _nearbyDeadline = null;
    if (invite != null) pairing.revokeInvite(invite.inviteId);
  }

  /// True while a nearby pairing window is open (for discovery records).
  bool get nearbyPairingOpen {
    final deadline = _nearbyDeadline;
    if (deadline == null) return false;
    if (_clock() >= deadline) {
      closeNearbyPairing();
      return false;
    }
    return true;
  }

  Map<String, dynamic> get capabilities => {
    'protocolMajor': 1,
    'protocolMinor': 1,
    'supportsFolders': true,
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
    final remote = request.connectionInfo?.remoteAddress.address ?? '?';
    _guard?.requestStarted(request);
    final peer = peers.authenticate(_auth(request, 'Bearer'));
    final authenticated = peer != null;
    var counted = false;
    try {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.headers.set('X-Content-Type-Options', 'nosniff');
      if (_closed) {
        throw const NetworkException('BUSY', 'Host is busy', statusCode: 503);
      }
      if (authenticated) {
        if (_authenticatedRequests >= maxAuthenticatedRequests) {
          throw const NetworkException('BUSY', 'Host is busy', statusCode: 503);
        }
        _authenticatedRequests++;
        counted = true;
        _guard?.markAuthenticated(request);
      } else {
        final perAddress = _unauthenticatedByAddress[remote] ?? 0;
        if (perAddress >= maxUnauthenticatedRequestsPerAddress ||
            _unauthenticatedRequests >= maxUnauthenticatedRequests) {
          throw const NetworkException('BUSY', 'Host is busy', statusCode: 503);
        }
        _unauthenticatedByAddress[remote] = perAddress + 1;
        _unauthenticatedRequests++;
        counted = true;
        // Free the connection right after the answer: unauthenticated
        // callers never keep a keep-alive slot.
        request.response.persistentConnection = false;
      }
      await _route(request, peer, remote);
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
      if (counted) {
        if (authenticated) {
          _authenticatedRequests--;
        } else {
          _unauthenticatedRequests--;
          final left = (_unauthenticatedByAddress[remote] ?? 1) - 1;
          if (left <= 0) {
            _unauthenticatedByAddress.remove(remote);
          } else {
            _unauthenticatedByAddress[remote] = left;
          }
        }
      }
    }
  }

  Future<void> _route(
    HttpRequest request,
    TrustedPeer? authenticatedPeer,
    String remote,
  ) async {
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
      // Unauthenticated: protocol versions only. No name or key identifier
      // that would let anyone on a network recognise this device later.
      return _json(request, {'protocolMajor': 1, 'protocolMinor': 1});
    }
    if (path == '/v1/pairing/nearby' && method == 'GET') {
      _rateLimitNearby(remote);
      final invite = nearbyPairingOpen ? _nearbyInvite : null;
      if (invite == null) {
        throw const NetworkException('NOT_FOUND', 'Not open for pairing');
      }
      return _json(request, {'invite': invite.encode()});
    }
    if (path == '/v1/pairing/requests' && method == 'POST') {
      // Authenticate the invitation before reading any body bytes.
      final secret = _auth(request, 'Invite');
      pairing.preauthorizeInvite(secret);
      final body = await _body(request, maxBytes: 16384);
      final result = await pairing.request(body, secret);
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
      final token = _auth(request, 'Bearer');
      pairing.preauthorizeCommit(parts[2], token);
      await _body(request, maxBytes: 1024, allowEmpty: true);
      final result = await pairing.commit(parts[2], token);
      _emit();
      return _json(request, result);
    }
    if (parts.length == 3 && parts[1] == 'pairing' && method == 'GET') {
      return _json(request, pairing.state(parts[2], _auth(request, 'Bearer')));
    }
    final token = _auth(request, 'Bearer');
    final peer = authenticatedPeer;
    if (peer == null || token == null) {
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
      bytes: _uploadBytes(request, token, peer.peerId, remaining),
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
    final done = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = request.listen(
      (chunk) {
        if (bytes.length + chunk.length > maxBytes) {
          unawaited(subscription.cancel());
          if (!done.isCompleted) {
            done.completeError(
              const NetworkException(
                'BODY_TOO_LARGE',
                'Metadata limit exceeded',
              ),
            );
          }
          return;
        }
        bytes.addAll(chunk);
      },
      onError: (Object error) {
        if (!done.isCompleted) done.completeError(error);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    try {
      // One deadline for the whole body, not per chunk.
      await done.future.timeout(bodyReadDeadline);
      _bodyRead[request] = true;
    } on TimeoutException {
      unawaited(subscription.cancel());
      throw const NetworkException(
        'REQUEST_TIMEOUT',
        'Request body was not delivered in time',
        statusCode: 408,
      );
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
    if (_mayHaveUnreadBody(request)) return _answerUnread(request, body);
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  bool _mayHaveUnreadBody(HttpRequest request) =>
      _bodyRead[request] != true &&
      (request.contentLength > 0 || request.headers.chunkedTransferEncoding);

  /// Answers a request whose body was never read (refused before reading,
  /// or a body deadline). HttpServer would destroy such a connection the
  /// moment the response completes, discarding the TLS-buffered answer, so the
  /// socket is detached, the answer flushed and the connection half-closed,
  /// with a hard bound before it is destroyed.
  Future<void> _answerUnread(
    HttpRequest request,
    Map<String, dynamic> body,
  ) async {
    final bytes = utf8.encode(jsonEncode(body));
    final response = request.response
      ..persistentConnection = false
      ..contentLength = bytes.length;
    final socket = await response.detachSocket();
    unawaited(() async {
      final linger = Timer(const Duration(seconds: 5), socket.destroy);
      try {
        // Discard whatever the caller still sends; end when it hangs up.
        socket.listen(
          (_) {},
          onDone: socket.destroy,
          onError: (Object _) => socket.destroy(),
          cancelOnError: true,
        );
        socket.add(bytes);
        await socket.flush();
        await socket.close();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } catch (_) {
        /* Peer went away. */
      } finally {
        linger.cancel();
        socket.destroy();
      }
    }());
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
      final retryAfter = switch (code) {
        'BUSY' => 2,
        'RATE_LIMITED' => 60,
        _ => null,
      };
      if (retryAfter != null) {
        request.response.headers.set(
          HttpHeaders.retryAfterHeader,
          retryAfter.toString(),
        );
      }
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
    'BUSY' => 503,
    'REQUEST_TIMEOUT' => 408,
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

  void _rateLimitNearby(String remote) {
    final now = _clock();
    final history = _nearbyRequests.putIfAbsent(remote, () => [])
      ..removeWhere((time) => now - time >= const Duration(minutes: 1));
    if (history.length >= nearbyRequestsPerMinute) {
      throw const NetworkException(
        'RATE_LIMITED',
        'Too many requests',
        statusCode: 429,
      );
    }
    history.add(now);
    if (_nearbyRequests.length > 256) {
      _nearbyRequests.remove(_nearbyRequests.keys.first);
    }
  }

  Future<void> close() async {
    _closed = true;
    closeNearbyPairing();
    await _server?.close(force: true);
    await _guard?.close();
    // Connections are gone; a handler stuck on storage must not hang close.
    await Future.wait(_handlers.toList())
        .timeout(const Duration(seconds: 5), onTimeout: () => const []);
    await _inboxSubscription?.cancel();
    _server = null;
    await _changes.close();
  }
}

/// Accepts TCP connections, performs the TLS handshake with a deadline and
/// hands only completed TLS sockets to [HttpServer.listenOn]. Enforces
/// connection caps by evicting the oldest connection that has not made an
/// authenticated request, and closes connections that do not send a request
/// head in time.
final class _ConnectionGuard extends Stream<Socket> implements ServerSocket {
  _ConnectionGuard(
    this._raw,
    this._context, {
    required this.handshakeTimeout,
    required this.requestHeaderTimeout,
    required this.maxConnections,
    required this.maxConnectionsPerAddress,
  }) {
    _rawSubscription = _raw.listen(
      _accept,
      onError: (Object _) {},
      onDone: () => unawaited(_sockets.close()),
    );
  }

  final RawServerSocket _raw;
  final SecurityContext _context;
  final Duration handshakeTimeout;
  final Duration requestHeaderTimeout;
  final int maxConnections;
  final int maxConnectionsPerAddress;
  final _sockets = StreamController<Socket>();
  late final StreamSubscription<RawSocket> _rawSubscription;
  final _connections = <_GuardedConnection>[];
  final _byRemote = <String, _GuardedConnection>{};
  var _sequence = 0;

  @override
  InternetAddress get address => _raw.address;
  @override
  int get port => _raw.port;

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _sockets.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Future<ServerSocket> close() async {
    await _rawSubscription.cancel();
    await _raw.close();
    await closeAll();
    if (!_sockets.isClosed) await _sockets.close();
    return this;
  }

  Future<void> closeAll() async {
    for (final connection in _connections.toList()) {
      connection.destroy();
    }
    _connections.clear();
    _byRemote.clear();
  }

  void _accept(RawSocket socket) {
    String address;
    int remotePort;
    try {
      address = socket.remoteAddress.address;
      remotePort = socket.remotePort;
    } catch (_) {
      socket.close();
      return;
    }
    final connection = _GuardedConnection(
      address,
      remotePort,
      socket,
      _sequence++,
    );
    if (!_admit(connection)) {
      socket.close();
      return;
    }
    _connections.add(connection);
    _byRemote[connection.key] = connection;
    connection.timer = Timer(handshakeTimeout, () {
      if (connection.secure == null) _drop(connection);
    });
    // The raw socket stays closable during the handshake (deadline and
    // eviction); SecureSocket.secureServer would detach it.
    RawSecureSocket.secureServer(socket, _context).then((rawSecure) {
      connection.timer?.cancel();
      if (connection.closed) {
        rawSecure.close();
        return;
      }
      final secure = SecureSocketAdapter(rawSecure);
      connection.secure = secure;
      connection.timer = Timer(requestHeaderTimeout, () {
        if (!connection.sawRequest) _drop(connection);
      });
      unawaited(
        secure.done.then<void>(
          (_) => _forget(connection),
          onError: (Object _) => _forget(connection),
        ),
      );
      if (_sockets.isClosed) {
        secure.destroy();
      } else {
        _sockets.add(secure);
      }
    }, onError: (Object _) => _drop(connection));
  }

  /// Makes room for [incoming] under the caps by evicting the oldest
  /// connection without an authenticated request (same address first for the
  /// per-address cap). Returns false when nothing can be evicted.
  bool _admit(_GuardedConnection incoming) {
    while (_connections.where((c) => c.address == incoming.address).length >=
        maxConnectionsPerAddress) {
      final victim = _connections
          .where((c) => c.address == incoming.address && !c.authenticated)
          .firstOrNull;
      if (victim == null) return false;
      _drop(victim);
    }
    while (_connections.length >= maxConnections) {
      final victim = _connections.where((c) => !c.authenticated).firstOrNull;
      if (victim == null) return false;
      _drop(victim);
    }
    return true;
  }

  _GuardedConnection? _of(HttpRequest request) {
    final info = request.connectionInfo;
    if (info == null) return null;
    return _byRemote['${info.remoteAddress.address}:${info.remotePort}'];
  }

  void requestStarted(HttpRequest request) {
    final connection = _of(request);
    if (connection == null) return;
    connection.sawRequest = true;
    connection.timer?.cancel();
  }

  void markAuthenticated(HttpRequest request) {
    _of(request)?.authenticated = true;
  }

  void _drop(_GuardedConnection connection) {
    connection.destroy();
    _forget(connection);
  }

  void _forget(_GuardedConnection connection) {
    connection.timer?.cancel();
    _connections.remove(connection);
    if (identical(_byRemote[connection.key], connection)) {
      _byRemote.remove(connection.key);
    }
  }
}

final class _GuardedConnection {
  _GuardedConnection(this.address, this.remotePort, this.raw, this.sequence);
  final String address;
  final int remotePort;
  final RawSocket raw;
  final int sequence;
  SecureSocket? secure;
  Timer? timer;
  bool sawRequest = false;
  bool authenticated = false;
  bool closed = false;
  String get key => '$address:$remotePort';

  void destroy() {
    if (closed) return;
    closed = true;
    timer?.cancel();
    try {
      secure?.destroy();
    } catch (_) {
      /* Already closed. */
    }
    try {
      unawaited(raw.close().then<void>((_) {}, onError: (Object _) {}));
    } catch (_) {
      /* Already closed. */
    }
  }
}
