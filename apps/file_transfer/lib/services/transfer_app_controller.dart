import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart' as picker;
// Compatibility during the Flutter 3.50 Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:transfer_core/transfer_core.dart' as core;
import 'package:uuid/uuid.dart';

import '../ui/app_controller.dart';
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
  bool _refreshing = false;
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

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      _busy = 'Подготовка защищённого хранилища';
      _emit();
      final root = await _runtime.storageDirectory();
      final data = Directory(p.join(root.path, 'file-transfer-v1'));
      await data.create(recursive: true);
      _dataPath = await data.resolveSymbolicLinks();
      _identity = await core.DeviceIdentity.loadOrCreate(
        _secrets,
        displayName: _runtime.initialDeviceName ?? _defaultName(),
      );
      _trusted = core.TrustedPeerStore(_secrets);
      await _trusted!.load();
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
      _inbox = await core.DurableInbox.open(
        Directory(p.join(data.path, 'inbox')),
        budget: _storageBudget,
      );
      _outbox = await core.DurableOutbox.open(
        Directory(p.join(data.path, 'outbox')),
        budget: _storageBudget,
      );
      _journal = OutgoingJournal(Directory(p.join(data.path, 'journal')));
      _exports = ExportJournal(Directory(p.join(data.path, 'journal')));
      _jobs.addAll(_journal!.recover());
      await _updateStorageOverview();
      _subscriptions.add(
        _inbox!.changes.listen((_) {
          _emit();
          _refreshStorageSoon();
        }),
      );
      _subscriptions.add(_trusted!.changes.listen((_) => _emit()));
      if (!await _runtime.ensurePermission()) {
        _network = NetworkState.permissionRequired;
        _error =
            'Разрешите доступ к локальной сети в настройках приложения, '
            'затем нажмите «Обновить».';
      } else {
        await _synchronizeHost();
        _peerTimer = Timer.periodic(const Duration(seconds: 12), (_) {
          _launch(_refreshTrusted());
        });
      }
    } catch (error) {
      _network = NetworkState.unavailable;
      _error = 'Не удалось запустить приложение. ${_friendly(error)}';
    } finally {
      _starting = false;
      _busy = null;
      _emit();
    }
  }

  static String _defaultName() => switch (Platform.operatingSystem) {
    'ios' => 'Мой iPhone',
    'android' => 'Мой Android',
    'windows' => 'Мой Windows',
    'linux' => 'Мой Linux',
    _ => 'Моё устройство',
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
    _network = NetworkState.ready;
    _subscriptions.add(host.changes.listen((_) => _emit()));
    if (!_runtime.discoveryEnabled) {
      _launch(_refreshTrusted());
      return;
    }
    final discovery = LanDiscovery();
    _discovery = discovery;
    _subscriptions.add(
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
    } catch (_) {
      // Foreground HTTPS remains usable via QR when discovery alone fails.
      _discoveryIssue =
          'Автопоиск недоступен. Подключитесь по QR-коду в общей сети.';
      await discovery.close();
      _discovery = null;
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
  String get versionLabel => '0.3.0 · техническая альфа';
  @override
  StorageOverview? get storageOverview => _storageOverview;
  @override
  bool get storageRefreshing => _storageRefreshing;
  @override
  String get saveLocationLabel => _dataPath == null
      ? 'Хранилище приложения'
      : p.join(_dataPath!, 'inbox', 'received');
  @override
  String? get networkDetail =>
      _discoveryIssue ??
      (_addresses.isEmpty
          ? 'Подключите устройства к одной сети Wi-Fi или Ethernet. '
                'В этой сборке используется IPv4.'
          : 'Локальная сеть · приложение должно оставаться открытым');
  @override
  AppCapabilities get capabilities => AppCapabilities(
    fileSelection: _outbox != null && !_starting,
    receiving: _inbox != null && !_starting,
    pairing: _host != null && !_pairing,
    discovery: _discovery != null && _discoveryIssue == null,
    rename: false,
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
                ? 'Ключ устройства проверен'
                : 'Откройте приложение на другом устройстве',
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
          detail: 'Для первого подключения отсканируйте QR-код',
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
        ),
      )
      .toList();

  @override
  List<IncomingTransfer> get pendingTransfers =>
      (_inbox?.list() ?? <core.TransferSnapshot>[])
          .where((item) => item.state == core.TransferState.offered)
          .map(
            (item) => IncomingTransfer(
              id: item.transferId,
              peerName: _peerName(item.peerId),
              fileNames: item.manifest.files
                  .map((file) => file.displayName)
                  .toList(),
              totalBytes: item.manifest.totalBytes,
              expiresAt: item.offerExpiresAt,
            ),
          )
          .toList();

  @override
  List<TransferItem> get transfers {
    final result = <TransferItem>[];
    for (final item in _inbox?.list() ?? <core.TransferSnapshot>[]) {
      final terminal = _terminal(item);
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
          detail: _snapshotDetail(item),
          locationLabel: saveLocationLabel,
          receivedFiles: item.files
              .where((file) => file.state == core.FileState.committed)
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
          canOpen: item.files.any(
            (file) => file.state == core.FileState.committed,
          ),
          canExport:
              capabilities.fileExport &&
              item.files.any((file) => file.state == core.FileState.committed),
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
                  ? 'Ожидание ответа получателя'
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
        ),
      );
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<void> chooseFiles() => _guard(() async {
    if (_outbox == null || isBusy) return;
    _picking = true;
    _busy = 'Выбор файлов';
    _emit();
    try {
      final picked = await picker.FilePicker.pickFiles(
        dialogTitle: 'Выберите файлы',
      );
      if (_closing || picked.isEmpty) return;
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
        _busy = 'Подготовка: ${item.name}';
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
            name: prepared.manifest.displayName,
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
        _busy = 'Подготовка: ${p.basename(path)}';
        _emit();
        final prepared = await _outbox!.stageFile(File(path));
        _sources.add(
          SelectedSource(
            id: prepared.manifest.fileId,
            name: prepared.manifest.displayName,
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
      _status =
          'Дождитесь окончания текущей отправки или поставьте её на паузу.';
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
    _status =
        'Запрос на получение отправлен. Подтвердите его на другом устройстве.';
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
          job.detail = 'Устройство недоступно или доверие отозвано.';
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
            job.detail = job.localState == 'cancelling'
                ? 'Автоматические попытки закончились. Отмена ещё не '
                      'подтверждена; «Продолжить» уточнит результат у получателя.'
                : 'Связь не восстановилась после ${_retryPolicy.maxRetries} '
                      'повторных попыток. Подтверждённый прогресс сохранён. '
                      'Откройте приложение на обоих устройствах и нажмите '
                      '«Продолжить».';
            break;
          }
          if (job.localState != 'cancelling') job.localState = 'retry_wait';
          final seconds = (delay.inMilliseconds / 1000).toStringAsFixed(1);
          job.detail = job.localState == 'cancelling'
              ? 'Уточняем отмену: повтор $retries из '
                    '${_retryPolicy.maxRetries} через $seconds с. '
                    'Результат получателя пока неизвестен.'
              : 'Связь прервалась. Повтор $retries из '
                    '${_retryPolicy.maxRetries} через $seconds с. '
                    'Подтверждённый прогресс сохранён.';
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
      _save(job);
      if (job.isTerminal) await _cleanupJobSources(job);
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
          job.detail =
              'Пауза отправителя. Для продолжения нажмите «Продолжить».';
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
        job.detail = 'Получатель поставил передачу на паузу.';
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
        job.detail =
            'Время ожидания согласия истекло. Для передачи нужен новый запрос.';
      case core.TransferState.failed:
        job.localState = 'failed';
        job.detail =
            'Приём не завершён. Выберите файлы заново для новой отправки.';
      case core.TransferState.partiallyCompleted:
        job.localState = 'partially_completed';
        final completed = snapshot.files
            .where((file) => file.state == core.FileState.committed)
            .length;
        job.detail =
            'Сохранено $completed из ${snapshot.files.length} файлов. '
            'Завершённые результаты доступны у получателя; остальные можно отправить заново.';
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
      _status =
          'Дождитесь окончания текущей отправки или поставьте её на паузу.';
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
    _status =
        'Создан новый запрос из сохранённых копий. Получатель должен '
        'подтвердить его заново.';
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
    _outgoingRuns[job.id]?.cancel();
    job.localState = 'paused';
    job.detail = 'Пауза отправителя';
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
      _status = 'Приём разрешён. На отправителе нажмите «Продолжить», если передача остановлена.';
      return;
    }
    final job = _job(transferId);
    if (_running.isNotEmpty) {
      _status = 'Дождитесь окончания текущей отправки.';
      return;
    }
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
    job.detail = 'Уточняем результат отмены у получателя.';
    _save(job);
    _activeClients[job.id]?.close();
    if (job.remoteId == null) {
      // An offer response may have been lost. Reconcile the same request ID
      // before cancelling; do not assume the remote offer does not exist.
      job.detail =
          'Нажмите «Продолжить», чтобы подтвердить отмену у получателя.';
      _save(job);
      return;
    }
    final peer = _trusted?.byId(job.peerId);
    if (peer == null || peer.endpoint == null) return;
    final control = core.CoreClient.forPeer(peer);
    try {
      _applySnapshot(job, await control.cancel(job.remoteId!));
    } catch (_) {
      job.detail =
          'Получатель недоступен. Отмена ещё не подтверждена; '
          '«Продолжить» повторно уточнит её результат.';
    } finally {
      control.close();
      _save(job);
    }
  });

  OutgoingJob _job(String value) =>
      _jobs.firstWhere((job) => 'out:${job.id}' == value);

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
    final invite = _host!.createInvite(hostAddress: _addresses.first);
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
    final client = core.CoreClient(
      endpoint: invite.endpoint,
      serverPin: invite.serverPin,
    );
    _pairing = true;
    _pairingClient = client;
    _status = 'Подтвердите подключение на другом устройстве.';
    _emit();
    try {
      _addresses = await _runtime.addresses();
      final local = _host == null || _addresses.isEmpty
          ? null
          : Uri(scheme: 'https', host: _addresses.first, port: _host!.port);
      await client.requestPairing(
        invite,
        identity: _identity!,
        peers: _trusted!,
        localEndpoint: local,
      );
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
          _status =
              'Подключено: ${peer.displayName}. Теперь можно отправлять файлы.';
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      throw const core.NetworkException('PAIRING_EXPIRED', 'Pairing timed out');
    } finally {
      client.close();
      _pairing = false;
      _pairingClient = null;
    }
  });

  @override
  Future<void> scanInvitation() => _guard(() async {
    final text = await scanCode?.call();
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
        _status = accept
            ? 'Подключение подтверждено. Ожидается завершение сопряжения.'
            : 'Запрос подключения отклонён.';
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
    await _refreshTrusted();
  });
  Future<void> _refreshTrusted() async {
    if (_refreshing || _trusted == null || _closing || _disposed) return;
    _refreshing = true;
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
      _refreshing = false;
      _emit();
    }
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
          ? 'Доверие отозвано. Удалённый результат отмены не подтверждён.'
          : 'Доверие отозвано. Передача остановлена.';
      _save(job);
    }
    // Stop transmission before an OS secret-store write can block. If that
    // write fails, the user sees a revocation error but the stopped run remains
    // paused instead of silently completing its pending retry.
    await (_host?.revoke(peerId) ?? _trusted!.revoke(peerId));
  });
  @override
  Future<void> renameDevice(String name) async {
    _status = 'Переименование появится в следующей сборке.';
    _emit();
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) => _guard(() async {
    await _secrets.write('transfer.settings.theme', mode.name);
    _theme = mode;
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
              name: file.manifest.displayName,
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
      _status = 'Лимит временного хранилища сохранён.';
    } finally {
      _changingQuota = false;
      await _updateStorageOverview();
    }
  });

  @override
  Future<void> clearUnusedTemporary(List<String> fileIds) => _guard(() async {
    if (isBusy || _outbox == null) return;
    _cleaning = true;
    _busy = 'Очистка неиспользуемых копий';
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
      _status =
          'Удалено неиспользуемых временных копий: $count. Полученные файлы сохранены.';
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
        _busy = 'Очистка незавершённого приёма';
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
          _status =
              'Обработано незавершённых передач: $stopped. '
              'Удалено временных файлов: $removedFiles. '
              'Готовые полученные файлы сохранены.';
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
      name: file.manifest.displayName,
      bytes: file.manifest.sizeBytes,
      exportPhase: phase,
      exportDestination: success?.destinationLabel,
      exportDetail: switch (phase) {
        ExportPhase.notExported => 'Получен в хранилище приложения',
        ExportPhase.exporting => 'Сохранение копии…',
        ExportPhase.exported => 'Копия сохранена: ${record!.destinationLabel}',
        ExportPhase.cancelled => 'Последнее сохранение отменено',
        ExportPhase.failed =>
          record?.errorCode == 'COMMITTED_FILE_CHANGED'
              ? 'Файл изменён или перемещён. Сохранение копии остановлено.'
              : 'Не удалось сохранить копию. Полученный файл остаётся в приложении.',
        ExportPhase.unknown => 'Результат сохранения не подтверждён. Проверьте выбранную папку перед повтором.',
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
      final result = await _runtime.exportFile!(
        source: source,
        displayName: p.basename(source.path),
        mimeType:
            file.manifest.mimeType != null &&
                RegExp(r'^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$')
                    .hasMatch(file.manifest.mimeType!)
            ? file.manifest.mimeType
            : 'application/octet-stream',
      );
      if (result == null) {
        _exports!.finish(record.id, ExportState.cancelled);
        _status =
            'Сохранение копии отменено. Полученный файл остаётся в приложении.';
      } else {
        copyReported = true;
        _exports!.finish(
          record.id,
          ExportState.exported,
          destinationLabel: result.destinationLabel,
          platformReference: result.platformReference,
        );
        _status = 'Копия сохранена: ${result.destinationLabel}';
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
        .where((item) => item.state == core.FileState.committed)
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
        final result = await OpenFilex.open(saved.path);
        if (result.type != ResultType.done) {
          _error = 'Файл сохранён, но подходящую программу открыть не удалось.';
        }
      });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_runtime.mobileLifecycle || _closing) return;
    if (state == AppLifecycleState.paused) {
      _foreground = false;
      for (final job in _jobs.where((job) => _running.contains(job.id))) {
        _outgoingRuns[job.id]?.cancel();
        // Preserve cancellation intent even when backgrounding interrupts it.
        if (job.localState != 'cancelling') job.localState = 'paused';
        job.detail = 'Приложение свёрнуто. Для продолжения откройте его на обоих устройствах.';
        _save(job);
        _activeClients[job.id]?.close();
      }
      _launch(_synchronizeHost());
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (!_starting && _identity != null) _launch(_guard(_synchronizeHost));
    }
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
    } catch (error) {
      if (!_closing) _error = _friendly(error);
    } finally {
      _refreshStorageSoon();
      _emit();
    }
  }

  void _launch(Future<void> action) {
    late final Future<void> task;
    task = action
        .catchError((Object error) {
          if (!_closing) {
            _error = _friendly(error);
            _emit();
          }
        })
        .whenComplete(() => _backgroundTasks.remove(task));
    _backgroundTasks.add(task);
  }

  void _emit() {
    if (!_closing && !_disposed) notifyListeners();
  }

  Future<void> shutdown() => _shutdown ??= _shutdownNow();
  Future<void> _shutdownNow() async {
    _closing = true;
    _receiveWanted = false;
    _foreground = false;
    _peerTimer?.cancel();
    _storageTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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
    _disposed = true;
    await _inbox?.close();
    await _outbox?.close();
    _journal?.close();
    _exports?.close();
  }

  String _peerName(String peerId) =>
      _trusted?.byId(peerId)?.displayName ?? 'Устройство';
  static String _title(core.TransferManifest manifest) =>
      manifest.files.length == 1
      ? manifest.files.single.displayName
      : '${manifest.files.length} файлов';
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

  static String? _snapshotDetail(core.TransferSnapshot value) {
    if (value.state == core.TransferState.completed) {
      return 'SHA-256 проверен · сохранение подтверждено';
    }
    if (value.state == core.TransferState.expired) {
      return 'Согласие не получено за 120 секунд. Для передачи нужен новый запрос.';
    }
    final spaceError = value.files
        .map((file) => file.errorCode)
        .where((code) => code == 'DISK_FULL' || code == 'TEMP_QUOTA_EXCEEDED')
        .firstOrNull;
    if (spaceError != null) {
      return '${_friendly(core.StorageException(spaceError, ''))} '
          'Подтверждённая часть файла сохранена; затем нажмите «Продолжить».';
    }
    if (value.pausedBySink) return 'Пауза получателя';
    if (value.pausedBySource) return 'Пауза отправителя';
    if (value.state == core.TransferState.offered) {
      return 'Требуется согласие получателя';
    }
    if (value.files.any((file) => file.errorCode != null)) {
      return 'Есть незавершённые файлы. Проверенные результаты сохранены.';
    }
    return null;
  }

  static DevicePlatform _platformOf(String value) =>
      DevicePlatform.values.where((item) => item.name == value).firstOrNull ??
      DevicePlatform.unknown;
  static String _friendly(Object error) {
    final code = error is core.NetworkException
        ? error.code
        : error is core.StorageException
        ? error.code
        : error is PlatformException
        ? error.code
        : null;
    return switch (code) {
      'PEER_UNAVAILABLE' || 'NO_LAN_ADDRESS' => 'Устройство недоступно. Подключите оба устройства к одной сети и откройте приложение.',
      'PAIRING_EXPIRED' || 'INVITE_EXPIRED' =>
        'Срок QR-кода истёк. Создайте новый код на другом устройстве.',
      'PAIRING_REJECTED' => 'Подключение отклонено на другом устройстве.',
      'SELF_PAIRING' => 'Этот QR-код принадлежит текущему устройству.',
      'UNAUTHORIZED' => 'Доверие отозвано или сопряжение не завершено. Подключите устройства заново.',
      'CONSENT_REQUIRED' || 'CONSENT_TIMEOUT' => 'Получатель ещё не подтвердил приём. Подтвердите запрос и продолжите отправку.',
      'OFFER_EXPIRED' || 'TRANSFER_EXPIRED' =>
        'Срок предложения истёк. Выберите файлы и отправьте новый запрос.',
      'TRANSFER_PAUSED' => 'Передача приостановлена. Продолжение доступно после снятия паузы обеими сторонами.',
      'HASH_MISMATCH' || 'INTEGRITY_MISMATCH' =>
        'Контрольная сумма не совпала. Файл не отмечен как готовый.',
      'SOURCE_CHANGED' =>
        'Исходный файл изменился во время подготовки. Выберите его повторно.',
      'FILE_TOO_LARGE' => 'Размер файла превышает предел этой сборки — 10 ГиБ.',
      'DISK_FULL' || 'STORAGE_FULL' => 'Недостаточно свободного места с учётом начатых передач и резерва. Освободите место в настройках хранилища и повторите.',
      'TEMP_QUOTA_EXCEEDED' => 'Достигнут лимит временных копий. Очистите неиспользуемые копии или увеличьте лимит в настройках.',
      'TEMP_QUOTA_BELOW_USAGE' => 'Этот лимит меньше объёма временных копий и места для начатых передач. Сначала завершите передачи или освободите место.',
      'CAPACITY_UNAVAILABLE' => 'Не удалось определить доступное место. Повторите проверку в настройках хранилища.',
      'COMMITTED_FILE_CHANGED' => 'Полученный файл удалён, перемещён или изменён. Сохранение копии остановлено; проверьте файл.',
      'EXPORT_INTERRUPTED' => 'Результат сохранения не подтверждён. Проверьте выбранную папку перед повтором.',
      'EXPORT_FAILED' || 'EXPORT_IO' || 'EXPORT_UNAVAILABLE' => 'Не удалось сохранить внешнюю копию. Полученный файл остаётся в приложении; выберите другое место или повторите.',
      'EXPORT_SOURCE_UNAVAILABLE' => 'Полученный файл недоступен для сохранения копии. Проверьте, что он не удалён или перемещён.',
      'EXPORT_UNSUPPORTED' => 'Системное сохранение не поддерживается на этом устройстве. Файл остаётся в приложении.',
      'EXPORT_BUSY' => 'Дождитесь завершения текущего сохранения или закройте открытое системное окно.',
      'DESTINATION_EXISTS' || 'EXPORT_DESTINATION_EXISTS' =>
        'Файл с таким именем уже существует. Укажите другое имя или папку.',
      'QUEUE_FULL' =>
        'Очередь заполнена. Завершите или отмените незавершённые передачи.',
      'BUSY' ||
      'WRITER_BUSY' => 'Получатель занят другой передачей. Повторите позже.',
      'STORAGE_MISSING' || 'NOT_FOUND' => 'Данные этой передачи недоступны. Проверьте сохранённые файлы или выберите источник заново.',
      _ =>
        error is HandshakeException
            ? 'Не удалось проверить ключ устройства. Перепроверьте устройство и выполните сопряжение заново.'
            : error is SocketException || error is TimeoutException
            ? 'Соединение прервано. Откройте приложение на обоих устройствах и продолжите передачу.'
            : error is FormatException
            ? 'Некорректный QR-код или неподдерживаемый формат данных.'
            : error is FileSystemException
            ? 'Не удалось прочитать или сохранить файл. Проверьте доступ и свободное место.'
            : code == null
            ? 'Операция недоступна. Проверьте системные разрешения и повторите.'
            : 'Операция остановлена ($code). Данные не отмечены как успешно переданные.',
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
