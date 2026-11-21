import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as picker;
// Compatibility during the Flutter 3.50 Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:transfer_core/transfer_core.dart' as core;
import 'package:uuid/uuid.dart';

import '../ui/app_controller.dart';
import 'lan_discovery.dart';
import 'app_runtime.dart';
import 'outgoing_journal.dart';
import 'receipt_validation.dart';

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
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _sources = <SelectedSource>[];
  final _jobs = <OutgoingJob>[];
  final _online = <String>{};
  final _platforms = <String, DevicePlatform>{};
  final _activeClients = <String, core.CoreClient>{};
  final _running = <String>{};
  final _discovered = <DiscoveredEndpoint>[];
  NetworkState _network = NetworkState.starting;
  ThemeMode _theme = ThemeMode.system;
  bool _starting = true;
  bool _preparing = false;
  bool _pairing = false;
  bool _receiving = false;
  bool _refreshing = false;
  bool _disposed = false;
  bool _closing = false;
  bool _receiveWanted = true;
  bool _foreground = true;
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

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      _busy = 'Подготовка защищённого хранилища';
      _emit();
      final root = await _runtime.storageDirectory();
      final data = Directory(p.join(root.path, 'file-transfer-v1'));
      await data.create(recursive: true);
      _dataPath = data.path;
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
      _inbox = await core.DurableInbox.open(
        Directory(p.join(data.path, 'inbox')),
      );
      _outbox = await core.DurableOutbox.open(
        Directory(p.join(data.path, 'outbox')),
      );
      _journal = OutgoingJournal(Directory(p.join(data.path, 'journal')));
      _jobs.addAll(_journal!.recover());
      _subscriptions.add(_inbox!.changes.listen((_) => _emit()));
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
  bool get isBusy => _starting || _preparing;
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
  String get versionLabel => '0.1.0 · техническая альфа';
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
              .map(
                (file) => ReceivedFile(
                  id: file.fileId,
                  name: file.manifest.displayName,
                  bytes: file.manifest.sizeBytes,
                ),
              )
              .toList(),
          canPause:
              !terminal &&
              !item.pausedBySink &&
              item.state != core.TransferState.offered,
          canResume: !terminal && item.pausedBySink,
          canCancel: !terminal,
          canOpen: item.files.any(
            (file) => file.state == core.FileState.committed,
          ),
        ),
      );
    }
    for (final job in _jobs) {
      final snapshot = job.snapshot;
      final phase = switch (job.localState) {
        'completed' => TransferPhase.completed,
        'cancelled' || 'rejected' => TransferPhase.cancelled,
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
              job.snapshot != null &&
              job.snapshot!.state != core.TransferState.offered &&
              job.localState != 'cancelling',
          canResume:
              !job.isTerminal &&
              job.localState != 'failed' &&
              !_running.contains(job.id),
          canCancel: !job.isTerminal && job.localState != 'cancelling',
        ),
      );
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<void> chooseFiles() => _guard(() async {
    if (_outbox == null || isBusy) return;
    final picked = await picker.FilePicker.pickFiles(
      dialogTitle: 'Выберите файлы',
    );
    if (picked.isEmpty) return;
    _preparing = true;
    try {
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
    if (_sources.isEmpty || _outbox == null) return;
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

  Future<void> _runJob(OutgoingJob job) async {
    if (_closing || _disposed || _running.isNotEmpty || job.isTerminal) return;
    final peer = _trusted?.byId(job.peerId);
    if (peer == null || peer.endpoint == null) {
      job.localState = 'paused';
      job.detail = 'Устройство недоступно или доверие отозвано.';
      _save(job);
      return;
    }
    final cancelling = job.localState == 'cancelling';
    final client = core.CoreClient.forPeer(peer);
    _activeClients[job.id] = client;
    _running.add(job.id);
    if (!cancelling) job.localState = 'sending';
    job.detail = null;
    _save(job);
    Timer? poller;
    var pollBusy = false;
    try {
      if (job.remoteId == null) {
        final remote = await client.offer(job.manifest);
        job.remoteId = remote.transferId;
        _applySnapshot(job, remote);
      }
      if (cancelling) {
        _applySnapshot(job, await client.cancel(job.remoteId!));
        return;
      }
      final consentWait = Stopwatch()..start();
      while (true) {
        if (job.localState == 'paused' ||
            job.localState == 'cancelling' ||
            _closing ||
            _disposed) {
          return;
        }
        final snapshot = await client.transferStatus(job.remoteId!);
        _applySnapshot(job, snapshot);
        if (_terminal(snapshot)) return;
        if (snapshot.state != core.TransferState.offered) break;
        if (consentWait.elapsed > const Duration(seconds: 120)) {
          throw const core.NetworkException(
            'CONSENT_TIMEOUT',
            'No consent received',
          );
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      // Resume clears this side's intent even if the other side is still paused.
      if (job.snapshot!.pausedBySource) {
        _applySnapshot(job, await client.resume(job.remoteId!));
      }
      if (job.snapshot!.pausedBySink) {
        job.localState = 'paused';
        job.detail = 'Получатель поставил передачу на паузу.';
        _save(job);
        return;
      }
      // Progress shown in the interface comes only from the Sink's journal.
      poller = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (pollBusy || _disposed || job.localState != 'sending') return;
        pollBusy = true;
        try {
          final snapshot = await client.transferStatus(job.remoteId!);
          if (job.localState == 'sending') _applySnapshot(job, snapshot);
        } catch (_) {
          /* Main upload resolves a network failure. */
        } finally {
          pollBusy = false;
        }
      });
      for (final file in job.manifest.files) {
        if (job.localState != 'sending' || _closing || _disposed) return;
        final prepared = _outbox!.get(file.fileId);
        await client.uploadFile(
          transferId: job.remoteId!,
          fileId: file.fileId,
          source: File(prepared.path),
        );
        _applySnapshot(job, await client.transferStatus(job.remoteId!));
      }
      _applySnapshot(job, await client.transferStatus(job.remoteId!));
      if (job.localState != 'completed') {
        job.localState = 'paused';
        job.detail = 'Ожидается подтверждение сохранения от получателя.';
      }
    } catch (error) {
      if (!job.isTerminal && job.localState != 'cancelling') {
        job.localState = 'paused';
        job.detail = _friendly(error);
      }
    } finally {
      poller?.cancel();
      client.close();
      _activeClients.remove(job.id);
      _running.remove(job.id);
      _save(job);
      if (job.isTerminal) await _cleanupJobSources(job);
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
    // Retain the prepared source of an unsuccessful/partial attempt. This alpha
    // has no automatic retention sweep; only confirmed delivery/cancellation
    // may release its managed copies here.
    if (job.localState == 'failed' || job.localState == 'partially_completed') {
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

  @override
  Future<void> pauseTransfer(String transferId) => _guard(() async {
    if (transferId.startsWith('in:')) {
      await _inbox!.pause(transferId.substring(3));
      return;
    }
    final job = _job(transferId);
    job.localState = 'paused';
    job.detail = 'Пауза отправителя';
    _save(job);
    _activeClients[job.id]?.close();
    final peer = _trusted?.byId(job.peerId);
    if (peer != null && job.remoteId != null) {
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
    _launch(_runJob(job));
  });

  @override
  Future<void> cancelTransfer(String transferId) => _guard(() async {
    if (transferId.startsWith('in:')) {
      await _inbox!.cancel(transferId.substring(3));
      return;
    }
    final job = _job(transferId);
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
    await (_host?.revoke(peerId) ?? _trusted!.revoke(peerId));
    _online.remove(peerId);
    for (final job in _jobs.where(
      (job) => job.peerId == peerId && !job.isTerminal,
    )) {
      _activeClients[job.id]?.close();
      job.localState = 'paused';
      job.detail = 'Доверие отозвано. Передача остановлена.';
      _save(job);
    }
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
        final result = await OpenFilex.open(file.finalPath!);
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
    WidgetsBinding.instance.removeObserver(this);
    _pairingClient?.close();
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
    };
  }

  static String? _snapshotDetail(core.TransferSnapshot value) {
    if (value.state == core.TransferState.completed) {
      return 'SHA-256 проверен · сохранение подтверждено';
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
        : null;
    return switch (code) {
      'PEER_UNAVAILABLE' || 'NO_LAN_ADDRESS' => 'Устройство недоступно. Подключите оба устройства к одной сети и откройте приложение.',
      'PAIRING_EXPIRED' || 'INVITE_EXPIRED' =>
        'Срок QR-кода истёк. Создайте новый код на другом устройстве.',
      'PAIRING_REJECTED' => 'Подключение отклонено на другом устройстве.',
      'SELF_PAIRING' => 'Этот QR-код принадлежит текущему устройству.',
      'UNAUTHORIZED' => 'Доверие отозвано или сопряжение не завершено. Подключите устройства заново.',
      'CONSENT_REQUIRED' || 'CONSENT_TIMEOUT' => 'Получатель ещё не подтвердил приём. Подтвердите запрос и продолжите отправку.',
      'TRANSFER_PAUSED' => 'Передача приостановлена. Продолжение доступно после снятия паузы обеими сторонами.',
      'HASH_MISMATCH' || 'INTEGRITY_MISMATCH' =>
        'Контрольная сумма не совпала. Файл не отмечен как готовый.',
      'SOURCE_CHANGED' =>
        'Исходный файл изменился во время подготовки. Выберите его повторно.',
      'FILE_TOO_LARGE' => 'Размер файла превышает предел этой сборки — 10 ГиБ.',
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
