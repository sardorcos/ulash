// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../dialogs/adaptive.dart';
import '../ui_format.dart';
import 'common.dart';

/// One transfer: status, progress with speed/ETA, and the actions allowed by
/// the controller. Primary actions stay visible; the rest go to "More".
class TransferTile extends StatelessWidget {
  const TransferTile({super.key, required this.controller, required this.item});
  final AppController controller;
  final TransferItem item;

  AppController get c => controller;

  @override
  Widget build(BuildContext context) {
    if (item.kind == TransferKind.text && item.messageText != null) {
      return _TextBubble(controller: c, item: item);
    }
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final error = item.phase == TransferPhase.failed;
    final complete = item.phase == TransferPhase.completed;
    final fraction = item.totalBytes > 0
        ? (item.transferredBytes / item.totalBytes).clamp(0.0, 1.0)
        : null;
    final indeterminate =
        item.phase == TransferPhase.preparing ||
        item.phase == TransferPhase.verifying;
    final outgoing = item.direction == TransferDirection.outgoing;
    final preview = item.receivedFiles
        .where((f) => f.previewPath != null)
        .firstOrNull;
    final phaseColor = error
        ? scheme.error
        : complete
        ? scheme.primary
        : item.isTerminal
        ? scheme.onSurfaceVariant
        : scheme.primary;
    final showSpeed =
        item.bytesPerSecond != null &&
        item.bytesPerSecond! > 0 &&
        item.phase == TransferPhase.transferring;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    preview != null
                        ? FileThumb(
                            name: preview.name,
                            previewPath: preview.previewPath,
                            size: 48,
                          )
                        : IconTile(
                            icon: item.kind == TransferKind.folder
                                ? Icons.folder_rounded
                                : item.fileCount == 1
                                ? fileTypeIcon(item.title)
                                : Icons.file_copy_outlined,
                            size: 48,
                          ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          outgoing
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.kind == TransferKind.folder
                            ? l.folderLabel(item.title)
                            : item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          outgoing
                              ? l.toPeer(item.peerName)
                              : l.fromPeer(item.peerName),
                          formatBytes(l, item.totalBytes),
                          formatTime(l, item.createdAt),
                        ].join(' · '),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (complete)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: scheme.primary,
                              ),
                            ),
                          if (error)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: scheme.error,
                              ),
                            ),
                          Flexible(
                            child: Text(
                              phaseLabel(l, item.phase),
                              style: text.labelMedium?.copyWith(
                                color: phaseColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _MoreMenu(controller: c, item: item),
              ],
            ),
            if (!item.isTerminal) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: indeterminate ? null : fraction ?? 0,
                    semanticsLabel: '${item.title}, ${phaseLabel(l, item.phase)}',
                    semanticsValue: fraction == null || indeterminate
                        ? null
                        : '${(fraction * 100).round()}%',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      '${formatBytes(l, item.transferredBytes)} / ${formatBytes(l, item.totalBytes)}',
                      style: text.bodySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (showSpeed)
                      Text(
                        [
                          l.speedPerSecond(formatBytes(l, item.bytesPerSecond!)),
                          if (item.totalBytes > item.transferredBytes)
                            l.etaLeft(
                              formatEta(
                                (item.totalBytes - item.transferredBytes) /
                                    item.bytesPerSecond!,
                              ),
                            ),
                        ].join(' · '),
                        key: Key('speed-${item.id}'),
                        style: text.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (item.detail?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  item.detail!,
                  style: text.bodySmall?.copyWith(
                    color: error ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (item.locationLabel?.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  complete
                      ? l.savedAt(item.locationLabel!)
                      : l.filesFolder(item.locationLabel!),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            for (final file in item.receivedFiles.where(
              (file) => file.exportPhase != ExportPhase.notExported,
            )) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${file.name}: ${file.exportDetail ?? ''}'
                  '${file.exportDestination != null && file.exportPhase != ExportPhase.exported ? '\n${l.previouslySaved(file.exportDestination!)}' : ''}',
                  key: Key('export-status-${file.id}'),
                  style: text.bodySmall?.copyWith(
                    color:
                        file.exportPhase == ExportPhase.failed ||
                            file.exportPhase == ExportPhase.unknown
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            _PrimaryActions(controller: c, item: item),
          ],
        ),
      ),
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({required this.controller, required this.item});
  final AppController controller;
  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final l = context.l10n;
    final buttons = <Widget>[
      if (item.canPause)
        TextButton.icon(
          key: Key('pause-${item.id}'),
          onPressed: () => runAction(context, c, () => c.pauseTransfer(item.id)),
          icon: const Icon(Icons.pause_rounded),
          label: Text(l.pause),
        ),
      if (item.canResume)
        TextButton.icon(
          key: Key('resume-${item.id}'),
          onPressed: () =>
              runAction(context, c, () => c.resumeTransfer(item.id)),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(l.resume),
        ),
      if (item.canCancel)
        TextButton(
          key: Key('cancel-${item.id}'),
          onPressed: () =>
              runAction(context, c, () => c.cancelTransfer(item.id)),
          child: Text(l.cancelTransfer),
        ),
      if (item.canRetry)
        TextButton.icon(
          key: Key('retry-${item.id}'),
          onPressed: c.isBusy ? null : () => confirmRetry(context, c, item),
          icon: const Icon(Icons.replay_rounded),
          label: Text(l.sendAgain),
        ),
      if (item.canOpen)
        TextButton.icon(
          key: Key('open-${item.id}'),
          onPressed: () => openReceived(context, c, item),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(item.receivedFiles.length > 1 ? l.openFiles : l.openFile),
        ),
      if (item.canExport)
        TextButton.icon(
          key: Key('export-${item.id}'),
          onPressed: () => exportReceived(context, c, item),
          icon: const Icon(Icons.save_alt_rounded, size: 18),
          label: Text(
            item.receivedFiles.length > 1
                ? l.saveFileCopyEllipsis
                : l.saveCopyEllipsis,
          ),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 4, runSpacing: 0, children: buttons),
    );
  }
}

enum _MoreAction { share, photos, reveal, copyText, delete }

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.controller, required this.item});
  final AppController controller;
  final TransferItem item;

  List<SheetAction<_MoreAction>> _actions(BuildContext context) {
    final c = controller;
    final l = context.l10n;
    final caps = c.capabilities;
    final files = item.receivedFiles;
    return [
      if (item.canOpen && caps.share && files.isNotEmpty)
        SheetAction(
          value: _MoreAction.share,
          label: l.share,
          icon: Icons.ios_share_rounded,
          key: Key('share-${item.id}'),
        ),
      if (caps.photosSave && files.any((f) => f.isMedia))
        SheetAction(
          value: _MoreAction.photos,
          label: l.saveToPhotos,
          icon: Icons.photo_library_outlined,
          key: Key('photos-${item.id}'),
        ),
      if (caps.revealInFolder && files.isNotEmpty)
        SheetAction(
          value: _MoreAction.reveal,
          label: l.revealInFolder,
          icon: Icons.folder_open_outlined,
          key: Key('reveal-${item.id}'),
        ),
      if (item.messageText != null)
        SheetAction(
          value: _MoreAction.copyText,
          label: l.copyAction,
          icon: Icons.copy_rounded,
        ),
      if (item.canDelete)
        SheetAction(
          value: _MoreAction.delete,
          label: l.delete,
          icon: Icons.delete_outline_rounded,
          destructive: true,
          key: Key('delete-${item.id}'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context);
    if (actions.isEmpty) return const SizedBox(width: 8);
    return IconButton(
      key: Key('more-${item.id}'),
      tooltip: context.l10n.moreActions,
      icon: const Icon(Icons.more_horiz_rounded),
      onPressed: controller.isBusy
          ? null
          : () async {
              final choice = await chooseAction<_MoreAction>(
                context,
                title: item.title,
                actions: actions,
              );
              if (choice == null || !context.mounted) return;
              await _perform(context, choice);
            },
    );
  }

  Future<void> _perform(BuildContext context, _MoreAction action) async {
    final c = controller;
    final l = context.l10n;
    switch (action) {
      case _MoreAction.share:
        final id = await pickReceivedFile(context, item, l.shareFile);
        if (id != null && context.mounted) {
          await runAction(context, c, () => c.shareReceivedFile(item.id, id));
        }
      case _MoreAction.photos:
        final media = item.receivedFiles.where((f) => f.isMedia).toList();
        final id = media.length == 1
            ? media.single.id
            : await pickReceivedFile(
                context,
                item,
                l.saveToPhotos,
                only: media,
              );
        if (id != null && context.mounted) {
          await runAction(context, c, () => c.saveToPhotos(item.id, id));
          Haptics.success();
        }
      case _MoreAction.reveal:
        final id = await pickReceivedFile(context, item, l.revealInFolder);
        if (id != null && context.mounted) {
          await runAction(context, c, () => c.revealReceivedFile(item.id, id));
        }
      case _MoreAction.copyText:
        await Clipboard.setData(ClipboardData(text: item.messageText!));
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.textCopied)));
        }
      case _MoreAction.delete:
        await confirmDelete(context, c, item);
    }
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.controller, required this.item});
  final AppController controller;
  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final outgoing = item.direction == TransferDirection.outgoing;
    final error = item.phase == TransferPhase.failed;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: outgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Material(
              color: outgoing
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(outgoing ? 18 : 4),
                bottomRight: Radius.circular(outgoing ? 4 : 18),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onLongPress: () => _copy(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: SelectableText(
                    item.messageText!,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 0, 0),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
                children: [
                  Text(
                    [
                      outgoing ? l.toPeer(item.peerName) : l.fromPeer(item.peerName),
                      if (item.phase != TransferPhase.completed)
                        phaseLabel(l, item.phase),
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: error ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    key: Key('copy-text-${item.id}'),
                    tooltip: l.copyAction,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () => _copy(context),
                  ),
                  if (item.canRetry)
                    IconButton(
                      key: Key('retry-${item.id}'),
                      tooltip: l.sendAgain,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      onPressed: () => confirmRetry(context, controller, item),
                    ),
                  if (item.canDelete)
                    IconButton(
                      key: Key('delete-${item.id}'),
                      tooltip: l.delete,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () => confirmDelete(context, controller, item),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: item.messageText!));
    Haptics.selection();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.textCopied)));
    }
  }
}

