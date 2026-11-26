import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models.dart' show sanitizeDisplayText;
import 'crypto.dart';
import 'device_identity.dart';
import 'pairing_invite.dart';
import 'trusted_peer_store.dart';

final class PairingException implements Exception {
  const PairingException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'PairingException($code)';
}

final class PendingPairing {
  const PendingPairing({
    required this.requestId,
    required this.pairingId,
    required this.peerId,
    required this.displayName,
    required this.serverPin,
    required this.state,
    required this.expiresAt,
    this.sas,
    this.legacy = false,
    this.legacyCode,
  });
  final String requestId;
  final String pairingId;
  final String peerId;
  final String displayName;
  final String serverPin;
  final String state;
  final DateTime expiresAt;

  /// Six-digit commit/reveal verification code ([pairingSasV2]); the joining
  /// device shows the same value (`PairingProgress.sas`). Approve only when
  /// both codes match. Null for [legacy] requests.
  final String? sas;

  /// A 1.0/1.1 joiner without commit/reveal (accepted only for QR
  /// invitations). There is no six-digit code; compare [legacyCode] instead.
  final bool legacy;

  /// For [legacy] requests: the joiner's key code (`ABCD-1234`, see
  /// [shortFingerprint]) that older apps show.
  final String? legacyCode;
  @override
  String toString() => 'PendingPairing($requestId, $state)';
}

final class _Invitation {
  _Invitation(
    this.digest,
    this.expiresAt,
    this.monotonicDeadline, {
    this.requireCommitment = false,
  });
  final String digest;
  final DateTime expiresAt;
  final Duration monotonicDeadline;
  final bool requireCommitment;
  String? requestId;
}

/// Manual approval + durable commit. Pending credentials are protected by the
/// same OS secret store as the identity, and are never exposed by public views.
final class PairingService {
  PairingService({required this.identity, required this.peers});
  final DeviceIdentity identity;
  final TrustedPeerStore peers;
  final _clock = Stopwatch()..start();
  final Map<String, _Invitation> _invitations = {};
  final Map<String, Map<String, dynamic>> _requests = {};
  final Map<String, Duration> _deadlines = {};
  Future<void> _tail = Future.value();
  String get _storageKey => '${peers.storageKey}.host-pairing';

