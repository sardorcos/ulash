import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:transfer_core/transfer_core.dart';

import 'lan_discovery.dart';
import 'network_retry_policy.dart';
import 'os_secret_store.dart';
import 'platform_permissions.dart';
import 'platform_storage.dart';

typedef ExportFileCallback = Future<NativeExportResult?> Function({
  required File source,
  required String displayName,
  String? mimeType,
});

/// Explicit platform boundary. Native launches use OS-protected credentials;
/// integration tests supply an isolated directory and temporary in-memory keys.
class AppRuntime {
  AppRuntime({
    required this.secrets,
    required this.storageDirectory,
    required this.ensurePermission,
    required this.addresses,
    required this.listenAddress,
    this.listenPort = 0,
    this.discoveryEnabled = false,
    this.mobileLifecycle = false,
    this.initialDeviceName,
    this.availableBytes,
    this.exportFile,
    this.exportSupported = false,
    this.retryPolicy,
    this.retryDelay,
    this.resetSecrets,
    this.versionLabel,
    this.defaultDeviceName,
    this.localNetworkDenied,
    this.openSystemSettings,
    this.setKeepAwake,
    this.beginBackgroundTask,
    this.endBackgroundTask,
    this.backgroundGrace = Duration.zero,
    this.temporaryDirectory,
    this.requireOnboarding = false,
    this.mediaPicker = false,
    this.shareFiles,
    this.excludeFromBackup,
    this.listenBackgroundExpiry,
    this.systemLocale,
  });

  factory AppRuntime.native() => AppRuntime(
    secrets: const OsSecretStore(),
    storageDirectory: getApplicationSupportDirectory,
    ensurePermission: PlatformPermissions.ensureLocalNetwork,
    addresses: localIpv4Addresses,
    listenAddress: InternetAddress.anyIPv4,
    listenPort: 53318,
    discoveryEnabled: true,
    mobileLifecycle: Platform.isAndroid || Platform.isIOS,
    availableBytes: PlatformStorage.freeBytes,
    exportFile: PlatformStorage.exportFile,
    exportSupported: PlatformStorage.supportsExport,
    resetSecrets: const OsSecretStore().deleteAll,
    versionLabel: _nativeVersionLabel,
    defaultDeviceName: _nativeDeviceName,
    setKeepAwake: (enabled) async {
      try {
        await WakelockPlus.toggle(enable: enabled);
      } catch (_) {
        /* Keeping the screen on is a convenience, not a guarantee. */
      }
    },
    backgroundGrace: Platform.isAndroid || Platform.isIOS
        ? const Duration(seconds: 20)
        : Duration.zero,
    temporaryDirectory: getTemporaryDirectory,
    requireOnboarding: true,
    mediaPicker: Platform.isAndroid || Platform.isIOS,
    localNetworkDenied: () async =>
        switch (await PlatformPermissions.localNetworkStatus()) {
          LocalNetworkStatus.denied => true,
          LocalNetworkStatus.granted => false,
          LocalNetworkStatus.unknown => null,
        },
    openSystemSettings: () async {
      await PlatformPermissions.openSettings();
    },
    excludeFromBackup: PlatformStorage.excludeFromBackup,
    beginBackgroundTask: PlatformStorage.beginBackgroundTask,
    endBackgroundTask: (token) =>
        PlatformStorage.endBackgroundTask(token is int ? token : null),
    systemLocale: () => PlatformDispatcher.instance.locale,
    listenBackgroundExpiry: (onExpired) =>
        PlatformStorage.onBackgroundTaskExpired((_) => onExpired()),
    shareFiles: Platform.isAndroid || Platform.isIOS
        ? (files) async {
            await SharePlus.instance.share(
              ShareParams(files: [for (final file in files) XFile(file.path)]),
            );
          }
        : null,
  );

  final SecretStore secrets;
  final Future<Directory> Function() storageDirectory;
  final Future<bool> Function() ensurePermission;
  final Future<List<String>> Function() addresses;
  final InternetAddress listenAddress;
  final int listenPort;
  final bool discoveryEnabled;
  final bool mobileLifecycle;
  final String? initialDeviceName;
  final Future<int?> Function(Directory directory)? availableBytes;
  final ExportFileCallback? exportFile;
  final bool exportSupported;
  final NetworkRetryPolicy? retryPolicy;

  /// Deletes every protected secret. Only for an explicit, confirmed reset.
  final Future<void> Function()? resetSecrets;
  final Future<String?> Function()? versionLabel;
  final Future<String?> Function()? defaultDeviceName;

  /// true = the OS denied local network access, false = granted, null = unknown.
  final Future<bool?> Function()? localNetworkDenied;
  final Future<void> Function()? openSystemSettings;
  final Future<void> Function(bool enabled)? setKeepAwake;
  final Future<Object?> Function()? beginBackgroundTask;
  final Future<void> Function(Object? token)? endBackgroundTask;

  /// How long a running transfer may continue after the app is backgrounded
  /// before it is stopped cleanly (bounded by the OS background allowance).
  final Duration backgroundGrace;
  final Future<Directory> Function()? temporaryDirectory;
  final bool requireOnboarding;
  /// The system photo/video picker is available (iOS/Android).
  final bool mediaPicker;
  final Future<void> Function(List<File> files)? shareFiles;
  final Future<bool> Function(Directory directory)? excludeFromBackup;

  /// Registers a callback for the OS ending the background grace period early.
  final void Function(void Function() onExpired)? listenBackgroundExpiry;

  /// The OS language. Null (tests) means Russian, the source language.
  final Locale Function()? systemLocale;

  /// Deterministic scheduler boundary for tests. Native operation leaves this
  /// null and uses cancellable monotonic timers, never a persisted wall clock.
  final Future<void> Function(Duration duration)? retryDelay;
}

Future<String?> _nativeVersionLabel() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  } catch (_) {
    return null;
  }
}

Future<String?> _nativeDeviceName() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      final model = info.modelName.trim();
      return model.isEmpty ? null : model;
    }
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      final brand = info.manufacturer.trim();
      final model = info.model.trim();
      final name = model.toLowerCase().startsWith(brand.toLowerCase())
          ? model
          : '${brand[0].toUpperCase()}${brand.substring(1)} $model';
      return name.trim().isEmpty ? null : name.trim();
    }
    if (Platform.isWindows) {
      final info = await plugin.windowsInfo;
      return info.computerName.trim().isEmpty ? null : info.computerName.trim();
    }
    if (Platform.isLinux) {
      final info = await plugin.linuxInfo;
      return info.prettyName.trim().isEmpty ? null : info.prettyName.trim();
    }
  } catch (_) {
    /* Fall back to the generic platform label. */
  }
  return null;
}
