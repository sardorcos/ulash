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
