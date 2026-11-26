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

  /// Longest single server-requested wait (`Retry-After`) honoured, and the
  /// total such waiting one send/resume action may spend.
  static const maxServerWait = Duration(seconds: 120);
  static const serverWaitBudget = Duration(minutes: 5);

  /// BUSY / RATE_LIMITED with a `Retry-After` hint: the wait the peer asked
  /// for, when it fits the budget ([alreadyWaited] is what this action has
  /// already spent on such waits). Null = use the ordinary policy.
  Duration? serverRequestedDelay(Object error, Duration alreadyWaited) {
    if (error is! NetworkException) return null;
    if (error.code != 'BUSY' && error.code != 'RATE_LIMITED') return null;
    final wait = error.retryAfter;
    if (wait == null || wait.isNegative || wait > maxServerWait) return null;
    if (alreadyWaited + wait > serverWaitBudget) return null;
    // Never hammer a peer that answered "busy" with a zero wait.
    return wait < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : wait;
  }

  bool canRetry(Object error) {
    // A plain TLS/handshake failure is a transport problem on a flaky
    // network. A key mismatch arrives as NetworkException IDENTITY_CHANGED
    // and is never retried (see below).
    if (error is TlsException) return true;
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
      // RATE_LIMITED is retried only through serverRequestedDelay.
      // IDENTITY_CHANGED, ENDPOINT_CHANGED, consent and integrity errors
      // fall through to false.
      'TRANSFER_TOO_SLOW' ||
      // Another transfer is running there; the ordinary backoff applies when
      // no Retry-After hint was given.
      'BUSY' => true,
      'HTTP_ERROR' => const {408, 502, 503, 504}.contains(error.statusCode),
      _ => false,
    };
  }
}

/// Counts retries per stall: when the receiver's durable offset has grown
/// since the previous failure, progress was made and the budget restarts.
class StallRetryCounter {
  StallRetryCounter(this._lastDurable);
  int _lastDurable;
  int _retries = 0;

  /// Returns the retry number (1-based) for a failure at [durableBytes].
  int next(int durableBytes) {
    if (durableBytes > _lastDurable) {
      _retries = 0;
      _lastDurable = durableBytes;
    }
    return ++_retries;
  }
}
