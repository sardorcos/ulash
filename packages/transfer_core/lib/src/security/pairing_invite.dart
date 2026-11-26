import 'dart:convert';

import 'crypto.dart';
import 'trusted_peer_store.dart';

/// Capability-bearing invitation. Do not send its URI to diagnostics or logs.
final class PairingInvite {
  PairingInvite({
    required this.inviteId,
    required this.inviteSecret,
    required this.hostPin,
    required this.displayName,
    required Uri endpoint,
    List<Uri>? endpoints,
    this.ttlSeconds = 120,
    this.discovered = false,
  }) : endpoint = validateEndpoint(endpoint),
       endpoints = _endpointList(endpoint, endpoints) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(inviteId) ||
        !isCanonicalToken(inviteSecret) ||
        !isCanonicalPin(hostPin) ||
        displayName.isEmpty ||
        displayName.length > 80 ||
        ttlSeconds < 1 ||
        ttlSeconds > 300) {
      throw const FormatException('Invalid pairing invitation');
    }
  }

  final String inviteId;
  final String inviteSecret;
  final String hostPin;
  String get serverPin => hostPin;
  final String displayName;

  /// The preferred address (the first of [endpoints]).
  final Uri endpoint;

  /// All candidate addresses of the host, preferred first (1–[maxEndpoints]).
  /// A client tries them in order; the pinned key, not the address, is trust.
  final List<Uri> endpoints;
  final int ttlSeconds;

  /// True for an invitation fetched over the network (nearby pairing) rather
  /// than scanned from the host's screen. Its key is not authenticated by the
  /// QR code, so pairing requires the commit/reveal code
  /// ([CoreClient.requestPairing] never falls back to the legacy scheme).
  /// Not part of the encoded invitation.
  final bool discovered;

  static const int maxEndpoints = 4;

  static List<Uri> _endpointList(Uri first, List<Uri>? extra) {
    final result = <Uri>[validateEndpoint(first)];
    for (final candidate in extra ?? const <Uri>[]) {
      final valid = validateEndpoint(candidate);
      if (!result.contains(valid)) result.add(valid);
    }
    if (result.length > maxEndpoints) {
      throw const FormatException('Too many invitation endpoints');
    }
    return List.unmodifiable(result);
  }

  /// Superseded invitation-bound code (see [pairingSas]); 1.2 hosts do not
  /// show it. Use `PairingProgress.sas` from `CoreClient.requestPairing`.
  String sasFor(String joinerPin) => pairingSas(
    inviteDigest: tokenDigest(inviteSecret),
    hostPin: hostPin,
    joinerPin: joinerPin,
  );

  String encode() {
    final payload = base64UrlEncode(
      utf8.encode(
        jsonEncode({
          'version': 1,
          'inviteId': inviteId,
          'inviteSecret': inviteSecret,
          'hostPin': hostPin,
          'displayName': displayName,
          'endpoints': [
            for (final item in endpoints)
              {'host': item.host, 'port': item.port},
          ],
          'ttlSeconds': ttlSeconds,
        }),
      ),
    ).replaceAll('=', '');
    return Uri(
      scheme: 'xferapp',
      host: 'pair',
      queryParameters: {'data': payload},
    ).toString();
  }

  static PairingInvite parse(String text) {
    try {
      return _parse(text);
    } on FormatException {
      // Uri/JSON parsing exceptions can otherwise embed the secret-bearing input.
      throw const FormatException('Invalid pairing invitation');
    } on TypeError {
      throw const FormatException('Invalid pairing invitation fields');
    } on RangeError {
      throw const FormatException('Invalid pairing invitation size');
    }
  }

  static PairingInvite _parse(String text) {
    if (text.length > 8192) {
      throw const FormatException('Invitation is too large');
    }
    final uri = Uri.parse(text.trim());
    if (uri.scheme != 'xferapp' ||
        uri.host != 'pair' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.path.isNotEmpty ||
        uri.queryParametersAll.length != 1 ||
        uri.queryParametersAll['data']?.length != 1) {
      throw const FormatException('Invalid invitation URI');
    }
    final value = uri.queryParameters['data'];
    if (value == null) throw const FormatException('Missing invitation data');
    final json = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(value))),
    ) as Map<String, dynamic>;
    const allowed = {
      'version',
      'inviteId',
      'inviteSecret',
      'hostPin',
      'displayName',
      'endpoints',
      'ttlSeconds',
    };
    if (json.keys.any((key) => !allowed.contains(key)) ||
        json['version'] != 1) {
      throw const FormatException('Unsupported invitation fields');
    }
    final addresses = json['endpoints'] as List;
    if (addresses.isEmpty || addresses.length > maxEndpoints) {
      throw const FormatException('Invalid number of endpoints');
    }
    final parsed = <Uri>[];
    for (final item in addresses) {
      final address = item as Map<String, dynamic>;
      if (address.keys.any((key) => key != 'host' && key != 'port')) {
        throw const FormatException('Invalid endpoint fields');
      }
      parsed.add(
        Uri(
          scheme: 'https',
          host: address['host'] as String,
          port: address['port'] as int,
        ),
      );
    }
    return PairingInvite(
      inviteId: json['inviteId'] as String,
      inviteSecret: json['inviteSecret'] as String,
      hostPin: json['hostPin'] as String,
      displayName: json['displayName'] as String,
      endpoint: parsed.first,
      endpoints: parsed,
      ttlSeconds: json['ttlSeconds'] as int,
    );
  }

  @override
  String toString() => 'PairingInvite(secret redacted)';
}
