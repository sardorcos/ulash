import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models.dart';
import '../security/crypto.dart';
import '../security/device_identity.dart';
import '../security/pairing_invite.dart';
import '../security/trusted_peer_store.dart';
import 'network_error.dart';
import 'pinned_http_client.dart';

final class PairingProgress {
  const PairingProgress({
    required this.requestId,
    required this.pairingId,
    required this.state,
    required this.expiresAt,
  });
  final String requestId;
  final String pairingId;
  final String state;
  final DateTime expiresAt;
  factory PairingProgress.fromJson(Map<String, dynamic> json) =>
      PairingProgress(
        requestId: json['requestId'] as String,
        pairingId: json['pairingId'] as String,
        state: json['state'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
  @override
  String toString() => 'PairingProgress($state)';
}

final class UploadPosition {
  const UploadPosition({
    required this.offset,
    required this.length,
    required this.incarnation,
  });
  final int offset;
  final int length;
  final String incarnation;
}

/// Per-peer client. It never follows redirects or reuses another peer's TLS pin.
final class CoreClient {
  CoreClient({
    required Uri endpoint,
    required this.serverPin,
    String? credential,
  }) : endpoint = validateEndpoint(endpoint),
       _credential = credential,
       _http = createPinnedHttpClient(endpoint, serverPin) {
    if (credential != null && !isCanonicalToken(credential)) {
      throw const FormatException('Invalid pairing credential');
    }
  }

  factory CoreClient.forPeer(TrustedPeer peer, {Uri? endpoint}) => CoreClient(
    endpoint:
        endpoint ??
        peer.endpoint ??
        (throw StateError('Peer endpoint is unknown')),
    serverPin: peer.serverPin,
    credential: peer.outgoingToken,
  );

  final Uri endpoint;
  final String serverPin;
  final HttpClient _http;
  String? _credential;
  String? get credential => _credential;
  String get _pendingKey =>
      'transfer.pairing.client.${peerIdFromPin(serverPin)}';

  /// Persists the request ID and reverse credential BEFORE the network request.
  /// Receiving this result never means the other user has approved pairing.
  Future<PairingProgress> requestPairing(
    PairingInvite invite, {
    required DeviceIdentity identity,
    required TrustedPeerStore peers,
    Uri? localEndpoint,
  }) async {
    if (!invite.endpoints.contains(endpoint) ||
        !constantTimeEqual(invite.hostPin, serverPin)) {
      throw const NetworkException(
        'INVITATION_MISMATCH',
        'Client does not match invitation',
      );
    }
    await peers.load();
    Map<String, dynamic>? record;
    final old = await peers.secretStore.read(_pendingKey);
    if (old != null) {
      final decoded = jsonDecode(old) as Map<String, dynamic>;
      if (decoded['inviteId'] == invite.inviteId &&
          decoded['selfPin'] == identity.serverPin) {
        record = decoded;
      }
    }
    record ??= {
      'version': 1,
      'requestId': const Uuid().v4(),
      'inviteId': invite.inviteId,
      'inviteSecret': invite.inviteSecret,
      'selfPin': identity.serverPin,
      'peerId': identity.peerId,
      'displayName': identity.displayName,
      'reverseToken': randomToken(),
      'hostPin': serverPin,
      'endpoint': localEndpoint == null
          ? null
          : validateEndpoint(localEndpoint).toString(),
      'hostEndpoint': endpoint.toString(),
    };
    await peers.secretStore.write(_pendingKey, jsonEncode(record));
    final response = await _json(
      'POST',
      '/v1/pairing/requests',
      authorization: 'Invite ${record['inviteSecret']}',
      body: {
        'requestId': record['requestId'],
        'inviteId': record['inviteId'],
        'peerId': record['peerId'],
        'serverPin': record['selfPin'],
        'displayName': record['displayName'],
        'reverseToken': record['reverseToken'],
        if (record['endpoint'] != null) 'endpoint': record['endpoint'],
      },
    );
    await _rememberPairingResponse(record, response, peers);
    return PairingProgress.fromJson(response);
  }

  /// Poll once. Returns null while manual approval is pending, otherwise commits
  /// and persists both directional credentials. Safe to repeat after a restart.
  Future<TrustedPeer?> completePairing({
    required DeviceIdentity identity,
    required TrustedPeerStore peers,
  }) async {
    await peers.load();
    final raw = await peers.secretStore.read(_pendingKey);
    if (raw == null) {
      final existing = peers.byId(peerIdFromPin(serverPin));
      if (existing == null) {
        throw const NetworkException(
          'PAIRING_NOT_STARTED',
          'Scan an invitation first',
        );
      }
      _credential = existing.outgoingToken;
      return existing;
    }
    final record = jsonDecode(raw) as Map<String, dynamic>;
    if (record['selfPin'] != identity.serverPin ||
        record['hostPin'] != serverPin) {
      throw const NetworkException(
        'IDENTITY_CHANGED',
        'Pending pairing identity changed',
      );
    }
    if (record['credential'] == null) {
      final response = await _json(
        'GET',
        '/v1/pairing/requests/${record['requestId']}',
        authorization: 'Invite ${record['inviteSecret']}',
      );
      if (response['state'] == 'waiting') return null;
      if (response['state'] != 'approved') {
        throw const NetworkException(
          'PAIRING_REJECTED',
          'Pairing is no longer pending',
        );
      }
      await _rememberPairingResponse(record, response, peers);
    }
    final token = record['credential'] as String;
    final response = await _json(
      'POST',
      '/v1/pairing/${record['pairingId']}/commit',
      authorization: 'Bearer $token',
      body: {},
    );
    if (response['state'] != 'active') {
      throw const NetworkException(
        'PAIRING_INCOMPLETE',
        'Pairing commit was not acknowledged',
      );
    }
    final hostName = sanitizeDisplayText(response['displayName'] as String);
    final peer = TrustedPeer(
      peerId: peerIdFromPin(serverPin),
      displayName: hostName.isEmpty ? 'Device' : hostName,
      serverPin: serverPin,
      outgoingToken: token,
      inboundTokenDigest: tokenDigest(record['reverseToken'] as String),
      pairingId: record['pairingId'] as String,
      pairedAt: DateTime.now().toUtc(),
      endpoint: endpoint,
    );
    await peers.save(peer);
    _credential = token;
    await peers.secretStore.delete(_pendingKey);
    return peer;
  }

  Future<void> _rememberPairingResponse(
    Map<String, dynamic> record,
    Map<String, dynamic> response,
    TrustedPeerStore peers,
  ) async {
    if (response['requestId'] != record['requestId'] ||
        response['hostPin'] != serverPin ||
        response['hostPeerId'] != peerIdFromPin(serverPin)) {
      throw const NetworkException(
        'PROTOCOL_CONFLICT',
        'Pairing identity did not match',
      );
    }
    record['pairingId'] = response['pairingId'];
    if (response['credential'] != null) {
      if (!isCanonicalToken(response['credential'] as String)) {
        throw const NetworkException(
          'PROTOCOL_CONFLICT',
          'Invalid pairing credential',
        );
      }
      record['credential'] = response['credential'];
    }
    await peers.secretStore.write(_pendingKey, jsonEncode(record));
  }

  Map<String, dynamic>? _capabilities;

  Future<Map<String, dynamic>> capabilities() async =>
      _capabilities = await _json('GET', '/v1/capabilities');

  /// True when a peer's capabilities accept folder paths (protocol minor 1).
  static bool capabilitiesSupportFolders(Map<String, dynamic> capabilities) =>
      capabilities['supportsFolders'] == true &&
      (capabilities['protocolMinor'] is int) &&
      (capabilities['protocolMinor'] as int) >= 1;

  /// Offers a manifest. A manifest with folder paths is refused locally
  /// (`FOLDERS_UNSUPPORTED`) when the receiver predates folder support, so an
  /// older receiver never silently flattens the structure.
  Future<TransferSnapshot> offer(TransferManifest manifest) async {
    if (manifest.usesFolders) {
      final caps = _capabilities ?? await capabilities();
      if (!capabilitiesSupportFolders(caps)) {
        throw const NetworkException(
          'FOLDERS_UNSUPPORTED',
          'The receiving device cannot store folders; update it first.',
        );
      }
    }
    return _offer(manifest);
  }

  Future<TransferSnapshot> _offer(TransferManifest manifest) async =>
      TransferSnapshot.fromJson(
        await _json('POST', '/v1/transfers', body: manifest.toJson()),
      );

  Future<TransferSnapshot> transferStatus(String transferId) async {
    validateOpaqueId(transferId, 'transferId');
    return TransferSnapshot.fromJson(
      await _json('GET', '/v1/transfers/$transferId'),
    );
  }

  Future<TransferSnapshot> pause(String transferId) =>
      _action(transferId, 'pause');
  Future<TransferSnapshot> resume(String transferId) =>
      _action(transferId, 'resume');
  Future<TransferSnapshot> cancel(String transferId) =>
      _action(transferId, 'cancel');

  Future<TransferSnapshot> _action(String id, String action) async {
    validateOpaqueId(id, 'transferId');
    return TransferSnapshot.fromJson(
      await _json(
        'POST',
        '/v1/transfers/$id/$action',
        body: {'requestId': const Uuid().v4()},
      ),
    );
  }

  Future<UploadPosition> headFile(String transferId, String fileId) async {
    final path = _filePath(transferId, fileId);
    final request = await _open('HEAD', path);
    request.headers.set('Tus-Resumable', '1.0.0');
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 && response.statusCode != 204) {
      await _throwResponse(response);
    }
    final offset = _headerInteger(response, 'Upload-Offset');
    final length = _headerInteger(response, 'Upload-Length');
    final incarnation = response.headers.value('X-Storage-Incarnation');
    if (incarnation == null ||
        incarnation.isEmpty ||
        offset > length ||
        response.headers.value('Tus-Resumable') != '1.0.0') {
      throw const NetworkException(
        'PROTOCOL_CONFLICT',
        'Invalid upload position',
      );
    }
    await response.drain<void>();
    return UploadPosition(
      offset: offset,
      length: length,
      incarnation: incarnation,
    );
  }

  /// Streams an immutable prepared file from the receiver's durable offset.
  /// onProgress is network progress, not a final delivery acknowledgment.
  /// Calling again after interruption resumes; no destructive blind retry occurs.
  Future<FileSnapshot> uploadFile({
    required String transferId,
    required String fileId,
    required File source,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final initial = await transferStatus(transferId);
    final existing = initial.files.firstWhere(
      (f) => f.fileId == fileId,
      orElse: () => throw const NetworkException('NOT_FOUND', 'File not found'),
    );
    if (existing.state == FileState.committed) return existing;
    if (initial.pausedBySink || initial.pausedBySource) {
      throw const NetworkException(
        'TRANSFER_PAUSED',
        'A participant paused this transfer',
        statusCode: 409,
      );
    }
    if (initial.state == TransferState.paused) await resume(transferId);
    final position = await headFile(transferId, fileId);
    if (await source.length() != position.length) {
      throw const NetworkException(
        'SOURCE_CHANGED',
        'Prepared file length changed',
      );
    }
    final request = await _open('PATCH', _filePath(transferId, fileId));
    request.headers.set('Tus-Resumable', '1.0.0');
    request.headers.set('Upload-Offset', position.offset.toString());
    request.headers.set('X-Storage-Incarnation', position.incarnation);
    request.headers.contentType = ContentType(
      'application',
      'offset+octet-stream',
    );
    request.contentLength = position.length - position.offset;
    var sent = position.offset;
    onProgress?.call(sent, position.length);
    try {
      await request.addStream(
        source.openRead(position.offset).map((chunk) {
          sent += chunk.length;
          onProgress?.call(sent, position.length);
          return chunk;
        }),
      );
      final response = await request.close().timeout(
        const Duration(minutes: 5),
      );
      if (response.statusCode != 204) await _throwResponse(response);
      if (_headerInteger(response, 'Upload-Offset') != position.length) {
        throw const NetworkException(
          'INCOMPLETE_FILE',
          'Receiver acknowledged only a prefix',
        );
      }
      await response.drain<void>();
    } catch (_) {
      request.abort();
      rethrow;
    }
    final finalStatus = await transferStatus(transferId);
    final file = finalStatus.files.firstWhere((f) => f.fileId == fileId);
    if (file.state != FileState.committed) {
      throw const NetworkException(
        'AWAITING_COMMIT',
        'Waiting for verified receiver commit',
      );
    }
    return file;
  }

  String _filePath(String transferId, String fileId) {
    validateOpaqueId(transferId, 'transferId');
    validateOpaqueId(fileId, 'fileId');
    return '/v1/transfers/$transferId/files/$fileId/data';
  }

  Future<HttpClientRequest> _open(
    String method,
    String path, {
    String? authorization,
  }) async {
    if (!path.startsWith('/v1/') || path.contains('?') || path.contains('#')) {
      throw const NetworkException('INVALID_REQUEST', 'Invalid API path');
    }
    final request = await _http.openUrl(method, endpoint.replace(path: path));
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    final auth =
        authorization ?? (_credential == null ? null : 'Bearer $_credential');
    if (auth != null) {
      request.headers.set(HttpHeaders.authorizationHeader, auth);
    }
    return request;
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? authorization,
  }) async {
    final data = body == null ? null : utf8.encode(jsonEncode(body));
    if (data != null && data.length > TransferLimits.maxManifestBytes) {
      throw const NetworkException('BODY_TOO_LARGE', 'Metadata limit exceeded');
    }
    final request = await _open(method, path, authorization: authorization);
    if (data != null) {
      request.headers.contentType = ContentType.json;
      request.contentLength = data.length;
      request.add(data);
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _throwResponse(response);
    }
    final decoded = await _readJson(response);
    return decoded;
  }

  Future<Map<String, dynamic>> _readJson(HttpClientResponse response) async {
    const maxResponseBytes = 6 * 1024 * 1024;
    if (response.contentLength > maxResponseBytes) {
      throw const NetworkException(
        'RESPONSE_TOO_LARGE',
        'Response limit exceeded',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const NetworkException(
          'RESPONSE_TOO_LARGE',
          'Response limit exceeded',
        );
      }
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return {};
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const NetworkException(
        'PROTOCOL_CONFLICT',
        'Expected metadata object',
      );
    }
    return decoded;
  }

  Future<Never> _throwResponse(HttpClientResponse response) async {
    Map<String, dynamic> json = {};
    try {
      json = await _readJson(response);
    } catch (_) {
      /* Do not echo remote bodies. */
    }
    final error = json['error'];
    final code = error is Map && error['code'] is String
        ? error['code'] as String
        : response.headers.value('X-Transfer-Error') ?? 'HTTP_ERROR';
    final safeCode = RegExp(r'^[A-Z0-9_]{1,80}$').hasMatch(code)
        ? code
        : 'HTTP_ERROR';
    final offsetRaw = error is Map ? error['durableOffset'] : null;
    throw NetworkException(
      safeCode,
      'Peer rejected the operation',
      statusCode: response.statusCode,
      offset: offsetRaw is String ? int.tryParse(offsetRaw) : null,
      retryAfter: _retryAfter(response),
    );
  }

  /// `Retry-After` in delta-seconds form (HTTP-date is not used by peers).
  static Duration? _retryAfter(HttpClientResponse response) {
    final raw = response.headers.value(HttpHeaders.retryAfterHeader)?.trim();
    if (raw == null || !RegExp(r'^[0-9]{1,5}$').hasMatch(raw)) return null;
    return Duration(seconds: int.parse(raw));
  }

  int _headerInteger(HttpClientResponse response, String name) {
    final raw = response.headers.value(name);
    if (raw == null || !RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(raw)) {
      throw const NetworkException(
        'PROTOCOL_CONFLICT',
        'Invalid numeric response header',
      );
    }
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      throw const NetworkException(
        'PROTOCOL_CONFLICT',
        'Numeric response overflow',
      );
    }
    return value;
  }

