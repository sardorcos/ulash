import 'dart:async';
import 'dart:convert';

import '../models.dart' show stripInvisibleNameCharacters;
import 'crypto.dart';
import 'secret_store.dart';

Uri validateEndpoint(Uri endpoint) {
  if (endpoint.scheme != 'https' ||
      endpoint.host.isEmpty ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      (endpoint.path.isNotEmpty && endpoint.path != '/') ||
      endpoint.port < 1 ||
      endpoint.port > 65535) {
    throw const FormatException('Endpoint must be a single HTTPS origin');
  }
  return endpoint.replace(path: '');
}

final class TrustedPeer {
  TrustedPeer({
    required this.peerId,
    required this.displayName,
    required this.serverPin,
    required this.outgoingToken,
    required this.inboundTokenDigest,
    required this.pairingId,
    required this.pairedAt,
    Uri? endpoint,
  }) : endpoint = endpoint == null ? null : validateEndpoint(endpoint) {
    if (peerId != peerIdFromPin(serverPin) ||
        !isCanonicalToken(outgoingToken) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(inboundTokenDigest)) {
      throw const FormatException('Invalid trusted peer credential');
    }
  }

  final String peerId;
  final String displayName;
  final String serverPin;
  final String outgoingToken;
  final String inboundTokenDigest;
  final String pairingId;
  final DateTime pairedAt;
  final Uri? endpoint;

  TrustedPeer withDisplayName(String value) => TrustedPeer(
    peerId: peerId,
    displayName: value,
    serverPin: serverPin,
    outgoingToken: outgoingToken,
    inboundTokenDigest: inboundTokenDigest,
    pairingId: pairingId,
    pairedAt: pairedAt,
    endpoint: endpoint,
  );

  TrustedPeer withEndpoint(Uri value) => TrustedPeer(
    peerId: peerId,
    displayName: displayName,
    serverPin: serverPin,
    outgoingToken: outgoingToken,
    inboundTokenDigest: inboundTokenDigest,
    pairingId: pairingId,
    pairedAt: pairedAt,
    endpoint: value,
  );

  Map<String, dynamic> toPublicJson() => {
    'peerId': peerId,
    'displayName': displayName,
    'serverPin': serverPin,
    'pairingId': pairingId,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
    if (endpoint != null) 'endpoint': endpoint.toString(),
  };

  Map<String, dynamic> _toSecretJson() => {
    ...toPublicJson(),
    'outgoingToken': outgoingToken,
    'inboundTokenDigest': inboundTokenDigest,
  };

  static TrustedPeer _fromSecretJson(Map<String, dynamic> json) => TrustedPeer(
    peerId: json['peerId'] as String,
    displayName: json['displayName'] as String,
    serverPin: json['serverPin'] as String,
    outgoingToken: json['outgoingToken'] as String,
    inboundTokenDigest: json['inboundTokenDigest'] as String,
    pairingId: json['pairingId'] as String,
    pairedAt: DateTime.parse(json['pairedAt'] as String),
    endpoint: json['endpoint'] == null
        ? null
        : Uri.parse(json['endpoint'] as String),
  );

  @override
  String toString() => 'TrustedPeer($peerId, credentials redacted)';
}

/// Persists credentials only in the application's injected OS-protected store.
final class TrustedPeerStore {
  TrustedPeerStore(this.secretStore, {this.storageKey = 'transfer.peers.v1'});

  final SecretStore secretStore;
  final String storageKey;
  final Map<String, TrustedPeer> _peers = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  Future<void> _tail = Future.value();
  bool _loaded = false;

  Future<void> load() => _serial(() async {
    if (_loaded) return;
    final raw = await secretStore.read(storageKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['version'] != 1) {
        throw const FormatException('Unsupported peer store version');
      }
      for (final item in decoded['peers'] as List) {
        final peer = TrustedPeer._fromSecretJson(
          Map<String, dynamic>.from(item as Map),
        );
        _peers[peer.peerId] = peer;
      }
    }
    _loaded = true;
  });

  List<TrustedPeer> list() {
    _ensureLoaded();
    return List.unmodifiable(_peers.values);
  }

  TrustedPeer? byId(String peerId) {
    _ensureLoaded();
    return _peers[peerId];
  }

  TrustedPeer? authenticate(String? token) {
    _ensureLoaded();
    if (token == null || !isCanonicalToken(token)) return null;
    final digest = tokenDigest(token);
    TrustedPeer? found;
    for (final peer in _peers.values) {
      if (constantTimeEqual(digest, peer.inboundTokenDigest)) found = peer;
    }
    return found;
  }

  Future<void> save(TrustedPeer peer) => _serial(() async {
    _ensureLoaded();
    final before = _peers[peer.peerId];
    _peers[peer.peerId] = peer;
    try {
      await _persist();
      _changes.add(null);
    } catch (_) {
      if (before == null) {
        _peers.remove(peer.peerId);
      } else {
        _peers[peer.peerId] = before;
      }
      rethrow;
    }
  });

  Future<void> updateEndpoint(String peerId, Uri endpoint) => _serial(() async {
    _ensureLoaded();
    final peer = _peers[peerId];
    if (peer == null) throw StateError('Device has not been paired');
    final updated = peer.withEndpoint(endpoint);
    _peers[peerId] = updated;
    try {
      await _persist();
      _changes.add(null);
    } catch (_) {
      _peers[peerId] = peer;
      rethrow;
    }
  });

  /// Applies a name reported by the peer over its pinned, authenticated
  /// connection (the user renamed that device). Invalid names are ignored.
  Future<bool> updateDisplayName(String peerId, String name) =>
      _serialResult(() async {
        _ensureLoaded();
        final peer = _peers[peerId];
        final clean = stripInvisibleNameCharacters(name).trim();
        if (peer == null ||
            clean.isEmpty ||
            clean.length > 80 ||
            clean.runes.any((rune) => rune < 32 || rune == 127) ||
            clean == peer.displayName) {
          return false;
        }
        _peers[peerId] = peer.withDisplayName(clean);
        try {
          await _persist();
          _changes.add(null);
          return true;
        } catch (_) {
          _peers[peerId] = peer;
          rethrow;
        }
      });

  Future<T> _serialResult<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> revoke(String peerId) => _serial(() async {
    _ensureLoaded();
    final previous = _peers.remove(peerId);
    try {
      await _persist();
      _changes.add(null);
    } catch (_) {
      if (previous != null) _peers[peerId] = previous;
      rethrow;
    }
  });

  Future<void> _persist() => secretStore.write(
    storageKey,
    jsonEncode({
      'version': 1,
      'peers': _peers.values.map((p) => p._toSecretJson()).toList(),
    }),
  );

  Future<void> _serial(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _ensureLoaded() {
    if (!_loaded) throw StateError('Call TrustedPeerStore.load() first');
  }

  Future<void> close() => _changes.close();

  @override
  String toString() => 'TrustedPeerStore(credentials redacted)';
}
