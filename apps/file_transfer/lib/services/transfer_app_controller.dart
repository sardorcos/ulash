import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart' as picker;
// Compatibility during the Flutter 3.50 Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:transfer_core/transfer_core.dart' as core;
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../ui/app_controller.dart';
import 'diagnostics_log.dart';
import 'lan_discovery.dart';
import 'app_runtime.dart';
import 'outgoing_journal.dart';
import 'receipt_validation.dart';
import 'export_journal.dart';
import 'network_retry_policy.dart';

/// Bridges the presentation contract to real native storage and HTTPS.
/// No simulated progress, peers, receipt, or automatic file acceptance.
class TransferAppController extends AppController with WidgetsBindingObserver {
  TransferAppController({this.scanCode, AppRuntime? runtime})
    : _runtime = runtime ?? AppRuntime.native();
  final AppRuntime _runtime;
  final Future<String?> Function()? scanCode;
  core.SecretStore get _secrets => _runtime.secrets;
  core.DeviceIdentity? _identity;
  core.TrustedPeerStore? _trusted;
  core.DurableInbox? _inbox;
  core.DurableOutbox? _outbox;
  core.CoreHost? _host;
  LanDiscovery? _discovery;
  OutgoingJournal? _journal;
  ExportJournal? _exports;
  core.StorageBudget? _storageBudget;
  StorageOverview? _storageOverview;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _sources = <SelectedSource>[];
  final _jobs = <OutgoingJob>[];
  final _online = <String>{};
  final _platforms = <String, DevicePlatform>{};
  final _activeClients = <String, core.CoreClient>{};
  final _running = <String>{};
  final _outgoingRuns = <String, _OutgoingRun>{};
  late final _retryPolicy = _runtime.retryPolicy ?? NetworkRetryPolicy();
  final _unconfirmedExports = <(String, String)>{};
  final _discovered = <DiscoveredEndpoint>[];
  NetworkState _network = NetworkState.starting;
  ThemeMode _theme = ThemeMode.system;
  bool _starting = true;
  bool _preparing = false;
  bool _picking = false;
  bool _pairing = false;
  bool _receiving = false;
  bool _disposed = false;
  bool _closing = false;
  bool _receiveWanted = true;
  bool _foreground = true;
  bool _exporting = false;
  bool _cleaning = false;
  bool _changingQuota = false;
  bool _storageRefreshing = false;
  Future<void> _hostLifecycle = Future.value();
  Future<void>? _initialization;
  Future<void>? _shutdown;
  final _backgroundTasks = <Future<void>>{};
  final _operations = <Future<void>>{};
  core.CoreClient? _pairingClient;
  String? _error;
  String? _status;
  String? _busy;
  String? _discoveryIssue;
  String? _dataPath;
  List<String> _addresses = [];
  PairingInvitation? _invitation;
  Timer? _peerTimer;
  Timer? _storageTimer;
  final _hostSubscriptions = <StreamSubscription<dynamic>>[];

