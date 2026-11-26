import 'dart:async';

// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_controller.dart';
import '../widgets/common.dart';

/// Creates a one-time invitation and shows it as a QR code. While the sheet is
/// open the device is visible to nearby devices and screenshots are blocked.
Future<void> openInvitationSheet(
  BuildContext context,
  AppController c,
) async {
  await runAction(context, c, c.createInvitation);
  if (!context.mounted || c.invitation == null) return;
  final nearby = c.capabilities.nearbyPairing;
  unawaited(c.setSecureScreen(true));
  if (nearby) unawaited(c.setNearbyPairing(true));
  try {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => InvitationSheet(controller: c),
    );
  } finally {
    unawaited(c.setSecureScreen(false));
    if (nearby) unawaited(c.setNearbyPairing(false));
  }
}

class InvitationSheet extends StatefulWidget {
  const InvitationSheet({super.key, required this.controller});
  final AppController controller;

  @override
  State<InvitationSheet> createState() => _InvitationSheetState();
}

class _InvitationSheetState extends State<InvitationSheet> {
  late final Timer _timer;
  late final Set<String> _trustedAtOpen;
  bool _copied = false;
  bool _closing = false;
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _trustedAtOpen = {
      for (final p in c.peers)
        if (p.isTrusted) p.id,
    };
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    c.addListener(_changed);
  }

  @override
  void dispose() {
    _timer.cancel();
    c.removeListener(_changed);
    super.dispose();
  }

  /// A newly trusted device means pairing finished: close the sheet.
  void _changed() {
    final paired = c.peers.any(
      (p) => p.isTrusted && !_trustedAtOpen.contains(p.id),
    );
    if (paired && !_closing) {
      _closing = true;
      Haptics.success();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final invitation = c.invitation;
    final remaining =
        invitation?.expiresAt.difference(DateTime.now()).inSeconds ?? 0;
    final expired = invitation == null || remaining <= 0;
    final width = MediaQuery.sizeOf(context).width;
    final qrSize = (width - 120).clamp(160.0, 260.0);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                l.invitationTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l.qrHint,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: expired
                  ? Container(
                      key: const ValueKey('expired'),
                      width: qrSize + 28,
                      height: qrSize + 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_off_outlined,
                            size: 48,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            key: const Key('renew-invitation'),
                            onPressed: c.isBusy
                                ? null
                                : () => runAction(
                                    context,
                                    c,
                                    c.createInvitation,
                                  ),
                            child: Text(l.showQr),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      key: ValueKey(invitation.payload),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: invitation.payload,
                        size: qrSize,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                        semanticsLabel: l.invitationQrSemantics,
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            Text(
              c.deviceName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              expired
                  ? l.invitationExpired
                  : l.invitationRemaining(
                      '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                    ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: expired ? scheme.error : scheme.primary,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (c.capabilities.nearbyPairing) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_tethering_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l.qrNearbyVisible,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('copy-invitation'),
                    onPressed: expired
                        ? null
                        : () async {
                            await runAction(context, c, c.copyInvitation);
                            if (mounted) setState(() => _copied = true);
                          },
                    icon: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 18,
                    ),
                    label: Text(_copied ? l.copied : l.copyInvitation),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const Key('close-invitation'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.close),
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
