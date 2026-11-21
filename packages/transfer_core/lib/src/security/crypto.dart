import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';

String randomToken() {
  final random = Random.secure();
  return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

bool isCanonicalToken(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) return false;
  try {
    final bytes = base64Url.decode(base64Url.normalize(value));
    return bytes.length == 32 &&
        base64UrlEncode(bytes).replaceAll('=', '') == value;
  } on FormatException {
    return false;
  }
}

bool isCanonicalPin(String value) {
  try {
    final bytes = base64Decode(value);
    return bytes.length == 32 && base64Encode(bytes) == value;
  } on FormatException {
    return false;
  }
}

String tokenDigest(String token) =>
    sha256.convert(utf8.encode(token)).toString();

bool constantTimeEqual(String a, String b) {
  final left = utf8.encode(a);
  final right = utf8.encode(b);
  var mismatch = left.length ^ right.length;
  final length = max(left.length, right.length);
  for (var i = 0; i < length; i++) {
    mismatch |=
        (i < left.length ? left[i] : 0) ^ (i < right.length ? right[i] : 0);
  }
  return mismatch == 0;
}

/// Parses the X.509 structure using asn1lib, retaining the DER SPKI object.
/// The optional [0] version field distinguishes X.509 v1 from v2/v3.
String spkiPinFromCertificateDer(List<int> certificateDer) {
  if (certificateDer.isEmpty || certificateDer.length > 65536) {
    throw const FormatException('Invalid certificate length');
  }
  final certificate = ASN1Parser(Uint8List.fromList(certificateDer))
      .nextObject();
  if (certificate is! ASN1Sequence || certificate.elements.length != 3) {
    throw const FormatException('Invalid X.509 certificate');
  }
  final tbs = certificate.elements.first;
  if (tbs is! ASN1Sequence || tbs.elements.isEmpty) {
    throw const FormatException('Invalid X.509 certificate body');
  }
  final hasVersion = tbs.elements.first.tag == 0xa0;
  final spkiIndex = hasVersion ? 6 : 5;
  if (tbs.elements.length <= spkiIndex ||
      tbs.elements[spkiIndex] is! ASN1Sequence) {
    throw const FormatException('Missing certificate public key');
  }
  final spki = tbs.elements[spkiIndex] as ASN1Sequence;
  if (spki.elements.length != 2 || spki.elements.first is! ASN1Sequence) {
    throw const FormatException('Invalid certificate public key');
  }
  return base64Encode(sha256.convert(spki.encodedBytes).bytes);
}

String peerIdFromPin(String pin) {
  if (!isCanonicalPin(pin)) throw const FormatException('Invalid SPKI pin');
  return base64Decode(pin)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

String canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
