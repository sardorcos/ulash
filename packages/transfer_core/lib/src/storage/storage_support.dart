import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../models.dart';

/// One owner per process plus an OS advisory lock across processes.
class StorageLease {
  StorageLease._(this._key, this._handle);
  static final Set<String> _owned = {};
  final String _key;
  final RandomAccessFile _handle;
  bool _released = false;

  static Future<StorageLease> acquire(Directory root, String name) async {
    final key = p.join(root.path, '.$name.lock');
    if (!_owned.add(key)) {
      throw const StorageException(
        'STORE_IN_USE',
        'Storage is open in another instance.',
      );
    }
    RandomAccessFile? handle;
    try {
      final type = await FileSystemEntity.type(key, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw const StorageException(
          'UNSAFE_PATH',
          'Storage lock is not a plain file.',
        );
      }
      handle = await File(key).open(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      return StorageLease._(key, handle);
    } catch (error) {
      await handle?.close();
      _owned.remove(key);
      if (error is StorageException) rethrow;
      throw const StorageException(
        'STORE_IN_USE',
        'Could not exclusively open storage.',
      );
    }
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _handle.unlock();
    } finally {
      await _handle.close();
      _owned.remove(_key);
    }
  }
}

Future<Directory> prepareStorageDirectory(Directory requested) async {
  final kind = await FileSystemEntity.type(requested.path, followLinks: false);
  if (kind == FileSystemEntityType.link ||
      (kind != FileSystemEntityType.notFound &&
          kind != FileSystemEntityType.directory)) {
    throw const StorageException('UNSAFE_PATH', 'Storage must be a directory.');
  }
  await requested.create(recursive: true);
  return Directory(await requested.resolveSymbolicLinks());
}

Future<void> ensurePlainDirectory(Directory directory) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    await directory.create(recursive: true);
  } else if (type != FileSystemEntityType.directory) {
    throw const StorageException('UNSAFE_PATH', 'Storage directory is a link.');
  }
}

Future<void> ensurePlainFile(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const StorageException(
      'RECOVERY_INCONSISTENT',
      'Storage file missing.',
    );
  }
}

/// Checks every managed directory component before touching a file. The alpha
/// assumes the app-private storage root is not concurrently modified by a
/// hostile local process; native handle-relative APIs are needed to remove
/// that assumption entirely.
Future<void> validateManagedDirectory(
  Directory root,
  Directory directory, {
  bool create = false,
}) async {
  final absolute = p.normalize(p.absolute(directory.path));
  // p.equals/p.isWithin compare case-insensitively on Windows.
  if (!p.equals(absolute, root.path)) requireContainedPath(root, absolute);
  if (await FileSystemEntity.type(root.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const StorageException(
      'UNSAFE_PATH',
      'Storage root is not a directory.',
    );
  }
  var current = root.path;
  final relative = p.relative(absolute, from: root.path);
  if (relative == '.') return;
  for (final component in p.split(relative)) {
    current = p.join(current, component);
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.notFound && create) {
      await Directory(current).create();
    } else if (type != FileSystemEntityType.directory) {
      throw const StorageException(
        'UNSAFE_PATH',
        'Managed parent is not a plain directory.',
      );
    }
  }
}

void requireContainedPath(Directory root, String target) {
  if (!p.isWithin(root.path, p.normalize(p.absolute(target)))) {
    throw const StorageException('UNSAFE_PATH', 'Path escapes storage root.');
  }
}

