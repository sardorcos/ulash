import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:uuid/uuid.dart';

import 'crypto.dart';
import 'secret_store.dart';

/// Software TLS identity protected at rest by the injected OS secret store.
/// Hardware non-exportability is deliberately not claimed by this adapter.
final class DeviceIdentity {
  DeviceIdentity._(
    this._privateKeyPem, {
    required this.deviceId,
    required this.displayName,
    required this.certificatePem,
    required this.serverPin,
  });

  final String deviceId;
  String get id => deviceId;
  final String displayName;
  final String certificatePem;
  final String _privateKeyPem;
  final String serverPin;
  String get peerId => peerIdFromPin(serverPin);

  static Future<DeviceIdentity> generate({required String displayName}) async {
    final name = _validName(displayName);
    final data = await Isolate.run(() => _generate(name));
    return _fromJson(data);
  }

  static Future<DeviceIdentity> loadOrCreate(
    SecretStore store, {
    required String displayName,
    String storageKey = 'transfer.identity.v1',
  }) async {
    final existing = await store.read(storageKey);
    if (existing != null) {
      // Corrupt identity MUST fail closed; never silently regenerate trust.
      return _fromJson(jsonDecode(existing) as Map<String, dynamic>);
    }
    final result = await generate(displayName: displayName);
    await store.write(storageKey, jsonEncode(result._toSecretJson()));
    return result;
  }

  SecurityContext serverContext() {
    return SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2
      ..useCertificateChainBytes(utf8.encode(certificatePem))
      ..usePrivateKeyBytes(utf8.encode(_privateKeyPem));
  }

  Map<String, dynamic> get publicInfo => {
    'peerId': peerId,
    'deviceId': deviceId,
    'displayName': displayName,
    'serverPin': serverPin,
  };

  Map<String, dynamic> _toSecretJson() => {
    'version': 1,
    'deviceId': deviceId,
    'displayName': displayName,
    'certificatePem': certificatePem,
    'privateKeyPem': _privateKeyPem,
    'serverPin': serverPin,
  };

  static DeviceIdentity _fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported stored identity version');
    }
    final pem = json['certificatePem'] as String;
    final pin = spkiPinFromCertificateDer(
      CryptoUtils.getBytesFromPEMString(pem),
    );
    if (!constantTimeEqual(pin, json['serverPin'] as String)) {
      throw const FormatException('Stored identity public key mismatch');
    }
    final result = DeviceIdentity._(
      json['privateKeyPem'] as String,
      deviceId: json['deviceId'] as String,
      displayName: _validName(json['displayName'] as String),
      certificatePem: pem,
      serverPin: pin,
    );
    result
        .serverContext(); // Also validate the private key/certificate loading.
    return result;
  }

  @override
  String toString() => 'DeviceIdentity($deviceId, credentials redacted)';
}

String _validName(String name) {
  final clean = name.trim();
  if (clean.isEmpty ||
      clean.length > 80 ||
      clean.runes.any((rune) => rune < 32 || rune == 127)) {
    throw const FormatException(
      'Device name must contain 1–80 printable characters',
    );
  }
  return clean;
}

Map<String, dynamic> _generate(String name) {
  final pair = CryptoUtils.generateEcKeyPair();
  final privateKey = pair.privateKey as ECPrivateKey;
  final publicKey = pair.publicKey as ECPublicKey;
  final deviceId = const Uuid().v4();
  final csr = X509Utils.generateEccCsrPem(
    {'CN': 'Transfer-$deviceId'},
    privateKey,
    publicKey,
  );
  final cert = X509Utils.generateSelfSignedCertificate(
    privateKey,
    csr,
    3650,
    serialNumber: BigInt.parse(
      tokenDigest(randomToken()).substring(0, 30),
      radix: 16,
    ).toString(),
    notBefore: DateTime.now().toUtc().subtract(const Duration(days: 1)),
  );
  return {
    'version': 1,
    'deviceId': deviceId,
    'displayName': name,
    'certificatePem': cert,
    'privateKeyPem': CryptoUtils.encodePrivateEcdsaKeyToPkcs8(privateKey),
    'serverPin': spkiPinFromCertificateDer(
      CryptoUtils.getBytesFromPEMString(cert),
    ),
  };
}
