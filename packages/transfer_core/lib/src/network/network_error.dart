final class NetworkException implements Exception {
  const NetworkException(
    this.code,
    this.message, {
    this.statusCode,
    this.offset,
  });
  final String code;
  final String message;
  final int? statusCode;
  final int? offset;

  /// Deliberately excludes URLs, headers, invitations and server error bodies.
  @override
  String toString() =>
      'NetworkException($code${statusCode == null ? '' : ', $statusCode'})';
}
