// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

/// Presentation-only contract. No peer, file, progress, or history is fabricated
/// by the interface. The service adapter owns every value and notifies changes.
abstract class AppController extends ChangeNotifier {
  String get deviceName;
  NetworkState get networkState;
  bool get receivingEnabled;
  bool get isBusy;
  List<SelectedSource> get selectedSources;
  List<PeerDevice> get peers;
  List<TransferItem> get transfers;
  List<IncomingTransfer> get pendingTransfers;
  List<PairingRequest> get pendingPairings;
  PairingInvitation? get invitation;
  ThemeMode get themeMode;

  AppCapabilities get capabilities => const AppCapabilities();
  String? get busyLabel => null;
  String? get errorMessage => null;
  String? get statusMessage => null;
  String? get networkDetail => null;
  String get saveLocationLabel => 'Хранилище приложения';
  String get versionLabel => 'Альфа-версия';
  StorageOverview? get storageOverview => null;
  bool get storageRefreshing => false;

  Future<void> chooseFiles();
  Future<void> removeSource(String sourceId);
  Future<void> clearSources();
  Future<void> sendTo(String peerId);
  Future<void> refreshPeers();
  Future<void> setReceiving(bool enabled);
  Future<void> createInvitation();
  Future<void> pairFromText(String payload);
  Future<void> respondToPairing(String requestId, bool accept);
  Future<void> respondToTransfer(String transferId, bool accept);
  Future<void> pauseTransfer(String transferId);
  Future<void> resumeTransfer(String transferId);
  Future<void> cancelTransfer(String transferId);
  Future<void> revokePeer(String peerId);
  Future<void> renameDevice(String name);
  Future<void> setThemeMode(ThemeMode mode);

  // Optional actions remain visibly disabled until a real adapter implements
  // them and enables the corresponding capability.
  Future<void> openTransfer(String transferId) =>
      Future.error(UnsupportedError('Открытие файла пока недоступно.'));
  Future<void> openReceivedFile(String transferId, String fileId) =>
      Future.error(UnsupportedError('Открытие файла пока недоступно.'));
  Future<void> chooseSaveLocation() =>
      Future.error(UnsupportedError('Выбор папки пока недоступен.'));
  Future<void> scanInvitation() =>
      Future.error(UnsupportedError('Сканирование QR пока недоступно.'));
  Future<void> addSourcePaths(List<String> paths) =>
      Future.error(UnsupportedError('Перетаскивание пока недоступно.'));
  Future<void> exportReceivedFile(String transferId, String fileId) =>
      Future.error(UnsupportedError('Сохранение копии пока недоступно.'));
  Future<void> refreshStorage() async {}
  Future<void> setTemporaryQuota(int bytes) =>
      Future.error(UnsupportedError('Изменение лимита пока недоступно.'));
  Future<void> clearUnusedTemporary(List<String> fileIds) =>
      Future.error(UnsupportedError('Очистка пока недоступна.'));
}

enum NetworkState { starting, ready, unavailable, permissionRequired }

enum DevicePlatform { ios, android, windows, macos, linux, unknown }

enum SourceStatus { preparing, ready, failed }

enum TransferDirection { outgoing, incoming }

enum TransferPhase {
  preparing,
  queued,
  waitingForConsent,
  transferring,
  verifying,
  completed,
  paused,
  failed,
  cancelled,
}

@immutable
class AppCapabilities {
  const AppCapabilities({
    this.fileSelection = true,
    this.receiving = true,
    this.pairing = true,
    this.discovery = false,
    this.rename = true,
    this.saveLocation = false,
    this.qrScanner = false,
    this.desktopDrop = false,
    this.fileExport = false,
    this.storageManagement = false,
  });

  final bool fileSelection;
  final bool receiving;
  final bool pairing;
  final bool discovery;
  final bool rename;
  final bool saveLocation;
  final bool qrScanner;
  final bool desktopDrop;
  final bool fileExport;
  final bool storageManagement;
}

@immutable
class SelectedSource {
  const SelectedSource({
    required this.id,
    required this.name,
    this.bytes,
    this.status = SourceStatus.ready,
    this.detail,
  });

  final String id;
  final String name;
  final int? bytes;
  final SourceStatus status;
  final String? detail;
}

@immutable
class PeerDevice {
  const PeerDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.isTrusted,
    required this.isOnline,
    this.detail,
  });

  final String id;
  final String name;
  final DevicePlatform platform;
  final bool isTrusted;
  final bool isOnline;
  final String? detail;
}

@immutable
class TransferItem {
  const TransferItem({
    required this.id,
    required this.title,
    required this.peerName,
    required this.direction,
    required this.phase,
    required this.totalBytes,
    required this.transferredBytes,
    required this.createdAt,
    this.fileCount = 1,
    this.bytesPerSecond,
    this.detail,
    this.locationLabel,
    this.canPause = false,
    this.canResume = false,
    this.canCancel = false,
    this.canOpen = false,
    this.canExport = false,
    this.receivedFiles = const [],
  });

  final String id;
  final String title;
  final String peerName;
  final TransferDirection direction;
  final TransferPhase phase;
  final int totalBytes;
  final int transferredBytes;
  final DateTime createdAt;
  final int fileCount;
  final double? bytesPerSecond;
  final String? detail;
  final String? locationLabel;
  final bool canPause;
  final bool canResume;
  final bool canCancel;
  final bool canOpen;
  final bool canExport;

  /// Only verified, committed files that the user can open explicitly.
  final List<ReceivedFile> receivedFiles;

  bool get isTerminal =>
      phase == TransferPhase.completed ||
      phase == TransferPhase.failed ||
      phase == TransferPhase.cancelled;
}

@immutable
class ReceivedFile {
  const ReceivedFile({
    required this.id,
    required this.name,
    required this.bytes,
    this.exportPhase = ExportPhase.notExported,
    this.exportDestination,
    this.exportDetail,
  });

  final String id;
  final String name;
  final int bytes;
  final ExportPhase exportPhase;
  final String? exportDestination;
  final String? exportDetail;
}

enum ExportPhase {
  notExported,
  exporting,
  exported,
  cancelled,
  failed,
  unknown,
}

@immutable
class TemporaryFileItem {
  const TemporaryFileItem({
    required this.id,
    required this.name,
    required this.bytes,
  });
  final String id;
  final String name;
  final int bytes;
}

@immutable
class StorageOverview {
  const StorageOverview({
    required this.availableBytes,
    required this.temporaryBytes,
    required this.reservedBytes,
    required this.safetyReserveBytes,
    required this.temporaryQuotaBytes,
    required this.unusedFiles,
    required this.checkedAt,
  });
  final int? availableBytes;
  final int temporaryBytes;
  final int reservedBytes;
  final int safetyReserveBytes;
  final int? temporaryQuotaBytes;
  final List<TemporaryFileItem> unusedFiles;
  final DateTime checkedAt;
  int get unusedBytes => unusedFiles.fold(0, (sum, file) => sum + file.bytes);
}

@immutable
class IncomingTransfer {
  const IncomingTransfer({
    required this.id,
    required this.peerName,
    required this.fileNames,
    required this.totalBytes,
  });

  final String id;
  final String peerName;
  final List<String> fileNames;
  final int totalBytes;
}

@immutable
class PairingRequest {
  const PairingRequest({
    required this.id,
    required this.deviceName,
    this.platform = DevicePlatform.unknown,
  });

  final String id;
  final String deviceName;
  final DevicePlatform platform;
}

@immutable
class PairingInvitation {
  const PairingInvitation({required this.payload, required this.expiresAt});

  final String payload;
  final DateTime expiresAt;
}
