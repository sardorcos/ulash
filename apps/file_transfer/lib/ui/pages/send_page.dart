import 'package:desktop_drop/desktop_drop.dart';
// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sheets/invitation_sheet.dart';
import '../sheets/text_message_sheet.dart';
import '../sheets/web_share_sheet.dart';
import '../ui_format.dart';
import '../widgets/common.dart';
import '../widgets/page_banners.dart';
import '../widgets/transfer_tile.dart';

List<PeerDevice> availablePeers(AppController c) =>
    c.peers.where((peer) => peer.isOnline && peer.isTrusted).toList();

/// The chosen recipient; a single available device is chosen implicitly.
PeerDevice? effectiveTarget(AppController c, String? chosen) {
  final available = availablePeers(c);
  return available.where((peer) => peer.id == chosen).firstOrNull ??
      (available.length == 1 ? available.single : null);
}

class SendPage extends StatefulWidget {
  const SendPage({
    super.key,
    required this.controller,
    required this.targetPeer,
    required this.onOpenDevices,
    this.settingsButton,
    this.showSendBar = false,
  });

  final AppController controller;
  final ValueNotifier<String?> targetPeer;
  final VoidCallback onOpenDevices;
  final Widget? settingsButton;

  /// Wide layouts show the send bar inside the page; phones show it above
  /// the tab bar.
  final bool showSendBar;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  bool _dragging = false;
  AppController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final active = c.transfers.where((t) => !t.isTerminal).toList();
    final page = LargeTitlePage(
      title: l.navSend,
      storageKey: 'send',
      actions: [
        NetworkIndicator(state: c.networkState),
        ?widget.settingsButton,
      ],
      slivers: [
        SliverToBoxAdapter(child: PageBanners(controller: c)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(
              l.sendLead,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _sourcesSection(context)),
        SliverToBoxAdapter(child: _recipientSection(context)),
        if (active.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
              child: Text(
                l.activeTransfers,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: active.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) =>
                TransferTile(controller: c, item: active[index]),
          ),
        ],
      ],
    );
    final content = widget.showSendBar
        ? Column(
            children: [
              Expanded(child: page),
              SendBar(controller: c, targetPeer: widget.targetPeer),
            ],
          )
        : page;
    if (!c.capabilities.desktopDrop) return content;
    return DropTarget(
      enable: !c.isBusy && (ModalRoute.of(context)?.isCurrent ?? false),
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        final files = details.files
            .whereType<DropItemFile>()
            .map((file) => file.path)
            .where((path) => path.isNotEmpty)
            .toList();
        if (details.files.any((file) => file is DropItemDirectory)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.foldersUnsupported)));
        }
        if (files.isNotEmpty) {
          runAction(context, c, () => c.addSourcePaths(files));
        }
      },
      child: Stack(
        children: [
          content,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: .94),
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
                        Text(l.dropFilesHere),
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

  List<Widget> _sourceButtons(BuildContext context, {required bool compact}) {
    final l = context.l10n;
    final caps = c.capabilities;
    final enabled = !c.isBusy && caps.fileSelection;
    Widget button({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool primary = false,
    }) => primary && !compact
        ? FilledButton.tonalIcon(
            key: key,
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            key: key,
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
    return [
      if (caps.mediaSelection)
        button(
          key: const Key('choose-media'),
          icon: Icons.photo_library_outlined,
          label: l.photosAndVideos,
          primary: true,
          onPressed: enabled ? () => runAction(context, c, c.chooseMedia) : null,
        ),
      button(
        key: const Key('choose-files'),
        icon: Icons.folder_open_outlined,
        label: caps.mediaSelection || compact ? l.files : l.chooseFiles,
        primary: !caps.mediaSelection,
        onPressed: enabled ? () => runAction(context, c, c.chooseFiles) : null,
      ),
      if (caps.folderSelection)
        button(
          key: const Key('choose-folder'),
          icon: Icons.create_new_folder_outlined,
          label: l.folder,
          onPressed: enabled ? () => runAction(context, c, c.chooseFolder) : null,
        ),
      if (caps.textMessages)
        button(
          key: const Key('compose-text'),
          icon: Icons.short_text_rounded,
          label: l.textMessage,
          onPressed: c.isBusy
              ? null
              : () => showTextMessageSheet(
                  context,
                  c,
                  effectiveTarget(c, widget.targetPeer.value)?.id,
                ),
        ),
    ];
  }

  Widget _sourcesSection(BuildContext context) {
    final l = context.l10n;
    final sources = c.selectedSources;
    final scheme = Theme.of(context).colorScheme;
    if (sources.isEmpty) {
      return Section(
        title: l.whatToSend,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        children: [
          Column(
            children: [
              IconTile(icon: Icons.upload_file_rounded, size: 56),
              const SizedBox(height: 12),
              Text(
                l.startWithFiles,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l.startWithFilesHint,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: _sourceButtons(context, compact: false),
              ),
              if (c.capabilities.desktopDrop) ...[
                const SizedBox(height: 10),
                Text(l.orDropHere, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ],
      );
    }
    final ready = sources.every((s) => s.status == SourceStatus.ready);
    final total = sources.every((s) => s.bytes != null)
        ? formatBytes(l, sources.fold<int>(0, (sum, s) => sum + s.bytes!))
        : l.sizePending;
    return Section(
      title: l.whatToSend,
      trailing: TextButton(
        key: const Key('clear-sources'),
        onPressed: c.isBusy ? null : () => runAction(context, c, c.clearSources),
        child: Text(l.clear),
      ),
      footer: ready ? l.selectedSummary(fileCountLabel(l, sources.length), total) : null,
      children: [
        for (final source in sources) _SourceRow(controller: c, source: source),
        const SectionGap(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sourceButtons(context, compact: true),
          ),
        ),
      ],
    );
  }

  Widget _recipientSection(BuildContext context) {
    final l = context.l10n;
    final available = availablePeers(c);
    final hasPeers = c.peers.any((peer) => peer.isTrusted);
    return ValueListenableBuilder<String?>(
      valueListenable: widget.targetPeer,
      builder: (context, chosen, _) {
        final target = effectiveTarget(c, chosen);
        final children = <Widget>[];
        if (available.isEmpty) {
          children.add(
            hasPeers
                ? EmptyState(
                    icon: Icons.devices_rounded,
                    title: l.connectDeviceTitle,
                    description: l.peerOpenApp,
                    action: OutlinedButton.icon(
                      onPressed: () => runAction(context, c, c.refreshPeers),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(l.refreshDevices),
                    ),
                  )
                : EmptyState(
                    icon: Icons.qr_code_2_rounded,
                    title: l.firstDeviceTitle,
                    description: l.firstDeviceBody,
                    action: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          key: const Key('first-device-show-qr'),
                          onPressed: c.capabilities.pairing && !c.isBusy
                              ? () => openInvitationSheet(context, c)
                              : null,
                          icon: const Icon(Icons.qr_code_rounded),
                          label: Text(l.showQr),
                        ),
                        OutlinedButton(
                          onPressed: widget.onOpenDevices,
                          child: Text(l.connect),
                        ),
                      ],
                    ),
                  ),
          );
        } else {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 132,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: available.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    if (index == available.length) {
                      return _AddDeviceCard(onTap: widget.onOpenDevices);
                    }
                    final peer = available[index];
                    return _DeviceChoice(
                      peer: peer,
                      selected: peer.id == target?.id,
                      onTap: () {
                        Haptics.selection();
                        widget.targetPeer.value = peer.id;
                      },
                    );
                  },
                ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Section(
              title: l.sendTo,
              trailing: IconButton(
                tooltip: l.refreshDevices,
                onPressed: c.isBusy ? null : () => runAction(context, c, c.refreshPeers),
                icon: const Icon(Icons.refresh_rounded),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: children,
            ),
            if (c.capabilities.webShare)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('open-web-share'),
                    onPressed: () => showWebShareSheet(context, c),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(l.noAppLink),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.controller, required this.source});
  final AppController controller;
  final SelectedSource source;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconTile(icon: fileTypeIcon(source.name), size: 40),
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
                Text(
                  switch (source.status) {
                    SourceStatus.preparing => l.preparingFile,
                    SourceStatus.failed => source.detail ?? l.preparationFailed,
                    SourceStatus.ready =>
                      source.bytes == null
                          ? l.sizePending
                          : formatBytes(l, source.bytes!),
                  },
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: source.status == SourceStatus.failed
                        ? scheme.error
                        : scheme.onSurfaceVariant,
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
              tooltip: l.removeSource(source.name),
              onPressed: controller.isBusy
                  ? null
                  : () => runAction(
                      context,
                      controller,
                      () => controller.removeSource(source.id),
                    ),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}

class _DeviceChoice extends StatelessWidget {
  const _DeviceChoice({
    required this.peer,
    required this.selected,
    required this.onTap,
  });
  final PeerDevice peer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: peer.name,
      child: SizedBox(
        width: 132,
        child: Material(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            key: Key('peer-${peer.id}'),
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(platformIcon(peer.platform), color: scheme.primary),
                      const Spacer(),
                      if (selected)
                        Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20),
                    ],
                  ),
                  const Spacer(),
                  ExcludeSemantics(
                    child: Text(
                      peer.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  ExcludeSemantics(
                    child: Text(
                      platformLabel(context.l10n, peer.platform),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddDeviceCard extends StatelessWidget {
  const _AddDeviceCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: scheme.primary),
              const SizedBox(height: 6),
              Text(
                context.l10n.add,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Always-visible send action.
class SendBar extends StatelessWidget {
  const SendBar({super.key, required this.controller, required this.targetPeer});
  final AppController controller;
  final ValueNotifier<String?> targetPeer;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final l = context.l10n;
    return ValueListenableBuilder<String?>(
      valueListenable: targetPeer,
      builder: (context, chosen, _) {
        final target = effectiveTarget(c, chosen);
        final sources = c.selectedSources;
        final ready =
            sources.isNotEmpty &&
            sources.every((s) => s.status == SourceStatus.ready);
        final label = sources.isEmpty
            ? l.addFilesFirst
            : target == null
            ? l.chooseRecipient
            : l.sendToDevice(target.name);
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kContentWidth),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('send-selected'),
                      onPressed: ready && target != null && !c.isBusy
                          ? () => runAction(context, c, () => c.sendTo(target.id))
                          : null,
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                      label: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
