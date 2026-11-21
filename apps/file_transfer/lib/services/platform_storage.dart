import 'dart:io';

import 'package:flutter/services.dart';

/// A completed system export. A provider reference is local history only; it
/// is not a portable filesystem path or proof of remote/cloud synchronization.
class NativeExportResult {
  const NativeExportResult({
    required this.destinationLabel,
    this.platformReference,
  });

  final String destinationLabel;
  final String? platformReference;
}

/// Narrow native boundary for volume capacity and explicit "Save a copy".
/// File bytes never cross the Flutter method channel. Native implementations
/// use a bounded copy or the operating system's document export facility.
abstract final class PlatformStorage {
  static const channel = MethodChannel('file_transfer/storage');

  static bool get supportsExport =>
      Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  /// Returns null when the operating system cannot provide a measurement.
  /// Neither an unknown result nor a native failure is converted to free bytes.
  static Future<int?> freeBytes(Directory directory) async {
    try {
      final value = await channel.invokeMethod<Object?>('freeBytes', {
        'path': directory.absolute.path,
      });
      if (value == null) return null;
      if (value is! int || value < 0) {
        throw const FormatException('Invalid native storage capacity.');
      }
      return value;
    } on MissingPluginException {
      // Linux is a development target with no storage adapter in this release.
      return null;
    } on PlatformException catch (error) {
      if (error.code == 'STORAGE_UNAVAILABLE') return null;
      rethrow;
    }
  }

  /// Keeps a managed directory (staging parts, prepared outgoing copies,
  /// received files) out of iCloud/iTunes backups. iOS only; other platforms
  /// exclude app data through their own manifests and return true. Returns
  /// false when the native adapter could not apply the flag; callers may retry
  /// on the next launch but must not treat this as a fatal storage error.
  /// iOS keeps the flag on the directory, so it must be applied again only if
  /// the directory is deleted and recreated.
  static Future<bool> excludeFromBackup(Directory directory) async {
    if (!Platform.isIOS) return true;
    try {
      final value = await channel.invokeMethod<bool>('excludeFromBackup', {
        'path': directory.absolute.path,
      });
      return value ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Asks iOS for a short grace period after the app leaves the foreground
  /// (typically up to ~30 s) to flush the current chunk and journal. Returns
  /// a task id to pass to [endBackgroundTask], or null when no time was
  /// granted or on other platforms. This never makes a transfer continue in
  /// the background. Listen to [onBackgroundTaskExpired] to stop promptly.
  static Future<int?> beginBackgroundTask() async {
    if (!Platform.isIOS) return null;
    try {
      return await channel.invokeMethod<int>('beginBackgroundTask');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Ends a grace period started by [beginBackgroundTask]. Safe to call with
  /// null or an id that has already expired.
  static Future<void> endBackgroundTask(int? id) async {
    if (id == null || !Platform.isIOS) return;
    try {
      await channel.invokeMethod<void>('endBackgroundTask', {'id': id});
    } on MissingPluginException {
      // Nothing to end.
    } on PlatformException {
      // The task already expired or was ended.
    }
  }

  /// Registers a callback for iOS grace-period expiry (argument: task id).
  /// The native side has already ended the task when this fires. Only one
  /// handler is kept; pass null to remove it.
  static void onBackgroundTaskExpired(void Function(int id)? handler) {
    channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method == 'backgroundTaskExpired' &&
                  call.arguments is int) {
                handler(call.arguments as int);
              }
              return null;
            },
    );
  }

  /// The caller must already have validated the committed receive record and
  /// source file. A null result is user cancellation, never successful export.
  /// Native adapters independently reject sources outside managed received data.
  static Future<NativeExportResult?> exportFile({
    required File source,
    required String displayName,
    String? mimeType,
  }) async {
    if (displayName.isEmpty ||
        displayName.length > 255 ||
        displayName == '.' ||
        displayName == '..' ||
        RegExp(r'[\x00-\x1f/\\]').hasMatch(displayName)) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'Invalid filename.',
      );
    }
    if (mimeType != null &&
        !RegExp(r'^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$')
            .hasMatch(mimeType)) {
      throw ArgumentError.value(mimeType, 'mimeType', 'Invalid MIME type.');
    }
    final value = await channel.invokeMethod<Object?>('exportFile', {
      'sourcePath': source.absolute.path,
      'displayName': displayName,
      'mimeType': ?mimeType,
    });
    if (value == null) return null;
    if (value is! Map || value['status'] != 'exported') {
      throw const FormatException('Native export did not confirm completion.');
    }
    final label = value['destinationLabel'];
    final reference = value['platformReference'];
    if (label is! String ||
        label.trim().isEmpty ||
        label.length > 4096 ||
        (reference != null &&
            (reference is! String ||
                reference.isEmpty ||
                reference.length > 32768))) {
      throw const FormatException('Invalid native export receipt.');
    }
    return NativeExportResult(
      destinationLabel: label,
      platformReference: reference as String?,
    );
  }
}
