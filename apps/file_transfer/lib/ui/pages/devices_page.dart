// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../dialogs/adaptive.dart';
import '../sheets/invitation_sheet.dart';
import '../ui_format.dart';
import '../widgets/common.dart';
import '../widgets/page_banners.dart';

/// This device, connecting new devices (QR, nearby, code) and trusted devices.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.controller, this.settingsButton});
  final AppController controller;
  final Widget? settingsButton;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _inFlight = <String>{};
  AppController get c => widget.controller;

  Future<void> _once(String key, Future<void> Function() action) async {
    if (!_inFlight.add(key)) return;
    setState(() {});
    try {
      await runAction(context, c, action);
    } finally {
      _inFlight.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _enterCode() async {
    final l = context.l10n;
    final payload = await showDialog<String>(
      context: context,
      builder: (_) => TextEntryDialog(
        title: l.pairByInvitation,
        description: l.pairByInvitationHint,
        label: l.invitationText,
        button: l.pairConnect,
        multiline: true,
      ),
    );
    if ((payload?.trim().isNotEmpty ?? false) && mounted) {
      await runAction(context, c, () => c.pairFromText(payload!.trim()));
    }
  }

  Future<void> _confirmRevoke(PeerDevice peer) async {
    final l = context.l10n;
    final accepted = await confirmDestructive(
      context,
      title: l.disconnectQuestion(peer.name),
      body: l.disconnectBody,
      confirmLabel: l.disconnect,
      confirmKey: Key('confirm-revoke-${peer.id}'),
    );
    if (accepted && mounted) {
      await runAction(context, c, () => c.revokePeer(peer.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final caps = c.capabilities;
    final scheme = Theme.of(context).colorScheme;
    final canPair = caps.pairing && !c.isBusy;
    final trusted = c.peers.where((p) => p.isTrusted).toList()
      ..sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return LargeTitlePage(
      title: l.navDevices,
      storageKey: 'devices',
      actions: [
        IconButton(
          key: const Key('refresh-devices'),
          tooltip: l.refreshDevices,
          onPressed: c.isBusy ? null : () => runAction(context, c, c.refreshPeers),
          icon: const Icon(Icons.refresh_rounded),
        ),
        ?widget.settingsButton,
      ],
      slivers: [
        SliverToBoxAdapter(child: PageBanners(controller: c)),
        // Pending requests come first: they need an answer now.
        if (c.pendingPairings.isNotEmpty)
          SliverToBoxAdapter(
            child: Section(
              title: l.waitingRequests,
              children: [
                for (final request in c.pendingPairings)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconTile(icon: platformIcon(request.platform)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                request.deviceName,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        if (request.code != null) ...[
                          const SizedBox(height: 10),
                          Text(l.sasHostBody(request.deviceName)),
                          const SizedBox(height: 8),
                          PairingCode(code: request.code!),
                        ] else ...[
                          const SizedBox(height: 8),
                          Text(l.pairingConfirmGeneric),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                key: Key('decline-pair-${request.id}'),
                                onPressed:
                                    c.isBusy ||
                                        _inFlight.contains('pair-${request.id}')
                                    ? null
                                    : () => _once(
                                        'pair-${request.id}',
                                        () => c.respondToPairing(
                                          request.id,
                                          false,
                                        ),
                                      ),
                                child: Text(
                                  request.code == null
                                      ? l.decline
                                      : l.codesDiffer,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                key: Key('approve-pair-${request.id}'),
                                onPressed:
                                    c.isBusy ||
                                        _inFlight.contains('pair-${request.id}')
                                    ? null
                                    : () => _once(
                                        'pair-${request.id}',
                                        () => c.respondToPairing(
                                          request.id,
                                          true,
                                        ),
                                      ),
                                child: Text(
                                  request.code == null
                                      ? l.connect
                                      : l.codesMatch,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: Section(
            title: l.connectDevice,
            footer: l.connectFooter,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final show = FilledButton.icon(
                    key: const Key('create-invitation'),
                    onPressed: canPair
                        ? () => openInvitationSheet(context, c)
                        : null,
                    icon: const Icon(Icons.qr_code_rounded),
                    label: Text(l.showQr, textAlign: TextAlign.center),
                  );
                  final scan = Tooltip(
                    message: caps.qrScanner
                        ? l.scanInvitationTooltip
                        : l.cameraUnavailableTooltip,
                    child: OutlinedButton.icon(
                      key: const Key('scan-invitation'),
                      onPressed: canPair && caps.qrScanner
                          ? () => runAction(context, c, c.scanInvitation)
                          : null,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: Text(l.scanQr, textAlign: TextAlign.center),
                    ),
                  );
                  // Side by side when both fit; stacked full-width otherwise.
                  final sideBySide =
                      constraints.maxWidth >= 420 &&
                      MediaQuery.textScalerOf(context).scale(10) <= 13;
                  return sideBySide
                      ? Row(
                          children: [
                            Expanded(child: show),
                            const SizedBox(width: 10),
                            Expanded(child: scan),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [show, const SizedBox(height: 10), scan],
                        );
                },
              ),
              const SectionGap(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('enter-invitation'),
                  onPressed: canPair ? _enterCode : null,
                  child: Text(l.noCameraEnterCode),
                ),
              ),
            ],
          ),
        ),
        if (caps.nearbyPairing)
          SliverToBoxAdapter(
            child: Section(
              title: l.nearby,
              footer: l.nearbyFooter,
              children: [
                if (c.nearbyPairable.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.radar_rounded, color: scheme.primary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            l.nearbyEmpty,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (final device in c.nearbyPairable)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          IconTile(icon: platformIcon(device.platform)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                Text(
                                  platformLabel(l, device.platform),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            key: Key('nearby-${device.id}'),
                            onPressed:
                                c.isBusy ||
                                    _inFlight.contains('nearby-${device.id}')
                                ? null
                                : () => _once(
                                    'nearby-${device.id}',
                                    () => c.pairNearby(device.id),
                                  ),
                            child: Text(l.connect),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: Section(
            title: l.connectedDevices,
            footer: trusted.isEmpty ? null : l.availabilityChecked,
            children: [
              if (trusted.isEmpty)
                EmptyState(
                  icon: Icons.devices_other_rounded,
                  title: l.noDevicesYet,
                  description: l.onlyThisDeviceHint,
                )
              else
                for (final peer in trusted)
                  PeerTile(
                    key: Key('trusted-${peer.id}'),
                    peer: peer,
                    trailing: IconButton(
                      key: Key('revoke-${peer.id}'),
                      tooltip: l.disconnectDevice(peer.name),
                      onPressed: c.isBusy ? null : () => _confirmRevoke(peer),
                      icon: const Icon(Icons.link_off_rounded),
                    ),
                  ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Section(
            title: l.thisDevice,
            children: [
              SettingTile(
                icon: platformIcon(DevicePlatform.unknown),
                title: c.deviceName,
                subtitle: c.deviceCode == null
                    ? null
                    : '${l.deviceCode}: ${c.deviceCode}',
                tileKey: const Key('device-code'),
              ),
              if (caps.receiving)
                SwitchListTile.adaptive(
                  key: const Key('receive-switch'),
                  contentPadding: EdgeInsets.zero,
                  value: c.receivingEnabled,
                  onChanged: c.isBusy
                      ? null
                      : (value) {
                          Haptics.selection();
                          runAction(context, c, () => c.setReceiving(value));
                        },
                  title: Text(l.receiveFiles),
                  subtitle: Text(
                    c.receivingEnabled ? l.receiveHintOn : l.receiveHintOff,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
