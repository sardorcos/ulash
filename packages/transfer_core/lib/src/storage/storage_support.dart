import 'dart:convert';
import 'dart:io';

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
  if (absolute != root.path) requireContainedPath(root, absolute);
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
  var name = input.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_');
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty || name == '.' || name == '..') name = 'file';
  final stem = name.split('.').first.toUpperCase();
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])$').hasMatch(stem)) {
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
  }
  return name;
}

Database openJournal(File file) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw const StorageException('UNSAFE_PATH', 'Journal cannot be a link.');
  }
  final db = sqlite3.open(file.path);
  try {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('PRAGMA busy_timeout=5000');
    final mode = db.select('PRAGMA journal_mode').first.values.first;
    final sync = db.select('PRAGMA synchronous').first.values.first;
    if (mode.toString().toLowerCase() != 'wal' || sync != 2) {
      throw const StorageException(
        'STORAGE_FAILURE',
        'Durability settings unavailable.',
      );
    }
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

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

StorageException storageIoError(Object error) {
  if (error is StorageException) return error;
  if (error is FileSystemException) {
    return StorageException(
      error.osError?.errorCode == 28 || error.osError?.errorCode == 112
          ? 'DISK_FULL'
          : 'STORAGE_FAILURE',
      'File operation failed.',
    );
  }
  if (error is SqliteException) {
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
