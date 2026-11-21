import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:transfer_core/transfer_core.dart';

/// A finite retry budget for one explicit send/resume action. Delays use a
/// monotonic timer in the coordinator; wall-clock changes do not extend them.
/// Authentication, consent, integrity and storage failures are deliberately
/// excluded even if a remote peer happens to attach an HTTP 5xx status.
class NetworkRetryPolicy {
  NetworkRetryPolicy({double Function()? randomUnit})
    : _randomUnit = randomUnit ?? Random().nextDouble;

  final double Function() _randomUnit;
  static const _baseSeconds = [1, 2, 4, 8, 16];
  int get maxRetries => _baseSeconds.length;

  Duration? delayBeforeRetry(int retryNumber) {
    if (retryNumber < 1 || retryNumber > maxRetries) return null;
    final jitter = _randomUnit();
    if (!jitter.isFinite || jitter < 0 || jitter > 1) {
      throw StateError('Retry jitter must be between zero and one.');
    }
    return Duration(
      microseconds:
          (_baseSeconds[retryNumber - 1] *
                  Duration.microsecondsPerSecond *
                  (1 + jitter * .25))
              .round(),
    );
  }

  bool canRetry(Object error) {
    if (error is TlsException) return false;
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return true;
    }
    if (error is! NetworkException) return false;
    return switch (error.code) {
      'TRANSFER_INTERRUPTED' ||
      'REQUEST_TIMEOUT' ||
      'AWAITING_COMMIT' ||
      'INCOMPLETE_FILE' ||
      // The receiver stopped a too-slow upload at a durable offset.
      // RATE_LIMITED is not retried: its window is minutes, not seconds.
      'TRANSFER_TOO_SLOW' => true,
      'HTTP_ERROR' => const {408, 502, 503, 504}.contains(error.statusCode),
      _ => false,
    };
  }
}