// ---------- actions shared by tiles ----------

Future<void> confirmRetry(
  BuildContext context,
  AppController c,
  TransferItem item,
) async {
  final l = context.l10n;
  final accepted = await confirmDialog(
    context,
    title: l.resendQuestion,
    body: l.resendBody(item.title, item.peerName, formatBytes(l, item.totalBytes)),
    cancelLabel: l.keep,
    confirmLabel: l.sendNewRequest,
    confirmKey: Key('confirm-retry-${item.id}'),
  );
  if (accepted && context.mounted) {
    await runAction(context, c, () => c.retryTransfer(item.id));
  }
}

Future<void> confirmDelete(
  BuildContext context,
  AppController c,
  TransferItem item,
) async {
  final l = context.l10n;
  final incoming =
      item.direction == TransferDirection.incoming &&
      item.receivedFiles.isNotEmpty;
  final accepted = await confirmDestructive(
    context,
    title: incoming ? l.deleteReceivedQuestion : l.deleteRecordQuestion,
    body: incoming
        ? l.deleteReceivedBody(item.title, formatBytes(l, item.totalBytes))
        : l.deleteRecordBody(item.title),
    confirmLabel: l.delete,
    confirmKey: Key('confirm-delete-${item.id}'),
  );
  if (accepted && context.mounted) {
    await runAction(context, c, () => c.deleteTransfer(item.id));
  }
}

