// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/app_localizations.dart';
import 'app_controller.dart';
import 'app_theme.dart';
import 'dialogs/pairing_dialogs.dart';
import 'pages/devices_page.dart';
import 'pages/history_page.dart';
import 'pages/send_page.dart';
import 'pages/settings_page.dart';
import 'sheets/incoming_offer_sheet.dart';
import 'startup_screens.dart';
import 'widgets/common.dart';

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
      title: 'Ulash',
      navigatorKey: navigatorKey,
      locale: controller.effectiveLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      debugShowCheckedModeBanner: false,
      theme: buildTransferTheme(Brightness.light),
      darkTheme: buildTransferTheme(Brightness.dark),
      themeMode: controller.themeMode,
      home: controller.startupIssue != StartupIssue.none
          ? StartupIssueScreen(controller: controller)
          : controller.needsOnboarding
          ? OnboardingScreen(controller: controller)
          : AppShell(controller: controller),
    ),
  );
}

enum AppTab { send, history, devices }

/// Three tabs (Send, History, Devices) with Settings behind a gear on phones;
/// a sidebar with the same destinations on iPad and desktop.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _tab = AppTab.send;
  bool _settingsInline = false;
  final _targetPeer = ValueNotifier<String?>(null);
  int _shownMessage = 0;
  final _promptedOffers = <String>{};
  final _promptedPairings = <String>{};
  final _promptedUploads = <String>{};
  String? _promptedOutgoing;
  Map<String, TransferPhase> _phases = {};
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _shownMessage = c.messageSerial;
    _phases = {for (final t in c.transfers) t.id: t.phase};
    c.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onControllerChanged);
    _targetPeer.dispose();
    super.dispose();
  }

  /// Shows each new message once, brings pairing requests and incoming offers
  /// to the front, and gives haptic/spoken feedback on finished transfers.
  void _onControllerChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showMessage();
      _promptPairings();
      _promptOutgoingPairing();
      _promptOffers();
      _promptWebUploads();
      _announceFinished();
    });
  }

  void _showMessage() {
    if (c.messageSerial == _shownMessage) return;
    _shownMessage = c.messageSerial;
    final message = c.errorMessage ?? c.statusMessage;
    if (message == null || message.isEmpty) return;
    final error = c.errorMessage != null;
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: error ? TextStyle(color: scheme.onErrorContainer) : null,
        ),
        backgroundColor: error ? scheme.errorContainer : null,
        showCloseIcon: true,
        closeIconColor: error ? scheme.onErrorContainer : null,
        duration: Duration(seconds: error ? 8 : 4),
      ),
    );
  }

  void _promptPairings() {
    for (final request in c.pendingPairings) {
      if (!_promptedPairings.add(request.id)) continue;
      Haptics.warning();
      showDialog<void>(
        context: context,
        builder: (context) =>
            PairingRequestDialog(controller: c, request: request),
      );
    }
  }

  void _promptOutgoingPairing() {
    final outgoing = c.outgoingPairing;
    if (outgoing == null) {
      _promptedOutgoing = null;
      return;
    }
    // One sheet per pairing: it updates itself from "connecting" to the code.
    final id = outgoing.hostName;
    if (_promptedOutgoing == id) return;
    _promptedOutgoing = id;
    showOutgoingPairingSheet(context, c);
  }

  void _promptOffers() {
    final pending = c.pendingTransfers;
    _promptedOffers.removeWhere(
      (id) => !pending.any((request) => request.id == id),
    );
    for (final request in pending) {
      if (!_promptedOffers.add(request.id)) continue;
      Haptics.warning();
      SemanticsService.sendAnnouncement(
        View.of(context),
        context.l10n.incomingFiles,
        Directionality.of(context),
      );
      // The History tab shows offers in full; elsewhere bring them forward.
      if (_tab == AppTab.history && !_settingsInline) continue;
      showIncomingOfferSheet(context, c, request);
    }
  }

  void _promptWebUploads() {
    for (final request in c.pendingWebUploads) {
      if (!_promptedUploads.add(request.id)) continue;
      Haptics.warning();
      showWebUploadDialog(context, c, request);
    }
  }

  void _announceFinished() {
    final next = <String, TransferPhase>{};
    for (final item in c.transfers) {
      next[item.id] = item.phase;
      final before = _phases[item.id];
      if (before == null || before == item.phase) continue;
      if (item.phase == TransferPhase.completed) {
        Haptics.success();
        SemanticsService.sendAnnouncement(
          View.of(context),
          context.l10n.phaseCompleted,
          Directionality.of(context),
        );
      } else if (item.phase == TransferPhase.failed) {
        Haptics.warning();
      }
    }
    _phases = next;
  }

  void _select(AppTab tab) {
    Haptics.selection();
    setState(() {
      _tab = tab;
      _settingsInline = false;
    });
  }

  void _openSettings(bool wide) {
    if (wide) {
      setState(() => _settingsInline = true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsPage(controller: c)),
    );
  }

  Widget _page(bool wide) {
    final gear = wide
        ? null
        : IconButton(
            key: const Key('nav-settings'),
            tooltip: context.l10n.navSettings,
            onPressed: () => _openSettings(false),
            icon: const Icon(Icons.settings_outlined),
          );
    if (wide && _settingsInline) {
      return SettingsPage(controller: c, embedded: true);
    }
    return switch (_tab) {
      AppTab.send => SendPage(
        controller: c,
        targetPeer: _targetPeer,
        settingsButton: gear,
        showSendBar: wide,
        onOpenDevices: () => _select(AppTab.devices),
      ),
      AppTab.history => HistoryPage(
        controller: c,
        settingsButton: gear,
        onSend: () => _select(AppTab.send),
      ),
      AppTab.devices => DevicesPage(controller: c, settingsButton: gear),
    };
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      final l = context.l10n;
      final destinations = [
        (AppTab.send, 'nav-send', Icons.arrow_upward_rounded, l.navSend, 0),
        (
          AppTab.history,
          'nav-history',
          Icons.schedule_rounded,
          l.navHistory,
          c.pendingTransfers.length,
        ),
        (
          AppTab.devices,
          'nav-devices',
          Icons.devices_rounded,
          l.navDevices,
          c.pendingPairings.length,
        ),
      ];
      Widget icon(IconData data, int badge) => badge == 0
          ? Icon(data)
          : Badge(label: Text('$badge'), child: Icon(data));
      final body = Column(
        children: [
          if (c.isBusy) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _page(wide)),
        ],
      );
      if (wide) {
        return Scaffold(
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  expanded: constraints.maxWidth >= 1000,
                  items: [
                    for (final (tab, key, data, label, badge) in destinations)
                      _SidebarItem(
                        key: Key(key),
                        icon: icon(data, badge),
                        label: label,
                        selected: !_settingsInline && _tab == tab,
                        onTap: () => _select(tab),
                      ),
                  ],
                  settings: _SidebarItem(
                    key: const Key('nav-settings'),
                    icon: const Icon(Icons.settings_outlined),
                    label: l.navSettings,
                    selected: _settingsInline,
                    onTap: () => _openSettings(true),
                  ),
                  version: c.versionLabel,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          ),
        );
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_tab == AppTab.send)
              SendBar(controller: c, targetPeer: _targetPeer),
            NavigationBar(
              selectedIndex: _tab.index,
              onDestinationSelected: (value) => _select(AppTab.values[value]),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final (_, key, data, label, badge) in destinations)
                  NavigationDestination(
                    key: Key(key),
                    icon: icon(data, badge),
                    label: label,
                    tooltip: label,
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.expanded,
    required this.items,
    required this.settings,
    required this.version,
  });
  final bool expanded;
  final List<Widget> items;
  final Widget settings;
  final String version;

  @override
  Widget build(BuildContext context) => Container(
    width: expanded ? 232 : 88,
    color: Theme.of(context).colorScheme.surface,
    padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 10, vertical: 18),
    child: Column(
      crossAxisAlignment: expanded
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.only(left: expanded ? 8 : 0, bottom: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(),
              if (expanded) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Ulash',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final item in items) ...[item, const SizedBox(height: 4)],
        const Spacer(),
        settings,
        if (expanded && version.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text(
              'Ulash $version',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
  );
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final Widget icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expanded =
        context.findAncestorWidgetOfExactType<_Sidebar>()?.expanded ?? true;
    return Semantics(
      selected: selected,
      button: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  IconTheme(
                    data: IconThemeData(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    child: icon,
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
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
    );
  }
}
