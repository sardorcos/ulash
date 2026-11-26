final class NetworkException implements Exception {
  const NetworkException(
    this.code,
    this.message, {
    this.statusCode,
    this.offset,
    this.retryAfter,
  });
  final String code;
  final String message;
  final int? statusCode;
  final int? offset;

  /// Server-suggested wait (HTTP `Retry-After`) for BUSY / RATE_LIMITED.
  final Duration? retryAfter;

  /// Deliberately excludes URLs, headers, invitations and server error bodies.
  @override
  String toString() =>
      'NetworkException($code${statusCode == null ? '' : ', $statusCode'})';
}
