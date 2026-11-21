import 'dart:io';

import 'package:flutter/services.dart';

abstract final class PlatformPermissions {
  static const _channel = MethodChannel('uz.sardor.file_transfer/permissions');

  /// Android 17+ local-network access is requested using the platform API.
  /// iOS prompts through Bonjour/network access; never pretend a denial means
  /// that another device is offline.
  static Future<bool> ensureLocalNetwork() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('ensureLocalNetwork') ?? false;
  }
}
