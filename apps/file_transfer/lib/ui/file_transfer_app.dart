import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'app_controller.dart';
import 'app_theme.dart';
import 'ui_format.dart';

/// Actual application UI. The supplied controller is the only source of data.
class FileTransferApp extends StatelessWidget {
  const FileTransferApp({
    super.key,
    required this.controller,
    this.navigatorKey,
  });

  final AppController controller;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'Передача файлов',
      navigatorKey: navigatorKey,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      // Use the localization delegates belonging to the bundled Material API.
      // ignore: deprecated_member_use
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: buildTransferTheme(Brightness.light),
      darkTheme: buildTransferTheme(Brightness.dark),
      themeMode: controller.themeMode,
      home: _TransferShell(controller: controller),
    ),
  );
}

class _TransferShell extends StatefulWidget {
  const _TransferShell({required this.controller});

  final AppController controller;

  @override
  State<_TransferShell> createState() => _TransferShellState();
}

class _TransferShellState extends State<_TransferShell> {
  int _tab = 0;
  String? _targetPeerId;
  int _historyFilter = 0;
  bool _draggingFiles = false;
  AppController get c => widget.controller;

  static const _labels = [
    'Отправить',
    'Получить',
    'Устройства',
    'История',
    'Настройки',
  ];
  static const _icons = [
    Icons.arrow_upward_rounded,
    Icons.arrow_downward_rounded,
    Icons.devices_rounded,
    Icons.history_rounded,
    Icons.tune_rounded,
  ];
  static const _navKeys = ['send', 'receive', 'devices', 'history', 'settings'];

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            c.errorMessage ??
                'Не удалось выполнить действие. Попробуйте ещё раз.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 980;
      final rail = constraints.maxWidth >= 760;
      return Scaffold(
        bottomNavigationBar: rail
            ? null
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (value) => setState(() => _tab = value),
                destinations: List.generate(
                  5,
                  (index) => NavigationDestination(
                    key: Key('nav-${_navKeys[index]}'),
                    icon: _navigationIcon(index),
                    label: _labels[index],
                  ),
                ),
              ),
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rail) _sidebar(desktop),
              Expanded(
                child: Column(
                  children: [
                    _topbar(rail),
                    if (c.isBusy) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: SingleChildScrollView(
                        key: PageStorageKey('page-$_tab'),
                        padding: EdgeInsets.all(
                          constraints.maxWidth < 480 ? 16 : 28,
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1140),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (c.errorMessage?.isNotEmpty ?? false) ...[
                                  _Notice(
                                    icon: Icons.error_outline_rounded,
                                    text: c.errorMessage!,
                                    error: true,
                                  ),
                                  const SizedBox(height: 16),
                                ] else if (c.statusMessage?.isNotEmpty ??
                                    false) ...[
                                  _Notice(
                                    icon: Icons.info_outline_rounded,
                                    text: c.statusMessage!,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                if (c.isBusy && c.busyLabel != null) ...[
                                  Text(
                                    c.busyLabel!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                if (c.pendingTransfers.isNotEmpty &&
                                    _tab != 1) ...[
                                  _Notice(
                                    icon: Icons.inbox_outlined,
                                    text: 'Входящие файлы ждут вашего подтверждения',
                                    action: TextButton(
                                      onPressed: () => setState(() => _tab = 1),
                                      child: const Text('Посмотреть'),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                if (c.pendingPairings.isNotEmpty &&
                                    _tab != 2) ...[
                                  _Notice(
                                    icon: Icons.devices_other_rounded,
                                    text: 'Новое устройство запрашивает подключение',
                                    action: TextButton(
                                      onPressed: () => setState(() => _tab = 2),
                                      child: const Text('Проверить'),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                switch (_tab) {
                                  0 => _sendPage(),
                                  1 => _receivePage(),
                                  2 => _devicesPage(),
                                  3 => _historyPage(),
                                  _ => _settingsPage(),
                                },
                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _navigationIcon(int index) {
    final count = index == 1
        ? c.pendingTransfers.length
        : index == 2
        ? c.pendingPairings.length
        : 0;
    final icon = Icon(_icons[index]);
    return count == 0 ? icon : Badge(label: Text('$count'), child: icon);
  }

  Widget _sidebar(bool expanded) => Container(
    width: expanded ? 228 : 88,
    color: ink,
    padding: EdgeInsets.symmetric(horizontal: expanded ? 18 : 12, vertical: 26),
    child: Column(
      crossAxisAlignment: expanded
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.only(left: expanded ? 10 : 0, bottom: 38),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BrandMark(),
              if (expanded) ...[
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'Передача',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (var index = 0; index < 5; index++) ...[
                Tooltip(
                  message: _labels[index],
                  child: Material(
                    color: _tab == index
                        ? const Color(0xFF214358)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: Key('nav-${_navKeys[index]}'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _tab = index),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: expanded ? 16 : 16,
                          vertical: 16,
                        ),
                        child: Row(
                          mainAxisSize: expanded
                              ? MainAxisSize.max
                              : MainAxisSize.min,
                          children: [
                            IconTheme(
                              data: IconThemeData(
                                color: _tab == index
                                    ? const Color(0xFF75E1D2)
                                    : const Color(0xFFA3B8C9),
                                size: 23,
                              ),
                              child: _navigationIcon(index),
                            ),
                            if (expanded) ...[
                              const SizedBox(width: 13),
                              Expanded(
                                child: Text(
                                  _labels[index],
                                  style: TextStyle(
                                    color: _tab == index
                                        ? Colors.white
                                        : const Color(0xFFB9C8D5),
                                    fontWeight: _tab == index
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
              ],
            ],
          ),
        ),
        if (expanded &&
            MediaQuery.sizeOf(context).height >= 780 &&
            MediaQuery.textScalerOf(context).scale(14) <= 18)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF18374B),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lan_outlined, color: Color(0xFF75E1D2), size: 24),
                SizedBox(height: 12),
                Text(
                  'Между вашими\nустройствами',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Файлы передаются\nпо локальной сети.',
                  style: TextStyle(
                    color: Color(0xFFACC3D2),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              c.versionLabel,
              style: const TextStyle(color: Color(0xFF8CA5B8), fontSize: 11),
            ),
          ),
      ],
    ),
  );

  Widget _topbar(bool rail) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    padding: EdgeInsets.symmetric(horizontal: rail ? 30 : 20, vertical: 18),
    child: Row(
      children: [
        if (!rail) ...[const _BrandMark(size: 34), const SizedBox(width: 12)],
        Expanded(
          child: Text(
            rail ? _labels[_tab] : 'Передача файлов',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: _StatusPill(networkState: c.networkState),
          ),
        ),
      ],
    ),
  );

  Widget _sendPage() {
    final active = c.transfers.where((t) => !t.isTerminal).toList();
    final ready =
        c.selectedSources.isNotEmpty &&
        c.selectedSources.every((s) => s.status == SourceStatus.ready);
    final available = c.peers.where((p) => p.isOnline && p.isTrusted).toList();
    final selected = available.where((p) => p.id == _targetPeerId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageIntro(
          eyebrow: 'ЛОКАЛЬНАЯ ПЕРЕДАЧА',
          title: 'Файлы — на нужном\nустройстве.',
          subtitle: 'Выберите, что отправить, и кому. Фото, видео и документы останутся в исходном качестве.',
        ),
        const SizedBox(height: 26),
        LayoutBuilder(
          builder: (context, size) {
            final files = _sourceDropTarget();
            final targets = _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionHeader(
                    title: '2. Получатель',
                    subtitle: 'Доступные доверенные устройства',
                    trailing: IconButton(
                      tooltip: 'Обновить устройства',
                      onPressed: c.isBusy ? null : () => _run(c.refreshPeers),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (available.isEmpty)
                    _EmptyState(
                      icon: Icons.devices_rounded,
                      title: 'Подключите устройство',
                      description: 'Откройте приложение на втором устройстве и добавьте его по приглашению.',
                      action: OutlinedButton.icon(
                        onPressed: () => setState(() => _tab = 2),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Подключить'),
                      ),
                    )
                  else ...[
                    for (final peer in available) ...[
                      _PeerCard(
                        peer: peer,
                        selected: peer.id == _targetPeerId,
                        onTap: () => setState(() => _targetPeerId = peer.id),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const Key('send-selected'),
                    onPressed: ready && selected != null && !c.isBusy
                        ? () => _run(() => c.sendTo(selected.id))
                        : null,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 19),
                    label: Text(
                      selected == null
                          ? 'Выберите получателя'
                          : 'Отправить файлы',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Получатель подтвердит передачу на своём устройстве.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
            if (size.maxWidth >= 760) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: files),
                  const SizedBox(width: 20),
                  Expanded(flex: 5, child: targets),
                ],
              );
            }
            return Column(
              children: [files, const SizedBox(height: 18), targets],
            );
          },
        ),
        if (active.isNotEmpty) ...[
          const SizedBox(height: 28),
          const _SectionHeader(title: 'Текущие передачи'),
          const SizedBox(height: 14),
          for (final item in active) ...[
            _transferCard(item),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }

  Widget _sourceDropTarget() {
    final content = _sourcePanel();
    if (!c.capabilities.desktopDrop) return content;
    return DropTarget(
      enable: !c.isBusy && (ModalRoute.of(context)?.isCurrent ?? false),
      onDragEntered: (_) => setState(() => _draggingFiles = true),
      onDragExited: (_) => setState(() => _draggingFiles = false),
      onDragDone: (details) {
        setState(() => _draggingFiles = false);
        final files = details.files
            .whereType<DropItemFile>()
            .map((file) => file.path)
            .where((path) => path.isNotEmpty)
            .toList();
        if (details.files.any((file) => file is DropItemDirectory)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Выберите отдельные файлы. Папки пока не поддерживаются.',
              ),
            ),
          );
        }
        if (files.isNotEmpty) _run(() => c.addSourcePaths(files));
      },
      child: Stack(
        children: [
          content,
          if (_draggingFiles)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer
                        .withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_download_outlined,
                          size: 44,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        const Text('Отпустите файлы здесь'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourcePanel() => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: '1. Файлы',
          subtitle: c.selectedSources.isEmpty
              ? 'Что хотите отправить?'
              : fileCountLabel(c.selectedSources.length),
          trailing: c.selectedSources.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Очистить выбранные файлы',
                  onPressed: c.isBusy ? null : () => _run(c.clearSources),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        const SizedBox(height: 20),
        if (c.selectedSources.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .055),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: .16),
              ),
            ),
            child: Column(
              children: [
                const _FileIllustration(),
                const SizedBox(height: 22),
                Text(
                  'Начнём с файлов',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Фото с телефона, рабочий документ\nили целое видео — выбирайте.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  key: const Key('choose-files'),
                  onPressed: !c.isBusy && c.capabilities.fileSelection
                      ? () => _run(c.chooseFiles)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Выбрать файлы'),
                ),
                if (c.capabilities.desktopDrop) ...[
                  const SizedBox(height: 12),
                  Text(
                    'или перетащите их сюда',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (!c.capabilities.fileSelection) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Выбор файлов недоступен в этой сборке.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          )
        else ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: ListView.separated(
              shrinkWrap: true,
              primary: false,
              itemCount: c.selectedSources.length,
              separatorBuilder: (_, _) => const Divider(height: 22),
              itemBuilder: (context, index) {
                final source = c.selectedSources[index];
                return Row(
                  children: [
                    _FileTypeIcon(name: source.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            switch (source.status) {
                              SourceStatus.preparing => 'Подготавливаем файл…',
                              SourceStatus.failed =>
                                source.detail ?? 'Не удалось подготовить',
                              SourceStatus.ready =>
                                source.bytes == null
                                    ? 'Размер уточняется'
                                    : formatBytes(source.bytes!),
                            },
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: source.status == SourceStatus.failed
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (source.status == SourceStatus.preparing)
                      const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: 'Убрать ${source.name}',
                        onPressed: c.isBusy
                            ? null
                            : () => _run(() => c.removeSource(source.id)),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('choose-files'),
                onPressed: !c.isBusy && c.capabilities.fileSelection
                    ? () => _run(c.chooseFiles)
                    : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить'),
              ),
              Text(
                c.selectedSources.any((source) => source.bytes == null)
                    ? 'Размер уточняется'
                    : 'Всего: ${formatBytes(c.selectedSources.fold<int>(0, (sum, source) => sum + source.bytes!))}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _receivePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _PageIntro(
        eyebrow: 'ПОЛУЧЕНИЕ',
        title: 'Здесь появятся\nваши файлы.',
        subtitle: 'Оставьте приложение открытым. Отправитель увидит устройство после подключения.',
      ),
      const SizedBox(height: 26),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _IconTile(icon: Icons.arrow_downward_rounded, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.deviceName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.receivingEnabled ? 'Приём включён' : 'Приём выключен',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const Key('receive-switch'),
                  value: c.receivingEnabled,
                  onChanged: !c.isBusy && c.capabilities.receiving
                      ? (value) => _run(() => c.setReceiving(value))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.folder_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Место сохранения: ${c.saveLocationLabel}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (!c.capabilities.receiving) ...[
              const SizedBox(height: 12),
              const Text(
                'Приём недоступен в этой сборке. Подключение к устройствам остаётся доступным.',
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: !c.isBusy && c.capabilities.pairing
                      ? _createInvitation
                      : null,
                  icon: const Icon(Icons.qr_code_rounded),
                  label: const Text('Показать приглашение'),
                ),
                TextButton(
                  onPressed: () => setState(() => _tab = 2),
                  child: const Text('Мои устройства'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      if (c.pendingTransfers.isEmpty)
        _Panel(
          child: _EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Входящих предложений пока нет',
            description: c.receivingEnabled
                ? 'Когда отправитель выберет это устройство, вы сможете проверить файлы и принять передачу.'
                : 'Включите приём, когда будете готовы получить файлы.',
          ),
        )
      else ...[
        const _SectionHeader(title: 'Входящие предложения'),
        const SizedBox(height: 14),
        for (final request in c.pendingTransfers) ...[
          _incomingCard(request),
          const SizedBox(height: 12),
        ],
      ],
      for (final item in c.transfers.where(
        (t) => t.direction == TransferDirection.incoming && !t.isTerminal,
      )) ...[const SizedBox(height: 14), _transferCard(item)],
    ],
  );

  Widget _incomingCard(IncomingTransfer request) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: request.peerName,
          subtitle:
              '${fileCountLabel(request.fileNames.length)} · ${formatBytes(request.totalBytes)}',
        ),
        const SizedBox(height: 16),
        for (final name in request.fileNames.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (request.fileNames.length > 3)
          Text(
            'И ещё ${fileCountLabel(request.fileNames.length - 3)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: Key('accept-${request.id}'),
              onPressed: c.isBusy
                  ? null
                  : () => _run(() => c.respondToTransfer(request.id, true)),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Принять файлы'),
            ),
            OutlinedButton(
              key: Key('reject-${request.id}'),
              onPressed: c.isBusy
                  ? null
                  : () => _run(() => c.respondToTransfer(request.id, false)),
              child: const Text('Отклонить'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _devicesPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _PageIntro(
        eyebrow: 'ВАШИ УСТРОЙСТВА',
        title: 'Один раз подключили.\nДальше — просто.',
        subtitle: 'Добавьте телефон или компьютер, чтобы отправлять файлы без повторной настройки.',
      ),
      const SizedBox(height: 26),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: 'Подключить устройство',
              subtitle: 'Приложение должно быть открыто на обеих сторонах.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const Key('create-invitation'),
                  onPressed: !c.isBusy && c.capabilities.pairing
                      ? _createInvitation
                      : null,
                  icon: const Icon(Icons.qr_code_rounded),
                  label: const Text('Создать приглашение'),
                ),
                OutlinedButton.icon(
                  key: const Key('enter-invitation'),
                  onPressed: !c.isBusy && c.capabilities.pairing
                      ? _enterInvitation
                      : null,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Ввести приглашение'),
                ),
                Tooltip(
                  message: c.capabilities.qrScanner
                      ? 'Сканировать приглашение с другого устройства'
                      : 'Камера пока недоступна. Используйте текст приглашения.',
                  child: OutlinedButton.icon(
                    key: const Key('scan-invitation'),
                    onPressed: !c.isBusy && c.capabilities.qrScanner
                        ? () => _run(c.scanInvitation)
                        : null,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Сканировать QR'),
                  ),
                ),
              ],
            ),
            if (!c.capabilities.discovery) ...[
              const SizedBox(height: 16),
              Text(
                'В этой сборке новые устройства подключаются по приглашению.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      for (final request in c.pendingPairings) ...[
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(
                title: 'Запрос подключения',
                subtitle:
                    '${request.deviceName} · ${platformLabel(request.platform)}',
              ),
              const SizedBox(height: 10),
              const Text(
                'Подтвердите, если вы только что добавили это устройство.',
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: Key('approve-pair-${request.id}'),
                    onPressed: c.isBusy
                        ? null
                        : () =>
                              _run(() => c.respondToPairing(request.id, true)),
                    child: const Text('Подключить'),
                  ),
                  OutlinedButton(
                    onPressed: c.isBusy
                        ? null
                        : () =>
                              _run(() => c.respondToPairing(request.id, false)),
                    child: const Text('Отклонить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 26),
      _SectionHeader(
        title: 'Подключённые устройства',
        subtitle: 'Доступность проверяется приложением',
        trailing: IconButton(
          tooltip: 'Обновить устройства',
          onPressed: c.isBusy ? null : () => _run(c.refreshPeers),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ),
      const SizedBox(height: 14),
      if (c.peers.isEmpty)
        const _Panel(
          child: _EmptyState(
            icon: Icons.devices_other_rounded,
            title: 'Пока только это устройство',
            description: 'Создайте приглашение или введите приглашение со второго устройства. Оно появится здесь после подтверждения.',
          ),
        )
      else
        for (final peer in c.peers) ...[
          _Panel(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(child: _PeerCard(peer: peer)),
                if (peer.isTrusted)
                  IconButton(
                    tooltip: 'Отключить ${peer.name}',
                    onPressed: () => _confirmRevoke(peer),
                    icon: const Icon(Icons.link_off_rounded),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
    ],
  );

  Widget _historyPage() {
    final items =
        c.transfers
            .where(
              (t) =>
                  _historyFilter == 0 ||
                  (_historyFilter == 1 &&
                      t.direction == TransferDirection.outgoing) ||
                  (_historyFilter == 2 &&
                      t.direction == TransferDirection.incoming),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageIntro(
          eyebrow: 'ИСТОРИЯ',
          title: 'Всё переданное.\nВ одном месте.',
          subtitle: 'Статус, получатель и сохранённые файлы. Незавершённые передачи тоже остаются здесь.',
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < 3; index++)
              ChoiceChip(
                label: Text(['Все', 'Отправленные', 'Полученные'][index]),
                selected: _historyFilter == index,
                onSelected: (_) => setState(() => _historyFilter = index),
              ),
          ],
        ),
        const SizedBox(height: 22),
        if (items.isEmpty)
          _Panel(
            child: _EmptyState(
              icon: Icons.history_rounded,
              title: c.transfers.isEmpty
                  ? 'История пока пуста'
                  : 'Таких передач пока нет',
              description: c.transfers.isEmpty
                  ? 'После первой передачи здесь появится её результат.'
                  : 'Выберите другой фильтр или начните новую передачу.',
              action: OutlinedButton(
                onPressed: () => setState(() => _tab = 0),
                child: const Text('Отправить файлы'),
              ),
            ),
          )
        else
          for (final item in items) ...[
            _transferCard(item),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _transferCard(TransferItem item) {
    final scheme = Theme.of(context).colorScheme;
    final error = item.phase == TransferPhase.failed;
    final complete = item.phase == TransferPhase.completed;
    final fraction = item.totalBytes > 0
        ? (item.transferredBytes / item.totalBytes).clamp(0.0, 1.0)
        : null;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconTile(
                icon: item.direction == TransferDirection.outgoing
                    ? Icons.north_east_rounded
                    : Icons.south_west_rounded,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.direction == TransferDirection.outgoing ? 'Кому' : 'От кого'}: ${item.peerName}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (complete)
                Icon(Icons.check_circle_rounded, color: scheme.primary),
              if (error) Icon(Icons.error_outline_rounded, color: scheme.error),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 5,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                phaseLabel(item.phase),
                style: TextStyle(
                  color: error ? scheme.error : scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                '${formatBytes(item.transferredBytes)} / ${formatBytes(item.totalBytes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (!item.isTerminal) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                minHeight: 6,
                value:
                    item.phase == TransferPhase.preparing ||
                        item.phase == TransferPhase.verifying
                    ? null
                    : fraction ?? 0,
                semanticsLabel: phaseLabel(item.phase),
                semanticsValue: fraction == null
                    ? null
                    : '${(fraction * 100).round()}%',
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                formatDate(item.createdAt),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (item.bytesPerSecond != null &&
                  item.bytesPerSecond! > 0 &&
                  item.phase == TransferPhase.transferring)
                Text(
                  '${formatBytes(item.bytesPerSecond!)} / с',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          if (item.detail?.isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              item.detail!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: error ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (item.locationLabel?.isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              '${complete ? 'Сохранено' : 'Папка для файлов'}: ${item.locationLabel}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          for (final file in item.receivedFiles.where(
            (file) => file.exportPhase != ExportPhase.notExported,
          )) ...[
            const SizedBox(height: 8),
            Text(
              '${file.name}: ${file.exportDetail ?? ''}'
              '${file.exportDestination != null && file.exportPhase != ExportPhase.exported ? '\nРанее сохранено: ${file.exportDestination}' : ''}',
              key: Key('export-status-${file.id}'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color:
                    file.exportPhase == ExportPhase.failed ||
                        file.exportPhase == ExportPhase.unknown
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (item.canPause ||
              item.canResume ||
              item.canCancel ||
              item.canOpen ||
              item.canExport) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (item.canPause)
                  TextButton.icon(
                    key: Key('pause-${item.id}'),
                    onPressed: () => _run(() => c.pauseTransfer(item.id)),
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('Пауза'),
                  ),
                if (item.canResume)
                  TextButton.icon(
                    key: Key('resume-${item.id}'),
                    onPressed: () => _run(() => c.resumeTransfer(item.id)),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Продолжить'),
                  ),
                if (item.canCancel)
                  TextButton(
                    key: Key('cancel-${item.id}'),
                    onPressed: () => _run(() => c.cancelTransfer(item.id)),
                    child: const Text('Отменить'),
                  ),
                if (item.canOpen)
                  TextButton.icon(
                    key: Key('open-${item.id}'),
                    onPressed: () => _openReceived(item),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(
                      item.receivedFiles.length > 1
                          ? 'Открыть файлы'
                          : 'Открыть файл',
                    ),
                  ),
                if (item.canExport)
                  TextButton.icon(
                    key: Key('export-${item.id}'),
                    onPressed: () => _exportReceived(item),
                    icon: const Icon(Icons.save_alt_rounded, size: 18),
                    label: Text(
                      item.receivedFiles.length > 1
                          ? 'Сохранить копию файла…'
                          : 'Сохранить копию…',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _PageIntro(
        eyebrow: 'НАСТРОЙКИ',
        title: 'Удобно именно вам.',
        subtitle: 'Имя устройства, внешний вид и место для полученных файлов.',
      ),
      const SizedBox(height: 26),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader(title: 'Это устройство'),
            const SizedBox(height: 18),
            _SettingRow(
              icon: Icons.devices_rounded,
              title: 'Имя устройства',
              subtitle: c.deviceName,
              action: TextButton(
                onPressed: c.capabilities.rename && !c.isBusy
                    ? _renameDevice
                    : null,
                child: const Text('Изменить'),
              ),
            ),
            const Divider(height: 32),
            _SettingRow(
              icon: Icons.folder_outlined,
              title: 'Полученные файлы',
              subtitle: c.saveLocationLabel,
              action: TextButton(
                onPressed: c.capabilities.saveLocation && !c.isBusy
                    ? () => _run(c.chooseSaveLocation)
                    : null,
                child: const Text('Выбрать'),
              ),
            ),
            if (!c.capabilities.saveLocation)
              Padding(
                padding: const EdgeInsets.only(left: 50, top: 6),
                child: Text(
                  c.capabilities.fileExport
                      ? 'В истории полученных файлов нажмите «Сохранить копию…» и выберите место в системном окне.'
                      : 'Полученные файлы остаются в приложении. Системное сохранение доступно на поддерживаемых платформах.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _storagePanel(),
      const SizedBox(height: 18),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader(title: 'Внешний вид'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _themeChip(
                  ThemeMode.system,
                  'Как в системе',
                  Icons.brightness_auto_outlined,
                ),
                _themeChip(
                  ThemeMode.light,
                  'Светлая',
                  Icons.light_mode_outlined,
                ),
                _themeChip(ThemeMode.dark, 'Тёмная', Icons.dark_mode_outlined),
              ],
            ),
            const Divider(height: 34),
            const _SettingRow(
              icon: Icons.language_rounded,
              title: 'Язык',
              subtitle: 'Русский · другие языки появятся позже',
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader(title: 'Подключение'),
            const SizedBox(height: 18),
            _SettingRow(
              icon: Icons.lan_outlined,
              title: 'Локальная сеть',
              subtitle: c.networkDetail ?? _networkLabel(c.networkState),
            ),
            const Divider(height: 30),
            _SettingRow(
              icon: Icons.verified_user_outlined,
              title: 'Доверенные устройства',
              subtitle: 'Каждое новое устройство подключается с вашим подтверждением.',
              action: TextButton(
                onPressed: () => setState(() => _tab = 2),
                child: const Text('Открыть'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Text(
        '${c.versionLabel} · Передача файлов',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _storagePanel() {
    final storage = c.storageOverview;
    final enabled = c.capabilities.storageManagement && !c.isBusy;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionHeader(title: 'Хранилище')),
              IconButton(
                key: const Key('refresh-storage'),
                tooltip: 'Обновить сведения о месте',
                onPressed: enabled && !c.storageRefreshing
                    ? () => _run(c.refreshStorage)
                    : null,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (storage == null)
            const Text('Сведения о хранилище пока недоступны.')
          else ...[
            _SettingRow(
              icon: Icons.storage_rounded,
              title: 'Свободное место',
              subtitle: storage.availableBytes == null
                  ? 'Система не сообщила объём. Проверка лимита временных копий работает.'
                  : '${formatBytes(storage.availableBytes!)} · проверено ${formatDate(storage.checkedAt)}',
            ),
            const Divider(height: 28),
            _SettingRow(
              icon: Icons.folder_copy_outlined,
              title: 'Временные копии',
              subtitle:
                  '${formatBytes(storage.temporaryBytes)} уже занято; '
                  '${formatBytes(storage.reservedBytes)} предусмотрено для начатых передач.',
            ),
            const SizedBox(height: 14),
            if (storage.temporaryQuotaBytes != null)
              LinearProgressIndicator(
                value:
                    ((storage.temporaryBytes + storage.reservedBytes) /
                            storage.temporaryQuotaBytes!)
                        .clamp(0.0, 1.0),
                semanticsLabel: 'Использование лимита временного хранилища',
              ),
            const SizedBox(height: 12),
            Text(
              'Лимит временного хранилища',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final gib in const [5, 10, 20, 50])
                  ChoiceChip(
                    key: Key('quota-$gib'),
                    label: Text('$gib ГиБ'),
                    selected:
                        storage.temporaryQuotaBytes == gib * 1024 * 1024 * 1024,
                    onSelected: enabled
                        ? (_) => _run(
                            () => c.setTemporaryQuota(gib * 1024 * 1024 * 1024),
                          )
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Перед записью проверяется запас ${formatBytes(storage.safetyReserveBytes)} '
              'свободного места. Готовые полученные файлы не входят в этот лимит '
              'и не удаляются при очистке временных копий.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 28),
            _SettingRow(
              icon: Icons.cleaning_services_outlined,
              title: 'Неиспользуемые копии',
              subtitle:
                  '${storage.unusedFiles.length} файлов · ${formatBytes(storage.unusedBytes)}',
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('cleanup-temporary'),
                onPressed: enabled && storage.unusedFiles.isNotEmpty
                    ? _confirmCleanup
                    : null,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Очистить неиспользуемые копии'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCleanup() async {
    final files = List<TemporaryFileItem>.of(
      c.storageOverview?.unusedFiles ?? [],
    );
    if (files.isEmpty) return;
    final bytes = files.fold<int>(0, (sum, file) => sum + file.bytes);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить временные копии?'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Будет удалено до ${files.length} копий (${formatBytes(bytes)}), '
                  'не используемых выбранными файлами и незавершёнными передачами. '
                  'Для новой отправки их потребуется выбрать заново. '
                  'Исходные и готовые полученные файлы останутся на месте. '
                  'Если исходный файл уже удалён, временная копия может быть единственной; '
                  'после очистки восстановить её из приложения нельзя.',
                ),
                const SizedBox(height: 14),
                for (final file in files.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text('${file.name} · ${formatBytes(file.bytes)}'),
                  ),
                if (files.length > 10)
                  Text('И ещё ${files.length - 10} файлов.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Оставить'),
          ),
          FilledButton(
            key: const Key('confirm-cleanup-temporary'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить копии'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await _run(
        () => c.clearUnusedTemporary(files.map((file) => file.id).toList()),
      );
    }
  }

  Widget _themeChip(ThemeMode mode, String label, IconData icon) => ChoiceChip(
    avatar: Icon(icon, size: 19),
    label: Text(label),
    selected: c.themeMode == mode,
    onSelected: (_) => _run(() => c.setThemeMode(mode)),
  );

  Future<void> _openReceived(TransferItem item) async {
    if (item.receivedFiles.isEmpty) {
      await _run(() => c.openTransfer(item.id));
      return;
    }
    if (item.receivedFiles.length == 1) {
      await _run(
        () => c.openReceivedFile(item.id, item.receivedFiles.single.id),
      );
      return;
    }
    final fileId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Полученные файлы'),
        content: SizedBox(
          width: 440,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: item.receivedFiles.length,
              separatorBuilder: (_, _) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final file = item.receivedFiles[index];
                return ListTile(
                  key: Key('received-file-${file.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: _FileTypeIcon(name: file.name),
                  title: Text(
                    file.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(formatBytes(file.bytes)),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                  onTap: () => Navigator.pop(context, file.id),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (fileId != null && mounted) {
      await _run(() => c.openReceivedFile(item.id, fileId));
    }
  }

  Future<void> _exportReceived(TransferItem item) async {
    if (item.receivedFiles.isEmpty) return;
    String? fileId;
    if (item.receivedFiles.length == 1) {
      fileId = item.receivedFiles.single.id;
    } else {
      fileId = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Сохранить копию файла'),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: item.receivedFiles.length,
                separatorBuilder: (_, _) => const Divider(height: 10),
                itemBuilder: (context, index) {
                  final file = item.receivedFiles[index];
                  return ListTile(
                    key: Key('export-file-${file.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: _FileTypeIcon(name: file.name),
                    title: Text(
                      file.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${formatBytes(file.bytes)}\n${file.exportDetail ?? 'Получен в приложении'}',
                    ),
                    trailing: const Icon(Icons.save_alt_rounded, size: 20),
                    onTap: () => Navigator.pop(context, file.id),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    }
    if (fileId != null && mounted) {
      await _run(() => c.exportReceivedFile(item.id, fileId!));
    }
  }

  Future<void> _createInvitation() async {
    await _run(c.createInvitation);
    if (!mounted || c.invitation == null || c.errorMessage != null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _InvitationDialog(controller: c),
    );
  }

  Future<void> _enterInvitation() async {
    final payload = await showDialog<String>(
      context: context,
      builder: (_) => const _TextEntryDialog(
        title: 'Подключиться по приглашению',
        description: 'На втором устройстве создайте приглашение и скопируйте его сюда целиком.',
        label: 'Текст приглашения',
        button: 'Подключиться',
        multiline: true,
      ),
    );
    if (payload?.trim().isNotEmpty ?? false) {
      await _run(() => c.pairFromText(payload!.trim()));
    }
  }

  Future<void> _renameDevice() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TextEntryDialog(
        title: 'Имя устройства',
        description:
            'Это имя увидят другие устройства при подключении и передаче.',
        label: 'Имя',
        button: 'Сохранить',
        initialValue: c.deviceName,
        maxLength: 80,
      ),
    );
    if (name?.trim().isNotEmpty ?? false) {
      await _run(() => c.renameDevice(name!.trim()));
    }
  }

  Future<void> _confirmRevoke(PeerDevice peer) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Отключить ${peer.name}?'),
        content: const Text(
          'Для следующей передачи это устройство потребуется подключить заново.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Оставить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
    if (accepted == true) await _run(() => c.revokePeer(peer.id));
  }
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({
    required this.title,
    required this.description,
    required this.label,
    required this.button,
    this.initialValue = '',
    this.multiline = false,
    this.maxLength,
  });
  final String title;
  final String description;
  final String label;
  final String button;
  final String initialValue;
  final bool multiline;
  final int? maxLength;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.description),
            const SizedBox(height: 20),
            TextField(
              key: const Key('dialog-text-input'),
              controller: _text,
              autofocus: true,
              minLines: widget.multiline ? 4 : 1,
              maxLines: widget.multiline ? 7 : 1,
              maxLength: widget.maxLength,
              autocorrect: false,
              enableSuggestions: !widget.multiline,
              decoration: InputDecoration(
                labelText: widget.label,
                alignLabelWithHint: widget.multiline,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: widget.multiline
                  ? null
                  : (_) {
                      if (_text.text.trim().isNotEmpty) {
                        Navigator.pop(context, _text.text.trim());
                      }
                    },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _text.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _text.text.trim()),
        child: Text(widget.button),
      ),
    ],
  );
}

class _InvitationDialog extends StatefulWidget {
  const _InvitationDialog({required this.controller});
  final AppController controller;

  @override
  State<_InvitationDialog> createState() => _InvitationDialogState();
}

class _InvitationDialogState extends State<_InvitationDialog> {
  late final Timer _timer;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final invitation = widget.controller.invitation;
      final remaining =
          invitation?.expiresAt.difference(DateTime.now()).inSeconds ?? 0;
      final expired = remaining <= 0;
      return AlertDialog(
        title: const Text('Приглашение на устройство'),
        content: SizedBox(
          width: 370,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.controller.deviceName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Отсканируйте QR в приложении на другом устройстве или передайте текст приглашения.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                if (!expired && invitation != null)
                  LayoutBuilder(
                    builder: (context, size) => Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: QrImageView(
                        data: invitation.payload,
                        size: (size.maxWidth - 28).clamp(120.0, 224.0),
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                        semanticsLabel:
                            'QR-код временного приглашения на устройство',
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Icon(Icons.timer_off_outlined, size: 68),
                  ),
                const SizedBox(height: 18),
                Text(
                  expired
                      ? 'Срок приглашения истёк. Создайте новое.'
                      : 'Действует ещё ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: expired
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: expired || invitation == null
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: invitation.payload),
                          );
                          if (mounted) setState(() => _copied = true);
                        },
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _copied ? 'Скопировано' : 'Скопировать приглашение',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      );
    },
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(24)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class _PageIntro extends StatelessWidget {
  const _PageIntro({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });
  final String eyebrow;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 10,
          letterSpacing: 1.65,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        title,
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
          fontSize: MediaQuery.sizeOf(context).width < 480 ? 29 : 36,
        ),
      ),
      const SizedBox(height: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
    child: Column(
      children: [
        _IconTile(icon: icon, size: 64),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    this.error = false,
    this.action,
  });
  final IconData icon;
  final String text;
  final bool error;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error ? scheme.error : scheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .17)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action!),
        ],
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.peer, this.selected = false, this.onTap});
  final PeerDevice peer;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: .08)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? scheme.primary : Colors.transparent),
      ),
      child: InkWell(
        key: Key('peer-${peer.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _IconTile(
                icon: switch (peer.platform) {
                  DevicePlatform.ios ||
                  DevicePlatform.android => Icons.smartphone_rounded,
                  DevicePlatform.windows ||
                  DevicePlatform.macos ||
                  DevicePlatform.linux => Icons.computer_rounded,
                  DevicePlatform.unknown => Icons.devices_rounded,
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${platformLabel(peer.platform)} · ${peer.isOnline ? 'Доступно' : 'Не в сети'}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (peer.detail != null)
                      Text(
                        peer.detail!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: scheme.primary,
                  size: 22,
                )
              else if (peer.isTrusted)
                Tooltip(
                  message: 'Доверенное устройство',
                  child: Icon(
                    Icons.verified_user_outlined,
                    color: scheme.primary,
                    size: 19,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              icon,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (action != null && size.maxWidth >= 440) ...[
            const SizedBox(width: 12),
            action!,
          ],
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          if (action != null && size.maxWidth < 440)
            Align(alignment: Alignment.centerRight, child: action!),
        ],
      );
    },
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 38});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF73E0CC),
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Icon(Icons.swap_horiz_rounded, color: ink, size: size * .7),
  );
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, this.size = 44});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(size * .28),
    ),
    child: Icon(
      icon,
      color: Theme.of(context).colorScheme.primary,
      size: size * .48,
    ),
  );
}

class _FileTypeIcon extends StatelessWidget {
  const _FileTypeIcon({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final extension = name.split('.').last.toLowerCase();
    final icon = switch (extension) {
      'jpg' ||
      'jpeg' ||
      'png' ||
      'heic' ||
      'webp' ||
      'gif' => Icons.image_outlined,
      'mp4' || 'mov' || 'mkv' || 'avi' => Icons.movie_outlined,
      'mp3' || 'wav' || 'aac' || 'flac' => Icons.music_note_rounded,
      'zip' || 'rar' || '7z' => Icons.folder_zip_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    return _IconTile(icon: icon);
  }
}

class _FileIllustration extends StatelessWidget {
  const _FileIllustration();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 160,
      height: 106,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .07),
              shape: BoxShape.circle,
            ),
          ),
          Transform.translate(
            offset: const Offset(-27, -9),
            child: Transform.rotate(
              angle: -.18,
              child: Container(
                width: 53,
                height: 65,
                decoration: BoxDecoration(
                  color: const Color(0xFFDFEAF5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: Color(0xFF557893),
                  size: 30,
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(25, -3),
            child: Transform.rotate(
              angle: .14,
              child: Container(
                width: 57,
                height: 65,
                decoration: BoxDecoration(
                  color: const Color(0xFFB8E8DE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.image_outlined,
                  color: Color(0xFF237B70),
                  size: 32,
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, 23),
            child: Container(
              width: 87,
              height: 52,
              decoration: BoxDecoration(
                color: turquoise,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: turquoise.withValues(alpha: .15),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _networkLabel(NetworkState state) => switch (state) {
  NetworkState.starting => 'Подключение…',
  NetworkState.ready => 'Локальная сеть',
  NetworkState.unavailable => 'Нет подключения',
  NetworkState.permissionRequired => 'Нужен доступ к сети',
};

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.networkState});
  final NetworkState networkState;
  @override
  Widget build(BuildContext context) {
    final ready = networkState == NetworkState.ready;
    final scheme = Theme.of(context).colorScheme;
    final color = ready ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              _networkLabel(networkState),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