  /// Jobs stopped by the app lifecycle or by exhausted network retries. They
  /// continue automatically (never jobs the user paused manually).
  final _autoResume = <String>{};
  final _autoResumeAttempts = <String, int>{};
  static const _maxAutoResumes = 3;
  int _messageSerial = 0;
  StartupIssue _startupIssue = StartupIssue.none;
  File? _failedJournal;
  bool _needsOnboarding = false;
  bool _localNetworkDenied = false;
  bool _observing = false;
  String _versionLabel = '1.0.0';
  Locale? _locale;
  int _systemUi = 0;
  Timer? _backgroundTimer;
  Object? _backgroundTask;
  bool _keepAwake = false;
  Directory? _logDirectory;
  bool _emitScheduled = false;
  List<core.TransferSnapshot>? _inboxCache;
  List<TransferItem>? _transfersCache;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      _runtime.listenBackgroundExpiry?.call(() {
        // The OS is ending our background allowance: stop cleanly now.
        if (_backgroundTimer != null) _stopForBackground();
      });
    }
    _startupIssue = StartupIssue.none;
    _failedJournal = null;
    try {
      _busy = _l.busyPreparingStorage;
      _emit();
      final root = await _runtime.storageDirectory();
      final data = Directory(p.join(root.path, 'file-transfer-v1'));
      await data.create(recursive: true);
      _dataPath = await data.resolveSymbolicLinks();
      _logDirectory = Directory(p.join(data.path, 'logs'));
      await DiagnosticsLog.instance.attach(_logDirectory!);
      DiagnosticsLog.instance.info('startup');
      _versionLabel = await _runtime.versionLabel?.call() ?? _versionLabel;
      // Transfer payloads, journals and received files are device-local and
      // can be large: keep them out of iCloud/iTunes backups. Keys are
      // this-device-only too, so a restored device starts consistently clean.
      try {
        await _runtime.excludeFromBackup?.call(data);
      } catch (error, stack) {
        DiagnosticsLog.instance.error('backup-exclusion', error, stack);
      }
      try {
        _identity = await core.DeviceIdentity.loadOrCreate(
          _secrets,
          displayName: await _initialName(),
        );
        _trusted = core.TrustedPeerStore(_secrets);
        await _trusted!.load();
      } catch (_) {
        _startupIssue = StartupIssue.secureStorage;
        rethrow;
      }
      final savedLocale = await _secrets.read('transfer.settings.locale');
      _locale = savedLocale == null || savedLocale.isEmpty
          ? null
          : Locale(savedLocale);
      final savedTheme = await _secrets.read('transfer.settings.theme');
      _theme =
          ThemeMode.values
              .where((value) => value.name == savedTheme)
              .firstOrNull ??
          ThemeMode.system;
      final savedQuota = int.tryParse(
        await _secrets.read('transfer.settings.temporaryQuotaBytes') ?? '',
      );
      _storageBudget = core.StorageBudget(
        availableBytes: () async => _runtime.availableBytes == null
            ? null
            : await _runtime.availableBytes!(data),
        temporaryQuotaBytes: _quotaOptions.contains(savedQuota)
            ? savedQuota!
            : 20 * 1024 * 1024 * 1024,
      );
      _inbox = await _openJournal(
        File(p.join(data.path, 'inbox', 'inbox.sqlite')),
        () => core.DurableInbox.open(
          Directory(p.join(data.path, 'inbox')),
          budget: _storageBudget,
        ),
      );
      _outbox = await _openJournal(
        File(p.join(data.path, 'outbox', 'outbox.sqlite')),
        () => core.DurableOutbox.open(
          Directory(p.join(data.path, 'outbox')),
          budget: _storageBudget,
        ),
      );
      _journal = await _openJournal(
        File(p.join(data.path, 'journal', 'outgoing.sqlite3')),
        () async => OutgoingJournal(Directory(p.join(data.path, 'journal'))),
      );
      _exports = await _openJournal(
        File(p.join(data.path, 'journal', 'exports.sqlite3')),
        () async => ExportJournal(Directory(p.join(data.path, 'journal'))),
      );
      _jobs
        ..clear()
        ..addAll(_journal!.recover(interruptedDetail: _l.interruptedOnClose));
      await _pruneHistory();
      await _updateStorageOverview();
      _subscriptions.add(
        _inbox!.changes.listen((_) {
          _emit();
          _refreshStorageSoon();
        }),
      );
      _subscriptions.add(_trusted!.changes.listen((_) => _emit()));
      _needsOnboarding =
          _runtime.requireOnboarding &&
          await _secrets.read('transfer.settings.onboarded') != 'true';
      if (!_needsOnboarding) await _startNetworking();
    } catch (error, stack) {
      DiagnosticsLog.instance.error('startup', error, stack);
      if (_startupIssue == StartupIssue.none) {
        _startupIssue = _failedJournal != null
            ? StartupIssue.journal
            : StartupIssue.other;
      }
      _network = NetworkState.unavailable;
      _setError(switch (_startupIssue) {
        StartupIssue.secureStorage => _l.startupKeysFailed,
        StartupIssue.journal => _l.startupJournalFailed,
        _ => _l.startupFailed(_friendly(error)),
      });
    } finally {
      _starting = false;
      _busy = null;
      _emit();
    }
  }

  /// Opens one journal and remembers which file failed, so that a confirmed
  /// repair can move exactly that database aside.
  Future<T> _openJournal<T>(File file, Future<T> Function() open) async {
    try {
      return await open();
    } catch (error) {
      final code = error is core.StorageException ? error.code : null;
      if (error is SqliteException ||
          code == 'JOURNAL_CORRUPT' ||
          code == 'JOURNAL_TOO_NEW') {
        _failedJournal = file;
        _startupIssue = StartupIssue.journal;
      }
      rethrow;
    }
  }

  Future<String> _initialName() async {
    final explicit = _runtime.initialDeviceName;
    if (explicit != null) return explicit;
    final model = await _runtime.defaultDeviceName?.call();
    final clean = model?.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    if (clean == null || clean.isEmpty) return _defaultName();
    return clean.length > 60 ? clean.substring(0, 60) : clean;
  }

  Future<void> _startNetworking() async {
    if (!await _runtime.ensurePermission()) {
      _network = NetworkState.permissionRequired;
      _setError(_l.allowLocalNetwork);
      return;
    }
    await _synchronizeHost();
    _updatePeerTimer();
    _launch(_checkLocalNetwork());
  }

  void _updatePeerTimer() {
    final wanted =
        _foreground &&
        !_closing &&
        !_needsOnboarding &&
        _identity != null &&
        _network != NetworkState.permissionRequired;
    if (wanted && _peerTimer == null) {
      _peerTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        _launch(_refreshTrusted());
        _launch(_refreshAddresses());
      });
    } else if (!wanted) {
      _peerTimer?.cancel();
      _peerTimer = null;
    }
  }

  /// The QR address list and the Bonjour record follow network changes
  /// (Wi-Fi switch, hotspot, VPN) while the app is open.
  Future<void> _refreshAddresses() async {
    if (_host == null || _closing) return;
    final next = await _runtime.addresses();
    if (next.join(',') == _addresses.join(',')) return;
    _addresses = next;
    DiagnosticsLog.instance.info('lan addresses changed (${next.length})');
    if (_invitation != null) _invitation = null;
    _emit();
  }

  Future<void> _checkLocalNetwork() async {
    final probe = _runtime.localNetworkDenied;
    if (probe == null || _closing) return;
    bool? denied;
    try {
      denied = await probe();
    } catch (_) {
      denied = null;
    }
    final wasDenied = _localNetworkDenied;
    _localNetworkDenied = denied == true;
    if (_localNetworkDenied) {
      _network = NetworkState.permissionRequired;
    } else if (wasDenied && _host != null) {
      _network = NetworkState.ready;
    }
    if (wasDenied != _localNetworkDenied) _emit();
  }

  @override
  Future<void> completeOnboarding() async {
    if (!_needsOnboarding || _closing) return;
    try {
      await _secrets.write('transfer.settings.onboarded', 'true');
    } catch (error, stack) {
      DiagnosticsLog.instance.error('onboarding', error, stack);
    }
    _needsOnboarding = false;
    _emit();
    await _guard(_startNetworking);
  }

  @override
  Future<void> retryStartup() async {
    if (_closing) return;
    final pending = _initialization;
    if (pending != null) await pending;
    if (_startupIssue == StartupIssue.none && _identity != null) return;
    await _releaseStartupResources();
    _initialization = null;
    _starting = true;
    _error = null;
    _emit();
    await initialize();
  }

  Future<void> _releaseStartupResources() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _stopHostNow();
    try {
      await _inbox?.close();
    } catch (_) {}
    try {
      await _outbox?.close();
    } catch (_) {}
    try {
      _journal?.close();
    } catch (_) {}
    try {
      _exports?.close();
    } catch (_) {}
    _inbox = null;
    _outbox = null;
    _journal = null;
    _exports = null;
    _identity = null;
    _trusted = null;
    _jobs.clear();
    _invalidate();
  }

  @override
  Future<void> resetDeviceKeys() async {
    if (_closing) return;
    DiagnosticsLog.instance.info('device keys reset by user');
    try {
      final reset = _runtime.resetSecrets;
      if (reset != null) {
        await reset();
      } else {
        for (final key in const [
          'transfer.identity.v1',
          'transfer.peers.v1',
          'transfer.peers.v1.host-pairing',
        ]) {
          await _secrets.delete(key);
        }
      }
    } catch (error, stack) {
      DiagnosticsLog.instance.error('reset-keys', error, stack);
      _setError(_l.resetKeysFailed);
      _emit();
      return;
    }
    _startupIssue = StartupIssue.other;
    await retryStartup();
  }

  @override
  Future<void> repairStorage() async {
    final file = _failedJournal;
    if (file == null || _closing) return;
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final suffix in const ['', '-wal', '-shm']) {
      final part = File('${file.path}$suffix');
      try {
        if (await part.exists()) {
          await part.rename('${file.path}.damaged-$stamp$suffix');
        }
      } catch (error, stack) {
        DiagnosticsLog.instance.error('repair-journal', error, stack);
      }
    }
    DiagnosticsLog.instance.info('journal moved aside by user');
    await retryStartup();
  }

  String _defaultName() => switch (Platform.operatingSystem) {
    'ios' => _l.defaultNameIos,
    'android' => _l.defaultNameAndroid,
    'windows' => _l.defaultNameWindows,
    'linux' => _l.defaultNameLinux,
    _ => _l.defaultNameOther,
  };

  Future<void> _synchronizeHost() {
    final next = _hostLifecycle.then((_) async {
      if (_receiveWanted && _foreground && !_closing && _identity != null) {
        await _startHostNow();
      } else {
        await _stopHostNow();
      }
    });
    // Keep the lifecycle queue usable after a rejected system permission or bind.
    _hostLifecycle = next.catchError((Object _) {});
    return next;
  }

  Future<void> _startHostNow() async {
    if (_host != null) return;
    _addresses = await _runtime.addresses();
    final host = core.CoreHost(
      identity: _identity!,
      peers: _trusted!,
      inbox: _inbox!,
    );
    try {
      await host.start(
        address: _runtime.listenAddress,
        port: _runtime.listenPort,
      );
    } on SocketException {
      await host.start(address: _runtime.listenAddress);
    }
    _host = host;
    _receiving = true;
    _network = _localNetworkDenied
        ? NetworkState.permissionRequired
        : NetworkState.ready;
    _hostSubscriptions.add(host.changes.listen((_) => _emit()));
    if (!_runtime.discoveryEnabled) {
      _launch(_refreshTrusted());
      return;
    }
    final discovery = LanDiscovery();
    _discovery = discovery;
    _hostSubscriptions.add(
      discovery.changes.listen((items) {
        _discovered
          ..clear()
          ..addAll(items);
        _launch(_refreshTrusted());
        _emit();
      }),
    );
    try {
      await discovery.start(name: deviceName, port: host.port);
      _discoveryIssue = null;
    } catch (error, stack) {
      DiagnosticsLog.instance.error('discovery', error, stack);
      // Foreground HTTPS remains usable via QR when discovery alone fails.
      _discoveryIssue = _l.discoveryUnavailable;
      await discovery.close();
      _discovery = null;
      _launch(_checkLocalNetwork());
    }
    _launch(_refreshTrusted());
  }

  @override
  String get deviceName => _identity?.displayName ?? _defaultName();
  @override
  NetworkState get networkState => _network;
  @override
  bool get receivingEnabled => _receiving;
  @override
  bool get isBusy =>
      _starting || _picking || _preparing || _cleaning || _changingQuota;
  @override
  String? get busyLabel => _busy;
  @override
  String? get errorMessage => _error;
  @override
  String? get statusMessage => _status;
  @override
  ThemeMode get themeMode => _theme;
  @override
  PairingInvitation? get invitation => _invitation;
  @override
  String get versionLabel => _versionLabel;
  @override
  int get messageSerial => _messageSerial;
  @override
  StartupIssue get startupIssue => _startupIssue;
  @override
  bool get needsOnboarding => _needsOnboarding;
  @override
  bool get localNetworkDenied => _localNetworkDenied;
  @override
  Locale? get locale => _locale;

  static const _languages = {'ru', 'uz', 'en'};

  @override
  Locale get effectiveLocale {
    final chosen = _locale;
    if (chosen != null && _languages.contains(chosen.languageCode)) {
      return chosen;
    }
    final system = _runtime.systemLocale?.call();
    if (system == null) return const Locale('ru');
    return _languages.contains(system.languageCode)
        ? Locale(system.languageCode)
        : const Locale('en');
  }

  AppLocalizations? _strings;
  Locale? _stringsLocale;

  /// Strings for messages the controller produces (status, details, errors).
  AppLocalizations get _l {
    final target = effectiveLocale;
    if (_strings == null || _stringsLocale != target) {
      _strings = lookupAppLocalizations(target);
      _stringsLocale = target;
    }
    return _strings!;
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    _strings = null;
    _emit();
  }

  @override
  String? get deviceCode =>
      _identity == null ? null : shortKeyCode(_identity!.peerId);

  /// Human-comparable code of a device key: first 8 hex digits, grouped.
  static String shortKeyCode(String peerId) {
    final hex = peerId.toUpperCase();
    if (hex.length < 8) return hex;
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}';
  }

  @override
  StorageOverview? get storageOverview => _storageOverview;
  @override
  bool get storageRefreshing => _storageRefreshing;
  @override
  String get saveLocationLabel =>
      _dataPath == null || Platform.isAndroid || Platform.isIOS
      // Mobile sandboxes are not user-visible paths; explain the action.
      ? _l.saveLocationMobile
      : p.join(_dataPath!, 'inbox', 'received');
  @override
  String? get networkDetail => _localNetworkDenied
      ? _l.networkDenied
      : _discoveryIssue ??
            (_addresses.isEmpty ? _l.networkNoAddress : _l.networkKeepOpen);
  @override
  AppCapabilities get capabilities => AppCapabilities(
    fileSelection: _outbox != null && !_starting,
    receiving: _inbox != null && !_starting,
    pairing: _host != null && !_pairing,
    discovery: _discovery != null && _discoveryIssue == null,
    rename: _identity != null && !_starting,
    mediaSelection: _runtime.mediaPicker && _outbox != null && !_starting,
    share: _runtime.shareFiles != null,
    diagnostics: _dataPath != null,
    fileExport:
        _runtime.exportSupported &&
        _runtime.exportFile != null &&
        _exports != null &&
        !_exporting,
    storageManagement: _storageBudget != null && _outbox != null && !_starting,
    qrScanner: scanCode != null && _host != null && !_pairing,
    desktopDrop:
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
        _outbox != null,
  );
  @override
  List<SelectedSource> get selectedSources => List.unmodifiable(_sources);

  @override
  List<PeerDevice> get peers {
    final trusted = _trusted?.list() ?? <core.TrustedPeer>[];
    final result = trusted
        .map(
          (peer) => PeerDevice(
            id: peer.peerId,
            name: peer.displayName,
            platform: _platforms[peer.peerId] ?? DevicePlatform.unknown,
            isTrusted: true,
            isOnline: _online.contains(peer.peerId),
            detail: _online.contains(peer.peerId)
                ? _l.peerKeyVerified
                : _l.peerOpenApp,
          ),
        )
        .toList();
    for (final candidate in _discovered) {
      if (trusted.any((peer) => peer.endpoint == candidate.endpoint)) continue;
      result.add(
        PeerDevice(
          id: 'nearby:${candidate.instanceId}',
          name: candidate.name,
          platform: _platformOf(candidate.platform),
          isTrusted: false,
          isOnline: true,
          detail: _l.peerScanToConnect,
        ),
      );
    }
    return result;
  }

  @override
  List<PairingRequest> get pendingPairings => (_host?.pendingPairings ?? [])
      .where((request) => request.state == 'waiting')
      .map(
        (request) => PairingRequest(
          id: request.requestId,
          deviceName: request.displayName,
          code: shortKeyCode(request.peerId),
        ),
      )
      .toList();

  /// One parsed inbox listing per change notification (the listing parses
  /// every manifest, so the interface must not trigger it per widget).
  List<core.TransferSnapshot> _inboxList() =>
      _inboxCache ??= _inbox?.list() ?? const <core.TransferSnapshot>[];

  bool get _incomingActive =>
      _inboxList().any((item) => item.state == core.TransferState.transferring);

  void _invalidate() {
    _inboxCache = null;
    _transfersCache = null;
  }

  @override
  List<IncomingTransfer> get pendingTransfers => _inboxList()
      .where((item) => item.state == core.TransferState.offered)
      .map(
        (item) => IncomingTransfer(
          id: item.transferId,
          peerName: _peerName(item.peerId),
          fileNames: item.manifest.files
              .map((file) => file.visibleName)
              .toList(),
          totalBytes: item.manifest.totalBytes,
          expiresAt: item.offerExpiresAt,
        ),
      )
      .toList();

  @override
  List<TransferItem> get transfers =>
      _transfersCache ??= List.unmodifiable(_buildTransfers());

  List<TransferItem> _buildTransfers() {
    final result = <TransferItem>[];
    for (final item in _inboxList()) {
      final terminal = _terminal(item);
      final committed = item.files
          .where((file) => file.state == core.FileState.committed)
          .toList();
      // A committed file deleted or moved outside the app cannot be opened,
      // shared or exported any more.
      final available = committed
          .where((file) => file.errorCode != 'FILE_MISSING')
          .toList();
      final allMissing = committed.isNotEmpty && available.isEmpty;
      result.add(
        TransferItem(
          id: 'in:${item.transferId}',
          title: _title(item.manifest),
          peerName: _peerName(item.peerId),
          direction: TransferDirection.incoming,
          phase: _snapshotPhase(item),
          totalBytes: item.manifest.totalBytes,
          transferredBytes: item.durableBytes,
          createdAt: item.createdAt,
          fileCount: item.files.length,
          detail: allMissing ? _l.receivedFilesMissing : _snapshotDetail(item),
          locationLabel: saveLocationLabel,
          receivedFiles: available
              .map((file) => _receivedFile(item.transferId, file))
              .toList(),
          canPause:
              !terminal &&
              !item.pausedBySink &&
              item.state != core.TransferState.offered,
          canResume:
              !terminal &&
              (item.pausedBySink ||
                  (item.state == core.TransferState.paused &&
                      !item.pausedBySource)),
          canCancel: !terminal,
          canOpen: available.isNotEmpty,
          canExport: capabilities.fileExport && available.isNotEmpty,
          canDelete: terminal,
        ),
      );
    }
    for (final job in _jobs) {
      final snapshot = job.snapshot;
      final phase = switch (job.localState) {
        'completed' => TransferPhase.completed,
        'cancelled' || 'rejected' => TransferPhase.cancelled,
        'expired' => TransferPhase.expired,
        'retry_wait' => TransferPhase.retrying,
        'paused' || 'cancelling' => TransferPhase.paused,
        'failed' || 'partially_completed' => TransferPhase.failed,
        _ =>
          snapshot == null
              ? TransferPhase.waitingForConsent
              : _snapshotPhase(snapshot),
      };
      result.add(
        TransferItem(
          id: 'out:${job.id}',
          title: _title(job.manifest),
          peerName: job.peerName,
          direction: TransferDirection.outgoing,
          phase: phase,
          totalBytes: job.manifest.totalBytes,
          transferredBytes: snapshot?.durableBytes ?? 0,
          createdAt: job.createdAt,
          fileCount: job.manifest.files.length,
          detail:
              job.detail ??
              (snapshot == null
                  ? _l.waitingForRecipient
                  : _snapshotDetail(snapshot)),
          canPause:
              !job.isTerminal &&
              _running.contains(job.id) &&
              job.localState != 'cancelling',
          canResume:
              !job.isTerminal &&
              job.localState != 'failed' &&
              !_running.contains(job.id),
          canCancel: !job.isTerminal && job.localState != 'cancelling',
          canRetry: _canRetryPrepared(job),
          canDelete: job.isTerminal && !_running.contains(job.id),
        ),
      );
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<void> chooseFiles() => _pickAndStage(media: false);

  @override
  Future<void> chooseMedia() => _pickAndStage(media: true);

  /// Runs [action] while a system sheet (picker, share, export, viewer) is in
  /// front of the app. On Android such a sheet stops the activity; that must
  /// not be mistaken for the user leaving the app.
  Future<T> _withSystemUi<T>(Future<T> Function() action) async {
    _systemUi++;
    try {
      return await action();
    } finally {
      _systemUi--;
    }
  }

  Future<void> _pickAndStage({required bool media}) => _guard(() async {
    if (_outbox == null || isBusy) return;
    _picking = true;
    _busy = media ? _l.busyChoosingMedia : _l.busyChoosingFiles;
    _emit();
    var usedPickerCache = false;
    try {
      final picked = await _withSystemUi(
        () => picker.FilePicker.pickFiles(
          dialogTitle: _l.pickerTitle,
          type: media ? picker.FileType.media : picker.FileType.any,
          // Original quality: no compression or transcoding of photos/videos.
          darwinOptions: const picker.DarwinOptions(
            assetRepresentationMode:
                picker.DarwinAssetRepresentationMode.current,
          ),
        ),
      );
      if (_closing || picked.isEmpty) return;
      usedPickerCache = Platform.isAndroid || Platform.isIOS;
      _preparing = true;
      for (final item in picked) {
        if (_sources.length >= core.TransferLimits.maxFiles) {
          throw const core.StorageException('TOO_MANY_FILES', 'Too many files');
        }
        final placeholder = const Uuid().v4();
        _sources.add(
          SelectedSource(
            id: placeholder,
            name: item.name,
            bytes: item.lengthSync(),
            status: SourceStatus.preparing,
          ),
        );
        _busy = _l.busyPreparing(item.name);
        _emit();
        try {
          final path = item.path;
          final prepared = path == null
              ? await _outbox!.stageStream(
                  item.readAsByteStream(),
                  displayName: item.name,
                  expectedSizeBytes: item.lengthSync(),
                )
              : await _outbox!.stageFile(File(path), displayName: item.name);
          final index = _sources.indexWhere(
            (source) => source.id == placeholder,
          );
          _sources[index] = SelectedSource(
            id: prepared.manifest.fileId,
            name: prepared.manifest.visibleName,
            bytes: prepared.manifest.sizeBytes,
          );
        } catch (error) {
          _sources.removeWhere((source) => source.id == placeholder);
          rethrow;
        }
        _emit();
      }
    } finally {
      _picking = false;
      _preparing = false;
      _busy = null;
      // The picker copied the selection into the app cache; the immutable
      // outbox copy is now the only one we need. Originals are untouched.
      if (usedPickerCache) {
        try {
          await picker.FilePicker.clearTemporaryFiles();
        } catch (error, stack) {
          DiagnosticsLog.instance.error('picker-cache', error, stack);
        }
      }
    }
  });

  @override
  Future<void> addSourcePaths(List<String> paths) => _guard(() async {
    if (isBusy || _outbox == null) return;
    _preparing = true;
    _emit();
    try {
      for (final path in paths) {
        if (_sources.length >= core.TransferLimits.maxFiles) break;
        _busy = _l.busyPreparing(p.basename(path));
        _emit();
        final prepared = await _outbox!.stageFile(File(path));
        _sources.add(
          SelectedSource(
            id: prepared.manifest.fileId,
            name: prepared.manifest.visibleName,
            bytes: prepared.manifest.sizeBytes,
          ),
        );
        _emit();
      }
    } finally {
      _preparing = false;
      _busy = null;
    }
  });

  @override
  Future<void> removeSource(String sourceId) => _guard(() async {
    _sources.removeWhere((item) => item.id == sourceId);
    if (!_referenced(sourceId)) await _outbox?.remove(sourceId);
  });
  @override
  Future<void> clearSources() => _guard(() async {
    final ids = _sources.map((source) => source.id).toList();
    _sources.clear();
    for (final id in ids) {
      if (!_referenced(id)) await _outbox?.remove(id);
    }
  });
  bool _referenced(String fileId) => _jobs.any(
    (job) =>
        !job.isTerminal &&
        job.manifest.files.any((file) => file.fileId == fileId),
  );

  @override
  Future<void> sendTo(String peerId) => _guard(() async {
    if (isBusy || _sources.isEmpty || _outbox == null) return;
    if (_jobs.where((job) => !job.isTerminal).length >= 10) {
      throw const core.StorageException('QUEUE_FULL', 'Queue is full');
    }
    if (_running.isNotEmpty) {
      _status = _l.waitCurrentSendOrPause;
      return;
    }
    final peer = _trusted?.byId(peerId);
    if (peer == null || !_online.contains(peerId)) {
      throw const core.NetworkException('PEER_UNAVAILABLE', 'Peer unavailable');
    }
    final manifest = core.TransferManifest(
      requestId: const Uuid().v4(),
      files: _sources
          .map((source) => _outbox!.get(source.id).manifest)
          .toList(),
    );
    final job = OutgoingJob(
      id: manifest.requestId,
      peerId: peerId,
      peerName: peer.displayName,
      manifest: manifest,
      createdAt: DateTime.now(),
    );
    _journal!.save(
      job,
    ); // Persist the idempotency key before the first request.
    _jobs.insert(0, job);
    _sources.clear();
    _status = _l.requestSent;
    _emit();
    _launch(_runJob(job));
  });

  Future<void> _runJob(OutgoingJob job, {bool resumeSource = false}) async {
    if (_closing ||
        _disposed ||
        !_foreground ||
        _running.isNotEmpty ||
        job.isTerminal) {
      return;
    }
    final run = _OutgoingRun(resumeSource: resumeSource);
    _outgoingRuns[job.id] = run;
    _running.add(job.id);
    var retries = 0;
    try {
      while (_canRun(job, run)) {
        // Re-read trust and the latest verified address for every attempt.
        // Discovery can update an endpoint but can never replace its pin.
        final peer = _trusted?.byId(job.peerId);
        if (peer == null || peer.endpoint == null) {
          if (job.localState != 'cancelling') job.localState = 'paused';
          job.detail = _l.peerUnavailableOrRevoked;
          break;
        }
        final client = core.CoreClient.forPeer(peer);
        _activeClients[job.id] = client;
        if (job.localState != 'cancelling') job.localState = 'sending';
        job.detail = null;
        _save(job);
        Duration? delay;
        try {
          await _runAttempt(job, client, run);
          break;
        } catch (error) {
          // A local action always wins over a transport error caused by closing
          // its socket. In particular, a delayed retry cannot undo that action.
          if (!_canRun(job, run) || job.isTerminal) break;
          if (!_retryPolicy.canRetry(error)) {
            if (job.localState != 'cancelling') job.localState = 'paused';
            job.detail = _friendly(error);
            break;
          }
          delay = _retryPolicy.delayBeforeRetry(++retries);
          if (delay == null) {
            if (job.localState != 'cancelling') job.localState = 'paused';
            // The peer did not answer: only a fresh successful probe may
            // mark it reachable again and continue this job.
            _online.remove(job.peerId);
            final attempts = _autoResumeAttempts[job.id] ?? 0;
            final automatic = attempts < _maxAutoResumes;
            if (automatic) _autoResume.add(job.id);
            job.detail = job.localState == 'cancelling'
                ? _l.cancelRetriesExhausted
                : automatic
                ? _l.connectionLostAutoResume
                : _l.connectionNotRestored;
            break;
          }
          if (job.localState != 'cancelling') job.localState = 'retry_wait';
          final seconds = (delay.inMilliseconds / 1000).toStringAsFixed(1);
          job.detail = job.localState == 'cancelling'
              ? _l.cancelRetrying(retries, _retryPolicy.maxRetries, seconds)
              : _l.connectionRetrying(
                  retries,
                  _retryPolicy.maxRetries,
                  seconds,
                );
          _save(job);
        } finally {
          client.close();
          _activeClients.remove(job.id);
        }
        if (!await run.wait(delay, injectedDelay: _runtime.retryDelay)) {
          break;
        }
      }
    } finally {
      run.cancel();
      _outgoingRuns.remove(job.id);
      _activeClients.remove(job.id);
      _running.remove(job.id);
      if (job.isTerminal) {
        _autoResume.remove(job.id);
        _autoResumeAttempts.remove(job.id);
      }
      _save(job);
      if (job.isTerminal) await _cleanupJobSources(job);
      _scheduleAutoResume();
    }
  }

  /// Continues one job that the lifecycle or the network interrupted, once
  /// its peer is reachable again. Manual pauses are never resumed here.
  void _scheduleAutoResume() {
    if (_closing || _disposed || !_foreground || _running.isNotEmpty) return;
    for (final id in _autoResume.toList()) {
      final job = _jobs.where((item) => item.id == id).firstOrNull;
      if (job == null ||
          job.isTerminal ||
          (job.localState != 'paused' && job.localState != 'cancelling')) {
        _autoResume.remove(id);
        continue;
      }
      if (!_online.contains(job.peerId)) continue;
      _autoResume.remove(id);
      _autoResumeAttempts[id] = (_autoResumeAttempts[id] ?? 0) + 1;
      DiagnosticsLog.instance.info('auto-resume');
      _launch(_runJob(job));
      return;
    }
  }

  bool _canRun(OutgoingJob job, _OutgoingRun run) =>
      !run.cancelled &&
      !_closing &&
      !_disposed &&
      _foreground &&
      !job.isTerminal;

  Future<void> _runAttempt(
    OutgoingJob job,
    core.CoreClient client,
    _OutgoingRun run,
  ) async {
    Timer? poller;
    var pollBusy = false;
    var attemptActive = true;
    try {
      if (job.remoteId == null) {
        // The same manifest request ID reconciles a lost offer response.
        final remote = await client.offer(job.manifest);
        job.remoteId = remote.transferId;
        _applySnapshot(job, remote);
      }
      if (!_canRun(job, run)) return;
      if (job.localState == 'cancelling') {
        _applySnapshot(job, await client.cancel(job.remoteId!));
        return;
      }
      final consentWait = Stopwatch()..start();
      while (true) {
        if (!_canRun(job, run) || job.localState != 'sending') return;
        final snapshot = await client.transferStatus(job.remoteId!);
        _applySnapshot(job, snapshot);
        if (_terminal(snapshot) || !_canRun(job, run)) return;
        if (snapshot.state != core.TransferState.offered) break;
        if (consentWait.elapsed > const Duration(seconds: 120)) {
          throw const core.NetworkException(
            'CONSENT_TIMEOUT',
            'No consent received',
          );
        }
        // This wait is also interruptible by pause/cancel/background/shutdown.
        if (!await run.wait(const Duration(seconds: 1))) return;
      }
      if (job.snapshot!.pausedBySource) {
        if (!run.resumeSource) {
          job.localState = 'paused';
          job.detail = _l.senderPausedTapResume;
          return;
        }
        _applySnapshot(job, await client.resume(job.remoteId!));
      }
      // Only an explicit resume action grants this once. A later automatic
      // attempt must not clear a pause that appeared after that action.
      run.resumeSource = false;
      if (!_canRun(job, run)) return;
      if (job.snapshot!.pausedBySink) {
        job.localState = 'paused';
        job.detail = _l.recipientPaused;
        return;
      }
      // Progress shown in the interface comes only from the Sink's journal.
      poller = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (pollBusy ||
            !attemptActive ||
            !_canRun(job, run) ||
            job.localState != 'sending') {
          return;
        }
        pollBusy = true;
        try {
          final snapshot = await client.transferStatus(job.remoteId!);
          if (attemptActive &&
              _canRun(job, run) &&
              job.localState == 'sending') {
            _applySnapshot(job, snapshot);
          }
        } catch (_) {
          /* Main upload resolves a network failure. */
        } finally {
          pollBusy = false;
        }
      });
      for (final file in job.manifest.files) {
        if (!_canRun(job, run) || job.localState != 'sending') return;
        final prepared = _outbox!.get(file.fileId);
        await client.uploadFile(
          transferId: job.remoteId!,
          fileId: file.fileId,
          source: File(prepared.path),
        );
        _applySnapshot(job, await client.transferStatus(job.remoteId!));
      }
      if (!_canRun(job, run)) return;
      _applySnapshot(job, await client.transferStatus(job.remoteId!));
      if (!_terminal(job.snapshot!)) {
        throw const core.NetworkException(
          'AWAITING_COMMIT',
          'Waiting for a verified final receipt',
        );
      }
    } finally {
      attemptActive = false;
      poller?.cancel();
    }
  }

  void _applySnapshot(OutgoingJob job, core.TransferSnapshot snapshot) {
    validateTransferReceipt(
      job.manifest,
      snapshot,
      transferId: job.remoteId,
      sourcePeerId: _identity?.peerId,
    );
    job.snapshot = snapshot;
    switch (snapshot.state) {
      case core.TransferState.completed:
        job.localState = 'completed';
      case core.TransferState.cancelled:
        job.localState = 'cancelled';
      case core.TransferState.rejected:
        job.localState = 'rejected';
      case core.TransferState.expired:
        job.localState = 'expired';
        job.detail = _l.consentExpiredNewRequest;
      case core.TransferState.failed:
        job.localState = 'failed';
        job.detail = _l.receiveNotFinished;
      case core.TransferState.partiallyCompleted:
        job.localState = 'partially_completed';
        final completed = snapshot.files
            .where((file) => file.state == core.FileState.committed)
            .length;
        job.detail = _l.partiallySaved(completed, snapshot.files.length);
      default:
        break;
    }
    _save(job);
  }

  void _save(OutgoingJob job) {
    if (!_disposed) {
      _journal?.save(job);
      _emit();
    }
  }

  Future<void> _cleanupJobSources(OutgoingJob job) async {
    // A rejection/cancel/expiry is not evidence that another copy exists. Keep
    // the prepared payload until a complete validated receipt, or a separate
    // explicit cleanup action with its last-copy warning.
    if (job.localState != 'completed' ||
        job.snapshot?.state != core.TransferState.completed) {
      return;
    }
    for (final file in job.manifest.files) {
      if (!_referenced(file.fileId) &&
          !_sources.any((item) => item.id == file.fileId)) {
        try {
          await _outbox?.remove(file.fileId);
        } catch (_) {
          /* Safe later cleanup. */
        }
      }
    }
  }

  bool _canRetryPrepared(OutgoingJob job) {
    if (!job.isTerminal ||
        job.localState == 'completed' ||
        _outbox == null ||
        _trusted?.byId(job.peerId) == null ||
        (job.snapshot?.files.any(
              (file) => file.state == core.FileState.committed,
            ) ??
            false)) {
      return false;
    }
    final available = {
      for (final file in _outbox!.list()) file.manifest.fileId: file.manifest,
    };
    return job.manifest.files.every((file) {
      final prepared = available[file.fileId];
      return prepared != null &&
          prepared.displayName == file.displayName &&
          prepared.sizeBytes == file.sizeBytes &&
          prepared.sha256 == file.sha256 &&
          prepared.mimeType == file.mimeType;
    });
  }

  @override
  Future<void> retryTransfer(String transferId) => _guard(() async {
    if (transferId.startsWith('in:') || isBusy || _outbox == null) return;
    final previous = _job(transferId);
    if (!_canRetryPrepared(previous)) return;
    if (_running.isNotEmpty) {
      _status = _l.waitCurrentSendOrPause;
      return;
    }
    if (_jobs.where((job) => !job.isTerminal).length >= 10) {
      throw const core.StorageException('QUEUE_FULL', 'Queue is full');
    }
    if (!_online.contains(previous.peerId)) {
      throw const core.NetworkException('PEER_UNAVAILABLE', 'Peer unavailable');
    }
    final manifest = core.TransferManifest(
      requestId: const Uuid().v4(),
      files: previous.manifest.files,
    );
    final job = OutgoingJob(
      id: manifest.requestId,
      peerId: previous.peerId,
      peerName: previous.peerName,
      manifest: manifest,
      createdAt: DateTime.now(),
    );
    _journal!.save(job);
    _jobs.insert(0, job);
    _status = _l.newRequestFromCopies;
    _emit();
    _launch(_runJob(job));
  });

  @override
  Future<void> pauseTransfer(String transferId) => _guard(() async {
    if (transferId.startsWith('in:')) {
      await _inbox!.pause(transferId.substring(3));
      return;
    }
    final job = _job(transferId);
    if (job.isTerminal || job.localState == 'cancelling') return;
    _autoResume.remove(job.id);
    _outgoingRuns[job.id]?.cancel();
    job.localState = 'paused';
    job.detail = _l.senderPaused;
    _save(job);
    _activeClients[job.id]?.close();
    final peer = _trusted?.byId(job.peerId);
    if (peer != null &&
        job.remoteId != null &&
        job.snapshot?.state != core.TransferState.offered) {
      final control = core.CoreClient.forPeer(peer);
      try {
        _applySnapshot(job, await control.pause(job.remoteId!));
      } finally {
        control.close();
      }
    }
  });

  @override
  Future<void> resumeTransfer(String transferId) => _guard(() async {
    if (transferId.startsWith('in:')) {
      await _inbox!.resume(transferId.substring(3));
      _status = _l.receiveAllowed;
      return;
    }
    final job = _job(transferId);
    if (_running.contains(job.id)) return;
    if (_running.isNotEmpty) {
      _setStatus(_l.waitCurrentSend);
      return;
    }
    _autoResume.remove(job.id);
    _autoResumeAttempts.remove(job.id);
    await _refreshTrusted();
    _launch(_runJob(job, resumeSource: true));
  });

  @override
  Future<void> cancelTransfer(String transferId) => _guard(() async {
    if (transferId.startsWith('in:')) {
      await _inbox!.cancel(transferId.substring(3));
      return;
    }
    final job = _job(transferId);
    if (job.isTerminal) return;
    _outgoingRuns[job.id]?.cancel();
    job.localState = 'cancelling';
    job.detail = _l.confirmingCancel;
    _save(job);
    _activeClients[job.id]?.close();
    if (job.remoteId == null) {
      // An offer response may have been lost. Reconcile the same request ID
      // before cancelling; do not assume the remote offer does not exist.
      job.detail = _l.tapResumeToConfirmCancel;
      _save(job);
      return;
    }
    final peer = _trusted?.byId(job.peerId);
    if (peer == null || peer.endpoint == null) return;
    final control = core.CoreClient.forPeer(peer);
    try {
      _applySnapshot(job, await control.cancel(job.remoteId!));
    } catch (_) {
      job.detail = _l.recipientUnavailableCancel;
    } finally {
      control.close();
      _save(job);
    }
  });

  OutgoingJob _job(String value) =>
      _jobs.where((job) => 'out:${job.id}' == value).firstOrNull ??
      (throw const core.StorageException('NOT_FOUND', 'Unknown transfer'));

  @override
  Future<void> respondToTransfer(String transferId, bool accept) =>
      _guard(() async {
        if (accept) {
          if (_cleaning || _changingQuota) {
            throw const core.StorageException(
              'BUSY',
              'Storage settings are changing.',
            );
          }
          await _inbox!.accept(transferId);
        } else {
          await _inbox!.reject(transferId);
        }
      });

  @override
  Future<void> createInvitation() => _guard(() async {
    if (_host == null) {
      throw const core.NetworkException('RECEIVING_DISABLED', 'Host off');
    }
    _addresses = await _runtime.addresses();
    if (_addresses.isEmpty) {
      throw const core.NetworkException('NO_LAN_ADDRESS', 'No LAN');
    }
    // Several ranked addresses: the scanner tries each, so a wrong first
    // guess (VPN, virtual adapter, hotspot) does not break pairing.
    final invite = _host!.createInvite(
      hostAddresses: _addresses.take(core.PairingInvite.maxEndpoints).toList(),
    );
    _invitation = PairingInvitation(
      payload: invite.encode(),
      expiresAt: DateTime.now().add(Duration(seconds: invite.ttlSeconds)),
    );
  });

  @override
  Future<void> pairFromText(String payload) => _guard(() async {
    if (_pairing || _identity == null || _trusted == null) return;
    final invite = core.PairingInvite.parse(payload);
    if (invite.serverPin == _identity!.serverPin) {
      throw const core.NetworkException('SELF_PAIRING', 'Same device');
    }
    _pairing = true;
    _setStatus(_l.confirmPairingWithCode(deviceCode ?? ''));
    _emit();
    core.CoreClient? client;
    try {
      _addresses = await _runtime.addresses();
      final local = _host == null || _addresses.isEmpty
          ? null
          : Uri(scheme: 'https', host: _addresses.first, port: _host!.port);
      // Try each advertised address; only the pinned key authenticates.
      Object? lastError;
      for (final endpoint in invite.endpoints) {
        final candidate = core.CoreClient(
          endpoint: endpoint,
          serverPin: invite.serverPin,
        );
        _pairingClient = candidate;
        try {
          await candidate.requestPairing(
            invite,
            identity: _identity!,
            peers: _trusted!,
            localEndpoint: local,
          );
          client = candidate;
          break;
        } on SocketException catch (error) {
          lastError = error;
          candidate.close();
        } on TimeoutException catch (error) {
          lastError = error;
          candidate.close();
        } on HttpException catch (error) {
          lastError = error;
          candidate.close();
        } on HandshakeException catch (error) {
          // A different TLS server at this address: try the next candidate.
          lastError = error;
          candidate.close();
        } on core.NetworkException catch (error) {
          if (error.code != 'IDENTITY_CHANGED' &&
              error.code != 'ENDPOINT_CHANGED') {
            candidate.close();
            rethrow;
          }
          lastError = error;
          candidate.close();
        }
      }
      if (client == null) {
        throw lastError ??
            const core.NetworkException('PEER_UNAVAILABLE', 'Unreachable');
      }
      // The remote clock is not a local timer. The Host validates expiry;
      // a monotonic local deadline only bounds how long this UI waits.
      final waiting = Stopwatch()..start();
      while (!_closing &&
          !_disposed &&
          waiting.elapsed < const Duration(seconds: 180)) {
        final peer = await client.completePairing(
          identity: _identity!,
          peers: _trusted!,
        );
        if (peer != null) {
          _online.add(peer.peerId);
          _status = _l.pairedWith(peer.displayName);
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      throw const core.NetworkException('PAIRING_EXPIRED', 'Pairing timed out');
    } finally {
      client?.close();
      _pairingClient?.close();
      _pairing = false;
      _pairingClient = null;
    }
  });

  @override
  Future<void> scanInvitation() => _guard(() async {
    final text = await _withSystemUi(() async => scanCode?.call());
    if (text != null) await pairFromText(text);
  });
  @override
  Future<void> respondToPairing(String requestId, bool accept) =>
      _guard(() async {
        if (accept) {
          await _host!.approvePairing(requestId);
        } else {
          await _host!.rejectPairing(requestId);
        }
        _status = accept ? _l.pairingApproved : _l.pairingDeclined;
        _launch(_refreshTrusted());
      });

  @override
  Future<void> refreshPeers() => _guard(() async {
    if (_identity == null) return;
    if (!await _runtime.ensurePermission()) {
      _network = NetworkState.permissionRequired;
      return;
    }
    if (_host == null) await _synchronizeHost();
    _updatePeerTimer();
    await _checkLocalNetwork();
    await _refreshTrusted();
  });
  Future<void>? _refreshInFlight;

  /// Concurrent callers share one probe, so nobody acts on stale reachability.
  Future<void> _refreshTrusted() => _refreshInFlight ??= _refreshTrustedNow()
      .whenComplete(() => _refreshInFlight = null);

  Future<void> _refreshTrustedNow() async {
    if (_trusted == null || _closing || _disposed) return;
    try {
      for (final peer in _trusted!.list()) {
        final candidates = <Uri>{
          if (peer.endpoint != null) peer.endpoint!,
          ..._discovered
              .where((item) => item.name == peer.displayName)
              .map((item) => item.endpoint),
          // Bonjour can suffix duplicate names. Try other bounded address hints
          // too; only the already pinned TLS key may authenticate the peer.
          ..._discovered.map((item) => item.endpoint),
        }.take(8);
        var reachable = false;
        for (final endpoint in candidates) {
          final client = core.CoreClient.forPeer(peer, endpoint: endpoint);
          try {
            await client.capabilities().timeout(const Duration(seconds: 3));
            if (_trusted!.byId(peer.peerId) == null) break;
            await _trusted!.updateEndpoint(peer.peerId, endpoint);
            final found = _discovered
                .where((item) => item.endpoint == endpoint)
                .firstOrNull;
            if (found != null) {
              _platforms[peer.peerId] = _platformOf(found.platform);
            }
            reachable = true;
            break;
          } catch (_) {
            /* An announcement cannot replace the trusted key. */
          } finally {
            client.close();
          }
        }
        if (reachable) {
          _online.add(peer.peerId);
        } else {
          _online.remove(peer.peerId);
        }
      }
    } finally {
      _emit();
    }
    _scheduleAutoResume();
  }

  @override
  Future<void> setReceiving(bool enabled) => _guard(() async {
    _receiveWanted = enabled;
    if (enabled) {
      if (!await _runtime.ensurePermission()) {
        _network = NetworkState.permissionRequired;
        return;
      }
      await _synchronizeHost();
    } else {
      await _synchronizeHost();
    }
  });
  Future<void> _stopHostNow() async {
    _invitation = null;
    _receiving = false;
    for (final subscription in _hostSubscriptions) {
      await subscription.cancel();
    }
    _hostSubscriptions.clear();
    await _discovery?.close();
    _discovery = null;
    _discovered.clear();
    final host = _host;
    _host = null;
    await host?.close();
    _emit();
  }

  @override
  Future<void> revokePeer(String peerId) => _guard(() async {
    // Local revocation is immediate; a disconnected remote cannot be forced
    // to delete its own record, and it receives no future authorization here.
    _online.remove(peerId);
    for (final job in _jobs.where(
      (job) => job.peerId == peerId && !job.isTerminal,
    )) {
      _outgoingRuns[job.id]?.cancel();
      _activeClients[job.id]?.close();
      if (job.localState != 'cancelling') job.localState = 'paused';
      job.detail = job.localState == 'cancelling'
          ? _l.trustRevokedCancelUnknown
          : _l.trustRevokedStopped;
      _save(job);
    }
    // Stop transmission before an OS secret-store write can block. If that
    // write fails, the user sees a revocation error but the stopped run remains
    // paused instead of silently completing its pending retry.
    await (_host?.revoke(peerId) ?? _trusted!.revoke(peerId));
  });
  @override
  Future<void> renameDevice(String name) => _guard(() async {
    final identity = _identity;
    if (identity == null) return;
    final clean = name.trim();
    if (clean.isEmpty || clean == identity.displayName) return;
    _identity = await identity.rename(_secrets, clean);
    // The host, invitations and Bonjour record carry the name: restart them.
    await _restartHost();
    _setStatus(_l.deviceRenamed);
  });

  Future<void> _restartHost() {
    final next = _hostLifecycle.then((_) async {
      await _stopHostNow();
      if (_receiveWanted && _foreground && !_closing && _identity != null) {
        await _startHostNow();
      }
    });
    _hostLifecycle = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) => _guard(() async {
    await _secrets.write('transfer.settings.theme', mode.name);
    _theme = mode;
  });

  @override
  Future<void> setLocale(Locale? locale) => _guard(() async {
    await _secrets.write(
      'transfer.settings.locale',
      locale?.languageCode ?? '',
    );
    _locale = locale;
  });

  @override
  Future<void> openSystemSettings() => _guard(() async {
    await _runtime.openSystemSettings?.call();
  });

  @override
  Future<void> deleteTransfer(String transferId) => _guard(() async {
    if (transferId.startsWith('in:')) {
      final id = transferId.substring(3);
      await _inbox!.deleteTransfer(id);
      _exports?.deleteTransfer(id);
      _setStatus(_l.transferDeleted);
      return;
    }
    final job = _job(transferId);
    if (!job.isTerminal || _running.contains(job.id)) return;
    await _removeJob(job);
    _setStatus(_l.recordDeleted);
  });

  /// Removes a finished outgoing record and its prepared copies that no
  /// selection or other unfinished job uses. The interface confirms first,
  /// including the warning that such a copy may be the last one.
  Future<void> _removeJob(OutgoingJob job) async {
    _jobs.remove(job);
    _journal?.delete(job.id);
    _autoResume.remove(job.id);
    _autoResumeAttempts.remove(job.id);
    for (final file in job.manifest.files) {
      if (_unusedSource(file.fileId) &&
          !_jobs.any(
            (other) => other.manifest.files.any((f) => f.fileId == file.fileId),
          ) &&
          (_outbox?.list().any((item) => item.manifest.fileId == file.fileId) ??
              false)) {
        await _outbox!.remove(file.fileId);
      }
    }
  }

  @override
  Future<void> clearHistory() => _guard(() async {
    var removed = 0;
    for (final job in _jobs.where((job) => job.isTerminal).toList()) {
      if (_running.contains(job.id)) continue;
      await _removeJob(job);
      removed++;
    }
    for (final item in _inboxList()) {
      // Completed incoming transfers own received files: they are deleted only
      // individually, never by a bulk history action.
      if (_terminal(item) &&
          item.state != core.TransferState.completed &&
          item.state != core.TransferState.partiallyCompleted) {
        await _inbox!.deleteTransfer(item.transferId);
        _exports?.deleteTransfer(item.transferId);
        removed++;
      }
    }
    _setStatus(_l.historyCleared(removed));
  });

  /// Keeps the history bounded: finished outgoing records and unsuccessful
  /// incoming records older than 90 days are removed at startup. Received
  /// files are never removed automatically.
  Future<void> _pruneHistory() async {
    final limit = DateTime.now().subtract(const Duration(days: 90));
    try {
      for (final job
          in _jobs
              .where((job) => job.isTerminal && job.createdAt.isBefore(limit))
              .toList()) {
        await _removeJob(job);
      }
      for (final item in _inbox?.list() ?? const <core.TransferSnapshot>[]) {
        if (_terminal(item) &&
            item.state != core.TransferState.completed &&
            item.state != core.TransferState.partiallyCompleted &&
            item.createdAt.isBefore(limit)) {
          await _inbox!.deleteTransfer(item.transferId);
          _exports?.deleteTransfer(item.transferId);
        }
      }
    } catch (error, stack) {
      DiagnosticsLog.instance.error('prune-history', error, stack);
    }
    _invalidate();
  }

  @override
  Future<void> shareReceivedFile(String transferId, String fileId) => _guard(
    () async {
      final share = _runtime.shareFiles;
      if (share == null || !transferId.startsWith('in:')) return;
      final snapshot = _inbox!.status(transferId.substring(3));
      final file = snapshot.files
          .where(
            (item) =>
                item.fileId == fileId && item.state == core.FileState.committed,
          )
          .firstOrNull;
      if (file == null) {
        throw const core.StorageException('NOT_FOUND', 'No committed file');
      }
      final saved = await _committedFile(file);
      await _withSystemUi(() => share([saved]));
    },
  );

  @override
  Future<void> exportDiagnostics() => _guard(() async {
    final data = _dataPath;
    if (data == null) return;
    final snapshot = await DiagnosticsLog.instance.exportSnapshot(
      Directory(p.join(data, 'logs', 'export')),
    );
    if (snapshot == null) {
      throw const core.StorageException('EXPORT_FAILED', 'No diagnostics');
    }
    final share = _runtime.shareFiles;
    if (share != null) {
      await _withSystemUi(() => share([snapshot]));
    } else {
      _setStatus(_l.diagnosticsSaved(snapshot.path));
    }
  });

  static const _quotaOptions = <int>[
    5 * 1024 * 1024 * 1024,
    10 * 1024 * 1024 * 1024,
    20 * 1024 * 1024 * 1024,
    50 * 1024 * 1024 * 1024,
  ];

  bool _unusedSource(String id) =>
      !_sources.any((source) => source.id == id) && !_referenced(id);

  Future<void> _updateStorageOverview() async {
    if (_storageRefreshing ||
        _storageBudget == null ||
        _outbox == null ||
        _closing) {
      return;
    }
    _storageRefreshing = true;
    _emit();
    try {
      final snapshot = await _storageBudget!.inspect();
      final unused = _outbox!.list().where(
        (file) => _unusedSource(file.manifest.fileId),
      );
      final incomplete = await _inbox!.previewIncompleteCleanup();
      _storageOverview = StorageOverview(
        availableBytes: snapshot.availableBytes,
        temporaryBytes: snapshot.temporaryBytes,
        reservedBytes: snapshot.reservedBytes,
        safetyReserveBytes: snapshot.safetyReserveBytes,
        temporaryQuotaBytes: snapshot.temporaryQuotaBytes,
        unusedFiles: List.unmodifiable(
          unused.map(
            (file) => TemporaryFileItem(
              id: file.manifest.fileId,
              name: file.manifest.visibleName,
              bytes: file.manifest.sizeBytes,
            ),
          ),
        ),
        incompleteIncoming: List.unmodifiable(
          incomplete.map((item) {
            final transfer = _inbox!.status(item.transferId);
            return IncomingCleanupItem(
              id: item.transferId,
              title: _title(transfer.manifest),
              peerName: _peerName(transfer.peerId),
              temporaryBytes: item.temporaryBytes,
              reservedBytes: item.reservedBytes,
              pendingFileCount: item.incompleteFileCount,
              completedFileCount: item.committedFileCount,
            );
          }),
        ),
        checkedAt: DateTime.now().toUtc(),
      );
    } finally {
      _storageRefreshing = false;
      _emit();
    }
  }

  void _refreshStorageSoon() {
    if (_closing || _disposed || _storageTimer != null) return;
    _storageTimer = Timer(const Duration(milliseconds: 500), () {
      _storageTimer = null;
      _launch(_updateStorageOverview());
    });
  }

  @override
  Future<void> refreshStorage() => _guard(_updateStorageOverview);

  @override
  Future<void> setTemporaryQuota(int bytes) => _guard(() async {
    if (isBusy || _storageBudget == null) return;
    if (!_quotaOptions.contains(bytes)) {
      throw const core.StorageException(
        'INVALID_QUOTA',
        'Unsupported storage limit.',
      );
    }
    _changingQuota = true;
    _emit();
    try {
      final previous = (await _storageBudget!.inspect()).temporaryQuotaBytes;
      await _storageBudget!.setTemporaryQuotaBytes(bytes);
      try {
        await _secrets.write(
          'transfer.settings.temporaryQuotaBytes',
          bytes.toString(),
        );
      } catch (_) {
        await _storageBudget!.setTemporaryQuotaBytes(previous);
        rethrow;
      }
      _status = _l.quotaSaved;
    } finally {
      _changingQuota = false;
      await _updateStorageOverview();
    }
  });

  @override
  Future<void> clearUnusedTemporary(List<String> fileIds) => _guard(() async {
    if (isBusy || _outbox == null) return;
    _cleaning = true;
    _busy = _l.busyCleaningCopies;
    _emit();
    var count = 0;
    try {
      // Only the exact previewed selection is eligible. New files and all
      // live job/source references are rechecked immediately before deletion.
      for (final id in fileIds.toSet()) {
        if (!_unusedSource(id)) continue;
        if (!_outbox!.list().any((file) => file.manifest.fileId == id)) {
          continue;
        }
        await _outbox!.remove(id);
        count++;
      }
      _status = _l.copiesCleared(count);
    } finally {
      _cleaning = false;
      _busy = null;
      await _updateStorageOverview();
    }
  });

  @override
  Future<void> clearIncompleteIncoming(List<String> transferIds) =>
      _guard(() async {
        if (isBusy || _inbox == null) return;
        _cleaning = true;
        _busy = _l.busyCleaningIncoming;
        _emit();
        var stopped = 0;
        var removedFiles = 0;
        try {
          // Confirmed IDs are the upper bound of this action. Re-read each
          // candidate; new offers and a batch committed since the preview are
          // excluded. The core serializes discard with any active writer.
          for (final id in transferIds.toSet()) {
            final eligible = await _inbox!.previewIncompleteCleanup();
            if (!eligible.any((item) => item.transferId == id)) continue;
            final result = await _inbox!.discardIncomplete(id);
            stopped++;
            removedFiles += result.removedFileCount;
          }
          _status = _l.incomingCleared(stopped, removedFiles);
        } finally {
          _cleaning = false;
          _busy = null;
          await _updateStorageOverview();
        }
      });

  ReceivedFile _receivedFile(String transferId, core.FileSnapshot file) {
    final record = _exports?.latest(transferId, file.fileId);
    final success = _exports?.lastSuccess(transferId, file.fileId);
    final phase = _unconfirmedExports.contains((transferId, file.fileId))
        ? ExportPhase.unknown
        : record == null
        ? ExportPhase.notExported
        : switch (record.state) {
            ExportState.exporting => ExportPhase.exporting,
            ExportState.exported => ExportPhase.exported,
            ExportState.cancelled => ExportPhase.cancelled,
            ExportState.failed => ExportPhase.failed,
            ExportState.unknown => ExportPhase.unknown,
          };
    return ReceivedFile(
      id: file.fileId,
      name: file.manifest.visibleName,
      bytes: file.manifest.sizeBytes,
      exportPhase: phase,
      exportDestination: success?.destinationLabel,
      exportDetail: switch (phase) {
        ExportPhase.notExported => _l.exportNotExported,
        ExportPhase.exporting => _l.exportInProgress,
        ExportPhase.exported => _l.exportDone(record!.destinationLabel ?? ''),
        ExportPhase.cancelled => _l.exportCancelledDetail,
        ExportPhase.failed =>
          record?.errorCode == 'COMMITTED_FILE_CHANGED'
              ? _l.exportFileChanged
              : _l.exportFailedDetail,
        ExportPhase.unknown => _l.exportUnknownDetail,
      },
    );
  }

  Future<File> _committedFile(core.FileSnapshot snapshot) async {
    final path = snapshot.finalPath;
    if (_dataPath == null ||
        snapshot.state != core.FileState.committed ||
        path == null) {
      throw const core.StorageException('NOT_FOUND', 'No committed file.');
    }
    final received = p.normalize(
      p.absolute(p.join(_dataPath!, 'inbox', 'received')),
    );
    final absolute = p.normalize(p.absolute(path));
    if (!p.isWithin(received, absolute) ||
        await FileSystemEntity.type(absolute, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const core.StorageException(
        'COMMITTED_FILE_CHANGED',
        'Committed file unavailable.',
      );
    }
    final file = File(absolute);
    if (p.normalize(await file.resolveSymbolicLinks()) != absolute ||
        await file.length() != snapshot.manifest.sizeBytes) {
      throw const core.StorageException(
        'COMMITTED_FILE_CHANGED',
        'Committed file changed.',
      );
    }
    return file;
  }

  @override
  Future<void> exportReceivedFile(
    String transferId,
    String fileId,
  ) => _guard(() async {
    if (!capabilities.fileExport ||
        _exporting ||
        !transferId.startsWith('in:')) {
      return;
    }
    final id = transferId.substring(3);
    final snapshot = _inbox!.status(id);
    final file = snapshot.files
        .where(
          (file) =>
              file.fileId == fileId && file.state == core.FileState.committed,
        )
        .firstOrNull;
    if (file == null) {
      throw const core.StorageException('NOT_FOUND', 'No committed file.');
    }
    _exporting = true;
    ExportRecord? record;
    var copyReported = false;
    try {
      record = _exports!.begin(id, fileId);
      _unconfirmedExports.remove((id, fileId));
      _emit();
      final source = await _committedFile(file);
      final digest = await sha256.bind(source.openRead()).first;
      if (digest.toString() != file.manifest.sha256) {
        throw const core.StorageException(
          'COMMITTED_FILE_CHANGED',
          'Committed contents changed.',
        );
      }
      if (_closing) {
        _exports!.finish(record.id, ExportState.cancelled);
        return;
      }
      final result = await _withSystemUi(
        () => _runtime.exportFile!(
          source: source,
          displayName: p.basename(source.path),
          mimeType:
              file.manifest.mimeType != null &&
                  RegExp(r'^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$')
                      .hasMatch(file.manifest.mimeType!)
              ? file.manifest.mimeType
              : 'application/octet-stream',
        ),
      );
      if (result == null) {
        _exports!.finish(record.id, ExportState.cancelled);
        _status = _l.exportCancelled;
      } else {
        copyReported = true;
        _exports!.finish(
          record.id,
          ExportState.exported,
          destinationLabel: result.destinationLabel,
          platformReference: result.platformReference,
        );
        _status = _l.exportDone(result.destinationLabel);
      }
    } catch (error) {
      final code = error is core.StorageException
          ? error.code
          : error is PlatformException
          ? error.code
          : 'EXPORT_FAILED';
      // The copy can have succeeded if an OS callback or journal write was
      // interrupted; only a positive persisted result yields "exported".
      final latest = _exports!.latest(id, fileId);
      if (record != null &&
          latest?.id == record.id &&
          latest?.state == ExportState.exporting) {
        try {
          _exports!.finish(
            record.id,
            copyReported ||
                    code == 'EXPORT_INTERRUPTED' ||
                    error is FormatException
                ? ExportState.unknown
                : ExportState.failed,
            errorCode: code,
          );
        } catch (_) {
          // A failed journal write cannot turn an uncertain copy into success.
          // The unfinished durable row also recovers as unknown after restart.
          _unconfirmedExports.add((id, fileId));
        }
      }
      rethrow;
    } finally {
      _exporting = false;
      _emit();
    }
  });

  @override
  Future<void> openTransfer(String transferId) => _guard(() async {
    if (!transferId.startsWith('in:')) return;
    final snapshot = _inbox!.status(transferId.substring(3));
    final file = snapshot.files
        .where(
          (item) =>
              item.state == core.FileState.committed &&
              item.errorCode != 'FILE_MISSING',
        )
        .firstOrNull;
    if (file != null) await openReceivedFile(transferId, file.fileId);
  });

  @override
  Future<void> openReceivedFile(String transferId, String fileId) =>
      _guard(() async {
        if (!transferId.startsWith('in:')) return;
        final snapshot = _inbox!.status(transferId.substring(3));
        final file = snapshot.files
            .where(
              (item) =>
                  item.fileId == fileId &&
                  item.state == core.FileState.committed &&
                  item.finalPath != null,
            )
            .firstOrNull;
        if (file == null) {
          throw const core.StorageException('NOT_FOUND', 'No committed file');
        }
        // Only an explicit user action may launch the system's file handler.
        final saved = await _committedFile(file);
        final result = await _withSystemUi(() => OpenFilex.open(saved.path));
        if (result.type != ResultType.done) {
          _setError(_l.cannotOpenFile);
        }
      });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_runtime.mobileLifecycle || _closing) return;
    if (state == AppLifecycleState.paused) {
      // A picker, share sheet, viewer or export dialog of our own stops the
      // Android activity too; the user has not left the app.
      if (_systemUi > 0) return;
      _enterBackground();
    } else if (state == AppLifecycleState.resumed) {
      _resumeForeground();
    }
  }

  /// A running transfer gets a short, OS-sanctioned grace period (iOS
  /// background task) so that briefly switching apps does not interrupt it.
  /// After that the work stops cleanly at a durable checkpoint.
  void _enterBackground() {
    if (!_foreground || _backgroundTimer != null) return;
    final grace = _runtime.backgroundGrace;
    if (grace > Duration.zero && (_running.isNotEmpty || _incomingActive)) {
      _backgroundTimer = Timer(grace, _stopForBackground);
      _launch(_acquireBackgroundTask());
      DiagnosticsLog.instance.info('background grace started');
      return;
    }
    _stopForBackground();
  }

  Future<void> _acquireBackgroundTask() async {
    final begin = _runtime.beginBackgroundTask;
    if (begin == null || _backgroundTask != null) return;
    try {
      _backgroundTask = await begin();
    } catch (error, stack) {
      DiagnosticsLog.instance.error('background-task', error, stack);
    }
    // The app may have returned while the platform call was in flight.
    if (_backgroundTimer == null && _foreground) {
      await _releaseBackgroundTask();
    }
  }

  Future<void> _releaseBackgroundTask() async {
    final token = _backgroundTask;
    _backgroundTask = null;
    if (token == null) return;
    try {
      await _runtime.endBackgroundTask?.call(token);
    } catch (error, stack) {
      DiagnosticsLog.instance.error('background-task-end', error, stack);
    }
  }

  void _stopForBackground() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    if (!_foreground || _closing) return;
    _foreground = false;
    for (final job in _jobs.where((job) => _running.contains(job.id))) {
      _outgoingRuns[job.id]?.cancel();
      // Preserve cancellation intent even when backgrounding interrupts it.
      if (job.localState != 'cancelling') job.localState = 'paused';
      _autoResume.add(job.id);
      job.detail = _l.backgroundedWillResume;
      _save(job);
      _activeClients[job.id]?.close();
    }
    // Reachability is unknown after a background period; re-probe on return.
    _online.clear();
    _updatePeerTimer();
    _launch(_synchronizeHost().whenComplete(_releaseBackgroundTask));
    DiagnosticsLog.instance.info('stopped for background');
  }

  void _resumeForeground() {
    final graceRunning = _backgroundTimer != null;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _launch(_releaseBackgroundTask());
    if (graceRunning || _foreground) {
      // Nothing was interrupted; just re-check what the user may have changed
      // in Settings meanwhile.
      _launch(_checkLocalNetwork());
      return;
    }
    _foreground = true;
    if (_starting || _identity == null || _needsOnboarding) return;
    _launch(
      _guard(() async {
        await _synchronizeHost();
        _updatePeerTimer();
        await _checkLocalNetwork();
        await _refreshTrusted();
      }),
    );
  }

  /// Desktop: close the HTTPS host and journals before the process exits.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    try {
      await shutdown().timeout(const Duration(seconds: 5));
    } catch (_) {
      /* Exit anyway; journals are crash-consistent. */
    }
    return AppExitResponse.exit;
  }

  void _setError(String message) {
    _error = message;
  }

  void _setStatus(String message) {
    _status = message;
  }

  Future<void> _guard(Future<void> Function() action) {
    if (_closing) return Future.value();
    late final Future<void> operation;
    operation = _runGuard(action)
        .whenComplete(() => _operations.remove(operation));
    _operations.add(operation);
    return operation;
  }

  Future<void> _runGuard(Future<void> Function() action) async {
    _error = null;
    try {
      await action();
    } catch (error, stack) {
      DiagnosticsLog.instance.error('action', error, stack);
      if (!_closing) _error = _friendly(error);
    } finally {
      _refreshStorageSoon();
      _emit();
    }
  }

  void _launch(Future<void> action) {
    late final Future<void> task;
    task = action
        .catchError((Object error, StackTrace stack) {
          DiagnosticsLog.instance.error('task', error, stack);
          if (!_closing) {
            _error = _friendly(error);
            _emit();
          }
        })
        .whenComplete(() => _backgroundTasks.remove(task));
    _backgroundTasks.add(task);
  }

  String? _lastMessage;

  /// Change notifications are coalesced per microtask: a burst of progress
  /// events rebuilds the interface once.
  void _emit() {
    _invalidate();
    if (_closing || _disposed || _emitScheduled) return;
    _emitScheduled = true;
    scheduleMicrotask(() {
      _emitScheduled = false;
      if (_closing || _disposed) return;
      final message = _error ?? _status;
      if (message != null && message != _lastMessage) _messageSerial++;
      _lastMessage = message;
      _updateKeepAwake();
      notifyListeners();
    });
  }

  /// Keep the screen on while bytes are moving, so auto-lock does not send
  /// the app to the background in the middle of a large transfer.
  void _updateKeepAwake() {
    final wanted =
        !_closing && _foreground && (_running.isNotEmpty || _incomingActive);
    if (wanted == _keepAwake) return;
    _keepAwake = wanted;
    final toggle = _runtime.setKeepAwake;
    if (toggle != null) unawaited(toggle(wanted).catchError((Object _) {}));
  }

  Future<void> shutdown() => _shutdown ??= _shutdownNow();
  Future<void> _shutdownNow() async {
    _closing = true;
    _receiveWanted = false;
    _foreground = false;
    _peerTimer?.cancel();
    _storageTimer?.cancel();
    _backgroundTimer?.cancel();
    if (_keepAwake) {
      _keepAwake = false;
      await _runtime.setKeepAwake?.call(false).catchError((Object _) {});
    }
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _pairingClient?.close();
    for (final run in _outgoingRuns.values) {
      run.cancel();
    }
    for (final client in _activeClients.values) {
      client.close();
    }
    // Initialization and callers can still own open resources until they settle.
    await _initialization;
    _peerTimer?.cancel();
    await _synchronizeHost();
    while (_backgroundTasks.isNotEmpty || _operations.isNotEmpty) {
      await Future.wait([..._backgroundTasks, ..._operations]);
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _releaseBackgroundTask();
    if (_logDirectory != null) {
      await DiagnosticsLog.instance.detach(_logDirectory!);
    }
    _disposed = true;
    await _inbox?.close();
    await _outbox?.close();
    _journal?.close();
    _exports?.close();
  }

  String _peerName(String peerId) =>
      _trusted?.byId(peerId)?.displayName ?? _l.platformUnknown;
  String _title(core.TransferManifest manifest) => manifest.files.length == 1
      ? manifest.files.single.visibleName
      : _l.filesCount(manifest.files.length);
  static bool _terminal(core.TransferSnapshot snapshot) => {
    core.TransferState.completed,
    core.TransferState.partiallyCompleted,
    core.TransferState.rejected,
    core.TransferState.cancelled,
    core.TransferState.failed,
    core.TransferState.expired,
  }.contains(snapshot.state);
  static TransferPhase _snapshotPhase(core.TransferSnapshot value) {
    if (value.state == core.TransferState.completed) {
      return TransferPhase.completed;
    }
    if (value.files.any(
      (file) =>
          file.state == core.FileState.verifying ||
          file.state == core.FileState.committing,
    )) {
      return TransferPhase.verifying;
    }
    return switch (value.state) {
      core.TransferState.offered => TransferPhase.waitingForConsent,
      core.TransferState.accepted => TransferPhase.queued,
      core.TransferState.transferring => TransferPhase.transferring,
      core.TransferState.paused => TransferPhase.paused,
      core.TransferState.rejected ||
      core.TransferState.cancelled => TransferPhase.cancelled,
      core.TransferState.failed ||
      core.TransferState.partiallyCompleted => TransferPhase.failed,
      core.TransferState.completed => TransferPhase.completed,
      core.TransferState.expired => TransferPhase.expired,
    };
  }

  String? _snapshotDetail(core.TransferSnapshot value) {
    if (value.state == core.TransferState.completed) {
      return _l.verifiedAndSaved;
    }
    if (value.state == core.TransferState.expired) {
      return _l.consentNotReceived;
    }
    final spaceError = value.files
        .map((file) => file.errorCode)
        .where((code) => code == 'DISK_FULL' || code == 'TEMP_QUOTA_EXCEEDED')
        .firstOrNull;
    if (spaceError != null) {
      return _l.partSavedTapResume(
        _friendly(core.StorageException(spaceError, '')),
      );
    }
    if (value.pausedBySink) return _l.recipientPausedShort;
    if (value.pausedBySource) return _l.senderPaused;
    if (value.state == core.TransferState.offered) {
      return _l.consentRequired;
    }
    if (value.files.any((file) => file.errorCode != null)) {
      return _l.someFilesUnfinished;
    }
    return null;
  }

  static DevicePlatform _platformOf(String value) =>
      DevicePlatform.values.where((item) => item.name == value).firstOrNull ??
      DevicePlatform.unknown;
  String _friendly(Object error) {
    final code = error is core.NetworkException
        ? error.code
        : error is core.StorageException
        ? error.code
        : error is PlatformException
        ? error.code
        : null;
    return switch (code) {
      'PEER_UNAVAILABLE' || 'NO_LAN_ADDRESS' => _l.errPeerUnavailable,
      'PAIRING_EXPIRED' || 'INVITE_EXPIRED' => _l.errQrExpired,
      'PAIRING_REJECTED' => _l.errPairingRejected,
      'SELF_PAIRING' => _l.errSelfPairing,
      'UNAUTHORIZED' => _l.errUnauthorized,
      'CONSENT_REQUIRED' || 'CONSENT_TIMEOUT' => _l.errConsentRequired,
      'OFFER_EXPIRED' || 'TRANSFER_EXPIRED' => _l.errOfferExpired,
      'TRANSFER_PAUSED' => _l.errTransferPaused,
      'HASH_MISMATCH' || 'INTEGRITY_MISMATCH' => _l.errHashMismatch,
      'SOURCE_CHANGED' => _l.errSourceChanged,
      'FILE_TOO_LARGE' => _l.errFileTooLarge,
      'DISK_FULL' || 'STORAGE_FULL' => _l.errDiskFull,
      'TEMP_QUOTA_EXCEEDED' => _l.errTempQuotaExceeded,
      'TEMP_QUOTA_BELOW_USAGE' => _l.errQuotaBelowUsage,
      'CAPACITY_UNAVAILABLE' => _l.errCapacityUnavailable,
      'COMMITTED_FILE_CHANGED' => _l.errCommittedFileChanged,
      'EXPORT_INTERRUPTED' => _l.exportUnknownDetail,
      'EXPORT_FAILED' ||
      'EXPORT_IO' ||
      'EXPORT_UNAVAILABLE' => _l.errExportFailed,
      'EXPORT_SOURCE_UNAVAILABLE' => _l.errExportSourceUnavailable,
      'EXPORT_UNSUPPORTED' => _l.errExportUnsupported,
      'EXPORT_BUSY' => _l.errExportBusy,
      'DESTINATION_EXISTS' ||
      'EXPORT_DESTINATION_EXISTS' => _l.errDestinationExists,
      'RATE_LIMITED' => _l.errRateLimited,
      'QUOTA_EXCEEDED' => _l.errQuotaExceeded,
      'JOURNAL_CORRUPT' || 'JOURNAL_TOO_NEW' => _l.errJournal,
      'IDENTITY_CHANGED' => _l.errIdentityChanged,
      'TRANSFER_TOO_SLOW' => _l.errTransferTooSlow,
      'FILE_MISSING' => _l.errFileMissing,
      'TRANSFER_ACTIVE' => _l.errTransferActive,
      'QUEUE_FULL' => _l.errQueueFull,
      'BUSY' || 'WRITER_BUSY' => _l.errBusy,
      'STORAGE_MISSING' || 'NOT_FOUND' => _l.errNotFound,
      _ =>
        error is HandshakeException
            ? _l.errHandshake
            : error is SocketException || error is TimeoutException
            ? _l.errConnectionLost
            : error is FormatException
            ? _l.errFormat
            : error is FileSystemException
            ? _l.errFileSystem
            : code == null
            ? _l.errUnknown
            : _l.errWithCode(code),
    };
  }
}

/// One explicit send/resume owns one finite retry sequence and one stop signal.
/// Cancellation wakes both consent polling and backoff immediately, so closing
/// the app never waits for a pending 16-second retry timer.
class _OutgoingRun {
  _OutgoingRun({required this.resumeSource});
  bool resumeSource;
  bool cancelled = false;
  final _stopped = Completer<void>();
  Timer? _timer;

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    _timer?.cancel();
    _stopped.complete();
  }

  Future<bool> wait(
    Duration duration, {
    Future<void> Function(Duration)? injectedDelay,
  }) async {
    if (cancelled) return false;
    final elapsed = Completer<void>();
    final Future<void> delay;
    if (injectedDelay != null) {
      delay = injectedDelay(duration);
    } else {
      _timer = Timer(duration, elapsed.complete);
      delay = elapsed.future;
    }
    try {
      return await Future.any([
        delay.then((_) => !cancelled),
        _stopped.future.then((_) => false),
      ]);
    } finally {
      _timer?.cancel();
      _timer = null;
    }
  }
}