  Future<void> load() async {
    await peers.load();
    final raw = await peers.secretStore.read(_storageKey);
    if (raw == null) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Invalid pairing journal version');
    }
    for (final item in json['requests'] as List) {
      final data = Map<String, dynamic>.from(item as Map);
      _requests[data['requestId'] as String] = data;
      final remaining = DateTime.parse(data['expiresAt'] as String)
          .difference(DateTime.now().toUtc());
      _deadlines[data['requestId'] as String] =
          _clock.elapsed +
          Duration(milliseconds: remaining.inMilliseconds.clamp(0, 120000));
    }
    if (_prune()) await _persist();
  }

  /// Terminal requests are kept only as long as a client may still retry the
  /// final poll/commit. Older entries would otherwise grow the secure-store
  /// item without bound.
  static const terminalRetention = Duration(minutes: 10);
  static const maxJournalEntries = 64;
  static const _terminalStates = {'rejected', 'expired', 'revoked', 'active'};

  bool _prune() {
    final now = DateTime.now().toUtc();
    var changed = false;
    for (final request in _requests.values) {
      if ((request['state'] == 'waiting' || request['state'] == 'approved') &&
          _expired(request)) {
        request['state'] = 'expired';
        request['issuedToken'] = null;
        request['reverseToken'] = null;
        changed = true;
      }
    }
    final stale = _requests.values
        .where(
          (request) =>
              _terminalStates.contains(request['state']) &&
              now
                      .difference(
                        DateTime.parse(request['expiresAt'] as String),
                      )
                      .compareTo(terminalRetention) >=
                  0,
        )
        .map((request) => request['requestId'] as String)
        .toList();
    for (final id in stale) {
      _requests.remove(id);
      _deadlines.remove(id);
      changed = true;
    }
    if (_requests.length > maxJournalEntries) {
      final terminal =
          _requests.values
              .where((request) => _terminalStates.contains(request['state']))
              .toList()
            ..sort(
              (a, b) => (a['expiresAt'] as String).compareTo(
                b['expiresAt'] as String,
              ),
            );
      for (final request in terminal) {
        if (_requests.length <= maxJournalEntries) break;
        _requests.remove(request['requestId']);
        _deadlines.remove(request['requestId']);
        changed = true;
      }
    }
    return changed;
  }

  /// [requireCommitment]: refuse legacy (1.0/1.1) joiners for this
  /// invitation. Required for invitations that are published on the network
  /// (nearby pairing), where the invitation itself is not secret.
  PairingInvite createInvite(
    Uri endpoint, {
    Duration ttl = const Duration(seconds: 120),
    List<Uri>? additionalEndpoints,
    bool requireCommitment = false,
  }) {
    if (ttl.inSeconds < 1 || ttl.inSeconds > 120) {
      throw ArgumentError('Invitation lifetime must be 1–120 seconds');
    }
    _invitations.removeWhere(
      (_, invite) => _clock.elapsed >= invite.monotonicDeadline,
    );
    if (_invitations.length >= 8) {
      throw const PairingException('BUSY', 'Too many active invitations');
    }
    final secret = randomToken();
    final id = const Uuid().v4();
    _invitations[id] = _Invitation(
      tokenDigest(secret),
      DateTime.now().toUtc().add(ttl),
      _clock.elapsed + ttl,
      requireCommitment: requireCommitment,
    );
    return PairingInvite(
      inviteId: id,
      inviteSecret: secret,
      hostPin: identity.serverPin,
      displayName: identity.displayName,
      endpoint: endpoint,
      endpoints: [endpoint, ...?additionalEndpoints],
      ttlSeconds: ttl.inSeconds,
    );
  }

  /// Requests awaiting a decision. A commit/reveal request appears only once
  /// the joiner revealed its nonce (before that no code exists to compare).
  List<PendingPairing> get pending => _requests.values
      .where(
        (p) =>
            (p['state'] == 'waiting' || p['state'] == 'approved') &&
            !_expired(p) &&
            !_awaitingReveal(p),
      )
      .map(
        (p) => PendingPairing(
          requestId: p['requestId'] as String,
          pairingId: p['pairingId'] as String,
          peerId: p['peerId'] as String,
          displayName: p['displayName'] as String,
          serverPin: p['serverPin'] as String,
          state: p['state'] as String,
          expiresAt: DateTime.parse(p['expiresAt'] as String),
          sas: _sasOf(p),
          legacy: _isLegacy(p),
          legacyCode: _isLegacy(p)
              ? shortFingerprint(p['peerId'] as String)
              : null,
        ),
      )
      .toList(growable: false);

  static bool _isLegacy(Map<String, dynamic> request) =>
      request['commitment'] == null;

  static bool _awaitingReveal(Map<String, dynamic> request) =>
      !_isLegacy(request) && request['joinerNonce'] == null;

  String? _sasOf(Map<String, dynamic> request) {
    final hostNonce = request['hostNonce'];
    final joinerNonce = request['joinerNonce'];
    if (hostNonce is! String || joinerNonce is! String) return null;
    try {
      return pairingSasV2(
        hostNonce: hostNonce,
        joinerNonce: joinerNonce,
        hostPin: identity.serverPin,
        joinerPin: request['serverPin'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  /// Pre-check for the reveal endpoint before its body is read.
  void preauthorizeReveal(String requestId, String? secret) {
    final request = _requests[requestId];
    if (request == null) {
      throw const PairingException('UNAUTHORIZED', 'Invalid invitation');
    }
    _checkInviteAuth(request, secret);
  }

  /// Second step of commit/reveal: the joiner discloses the nonce it
  /// committed to, after it received the host nonce. A nonce that does not
  /// match the commitment rejects the request for good (one attempt per
  /// invitation). Idempotent for the same nonce.
  Future<Map<String, dynamic>> reveal(
    String requestId,
    Map<String, dynamic> body,
    String? secret,
  ) => _serial(() async {
    final request = _get(requestId);
    _checkInviteAuth(request, secret);
    if (body.keys.any((key) => key != 'nonce')) {
      throw const PairingException(
        'INVALID_REQUEST',
        'Unexpected pairing fields',
      );
    }
    final nonce = body['nonce'];
    final commitment = request['commitment'];
    if (commitment is! String) {
      throw const PairingException(
        'INVALID_REQUEST',
        'Request did not use commit/reveal',
      );
    }
    if (nonce is! String || !isCanonicalToken(nonce)) {
      throw const PairingException('INVALID_REQUEST', 'Invalid nonce');
    }
    final known = request['joinerNonce'];
    if (known is String) {
      if (!constantTimeEqual(known, nonce)) {
        throw const PairingException(
          'COMMITMENT_MISMATCH',
          'Nonce does not match the commitment',
        );
      }
      return _response(request);
    }
    _checkPending(request);
    if (request['state'] != 'waiting') {
      throw const PairingException('CONFLICT', 'Pairing is not pending');
    }
    if (!constantTimeEqual(pairingCommitment(nonce), commitment)) {
      request['state'] = 'rejected';
      request['issuedToken'] = null;
      request['reverseToken'] = null;
      await _persist();
      throw const PairingException(
        'COMMITMENT_MISMATCH',
        'Nonce does not match the commitment',
      );
    }
    request['joinerNonce'] = nonce;
    await _persist();
    return _response(request);
  });

  /// Cheap pre-check before any request body is read: the secret must be a
  /// canonical token whose digest belongs to a live invitation or to a known
  /// pairing request (an idempotent retry). Unknown callers are rejected
  /// without consuming their body.
  void preauthorizeInvite(String? secret) {
    if (secret == null || !isCanonicalToken(secret)) {
      throw const PairingException('UNAUTHORIZED', 'Invalid invitation');
    }
    final digest = tokenDigest(secret);
    final live = _invitations.values.any(
      (invite) =>
          _clock.elapsed < invite.monotonicDeadline &&
          constantTimeEqual(invite.digest, digest),
    );
    final known = _requests.values.any(
      (request) => constantTimeEqual(request['inviteDigest'] as String, digest),
    );
    if (!live && !known) {
      throw const PairingException('UNAUTHORIZED', 'Invalid invitation');
    }
  }

  /// Pre-check for the commit endpoint before its (empty) body is read.
  void preauthorizeCommit(String pairingId, String? token) {
    if (token == null || !isCanonicalToken(token)) {
      throw const PairingException('UNAUTHORIZED', 'Pairing is not authorized');
    }
    final request = _requests.values
        .where((r) => r['pairingId'] == pairingId)
        .firstOrNull;
    if (request == null) {
      throw const PairingException('UNAUTHORIZED', 'Pairing is not authorized');
    }
    final issued = request['issuedToken'];
    final peer = peers.authenticate(token);
    if ((issued is String && constantTimeEqual(issued, token)) ||
        peer?.pairingId == pairingId) {
      return;
    }
    throw const PairingException('UNAUTHORIZED', 'Pairing is not authorized');
  }

  /// Invalidates an invitation that has not been used yet (for example when
  /// the nearby pairing window is closed early).
  void revokeInvite(String inviteId) {
    final invite = _invitations[inviteId];
    if (invite != null && invite.requestId == null) {
      _invitations.remove(inviteId);
    }
  }

  Future<Map<String, dynamic>> request(
    Map<String, dynamic> body,
    String? secret,
  ) => _serial(() async {
    if (secret == null || !isCanonicalToken(secret)) {
      throw const PairingException('UNAUTHORIZED', 'Invalid invitation');
    }
    const fields = {
      'requestId',
      'inviteId',
      'peerId',
      'serverPin',
      'displayName',
      'reverseToken',
      'endpoint',
      'commitment',
    };
    if (body.keys.any((key) => !fields.contains(key))) {
      throw const PairingException(
        'INVALID_REQUEST',
        'Unexpected pairing fields',
      );
    }
    final requestId = _id(body['requestId']);
    final inviteId = _id(body['inviteId']);
    final pin = body['serverPin'];
    final reverseToken = body['reverseToken'];
    final rawName = body['displayName'];
    final name = rawName is String ? sanitizeDisplayText(rawName) : null;
    if (pin is! String ||
        !isCanonicalPin(pin) ||
        reverseToken is! String ||
        !isCanonicalToken(reverseToken) ||
        name == null ||
        name.isEmpty ||
        name.length > 80 ||
        name.runes.any((rune) => rune < 32 || rune == 127) ||
        body['peerId'] != peerIdFromPin(pin) ||
        pin == identity.serverPin) {
      throw const PairingException('INVALID_REQUEST', 'Invalid peer identity');
    }
    if (body['endpoint'] != null) {
      validateEndpoint(Uri.parse(body['endpoint'] as String));
    }
    final commitment = body['commitment'];
    if (commitment != null &&
        (commitment is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(commitment))) {
      throw const PairingException('INVALID_REQUEST', 'Invalid commitment');
    }
    final bodyDigest = tokenDigest(canonicalJson(body));
    final old = _requests[requestId];
    if (old != null) {
      _checkInviteAuth(old, secret);
      if (!constantTimeEqual(old['bodyDigest'] as String, bodyDigest)) {
        throw const PairingException(
          'CONFLICT',
          'Request identifier was reused',
        );
      }
      await _persist();
      return _response(old);
    }
    final invite = _invitations[inviteId];
    if (invite == null ||
        _clock.elapsed >= invite.monotonicDeadline ||
        !constantTimeEqual(invite.digest, tokenDigest(secret))) {
      throw const PairingException(
        'INVITE_EXPIRED',
        'Invitation is invalid or expired',
      );
    }
    if (invite.requestId != null && invite.requestId != requestId) {
      throw const PairingException('CONFLICT', 'Invitation already reserved');
    }
    if (invite.requireCommitment && commitment == null) {
      throw const PairingException(
        'UPGRADE_REQUIRED',
        'This pairing requires an updated app on the joining device',
      );
    }
    for (final stale in _requests.values) {
      if ((stale['state'] == 'waiting' || stale['state'] == 'approved') &&
          _expired(stale)) {
        stale['state'] = 'expired';
        stale['issuedToken'] = null;
        stale['reverseToken'] = null;
      }
    }
    if (_requests.values
            .where((p) => p['state'] == 'waiting' || p['state'] == 'approved')
            .length >=
        32) {
      throw const PairingException('BUSY', 'Too many pending pairing requests');
    }
    // Reservation happens before any await, under the service's serial lock.
    invite.requestId = requestId;
    final data = <String, dynamic>{
      ...body,
      // Stored and shown without invisible/bidi characters or space padding.
      'displayName': name,
      'bodyDigest': bodyDigest,
      'inviteDigest': invite.digest,
      'pairingId': const Uuid().v4(),
      'state': 'waiting',
      'expiresAt': invite.expiresAt.toIso8601String(),
      'issuedToken': null,
      // Chosen after the joiner committed to its nonce, before it reveals.
      if (commitment != null) 'hostNonce': randomToken(),
    };
    _requests[requestId] = data;
    _deadlines[requestId] = invite.monotonicDeadline;
    await _persist();
    return _response(data);
  });

  Future<void> approve(String requestId) => _serial(() async {
    final request = _get(requestId);
    _checkPending(request);
    if (request['state'] == 'approved') {
      await _persist();
      return;
    }
    if (request['state'] != 'waiting') {
      throw const PairingException('CONFLICT', 'Pairing cannot be approved');
    }
    if (_awaitingReveal(request)) {
      throw const PairingException(
        'SAS_PENDING',
        'The verification code is not available yet',
      );
    }
    request['issuedToken'] = randomToken();
    request['state'] = 'approved';
    try {
      await _persist();
    } catch (_) {
      request['issuedToken'] = null;
      request['state'] = 'waiting';
      rethrow;
    }
  });

  Future<void> reject(String requestId) => _serial(() async {
    final request = _get(requestId);
    if (request['state'] == 'active') {
      throw const PairingException('CONFLICT', 'Use device revocation');
    }
    request['state'] = 'rejected';
    request['issuedToken'] = null;
    request['reverseToken'] = null;
    await _persist();
  });

  Map<String, dynamic> poll(String requestId, String? secret) {
    final request = _get(requestId);
    _checkInviteAuth(request, secret);
    return _response(request);
  }

  Future<Map<String, dynamic>> commit(String pairingId, String? token) =>
      _serial(() async {
        final request = _byPairing(pairingId);
        if (request['state'] == 'active') {
          final peer = peers.authenticate(token);
          if (peer == null || peer.pairingId != pairingId) {
            throw const PairingException(
              'UNAUTHORIZED',
              'Pairing is no longer active',
            );
          }
          await _persist();
          return _response(request);
        }
        _checkPending(request);
        final issued = request['issuedToken'];
        if (request['state'] != 'approved' ||
            token == null ||
            issued is! String ||
            !constantTimeEqual(tokenDigest(token), tokenDigest(issued))) {
          throw const PairingException(
            'UNAUTHORIZED',
            'Pairing has not been approved',
          );
        }
        final peer = TrustedPeer(
          peerId: request['peerId'] as String,
          displayName: request['displayName'] as String,
          serverPin: request['serverPin'] as String,
          outgoingToken: request['reverseToken'] as String,
          inboundTokenDigest: tokenDigest(issued),
          pairingId: pairingId,
          pairedAt: DateTime.now().toUtc(),
          endpoint: request['endpoint'] == null
              ? null
              : Uri.parse(request['endpoint'] as String),
        );
        await peers.save(peer);
        request['state'] = 'active';
        request['issuedToken'] = null;
        request['reverseToken'] = null;
        _invitations.remove(request['inviteId']);
        await _persist();
        return _response(request);
      });

  Map<String, dynamic> state(String pairingId, String? token) {
    final request = _byPairing(pairingId);
    final peer = peers.authenticate(token);
    if (peer?.pairingId == pairingId) return _response(request);
    final issued = request['issuedToken'];
    if (issued is String && token != null && constantTimeEqual(issued, token)) {
      _checkPending(request);
      return _response(request);
    }
    throw const PairingException('UNAUTHORIZED', 'Pairing is not authorized');
  }

  Future<void> revoke(String peerId) => _serial(() async {
    await peers.revoke(peerId);
    for (final request in _requests.values.where(
      (p) => p['peerId'] == peerId,
    )) {
      request['state'] = 'revoked';
      request['issuedToken'] = null;
      request['reverseToken'] = null;
    }
    await _persist();
  });

  Map<String, dynamic> _response(Map<String, dynamic> request) {
    if (request['state'] == 'waiting' || request['state'] == 'approved') {
      _checkPending(request);
    }
    if (request['state'] == 'expired') {
      throw const PairingException('INVITE_EXPIRED', 'Pairing window expired');
    }
    return {
      'requestId': request['requestId'],
      'pairingId': request['pairingId'],
      'state': request['state'],
      'hostPeerId': identity.peerId,
      'hostPin': identity.serverPin,
      'displayName': identity.displayName,
      'expiresAt': request['expiresAt'],
      if (request['hostNonce'] != null) 'hostNonce': request['hostNonce'],
      if (request['commitment'] != null)
        'revealed': request['joinerNonce'] != null,
      if (request['state'] == 'approved') 'credential': request['issuedToken'],
    };
  }

  void _checkInviteAuth(Map<String, dynamic> request, String? secret) {
    if (secret == null ||
        !isCanonicalToken(secret) ||
        !constantTimeEqual(
          request['inviteDigest'] as String,
          tokenDigest(secret),
        )) {
      throw const PairingException(
        'UNAUTHORIZED',
        'Invalid invitation authentication',
      );
    }
  }

  bool _expired(Map<String, dynamic> request) =>
      _clock.elapsed >= (_deadlines[request['requestId']] ?? Duration.zero);

  void _checkPending(Map<String, dynamic> request) {
    if (_expired(request)) {
      throw const PairingException('INVITE_EXPIRED', 'Pairing window expired');
    }
    if (request['state'] == 'rejected' || request['state'] == 'revoked') {
      throw const PairingException(
        'PAIRING_REJECTED',
        'Pairing was rejected or revoked',
      );
    }
  }

  Map<String, dynamic> _get(String requestId) =>
      _requests[requestId] ??
      (throw const PairingException('NOT_FOUND', 'Pairing request not found'));

  Map<String, dynamic> _byPairing(String pairingId) =>
      _requests.values.firstWhere(
        (r) => r['pairingId'] == pairingId,
        orElse: () =>
            throw const PairingException('NOT_FOUND', 'Pairing not found'),
      );

  String _id(Object? value) {
    if (value is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(value)) {
      throw const PairingException('INVALID_REQUEST', 'Invalid identifier');
    }
    return value;
  }

  Future<void> _persist() {
    _prune();
    return peers.secretStore.write(
      _storageKey,
      jsonEncode({'version': 1, 'requests': _requests.values.toList()}),
    );
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
