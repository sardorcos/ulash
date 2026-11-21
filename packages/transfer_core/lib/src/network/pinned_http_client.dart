import 'dart:io';

import '../security/crypto.dart';
import '../security/trusted_peer_store.dart';
import 'network_error.dart';

/// Returns only an already-authenticated TLS socket to HttpClient. Pin checking
/// happens before HttpClient can write Authorization or any HTTP request bytes.
HttpClient createPinnedHttpClient(Uri origin, String expectedPin) {
  final endpoint = validateEndpoint(origin);
  if (!isCanonicalPin(expectedPin)) {
    throw const FormatException('Invalid server pin');
  }
  final context = SecurityContext(withTrustedRoots: false)
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;
  bool matches(X509Certificate cert) {
    try {
      return constantTimeEqual(
        spkiPinFromCertificateDer(cert.der),
        expectedPin,
      );
    } catch (_) {
      return false;
    }
  }

  final client = HttpClient(context: context)
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 20)
    ..maxConnectionsPerHost = 4
    ..findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (proxyHost != null ||
        proxyPort != null ||
        uri.scheme != 'https' ||
        uri.host != endpoint.host ||
        uri.port != endpoint.port) {
      throw const NetworkException(
        'ENDPOINT_CHANGED',
        'Connection origin was rejected',
      );
    }
    final task = await SecureSocket.startConnect(
      uri.host,
      uri.port,
      context: context,
      onBadCertificate: matches,
    );
    final verified = task.socket.then<Socket>((socket) {
      final certificate = socket.peerCertificate;
      // This unconditional post-handshake check also rejects CA-valid impostors.
      if (certificate == null || !matches(certificate)) {
        socket.destroy();
        throw const NetworkException(
          'IDENTITY_CHANGED',
          'Server key did not match the paired identity',
        );
      }
      return socket;
    });
    return ConnectionTask.fromSocket(verified, task.cancel);
  };
  return client;
}
