import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

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
  });
  final String requestId;
  final String pairingId;
  final String peerId;
  final String displayName;
  final String serverPin;
  final String state;
  final DateTime expiresAt;
  @override
  String toString() => 'PendingPairing($requestId, $state)';
}

final class _Invitation {
  _Invitation(this.digest, this.expiresAt, this.monotonicDeadline);
  final String digest;
  final DateTime expiresAt;
  final Duration monotonicDeadline;
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
  }

  PairingInvite createInvite(
    Uri endpoint, {
    Duration ttl = const Duration(seconds: 120),
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
    );
    return PairingInvite(
      inviteId: id,
      inviteSecret: secret,
      hostPin: identity.serverPin,
      displayName: identity.displayName,
      endpoint: endpoint,
      ttlSeconds: ttl.inSeconds,
    );
  }

  List<PendingPairing> get pending => _requests.values
      .where(
        (p) =>
            (p['state'] == 'waiting' || p['state'] == 'approved') &&
            !_expired(p),
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
        ),
      )
      .toList(growable: false);

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
    final name = body['displayName'];
    if (pin is! String ||
        !isCanonicalPin(pin) ||
        reverseToken is! String ||
        !isCanonicalToken(reverseToken) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        name.runes.any((rune) => rune < 32 || rune == 127) ||
        body['peerId'] != peerIdFromPin(pin) ||
        pin == identity.serverPin) {
      throw const PairingException('INVALID_REQUEST', 'Invalid peer identity');
    }
    if (body['endpoint'] != null) {
      validateEndpoint(Uri.parse(body['endpoint'] as String));
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
      'bodyDigest': bodyDigest,
      'inviteDigest': invite.digest,
      'pairingId': const Uuid().v4(),
      'state': 'waiting',
      'expiresAt': invite.expiresAt.toIso8601String(),
      'issuedToken': null,
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
    return {
      'requestId': request['requestId'],
      'pairingId': request['pairingId'],
      'state': request['state'],
      'hostPeerId': identity.peerId,
      'hostPin': identity.serverPin,
      'displayName': identity.displayName,
      'expiresAt': request['expiresAt'],
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

  Future<void> _persist() => peers.secretStore.write(
    _storageKey,
    jsonEncode({'version': 1, 'requests': _requests.values.toList()}),
  );

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
