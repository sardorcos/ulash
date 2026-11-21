import 'dart:async';

import '../models.dart';

/// One shared budget for inbox and outbox payloads on the same filesystem.
///
/// [availableBytes] returns the space currently available to this application,
/// not the total size of the volume. `null` means the platform cannot report it;
/// the temporary-data quota still applies, but no free-space guarantee is made.
/// Reservations are an admission guard, not an operating-system disk reservation.
/// Other applications may consume space after a check, so stores still handle
/// real write errors and periodically check capacity while streaming.
class StorageBudget {
  StorageBudget({
    required this.availableBytes,
    this.safetyReserveBytes = 128 * 1024 * 1024,
    int? temporaryQuotaBytes = 20 * 1024 * 1024 * 1024,
    this.recheckBytes = 4 * 1024 * 1024,
    this.recheckInterval = const Duration(seconds: 2),
  }) : _temporaryQuotaBytes = temporaryQuotaBytes {
    if (safetyReserveBytes < 0 ||
        (temporaryQuotaBytes != null && temporaryQuotaBytes < 0) ||
        recheckBytes < 1 ||
        recheckInterval <= Duration.zero) {
      throw ArgumentError(
        'Storage limits must be nonnegative and intervals positive.',
      );
    }
  }

  final Future<int?> Function() availableBytes;
  final int safetyReserveBytes;
  final int recheckBytes;
  final Duration recheckInterval;
  int? _temporaryQuotaBytes;

  /// The configured temporary-data quota (null = unlimited).
  int? get temporaryQuotaBytes => _temporaryQuotaBytes;
  final _queue = _BudgetQueue();
  final _scopes = <String, Map<String, StorageBudgetClaim>>{};
  final _sinceCheck = Stopwatch();
  var _writtenSinceCheck = 0;

  int get _used => _scopes.values.fold(
    0,
    (sum, claims) =>
        sum + claims.values.fold(0, (n, claim) => n + claim.usedBytes),
  );

  int get _future => _scopes.values.fold(
    0,
    (sum, claims) =>
        sum +
        claims.values.fold(
          0,
          (n, claim) => n + claim.totalBytes - claim.usedBytes,
        ),
  );

  /// Reads actual capacity without changing or deleting any file.
  Future<StorageBudgetSnapshot> inspect() => _queue.run(() async {
    final free = await _readAvailable();
    return StorageBudgetSnapshot(
      availableBytes: free,
      temporaryBytes: _used,
      reservedBytes: _future,
      safetyReserveBytes: safetyReserveBytes,
      temporaryQuotaBytes: _temporaryQuotaBytes,
    );
  });

  /// Lowering the quota cannot silently invalidate admitted transfers.
  Future<void> setTemporaryQuotaBytes(int? value) => _queue.run(() async {
    if (value != null && value < 0) {
      throw ArgumentError.value(value, 'value', 'Quota cannot be negative.');
    }
    if (value != null && value < _used + _future) {
      throw const StorageException(
        'TEMP_QUOTA_BELOW_USAGE',
        'Quota is below existing temporary files and reservations.',
      );
    }
    _temporaryQuotaBytes = value;
  });

  /// Store-internal recovery operation. Existing files are accounted even when
  /// they already exceed a newly configured limit; recovery never deletes them.
  Future<void> restoreScope(String scope, List<StorageBudgetClaim> claims) =>
      _queue.run(() async {
        final recovered = <String, StorageBudgetClaim>{};
        for (final claim in claims) {
          claim.validate();
          if (recovered.containsKey(claim.key)) {
            throw StateError('Duplicate recovered storage claim.');
          }
          recovered[claim.key] = claim;
        }
        _scopes[scope] = recovered;
      });

  /// Atomically admits a whole incoming batch or one outgoing preparation.
  Future<void> reserveAll(String scope, List<StorageBudgetClaim> claims) =>
      _queue.run(() async {
        final prior = Map<String, StorageBudgetClaim>.of(_scopes[scope] ?? {});
        final next = Map<String, StorageBudgetClaim>.of(prior);
        for (final claim in claims) {
          claim.validate();
          next[claim.key] = claim;
        }
        _scopes[scope] = next;
        try {
          _checkQuota();
          await _checkCapacity();
        } catch (_) {
          _scopes[scope] = prior;
          rethrow;
        }
      });