/// Opens a received file; executables need an explicit second confirmation.
Future<void> openReceived(
  BuildContext context,
  AppController c,
  TransferItem item,
) async {
  if (item.receivedFiles.isEmpty) {
    await runAction(context, c, () => c.openTransfer(item.id));
    return;
  }
  final fileId = item.receivedFiles.length == 1
      ? item.receivedFiles.single.id
      : await pickReceivedFile(
          context,
          item,
          context.l10n.receivedFiles,
          keyPrefix: 'received-file-',
          trailing: Icons.open_in_new_rounded,
        );
  if (fileId == null || !context.mounted) return;
  final file = item.receivedFiles.firstWhere((f) => f.id == fileId);
  if (file.potentiallyExecutable) {
    final l = context.l10n;
    final accepted = await confirmDialog(
      context,
      title: l.executableTitle,
      body: l.executableBody(file.name),
      confirmLabel: l.openAnyway,
      destructive: true,
      confirmKey: Key('confirm-open-${file.id}'),
    );
    if (!accepted || !context.mounted) return;
  }
  await runAction(context, c, () => c.openReceivedFile(item.id, fileId));
}

Future<void> exportReceived(
  BuildContext context,
  AppController c,
  TransferItem item,
) async {
  if (item.receivedFiles.isEmpty) return;
  final l = context.l10n;
  final fileId = item.receivedFiles.length == 1
      ? item.receivedFiles.single.id
      : await pickReceivedFile(
          context,
          item,
          l.saveFileCopyTitle,
          keyPrefix: 'export-file-',
          trailing: Icons.save_alt_rounded,
          showExportDetail: true,
        );
  if (fileId != null && context.mounted) {
    await runAction(context, c, () => c.exportReceivedFile(item.id, fileId));
  }
}

/// Lets the user choose one committed file of a package (grouped by folder).
Future<String?> pickReceivedFile(
  BuildContext context,
  TransferItem item,
  String title, {
  List<ReceivedFile>? only,
  String keyPrefix = 'pick-file-',
  IconData? trailing,
  bool showExportDetail = false,
}) async {
  final files = only ?? item.receivedFiles;
  if (files.isEmpty) return null;
  if (files.length == 1 && keyPrefix == 'pick-file-') return files.single.id;
  final l = context.l10n;
  final grouped = <String, List<ReceivedFile>>{};
  for (final file in files) {
    grouped.putIfAbsent(file.relativeDirectory ?? '', () => []).add(file);
  }
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final MapEntry(key: folder, value: entries)
                  in grouped.entries) ...[
                if (folder.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            folder,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final file in entries)
                  ListTile(
                    key: Key('$keyPrefix${file.id}'),
                    leading: FileThumb(
                      name: file.name,
                      previewPath: file.previewPath,
                      size: 40,
                    ),
                    title: Text(
                      file.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      showExportDetail
                          ? '${formatBytes(l, file.bytes)}\n${file.exportDetail ?? l.receivedInApp}'
                          : formatBytes(l, file.bytes),
                    ),
                    trailing: trailing == null ? null : Icon(trailing, size: 20),
                    onTap: () => Navigator.pop(context, file.id),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    ),
  );
}
