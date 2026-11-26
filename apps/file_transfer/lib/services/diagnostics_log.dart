import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Small local diagnostics journal. It never leaves the device unless the user
/// explicitly shares it. Entries contain error types and protocol codes only:
/// no file names, paths, tokens, invitations or device names.
class DiagnosticsLog {
  DiagnosticsLog._();
  static final instance = DiagnosticsLog._();

  static const _maxBytes = 512 * 1024;
  final _memory = ListQueue<String>();
  File? _file;
  Future<void> _tail = Future.value();

  /// Attach the persistent file. Earlier in-memory entries are flushed.
  Future<void> attach(Directory directory) async {
    try {
      await directory.create(recursive: true);
      _file = File(p.join(directory.path, 'diagnostics.log'));
      final pending = _memory.toList();
      for (final line in pending) {
        _append(line);
      }
    } catch (_) {
      _file = null;
    }
  }

  File? get file => _file;

  /// Waits for queued writes, then stops writing into [directory] (the app's
  /// data folder is closing). Later entries stay in memory only.
  Future<void> detach(Directory directory) async {
    await _tail;
    final current = _file;
    if (current != null && p.isWithin(directory.path, current.path)) {
      _file = null;
    }
  }

  void info(String event) => _record('I', event);

  void error(String context, Object error, [StackTrace? stack]) {
    final code = errorCode(error);
    final frame = stack == null ? '' : ' @ ${_firstFrame(stack)}';
    _record(
      'E',
      '$context: ${error.runtimeType}${code == null ? '' : ' [$code]'}$frame',
    );
  }

  void _record(String level, String event) {
    final line =
        '${DateTime.now().toUtc().toIso8601String()} $level ${_scrub(event)}';
    _memory.add(line);
    while (_memory.length > 200) {
      _memory.removeFirst();
    }
    if (_file != null) _append(line);
  }

  void _append(String line) {
    final file = _file;
    if (file == null) return;
    _tail = _tail.then((_) async {
      try {
        if (await file.exists() && await file.length() > _maxBytes) {
          final previous = File('${file.path}.1');
          if (await previous.exists()) await previous.delete();
          await file.rename(previous.path);
        }
        await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      } catch (_) {
        /* Diagnostics must never break the app. */
      }
    });
  }

  /// Returns a snapshot suitable for sharing (current + previous file).
  Future<File?> exportSnapshot(Directory into) async {
    await _tail;
    try {
      await into.create(recursive: true);
      final out = File(p.join(into.path, 'ulash-diagnostics.txt'));
      final sink = out.openWrite();
      final current = _file;
      if (current != null) {
        final previous = File('${current.path}.1');
        if (await previous.exists()) await sink.addStream(previous.openRead());
        if (await current.exists()) await sink.addStream(current.openRead());
      } else {
        sink.writeln(_memory.join('\n'));
      }
      await sink.close();
      return out;
    } catch (_) {
      return null;
    }
  }

  static String? errorCode(Object error) {
    try {
      final dynamic value = error;
      final code = value.code;
      return code is String ? code : null;
    } catch (_) {
      return null;
    }
  }

  static String _firstFrame(StackTrace stack) {
    final line = stack
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.contains('package:file_transfer') ||
              line.contains('package:transfer_core'),
        )
        .firstOrNull;
    if (line == null) return '?';
    final match = RegExp(r'\((package:[^)]+)\)').firstMatch(line);
    return match?.group(1) ?? '?';
  }

  // Remove anything that looks like a path, URL, address or long token.
  static String _scrub(String text) => text
      .replaceAll(RegExp(r'[A-Za-z]:\\[^\s]*'), '<path>')
      .replaceAll(RegExp(r'(?<![A-Za-z:])/[^\s]*/[^\s]*'), '<path>')
      .replaceAll(RegExp(r'[a-z]+://[^\s]+'), '<uri>')
      .replaceAll(RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b'), '<ip>')
      .replaceAll(RegExp(r'[A-Za-z0-9_\-+/=]{32,}'), '<redacted>');
}
