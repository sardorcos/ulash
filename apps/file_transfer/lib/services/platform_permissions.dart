import 'dart:io';

import 'package:flutter/services.dart';

/// What the operating system reports about Local Network access.
///
/// [denied] is returned only when the platform positively reports a refusal.
/// [unknown] covers "not asked yet", "still deciding" and probes that cannot
/// tell; it must never be presented to the user as a denial.
enum LocalNetworkStatus { granted, denied, unknown }

abstract final class PlatformPermissions {
  static const _channel = MethodChannel('uz.sardor.file_transfer/permissions');
  static const _networkChannel = MethodChannel('file_transfer/network');

  /// Android 17+ local-network access is requested using the platform API.
  /// iOS prompts through Bonjour/network access; never pretend a denial means
  /// that another device is offline.
  static Future<bool> ensureLocalNetwork() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('ensureLocalNetwork') ?? false;
  }

  /// Reads the current Local Network decision without asking for it on
  /// Android. On iOS the probe is a short Bonjour browse (about 2.5 s), which
  /// shows the system prompt on first use. Re-query after the app returns to
  /// the foreground: the user may answer the prompt or change Settings.
  static Future<LocalNetworkStatus> localNetworkStatus() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return LocalNetworkStatus.granted;
    }
    try {
      final channel = Platform.isIOS ? _networkChannel : _channel;
      final value = await channel.invokeMethod<String>('localNetworkStatus');
      return switch (value) {
        'granted' => LocalNetworkStatus.granted,
        'denied' => LocalNetworkStatus.denied,
        _ => LocalNetworkStatus.unknown,
      };
    } on MissingPluginException {
      return LocalNetworkStatus.unknown;
    } on PlatformException {
      return LocalNetworkStatus.unknown;
    }
  }

  /// Opens this app's page in the system Settings. Returns false when the
  /// platform cannot open it (desktop, or the native adapter failed).
  static Future<bool> openSettings() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      final channel = Platform.isIOS ? _networkChannel : _channel;
      return await channel.invokeMethod<bool>('openSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
