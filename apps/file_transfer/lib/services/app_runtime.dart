import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:transfer_core/transfer_core.dart';

import 'lan_discovery.dart';
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
}