/// This name is used only inside a private, per-file directory. Wire names are
/// never used as directory paths. This is not a replacement for native
/// no-follow/no-replace filesystem primitives on hostile shared directories.
String safeDisplayName(String input) {
  var name = sanitizeDisplayText(input);
  // `& ^ % !` are shell metacharacters for `cmd /c start`-style launchers on
  // Windows; they are never needed in a locally stored name.
  name = name.replaceAll(RegExp(r'[<>:"/\\|?*&^%!\x00-\x1f\x7f]'), '_');
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty || name == '.' || name == '..') name = 'file';
  // Windows ignores trailing spaces before the extension: `CON .txt` is CON.
  final stem = name
      .split('.')
      .first
      .replaceAll(RegExp(r' +$'), '')
      .toUpperCase();
  if (RegExp(r'^(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[0-9¹²³]|LPT[0-9¹²³])$')
      .hasMatch(stem)) {
    name = '_$name';
  }
  // Keep names short enough for common Windows application data paths. The
  // original display name remains in the manifest/history.
  if (utf8.encode(name).length > 100) {
    final extension = p.extension(name);
    final suffix = utf8.encode(extension).length <= 20 ? extension : '';
    final limit = 100 - utf8.encode(suffix).length;
    final result = StringBuffer();
    var bytes = 0;
    final base = suffix.isEmpty
        ? name
        : name.substring(0, name.length - suffix.length);
    for (final rune in base.runes) {
      final text = String.fromCharCode(rune);
      final length = utf8.encode(text).length;
      if (bytes + length > limit) break;
      result.write(text);
      bytes += length;
    }
    name = '${result.toString().replaceAll(RegExp(r'[. ]+$'), '')}$suffix';
    if (name.isEmpty) name = 'file';
  }
  return name;
}

/// Stored journal paths are relative to the store root and always use `/`.
/// The application container path can change between launches (iOS updates,
/// device restore), so an absolute path must never be persisted.
String toStoredPath(Directory root, String absolute) {
  final normalized = p.normalize(p.absolute(absolute));
  requireContainedPath(root, normalized);
  return p.split(p.relative(normalized, from: root.path)).join('/');
}

/// Resolves a stored relative path. A legacy absolute path from an older
/// journal is rebased by its managed suffix (see [rebaseLegacyPath]).
String resolveStoredPath(
  Directory root,
  String stored, {
  required Set<String> managedTopLevel,
}) {
  final relative = p.isAbsolute(stored) || stored.startsWith('/')
      ? rebaseLegacyPath(stored, managedTopLevel: managedTopLevel)
      : stored;
  if (relative == null) {
    throw const StorageException('UNSAFE_PATH', 'Unrecognised stored path.');
  }
  final parts = relative.split('/');
  if (parts.isEmpty ||
      !managedTopLevel.contains(parts.first) ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const StorageException('UNSAFE_PATH', 'Unsafe stored path.');
  }
  final absolute = p.joinAll([root.path, ...parts]);
  requireContainedPath(root, absolute);
  return absolute;
}

/// Converts `/old/container/…/inbox/received/t/i/name` into
/// `received/t/i/name` by locating the last managed top-level component.
/// Returns null when no managed component is present.
String? rebaseLegacyPath(
  String absolute, {
  required Set<String> managedTopLevel,
}) {
  // Old journals may come from another platform style only in tests; accept
  // both separators but never `..` components.
  final parts = absolute
      .split(RegExp(r'[/\\]'))
      .where((part) => part.isNotEmpty)
      .toList();
  for (var index = parts.length - 2; index >= 0; index--) {
    if (managedTopLevel.contains(parts[index])) {
      final suffix = parts.sublist(index);
      if (suffix.any((part) => part == '.' || part == '..')) return null;
      return suffix.join('/');
    }
  }
  return null;
}

