import 'dart:async';

// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_controller.dart';
import '../ui_format.dart';
import '../widgets/common.dart';

/// Opt-in browser link for devices without the app.
Future<void> showWebShareSheet(BuildContext context, AppController c) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _WebShareSheet(controller: c),
    );

class _WebShareSheet extends StatefulWidget {
  const _WebShareSheet({required this.controller});
  final AppController controller;

  @override
  State<_WebShareSheet> createState() => _WebShareSheetState();
}

class _WebShareSheetState extends State<_WebShareSheet> {
  bool _allowUpload = false;
  bool _copied = false;
  Timer? _timer;
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _allowUpload = c.webShare?.allowUpload ?? false;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final share = c.webShare;
        final active = share != null && share.expiresAt.isAfter(DateTime.now());
        final readySources = c.selectedSources
            .where((s) => s.status == SourceStatus.ready)
            .length;
        final canStart = !c.isBusy && (readySources > 0 || _allowUpload);
        final insecure = share?.url.scheme == 'http';
        final qrSize = (MediaQuery.sizeOf(context).width - 140).clamp(
          150.0,
          230.0,
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
                    l.webShareTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.webShareBody,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (active) ...[
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: QrImageView(
                        data: share.url.toString(),
                        size: qrSize,
                        backgroundColor: Colors.white,
                        semanticsLabel: l.webShareQrSemantics,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    share.url.toString(),
                    key: const Key('web-share-url'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.webShareValid(formatDate(l, share.expiresAt)),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.webShareStats(
                      share.connectedClients,
                      share.downloadedFiles,
                      share.uploadedFiles,
                    ),
                    key: const Key('web-share-stats'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (insecure) ...[
                    const SizedBox(height: 4),
                    Notice(
                      icon: Icons.lock_open_rounded,
                      text: l.webShareInsecure,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: share.url.toString()),
                            );
                            if (mounted) setState(() => _copied = true);
                          },
                          icon: Icon(
                            _copied ? Icons.check_rounded : Icons.copy_rounded,
                            size: 18,
                          ),
                          label: Text(_copied ? l.copied : l.copyLink),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          key: const Key('web-share-stop'),
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                          ),
                          onPressed: () => runAction(context, c, c.stopWebShare),
                          child: Text(l.webShareStop),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          SettingTile(
                            icon: Icons.insert_drive_file_outlined,
                            title: readySources == 0
                                ? l.webShareSelectFirst
                                : fileCountLabel(l, readySources),
                          ),
                          const Divider(height: 1),
                          SwitchListTile.adaptive(
                            key: const Key('web-share-upload'),
                            contentPadding: EdgeInsets.zero,
                            value: _allowUpload,
                            onChanged: (value) =>
                                setState(() => _allowUpload = value),
                            title: Text(l.webShareAllowUpload),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Notice(icon: Icons.info_outline_rounded, text: l.webShareInsecure),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('web-share-start'),
                    onPressed: canStart
                        ? () => runAction(
                            context,
                            c,
                            () => c.startWebShare(allowUpload: _allowUpload),
                          )
                        : null,
                    icon: const Icon(Icons.link_rounded),
                    label: Text(l.webShareCreate),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