  void close() => _http.close(force: true);

  /// Fetches the invitation a nearby device publishes while its pairing
  /// window is open (`GET /v1/pairing/nearby`). The discovered address is
  /// only a hint and no key is pinned yet, so the TLS certificate presented
  /// here must carry the same key as the invitation (`hostPin`). Trust still
  /// comes from the host's manual approval with matching six-digit codes on
  /// both screens ([PairingInvite.sasFor] / `PendingPairing.sas`).
  static Future<PairingInvite> fetchNearbyInvite(
    Uri endpoint, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final origin = validateEndpoint(endpoint);
    X509Certificate? presented;
    final context = SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;
    final client = HttpClient(context: context)
      ..autoUncompress = false
      ..connectionTimeout = timeout
      ..findProxy = ((_) => 'DIRECT')
      ..badCertificateCallback =
          (X509Certificate certificate, String host, int port) {
            presented = certificate;
            return host == origin.host && port == origin.port;
          };
    try {
      final request = await client
          .getUrl(origin.replace(path: '/v1/pairing/nearby'))
          .timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw NetworkException(
          response.statusCode == 429 ? 'RATE_LIMITED' : 'NEARBY_UNAVAILABLE',
          'The device is not open for pairing',
          statusCode: response.statusCode,
          retryAfter: _retryAfter(response),
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        if (bytes.length + chunk.length > 16384) {
          throw const NetworkException(
            'PROTOCOL_CONFLICT',
            'Nearby invitation is too large',
          );
        }
        bytes.addAll(chunk);
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic> || json['invite'] is! String) {
        throw const NetworkException(
          'PROTOCOL_CONFLICT',
          'Invalid nearby invitation',
        );
      }
      final invite = PairingInvite.parse(json['invite'] as String);
      final certificate = presented;
      if (certificate == null ||
          !constantTimeEqual(
            spkiPinFromCertificateDer(certificate.der),
            invite.hostPin,
          )) {
        throw const NetworkException(
          'IDENTITY_CHANGED',
          'Nearby invitation does not match the device key',
        );
      }
      // The discovered address answered with the invited key: use it first.
      return PairingInvite(
        inviteId: invite.inviteId,
        inviteSecret: invite.inviteSecret,
        hostPin: invite.hostPin,
        displayName: invite.displayName,
        endpoint: origin,
        endpoints: [
          origin,
          ...invite.endpoints.where((item) => item != origin),
        ].take(PairingInvite.maxEndpoints).toList(),
        ttlSeconds: invite.ttlSeconds,
      );
    } on FormatException {
      throw const NetworkException(
        'PROTOCOL_CONFLICT',
        'Invalid nearby invitation',
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  String toString() => 'CoreClient(credentials redacted)';
}