/// Opens a durable WAL journal and applies numbered, idempotent migrations.
///
/// `PRAGMA user_version` stores the applied schema level. Every migration step
/// must be safe to re-run because 0.1–0.3 journals have version 0. A database
/// from a newer app version fails with `JOURNAL_TOO_NEW`; a damaged file fails
/// with `JOURNAL_CORRUPT` so the application can offer an explicit recovery
/// (see [quarantineJournalFiles]) instead of silently recreating state.
Database openJournal(
  File file, {
  int version = 0,
  void Function(Database db, int fromVersion)? migrate,
}) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const StorageException('UNSAFE_PATH', 'Journal cannot be a link.');
  }
  final Database db;
  try {
    db = sqlite3.open(file.path);
  } on SqliteException catch (error) {
    throw _journalOpenError(error);
  }
  try {
    db.execute('PRAGMA busy_timeout=5000');
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute('PRAGMA foreign_keys=ON');
    final mode = db.select('PRAGMA journal_mode').first.values.first;
    final sync = db.select('PRAGMA synchronous').first.values.first;
    if (mode.toString().toLowerCase() != 'wal' || sync != 2) {
      throw const StorageException(
        'STORAGE_FAILURE',
        'Durability settings unavailable.',
      );
    }
    final check = db.select('PRAGMA quick_check');
    if (check.length != 1 || check.first.values.first != 'ok') {
      throw const StorageException(
        'JOURNAL_CORRUPT',
        'The local journal is damaged.',
      );
    }
    final current = db.select('PRAGMA user_version').first.values.first as int;
    if (current > version) {
      throw const StorageException(
        'JOURNAL_TOO_NEW',
        'The local journal was created by a newer version of the app.',
      );
    }
    if (migrate != null) {
      journalTransaction(db, () {
        migrate(db, current);
        if (current != version) db.execute('PRAGMA user_version=$version');
      });
    }
    return db;
  } on SqliteException catch (error) {
    db.close();
    throw _journalOpenError(error);
  } catch (_) {
    db.close();
    rethrow;
  }
}

StorageException _journalOpenError(SqliteException error) {
  // SQLITE_CORRUPT (11) and SQLITE_NOTADB (26).
  if (error.resultCode == 11 || error.resultCode == 26) {
    return const StorageException(
      'JOURNAL_CORRUPT',
      'The local journal is damaged.',
    );
  }
  if (error.resultCode == 13) {
    return const StorageException('DISK_FULL', 'Storage is full.');
  }
  return const StorageException(
    'STORAGE_FAILURE',
    'Journal could not be opened.',
  );
}

/// Moves a damaged journal and its WAL/SHM side files aside, keeping them for
/// diagnosis. Payload files are not touched. The caller must have closed the
/// store (a failed open has already released it). Returns the moved paths.
Future<List<String>> quarantineJournalFiles(File journal) async {
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[^0-9TZ]'),
    '',
  );
  final moved = <String>[];
  for (final suffix in ['', '-wal', '-shm']) {
    final source = '${journal.path}$suffix';
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type != FileSystemEntityType.file) {
      throw const StorageException(
        'UNSAFE_PATH',
        'Journal side file is not a plain file.',
      );
    }
    final target = '${journal.path}.corrupt-$stamp$suffix';
    await File(source).rename(target);
    moved.add(target);
  }
  return moved;
}

/// Public name for application journals: versioned, WAL + FULL, quick_check,
/// `JOURNAL_CORRUPT` / `JOURNAL_TOO_NEW` (see [openJournal]).
Database openVersionedJournal(
  File file, {
  required int version,
  required void Function(Database db, int fromVersion) migrate,
}) => openJournal(file, version: version, migrate: migrate);

/// Moves one damaged journal (and its WAL/SHM files) aside; see
/// [quarantineJournalFiles]. The caller must have closed the database.
Future<List<String>> quarantineJournalFile(File journal) =>
    quarantineJournalFiles(journal);

