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
  String get saveLocationLabel => '';
  String get versionLabel => '';
  StorageOverview? get storageOverview => null;
  bool get storageRefreshing => false;

  /// Incremented whenever a new error or status message is published, so the
  /// interface can show each message once (snackbar) without re-showing it.
  int get messageSerial => 0;

  /// Why startup failed, if it did. The interface offers matching recovery.
  StartupIssue get startupIssue => StartupIssue.none;
  bool get needsOnboarding => false;
  bool get canRepairStorage => false;

  /// Short code of this device's key (compare during pairing).
  String? get deviceCode => null;

  /// The OS denied local network access; settings must be changed by the user.
  bool get localNetworkDenied => false;

  /// null = follow the system language.
  Locale? get locale => null;

  /// The language the interface is shown in (explicit choice or system).
  Locale get effectiveLocale => locale ?? const Locale('ru');

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
  Future<void> retryTransfer(String transferId) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  Future<void> revokePeer(String peerId);
  Future<void> renameDevice(String name);
  Future<void> setThemeMode(ThemeMode mode);

  // Optional actions remain visibly disabled until a real adapter implements
  // them and enables the corresponding capability.
  Future<void> openTransfer(String transferId) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  Future<void> openReceivedFile(String transferId, String fileId) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  Future<void> chooseSaveLocation() =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  Future<void> scanInvitation() =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  Future<void> addSourcePaths(List<String> paths) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  Future<void> exportReceivedFile(String transferId, String fileId) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  Future<void> refreshStorage() async {}
  Future<void> completeOnboarding() async {}
  Future<void> retryStartup() async {}
  Future<void> resetDeviceKeys() async {}
  Future<void> repairStorage() async {}
  Future<void> openSystemSettings() async {}
  Future<void> setLocale(Locale? locale) async {}
  Future<void> chooseMedia() =>
      Future.error(UnsupportedError('Media selection is unavailable.'));
  Future<void> deleteTransfer(String transferId) =>
      Future.error(UnsupportedError('Deleting is unavailable.'));
  Future<void> clearHistory() =>
      Future.error(UnsupportedError('Clearing history is unavailable.'));
  Future<void> shareReceivedFile(String transferId, String fileId) =>
      Future.error(UnsupportedError('Sharing is unavailable.'));
  Future<void> exportDiagnostics() =>
      Future.error(UnsupportedError('Diagnostics are unavailable.'));

  // ---- 1.2 contract (implemented by TransferAppController) ----

  /// Public privacy policy and support pages (required by the stores).
  Uri get privacyPolicyUrl =>
      Uri.parse('https://sardorcos.github.io/neverland-legal/ulash/privacy.html');
  Uri get supportUrl =>
      Uri.parse('https://sardorcos.github.io/neverland-legal/ulash/support.html');
  Future<void> openExternalUrl(Uri url) async {}

  /// Joiner side of a pairing in progress: the 6-digit code that must match
  /// the code shown on the other device (null when not pairing).
  OutgoingPairing? get outgoingPairing => null;

  /// Devices on this network that currently accept pairing without a QR code.
  List<NearbyDevice> get nearbyPairable => const [];
  Future<void> pairNearby(String nearbyId) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));

  /// Host side: this device is visible for QR-less pairing (time-limited).
  bool get nearbyPairingOpen => false;
  Future<void> setNearbyPairing(bool open) async {}

  /// Sends a short text or link as a message.
  Future<void> sendText(String peerId, String text) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));

  /// Adds a whole folder (keeps its structure when the peer supports it).
  Future<void> chooseFolder() =>
      Future.error(UnsupportedError('Not supported by this adapter.'));

  /// Opt-in browser link to download selected files / upload to this device.
  WebShareState? get webShare => null;
  Future<void> startWebShare({bool allowUpload = false}) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  Future<void> stopWebShare() async {}

  /// Saves a received photo/video into the system photo library.
  Future<void> saveToPhotos(String transferId, String fileId) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  bool get autoSaveToPhotos => false;
  Future<void> setAutoSaveToPhotos(bool enabled) async {}

  /// Desktop: shows a received file in Explorer/Finder.
  Future<void> revealReceivedFile(String transferId, String fileId) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));

  /// Copies the pairing invitation with sensitive/local-only clipboard flags
  /// and clears it after the invitation expires.
  Future<void> copyInvitation() async {}

  /// Hides sensitive content (QR) from screenshots/app switcher while shown.
  Future<void> setSecureScreen(bool enabled) async {}
  Future<void> setTemporaryQuota(int bytes) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  Future<void> clearUnusedTemporary(List<String> fileIds) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
  Future<void> clearIncompleteIncoming(List<String> transferIds) =>
      Future.error(UnsupportedError('Not supported by this adapter.'));
}

enum NetworkState { starting, ready, unavailable, permissionRequired }

enum StartupIssue {
  none,

  /// Protected keys could not be read (locked, lost after a device move, or
  /// corrupted). Recovery: retry, or reset device keys and pair again.
  secureStorage,

  /// A local journal is damaged or from a newer app version.
  journal,

  /// Any other failure; retry is offered.
  other,
}

enum DevicePlatform { ios, android, windows, macos, linux, unknown }

enum SourceStatus { preparing, ready, failed }

enum TransferDirection { outgoing, incoming }

