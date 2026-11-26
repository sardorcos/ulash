import 'dart:async';
import 'dart:io';

import 'package:file_transfer/services/network_retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_core/transfer_core.dart';

void main() {
  test('retry delays have a finite five-step budget and bounded jitter', () {
    final lower = NetworkRetryPolicy(randomUnit: () => 0);
    final upper = NetworkRetryPolicy(randomUnit: () => 1);
    expect(lower.maxRetries, 5);
    expect(
      [for (var i = 1; i <= 5; i++) lower.delayBeforeRetry(i)!.inMilliseconds],
      [1000, 2000, 4000, 8000, 16000],
    );
    expect(
      [for (var i = 1; i <= 5; i++) upper.delayBeforeRetry(i)!.inMilliseconds],
      [1250, 2500, 5000, 10000, 20000],
    );
    expect(lower.delayBeforeRetry(0), isNull);
    expect(lower.delayBeforeRetry(6), isNull);
  });

  test(
    'only bounded transport and incomplete acknowledgment failures retry',
    () {
      final policy = NetworkRetryPolicy(randomUnit: () => 0);
      for (final error in <Object>[
        const SocketException('Connection lost'),
        TimeoutException('Request timeout'),
        const HttpException('Connection closed before headers'),
        const NetworkException('TRANSFER_INTERRUPTED', ''),
        const NetworkException('INCOMPLETE_FILE', ''),
        const NetworkException('AWAITING_COMMIT', ''),
        const NetworkException('HTTP_ERROR', '', statusCode: 503),
        // A handshake failure without a key mismatch is a flaky network;
        // a mismatch is reported as IDENTITY_CHANGED (never retried).
        const HandshakeException('Connection reset during handshake'),
        const TlsException('TLS failure'),
        const NetworkException('BUSY', '', statusCode: 503),
      ]) {
        expect(
          policy.canRetry(error),
          isTrue,
          reason: error.runtimeType.toString(),
        );
      }
      for (final error in <Object>[
        const FileSystemException('Source cannot be read'),
        const FormatException('Malformed receipt'),
        const StorageException('DISK_FULL', ''),
        for (final code in [
          'UNAUTHORIZED',
          'IDENTITY_CHANGED',
          'PROTOCOL_CONFLICT',
          'ENDPOINT_CHANGED',
          'CONSENT_REQUIRED',
          'CONSENT_TIMEOUT',
          'TRANSFER_PAUSED',
          'OFFER_EXPIRED',
          'TRANSFER_EXPIRED',
          'HASH_MISMATCH',
          'SOURCE_CHANGED',
          'NOT_FOUND',
          'TEMP_QUOTA_EXCEEDED',
          'DISK_FULL',
          'UNKNOWN_FUTURE_ERROR',
          'RATE_LIMITED',
          'FOLDERS_UNSUPPORTED',
        ])
          NetworkException(code, '', statusCode: 503),
        const NetworkException('HTTP_ERROR', '', statusCode: 401),
        const NetworkException('HTTP_ERROR', '', statusCode: 403),
        const NetworkException('HTTP_ERROR', '', statusCode: 302),
      ]) {
        expect(
          policy.canRetry(error),
          isFalse,
          reason: error.runtimeType.toString(),
        );
      }
    },
  );

  test('Retry-After is honoured for BUSY/RATE_LIMITED within a budget', () {
    final policy = NetworkRetryPolicy(randomUnit: () => 0);
    const busy = NetworkException(
      'BUSY',
      '',
      statusCode: 503,
      retryAfter: Duration(seconds: 2),
    );
    const limited = NetworkException(
      'RATE_LIMITED',
      '',
      statusCode: 429,
      retryAfter: Duration(seconds: 60),
    );
    expect(
      policy.serverRequestedDelay(busy, Duration.zero),
      const Duration(seconds: 2),
    );
    expect(
      policy.serverRequestedDelay(limited, const Duration(minutes: 3)),
      const Duration(seconds: 60),
    );
    expect(
      policy.serverRequestedDelay(
        limited,
        const Duration(minutes: 4, seconds: 30),
      ),
      isNull,
      reason: 'the total waiting budget is exhausted',
    );
    expect(
      policy.serverRequestedDelay(
        const NetworkException(
          'RATE_LIMITED',
          '',
          retryAfter: Duration(minutes: 10),
        ),
        Duration.zero,
      ),
      isNull,
      reason: 'a wait longer than two minutes is not taken silently',
    );
    expect(
      policy.serverRequestedDelay(
        const NetworkException('BUSY', '', retryAfter: Duration.zero),
        Duration.zero,
      ),
      const Duration(seconds: 1),
    );
    expect(
      policy.serverRequestedDelay(
        const NetworkException(
          'IDENTITY_CHANGED',
          '',
          retryAfter: Duration(seconds: 2),
        ),
        Duration.zero,
      ),
      isNull,
    );
    expect(
      policy.serverRequestedDelay(const SocketException('x'), Duration.zero),
      isNull,
    );
  });
}