  /// Stores call this only after observing actual on-disk bytes. It does not
  /// perform admission: already-written data must remain accounted on failure.
  Future<void> reconcile(String scope, StorageBudgetClaim claim) =>
      _queue.run(() async {
        claim.validate();
        (_scopes[scope] ??= {})[claim.key] = claim;
      });

  /// Forget only after the temporary payload is deleted or committed outside
  /// the temporary quota. Removing a reservation alone never deletes bytes.
  Future<void> forget(String scope, String key) => _queue.run(() async {
    _scopes[scope]?.remove(key);
  });

  /// Checks current free space before starting or resuming an admitted stream.
  Future<void> check() => _queue.run(() async {
    _checkQuota();
    await _checkCapacity();
  });

  /// Serializes a bounded physical write with the accounting update. A query
  /// cannot count newly written bytes once in the OS free value and again as
  /// future reserved bytes. Unknown-length provider streams grow incrementally.
  Future<void> write(
    String scope,
    String key,
    int byteCount,
    Future<void> Function() writeBytes,
  ) => _queue.run(() async {
    if (byteCount < 0) throw ArgumentError.value(byteCount, 'byteCount');
    final claims = _scopes[scope];
    final prior = claims?[key];
    if (claims == null || prior == null) {
      throw StateError('Write has no storage reservation.');
    }
    final nextUsed = prior.usedBytes + byteCount;
    final grows = nextUsed > prior.totalBytes;
    final target = grows ? nextUsed : prior.totalBytes;
    claims[key] = StorageBudgetClaim(
      key: key,
      usedBytes: prior.usedBytes,
      totalBytes: target,
    );
    var writeStarted = false;
    try {
      _checkQuota();
      if (grows ||
          !_sinceCheck.isRunning ||
          _writtenSinceCheck + byteCount >= recheckBytes ||
          _sinceCheck.elapsed >= recheckInterval) {
        await _checkCapacity();
      }
      writeStarted = true;
      await writeBytes();
      claims[key] = StorageBudgetClaim(
        key: key,
        usedBytes: nextUsed,
        totalBytes: target,
      );
      _writtenSinceCheck += byteCount;
    } catch (_) {
      // A failed OS write may have written a partial chunk. Keep its whole
      // reservation conservatively until the owning store stats the file.
      if (!writeStarted) claims[key] = prior;
      rethrow;
    }
  });

  void _checkQuota() {
    final quota = _temporaryQuotaBytes;
    if (quota != null && _used + _future > quota) {
      throw const StorageException(
        'TEMP_QUOTA_EXCEEDED',
        'Temporary file quota would be exceeded.',
      );
    }
  }

  Future<int?> _readAvailable() async {
    final free = await availableBytes();
    if (free != null && free < 0) {
      throw const StorageException(
        'CAPACITY_UNAVAILABLE',
        'The platform returned an invalid available-space value.',
      );
    }
    return free;
  }

  Future<void> _checkCapacity() async {
    final free = await _readAvailable();
    if (free != null && free < _future + safetyReserveBytes) {
      // An admission failure may reveal that another application consumed
      // space. Existing streams must recheck on their next bounded write.
      _writtenSinceCheck = recheckBytes;
      throw const StorageException(
        'DISK_FULL',
        'Available space is below outstanding payloads and safety reserve.',
      );
    }
    _writtenSinceCheck = 0;
    _sinceCheck
      ..reset()
      ..start();
  }
}

class StorageBudgetSnapshot {
  const StorageBudgetSnapshot({
    required this.availableBytes,
    required this.temporaryBytes,
    required this.reservedBytes,
    required this.safetyReserveBytes,
    required this.temporaryQuotaBytes,
  });

  final int? availableBytes;
  final int temporaryBytes;
  final int reservedBytes;
  final int safetyReserveBytes;
  final int? temporaryQuotaBytes;
}

/// Internal claim identifiers are generated by the stores, never wire paths.
class StorageBudgetClaim {
  const StorageBudgetClaim({
    required this.key,
    required this.usedBytes,
    required this.totalBytes,
  });

  final String key;
  final int usedBytes;
  final int totalBytes;

  void validate() {
    if (key.isEmpty || usedBytes < 0 || totalBytes < usedBytes) {
      throw ArgumentError('Invalid storage allocation.');
    }
  }
}

class _BudgetQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) async {
    final before = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await before;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }
}