enum TransferPhase {
  preparing,
  queued,
  retrying,
  waitingForConsent,
  transferring,
  verifying,
  completed,
  paused,
  failed,
  cancelled,
  expired,
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
    this.mediaSelection = false,
    this.share = false,
    this.diagnostics = false,
    this.folderSelection = false,
    this.textMessages = false,
    this.nearbyPairing = false,
    this.webShare = false,
    this.photosSave = false,
    this.revealInFolder = false,
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

  /// Photos/videos from the system photo library picker.
  final bool mediaSelection;

  /// System share sheet for received files.
  final bool share;
  final bool diagnostics;
  final bool folderSelection;
  final bool textMessages;
  final bool nearbyPairing;
  final bool webShare;
  final bool photosSave;
  final bool revealInFolder;
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
    this.canRetry = false,
    this.canOpen = false,
    this.canExport = false,
    this.canDelete = false,
    this.receivedFiles = const [],
    this.kind = TransferKind.files,
    this.messageText,
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
  final bool canRetry;
  final bool canOpen;
  final bool canExport;

  /// Terminal item that can be removed (incoming: also deletes its files).
  final bool canDelete;

  /// Only verified, committed files that the user can open explicitly.
  final List<ReceivedFile> receivedFiles;
  final TransferKind kind;

  /// Text of a message transfer (sent or received), shown inline.
  final String? messageText;

  bool get isTerminal =>
      phase == TransferPhase.completed ||
      phase == TransferPhase.failed ||
      phase == TransferPhase.cancelled ||
      phase == TransferPhase.expired;
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
    this.isMedia = false,
    this.previewPath,
    this.potentiallyExecutable = false,
    this.relativeDirectory,
  });

  final String id;
  final String name;
  final int bytes;
  final ExportPhase exportPhase;
  final String? exportDestination;
  final String? exportDetail;

  /// Photo or video that can be saved to the photo library.
  final bool isMedia;

  /// Local path for a thumbnail (images only); null when not previewable.
  final String? previewPath;

  /// Executable/script type: the interface must warn before opening.
  final bool potentiallyExecutable;

  /// Folder inside the transfer (folder transfers), forward slashes.
  final String? relativeDirectory;
}

enum TransferKind { files, folder, text }

@immutable
class OutgoingPairing {
  const OutgoingPairing({
    required this.hostName,
    required this.code,
    this.waitingForApproval = true,
  });
  final String hostName;

  /// 6 digits; the other device shows the same code.
  final String code;
  final bool waitingForApproval;
}

@immutable
class NearbyDevice {
  const NearbyDevice({
    required this.id,
    required this.name,
    this.platform = DevicePlatform.unknown,
  });
  final String id;
  final String name;
  final DevicePlatform platform;
}

@immutable
class WebShareState {
  const WebShareState({
    required this.url,
    required this.expiresAt,
    this.allowUpload = false,
    this.connectedClients = 0,
    this.downloadedFiles = 0,
    this.uploadedFiles = 0,
    this.sharedFileCount = 0,
  });

  /// `http://LAN-IP:PORT/TOKEN` — encode as QR for the browser.
  final Uri url;
  final DateTime expiresAt;
  final bool allowUpload;
  final int connectedClients;
  final int downloadedFiles;
  final int uploadedFiles;
  final int sharedFileCount;
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
    this.incompleteIncoming = const [],
  });
  final int? availableBytes;
  final int temporaryBytes;
  final int reservedBytes;
  final int safetyReserveBytes;
  final int? temporaryQuotaBytes;
  final List<TemporaryFileItem> unusedFiles;
  final List<IncomingCleanupItem> incompleteIncoming;
  final DateTime checkedAt;
  int get unusedBytes => unusedFiles.fold(0, (sum, file) => sum + file.bytes);
  int get incompleteTemporaryBytes =>
      incompleteIncoming.fold(0, (sum, item) => sum + item.temporaryBytes);
  int get incompleteReservedBytes =>
      incompleteIncoming.fold(0, (sum, item) => sum + item.reservedBytes);
}

/// A confirmed cleanup acts on these exact transfer IDs, never on a later
/// refreshed list. The native/core adapter rechecks committed files at deletion.
@immutable
class IncomingCleanupItem {
  const IncomingCleanupItem({
    required this.id,
    required this.title,
    required this.peerName,
    required this.temporaryBytes,
    required this.reservedBytes,
    required this.pendingFileCount,
    required this.completedFileCount,
  });

  final String id;
  final String title;
  final String peerName;
  final int temporaryBytes;
  final int reservedBytes;
  final int pendingFileCount;
  final int completedFileCount;
}

@immutable
class IncomingTransfer {
  const IncomingTransfer({
    required this.id,
    required this.peerName,
    required this.fileNames,
    required this.totalBytes,
    this.expiresAt,
  });

  final String id;
  final String peerName;
  final List<String> fileNames;
  final int totalBytes;
  final DateTime? expiresAt;
}

@immutable
class PairingRequest {
  const PairingRequest({
    required this.id,
    required this.deviceName,
    this.platform = DevicePlatform.unknown,
    this.code,
  });

  final String id;
  final String deviceName;
  final DevicePlatform platform;

  /// Short key code shown on the requesting device too; must match.
  final String? code;
}

@immutable
class PairingInvitation {
  const PairingInvitation({required this.payload, required this.expiresAt});

  final String payload;
  final DateTime expiresAt;
}