T journalTransaction<T>(Database db, T Function() body) {
  db.execute('BEGIN IMMEDIATE');
  try {
    final value = body();
    db.execute('COMMIT');
    return value;
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

class DigestCollector implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Future<String> hashStoredFile(File file, {void Function()? check}) async {
  final result = DigestCollector();
  final digest = sha256.startChunkedConversion(result);
  await for (final bytes in file.openRead()) {
    check?.call();
    digest.add(bytes);
  }
  digest.close();
  check?.call();
  return result.value!.toString();
}

/// Streams a file through SHA-256 in a background isolate so large files
/// never block the caller's event loop (the UI isolate in the app). [check] is
/// polled while hashing; when it throws, the isolate is killed and the error
/// is rethrown.
Future<String> hashFileIsolated(
  File file, {
  void Function()? check,
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  check?.call();
  final result = await _runFileWorker(
    _FileJob(kind: _FileJobKind.hash, source: file.path),
    check: check,
    pollInterval: pollInterval,
  );
  check?.call();
  return result.sha256;
}

/// Copies [source] to [destination] (which must exist and be empty) while
/// hashing, in a background isolate. Fails with `SOURCE_CHANGED` when more
/// than [maxBytes] are read. Returns the copied length and SHA-256.
Future<({int length, String sha256})> copyAndHashIsolated(
  File source,
  File destination, {
  required int maxBytes,
  void Function(int bytes)? onProgress,
  void Function()? check,
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  check?.call();
  final result = await _runFileWorker(
    _FileJob(
      kind: _FileJobKind.copy,
      source: source.path,
      destination: destination.path,
      maxBytes: maxBytes,
    ),
    check: check,
    onProgress: onProgress,
    pollInterval: pollInterval,
  );
  check?.call();
  return (length: result.length, sha256: result.sha256);
}

enum _FileJobKind { hash, copy }

final class _FileJob {
  const _FileJob({
    required this.kind,
    required this.source,
    this.destination,
    this.maxBytes = 0,
  });
  final _FileJobKind kind;
  final String source;
  final String? destination;
  final int maxBytes;
}

/// Runs [job] in a background isolate. Cancellation (a throwing [check]) is
/// cooperative: the worker is asked to stop, closes its file handles and
/// exits, and only then does this future fail. Callers may therefore delete
/// the files right away (Windows refuses to delete open files). A worker
/// that does not stop within 10 s is killed as a last resort.
Future<({int length, String sha256})> _runFileWorker(
  _FileJob job, {
  void Function()? check,
  void Function(int bytes)? onProgress,
  required Duration pollInterval,
}) async {
  final port = ReceivePort();
  final errors = ReceivePort();
  final exits = ReceivePort();
  final exited = Completer<void>();
  final cancelRequested = Completer<void>();
  ({int length, String sha256})? value;
  Object? failure;
  SendPort? control;
  Isolate? isolate;
  Timer? poller;

  void cancel(Object error) {
    if (cancelRequested.isCompleted) return;
    failure = error;
    control?.send('cancel');
    cancelRequested.complete();
  }

  port.listen((message) {
    if (message is SendPort) {
      control = message;
      if (cancelRequested.isCompleted) message.send('cancel');
    } else if (message is int) {
      if (!cancelRequested.isCompleted) onProgress?.call(message);
    } else if (message is List && message.length == 2) {
      value = (length: message[0] as int, sha256: message[1] as String);
    } else if (message is List && message.length == 3) {
      failure ??= StorageException(message[1] as String, message[2] as String);
    }
  });
  errors.listen((_) {
    failure ??= const StorageException(
      'STORAGE_FAILURE',
      'Background file operation failed.',
    );
  });
  exits.listen((_) {
    if (!exited.isCompleted) exited.complete();
  });
  try {
    isolate = await Isolate.spawn(
      _fileWorker,
      (port.sendPort, job),
      onError: errors.sendPort,
      onExit: exits.sendPort,
      errorsAreFatal: true,
    );
    if (check != null) {
      poller = Timer.periodic(pollInterval, (_) {
        try {
          check();
        } catch (error) {
          poller?.cancel();
          cancel(error);
        }
      });
    }
    await Future.any([exited.future, cancelRequested.future]);
    if (!exited.isCompleted) {
      // Cancelled: wait for the worker to close its files and exit.
      await exited.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () async {
          isolate?.kill(priority: Isolate.immediate);
          await exited.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
        },
      );
    }
    if (value == null && failure == null) {
      // The exit notice uses another port; let a pending result land.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  } finally {
    poller?.cancel();
    port.close();
    errors.close();
    exits.close();
  }
  final error = failure;
  if (error != null) throw error;
  final result = value;
  if (result == null) {
    throw const StorageException(
      'STORAGE_FAILURE',
      'Background file operation stopped.',
    );
  }
  return result;
}

/// Reads with an explicit handle (not a stream) so that every exit path,
/// including cancellation, closes the files before the result is reported.
Future<void> _fileWorker((SendPort, _FileJob) message) async {
  final (reply, job) = message;
  final control = ReceivePort();
  var cancelled = false;
  control.listen((_) => cancelled = true);
  reply.send(control.sendPort);
  RandomAccessFile? input;
  RandomAccessFile? output;
  Object response;
  try {
    input = await File(job.source).open();
    if (job.kind == _FileJobKind.copy) {
      output = await File(job.destination!).open(mode: FileMode.write);
    }
    final collector = DigestCollector();
    final digest = sha256.startChunkedConversion(collector);
    var length = 0;
    var reported = 0;
    Object? stopped;
    while (true) {
      if (cancelled) {
        stopped = [0, 'PREPARATION_CANCELLED', 'Preparation cancelled.'];
        break;
      }
      final chunk = await input.read(1024 * 1024);
      if (chunk.isEmpty) break;
      length += chunk.length;
      if (job.kind == _FileJobKind.copy && length > job.maxBytes) {
        stopped = [
          0,
          'SOURCE_CHANGED',
          'Source length changed during preparation.',
        ];
        break;
      }
      digest.add(chunk);
      await output?.writeFrom(chunk);
      if (length - reported >= 4 * 1024 * 1024) {
        reported = length;
        reply.send(length);
      }
    }
    if (stopped != null) {
      response = stopped;
    } else {
      digest.close();
      await output?.flush();
      reply.send(length);
      response = [length, collector.value!.toString()];
    }
  } on FileSystemException catch (error) {
    final mapped = storageIoError(error);
    response = [0, mapped.code, mapped.message];
  } finally {
    try {
      await input?.close();
    } catch (_) {
      /* Already closed. */
    }
    try {
      await output?.close();
    } catch (_) {
      /* Already closed. */
    }
    control.close();
  }
  reply.send(response);
}

/// OS error numbers that mean "no space" (or per-user quota) differ per OS.
/// Linux/Android: ENOSPC 28, EDQUOT 122. Apple: ENOSPC 28, EDQUOT 69.
/// Windows: ERROR_HANDLE_DISK_FULL 39, ERROR_DISK_FULL 112.
bool isDiskFullErrorCode(int? code, {String? operatingSystem}) {
  if (code == null) return false;
  final os = operatingSystem ?? Platform.operatingSystem;
  return switch (os) {
    'windows' => code == 39 || code == 112,
    'macos' || 'ios' => code == 28 || code == 69,
    _ => code == 28 || code == 122,
  };
}

StorageException storageIoError(Object error) {
  if (error is StorageException) return error;
  if (error is FileSystemException) {
    return StorageException(
      isDiskFullErrorCode(error.osError?.errorCode)
          ? 'DISK_FULL'
          : 'STORAGE_FAILURE',
      'File operation failed.',
    );
  }
  if (error is SqliteException) {
    // SQLITE_FULL (13): the journal could not grow.
    if (error.resultCode == 13) {
      return const StorageException('DISK_FULL', 'Storage is full.');
    }
    return const StorageException(
      'STORAGE_FAILURE',
      'Journal operation failed.',
    );
  }
  return const StorageException(
    'TRANSFER_INTERRUPTED',
    'Input stream interrupted.',
  );
}
