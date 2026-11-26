// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../ui_format.dart';
import '../widgets/common.dart';

Future<void> showIncomingOfferSheet(
  BuildContext context,
  AppController controller,
  IncomingTransfer request,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _IncomingOfferSheet(controller: controller, request: request),
);

/// The files of an offer: icons, first names and "and N more".
class _OfferFiles extends StatelessWidget {
  const _OfferFiles({required this.request, this.limit = 3});
  final IncomingTransfer request;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final name in request.fileNames.take(limit))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(fileTypeIcon(name), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        if (request.fileNames.length > limit)
          Text(
            l.andMoreFiles(fileCountLabel(l, request.fileNames.length - limit)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _OfferDeadline extends StatelessWidget {
  const _OfferDeadline({required this.request});
  final IncomingTransfer request;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (request.expiresAt == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            Icons.timer_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l.offerValidUntil(
                formatDate(l, request.expiresAt!, includeSeconds: true),
              ),
              key: Key('offer-deadline-${request.id}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline offer in History. Answers once; buttons lock while in flight.
class IncomingOfferCard extends StatefulWidget {
  const IncomingOfferCard({
    super.key,
    required this.controller,
    required this.request,
  });
  final AppController controller;
  final IncomingTransfer request;

  @override
  State<IncomingOfferCard> createState() => _IncomingOfferCardState();
}

class _IncomingOfferCardState extends State<IncomingOfferCard> {
  bool _working = false;

  Future<void> _answer(bool accept) async {
    setState(() => _working = true);
    if (accept) Haptics.success();
    try {
      await runAction(
        context,
        widget.controller,
        () => widget.controller.respondToTransfer(widget.request.id, accept),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final request = widget.request;
    final scheme = Theme.of(context).colorScheme;
    final locked = _working || widget.controller.isBusy;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: .45),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconTile(icon: Icons.download_rounded, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.peerName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        l.filesAndSize(
                          fileCountLabel(l, request.fileNames.length),
                          formatBytes(l, request.totalBytes),
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _OfferFiles(request: request),
            _OfferDeadline(request: request),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('reject-${request.id}'),
                    onPressed: locked ? null : () => _answer(false),
                    child: Text(l.decline),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: Key('accept-${request.id}'),
                    onPressed: locked ? null : () => _answer(true),
                    child: Text(l.acceptFiles, textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingOfferSheet extends StatefulWidget {
  const _IncomingOfferSheet({required this.controller, required this.request});
  final AppController controller;
  final IncomingTransfer request;

  @override
  State<_IncomingOfferSheet> createState() => _IncomingOfferSheetState();
}

class _IncomingOfferSheetState extends State<_IncomingOfferSheet> {
  bool _working = false;

  Future<void> _answer(bool accept) async {
    setState(() => _working = true);
    if (accept) Haptics.success();
    try {
      await widget.controller.respondToTransfer(widget.request.id, accept);
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final request = widget.request;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final stillPending = widget.controller.pendingTransfers.any(
          (item) => item.id == request.id,
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l.incomingFiles,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.offerSummary(
                    request.peerName,
                    fileCountLabel(l, request.fileNames.length),
                    formatBytes(l, request.totalBytes),
                  ),
                ),
                const SizedBox(height: 14),
                _OfferFiles(request: request, limit: 4),
                if (!stillPending) ...[
                  const SizedBox(height: 10),
                  Text(
                    l.offerNoLongerActive,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: Key('sheet-accept-${request.id}'),
                  onPressed: _working || !stillPending
                      ? null
                      : () => _answer(true),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l.acceptFiles),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: Key('sheet-reject-${request.id}'),
                  onPressed: _working || !stillPending
                      ? null
                      : () => _answer(false),
                  child: Text(l.decline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Browser upload request while a web share link is active: shown like an
/// incoming offer (file names and sizes as reported by the browser).
Future<void> showWebUploadDialog(
  BuildContext context,
  AppController controller,
  WebUploadRequest request,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final l = context.l10n;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pending = controller.pendingWebUploads.any(
          (r) => r.id == request.id,
        );
        void answer(bool accept) {
          if (accept) Haptics.success();
          controller.respondToWebUpload(request.id, accept);
          Navigator.pop(context);
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l.webUploadTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.webUploadBody(
                    request.client.isEmpty ? l.browserPeer : request.client,
                    fileCountLabel(l, request.fileNames.length),
                    formatBytes(l, request.totalBytes),
                  ),
                ),
                const SizedBox(height: 14),
                _OfferFiles(
                  limit: 4,
                  request: IncomingTransfer(
                    id: request.id,
                    peerName: request.client,
                    fileNames: request.fileNames,
                    totalBytes: request.totalBytes,
                  ),
                ),
                if (!pending) ...[
                  const SizedBox(height: 10),
                  Text(
                    l.offerNoLongerActive,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: Key('web-upload-allow-${request.id}'),
                  onPressed: pending ? () => answer(true) : null,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l.acceptFiles),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: Key('web-upload-reject-${request.id}'),
                  onPressed: pending
                      ? () => answer(false)
                      : () => Navigator.pop(context),
                  child: Text(pending ? l.decline : l.close),
                ),
              ],
            ),
          ),
        );
      },
    );
  },
);
