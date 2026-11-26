import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// A file handed to Ulash by another app ("Share → Ulash", "Open in Ulash",
/// Android share/open intents). [path] is a copy inside the app's own cache;
/// the caller stages (adopts) it and may delete it afterwards. The user's
/// original is never touched.
class IntakeItem {
  const IntakeItem({required this.path, required this.name});
  final String path;
  final String name;
}

/// Result of [NativeBridge.saveToPhotos].
enum SaveToPhotosResult { saved, denied, failed, unsupported }

/// Result of [NativeBridge.openFileSafely] on Windows.
enum OpenFileResult {
  opened,

  /// An executable/script type was refused; the caller should warn the user
  /// and offer "Show in folder" instead.
  blocked,
  missing,
  failed,
  unsupported,
}

/// Thin, failure-tolerant wrappers over the native channels added in 1.2.
/// Every method degrades to a safe default when the platform has no adapter
/// (MissingPluginException) or the native side reports an error.
abstract final class NativeBridge {
  static const _intake = MethodChannel('file_transfer/intake');
  static const _device = MethodChannel('file_transfer/device');
  static const _desktop = MethodChannel('file_transfer/desktop');

  static final _intakeController = StreamController<void>.broadcast(
    onListen: _listenIntake,
  );
  static bool _intakeListening = false;

  /// Fires when new shared/opened files may be waiting; call [takePendingIntake].
  static Stream<void> get intakeAvailable => _intakeController.stream;

  static void _listenIntake() {
    if (_intakeListening) return;
    _intakeListening = true;
    _intake.setMethodCallHandler((call) async {
      if (call.method == 'intakeAvailable') _intakeController.add(null);
      return null;
    });
  }

  static bool get supportsIntake => Platform.isIOS || Platform.isAndroid;

  /// Returns each pending item exactly once (iOS/Android); empty elsewhere.
  static Future<List<IntakeItem>> takePendingIntake() async {
    if (!supportsIntake) return const [];
    try {
      final raw = await _intake.invokeListMethod<Object?>('takePending');
      return [
        for (final item in raw ?? const <Object?>[])
          if (item is Map &&
              item['path'] is String &&
              (item['path'] as String).isNotEmpty)
            IntakeItem(
              path: item['path'] as String,
              name: item['name'] is String && (item['name'] as String).isNotEmpty
                  ? item['name'] as String
                  : (item['path'] as String).split(Platform.pathSeparator).last,
            ),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<int> pendingIntakeCount() async {
    if (!supportsIntake) return 0;
    try {
      return await _intake.invokeMethod<int>('pendingCount') ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  static bool get supportsSaveToPhotos => Platform.isIOS || Platform.isAndroid;

  /// Adds a received photo or video to the system gallery (iOS add-only
  /// permission; Android MediaStore Pictures|Movies/Ulash, no permission).
  static Future<SaveToPhotosResult> saveToPhotos(
    File file, {
    required bool isVideo,
  }) async {
    if (!supportsSaveToPhotos) return SaveToPhotosResult.unsupported;
    try {
      final value = await _device.invokeMethod<String>('saveToPhotos', {
        'path': file.absolute.path,
        'kind': isVideo ? 'video' : 'image',
      });
      return switch (value) {
        'saved' => SaveToPhotosResult.saved,
        'denied' => SaveToPhotosResult.denied,
        _ => SaveToPhotosResult.failed,
      };
    } on MissingPluginException {
      return SaveToPhotosResult.unsupported;
    } on PlatformException {
      return SaveToPhotosResult.failed;
    }
  }

  /// Hides the screen from screenshots/recordings and the app switcher
  /// (Android FLAG_SECURE) or blurs it in the app switcher (iOS) while a
  /// pairing QR code is visible. No-op elsewhere.
  static Future<void> setSecureScreen(bool enabled) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      await _device.invokeMethod<bool>('setSecureScreen', {'enabled': enabled});
    } on MissingPluginException {
      // Older native shell: nothing to do.
    } on PlatformException {
      // Best effort.
    }
  }

  /// Copies a secret-bearing text (a pairing invitation) so that it stays on
  /// this device (iOS: local-only, expires; Android: marked sensitive, cleared
  /// later). Returns false when the native path is unavailable; the caller
  /// may then fall back to [Clipboard.setData] and clear it itself.
  static Future<bool> copySensitive(String text, {int seconds = 120}) async {
    if (!Platform.isIOS && !Platform.isAndroid) return false;
    try {
      return await _device.invokeMethod<bool>('copySensitive', {
            'text': text,
            'seconds': seconds,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Windows: opens a file with its associated application through
  /// ShellExecuteEx (never cmd.exe). Executable, script, installer, disk
  /// image and shortcut types (a superset of core's isPotentiallyExecutable)
  /// are refused unless [allowExecutable] is true. Other platforms: [OpenFileResult.unsupported].
  static Future<OpenFileResult> openFileSafely(
    File file, {
    bool allowExecutable = false,
  }) async {
    if (!Platform.isWindows) return OpenFileResult.unsupported;
    try {
      final value = await _desktop.invokeMethod<String>('openFile', {
        'path': file.absolute.path,
        'allowExecutable': allowExecutable,
      });
      return switch (value) {
        'opened' => OpenFileResult.opened,
        'blocked' => OpenFileResult.blocked,
        'missing' => OpenFileResult.missing,
        _ => OpenFileResult.failed,
      };
    } on MissingPluginException {
      return OpenFileResult.unsupported;
    } on PlatformException {
      return OpenFileResult.failed;
    }
  }

  /// Windows: shows the file selected in Explorer.
  static Future<bool> revealInFolder(File file) async {
    if (!Platform.isWindows) return false;
    try {
      return await _desktop.invokeMethod<bool>('revealInFolder', {
            'path': file.absolute.path,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Windows: writes the Mark-of-the-Web (Zone.Identifier, ZoneId=3) so that
  /// SmartScreen/Office treat a received file as downloaded. True elsewhere
  /// (no equivalent needed); false when the volume does not support streams.
  static Future<bool> markFromInternet(File file) async {
    if (!Platform.isWindows) return true;
    try {
      return await _desktop.invokeMethod<bool>('markFromInternet', {
            'path': file.absolute.path,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Windows: %LOCALAPPDATA%\Ulash (created). Null elsewhere, on failure and
  /// when running as an MSIX package (AppData is virtualised there and there
  /// is no 1.0 Roaming data to migrate); callers then keep using the
  /// platform's application-support directory.
  static Future<Directory?> localDataDirectory() async {
    if (!Platform.isWindows) return null;
    return _desktopDirectory('localDataDirectory');
  }

  /// Windows: the user's Downloads folder (for visible received files).
  static Future<Directory?> downloadsDirectory() async {
    if (!Platform.isWindows) return null;
    return _desktopDirectory('downloadsDirectory');
  }

  static Future<Directory?> _desktopDirectory(String method) async {
    try {
      final path = await _desktop.invokeMethod<String>(method);
      return path == null || path.isEmpty ? null : Directory(path);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
