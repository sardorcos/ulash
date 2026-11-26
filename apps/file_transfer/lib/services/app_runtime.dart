import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:transfer_core/transfer_core.dart';

import 'lan_discovery.dart';
import 'native_bridge.dart';
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
    this.requestReview,
    this.openUrl,
    this.webShareAddress,
    this.pickerCopiesToCache = false,
    this.webSharePort = 53320,
    this.webShareTtl = const Duration(minutes: 10),
    this.systemLocale,
    this.receivedDirectory,
    this.legacyStorageDirectory,
    this.pickDirectory,
    this.createDiscovery,
    this.takePendingIntake,
    this.intakeAvailable,
    this.saveToPhotos,
    this.setSecureScreen,
    this.copySensitive,
    this.openFileSafely,
    this.revealInFolder,
    this.markFromInternet,
  });

  factory AppRuntime.native() => AppRuntime(
    secrets: const OsSecretStore(),
    // Windows 1.2+: %LOCALAPPDATA%\Ulash (large, device-local data must not
    // roam). The 1.0 Roaming location is migrated once at startup.
    storageDirectory: Platform.isWindows
        ? () async =>
              await NativeBridge.localDataDirectory() ??
              await getApplicationSupportDirectory()
        : getApplicationSupportDirectory,
    legacyStorageDirectory: Platform.isWindows
        ? getApplicationSupportDirectory
        : null,
    receivedDirectory: _nativeReceivedDirectory,
    // Folder selection needs a readable directory tree: desktop only. The
    // Android/iOS pickers return a tree the app cannot enumerate reliably.
    pickDirectory: Platform.isWindows || Platform.isLinux || Platform.isMacOS
        ? () async {
            final uri = await FilePicker.pickDirectory();
            return uri == null || uri.scheme != 'file'
                ? null
                : uri.toFilePath();
          }
        : null,
    takePendingIntake: NativeBridge.supportsIntake
        ? NativeBridge.takePendingIntake
        : null,
    intakeAvailable: NativeBridge.supportsIntake
        ? NativeBridge.intakeAvailable
        : null,
    saveToPhotos: NativeBridge.supportsSaveToPhotos
        ? (file, {required isVideo}) =>
              NativeBridge.saveToPhotos(file, isVideo: isVideo)
        : null,
    setSecureScreen: NativeBridge.setSecureScreen,
    copySensitive: (text, seconds) =>
        NativeBridge.copySensitive(text, seconds: seconds),
    openFileSafely: Platform.isWindows
        ? (file, {required allowExecutable}) => NativeBridge.openFileSafely(
            file,
            allowExecutable: allowExecutable,
          )
        : null,
    revealInFolder: Platform.isWindows ? NativeBridge.revealInFolder : null,
    markFromInternet: Platform.isWindows ? NativeBridge.markFromInternet : null,
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
    pickerCopiesToCache: Platform.isAndroid || Platform.isIOS,
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
    requestReview: () async {
      try {
        final review = InAppReview.instance;
        if (await review.isAvailable()) await review.requestReview();
      } catch (_) {
        /* A rating prompt is optional. */
      }
    },
    openUrl: (url) async {
      try {
        return await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    },
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

  /// Asks the store for a rating prompt (the OS decides whether to show it).
  final Future<void> Function()? requestReview;

  /// Opens a web page in the external browser.
  final Future<bool> Function(Uri url)? openUrl;

  /// Where the opt-in browser share listens (null = all IPv4 interfaces).
  final InternetAddress? webShareAddress;

  /// The system picker returns copies inside the app's temporary directory
  /// (iOS/Android); they are deleted right after staging. Desktop pickers
  /// return originals, which are never deleted.
  final bool pickerCopiesToCache;
  final int webSharePort;

  /// How long an opt-in browser share stays open before stopping itself.
  final Duration webShareTtl;

  /// The OS language. Null (tests) means Russian, the source language.
  final Locale Function()? systemLocale;

  /// Where received files become visible to the user (iOS: Documents/Ulash
  /// in the Files app; Windows: Downloads\Ulash). Null keeps them inside the
  /// app's private storage (Android, Linux, tests).
  final Future<Directory?> Function()? receivedDirectory;

  /// An older data root to move once into [storageDirectory] (Windows 1.0
  /// Roaming profile → LocalAppData). Never deleted when the move fails.
  final Future<Directory> Function()? legacyStorageDirectory;

  /// System folder picker (desktop); returns a readable directory path.
  final Future<String?> Function()? pickDirectory;

  /// Overrides the Bonjour/NSD discovery (tests).
  final LanDiscovery Function()? createDiscovery;

  /// Files shared/opened into the app by other apps (iOS/Android).
  final Future<List<IntakeItem>> Function()? takePendingIntake;
  final Stream<void>? intakeAvailable;
  final Future<SaveToPhotosResult> Function(File file, {required bool isVideo})?
  saveToPhotos;
  final Future<void> Function(bool enabled)? setSecureScreen;

  /// Copies sensitive text (local-only, auto-expiring). False = unavailable.
  final Future<bool> Function(String text, int seconds)? copySensitive;

  /// Windows: opens via ShellExecuteEx, refusing executables by default.
  final Future<OpenFileResult> Function(
    File file, {
    required bool allowExecutable,
  })?
  openFileSafely;
  final Future<bool> Function(File file)? revealInFolder;

  /// Windows: Mark-of-the-Web for received/exported files.
  final Future<bool> Function(File file)? markFromInternet;

  /// Deterministic scheduler boundary for tests. Native operation leaves this
  /// null and uses cancellable monotonic timers, never a persisted wall clock.
  final Future<void> Function(Duration duration)? retryDelay;
}

Future<Directory?> _nativeReceivedDirectory() async {
  try {
    if (Platform.isIOS) {
      final documents = await getApplicationDocumentsDirectory();
      return Directory('${documents.path}/Ulash');
    }
    if (Platform.isWindows) {
      final downloads = await NativeBridge.downloadsDirectory();
      return downloads == null
          ? null
          : Directory('${downloads.path}${Platform.pathSeparator}Ulash');
    }
  } catch (_) {
    /* Keep received files in the app's private storage. */
  }
  return null;
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
