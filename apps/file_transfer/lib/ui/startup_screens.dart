// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_controller.dart';

/// First launch: explains what the app does and why the system will ask for
/// local network access, before that prompt appears.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _finishing = false;

  AppLocalizations get l => AppLocalizations.of(context);

  List<(IconData, String, String)> get _steps => [
    (Icons.swap_horiz_rounded, l.onbTitle1, l.onbBody1),
    (Icons.wifi_rounded, l.onbTitle2, l.onbBody2),
    (Icons.verified_user_outlined, l.onbTitle3, l.onbBody3),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _steps.length - 1) {
      await _pages.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    setState(() => _finishing = true);
    await widget.controller.completeOnboarding();
    if (mounted) setState(() => _finishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _steps.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const Key('onboarding-skip'),
                      onPressed: _finishing || last
                          ? null
                          : () => _pages.animateToPage(
                              _steps.length - 1,
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                            ),
                      child: Text(last ? '' : l.skip),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _steps.length,
                      onPageChanged: (value) => setState(() => _page = value),
                      itemBuilder: (context, index) {
                        final (icon, title, body) = _steps[index];
                        return SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Column(
                              children: [
                                Container(
                                  width: 112,
                                  height: 112,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(32),
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 56,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 36),
                                Semantics(
                                  header: true,
                                  child: Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  body,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        height: 1.45,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Semantics(
                    label: l.onbStep(_page + 1, _steps.length),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _steps.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _page ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('onboarding-next'),
                      onPressed: _finishing ? null : _next,
                      child: Text(last ? l.start : l.next),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Startup failed: offer the recovery that matches the cause instead of a
/// dead end. Resetting keys or moving a journal aside always needs consent.
class StartupIssueScreen extends StatefulWidget {
  const StartupIssueScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<StartupIssueScreen> createState() => _StartupIssueScreenState();
}

class _StartupIssueScreenState extends State<StartupIssueScreen> {
  bool _working = false;
  AppController get c => widget.controller;
  AppLocalizations get l => AppLocalizations.of(context);

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _confirmReset() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.resetKeysQuestion),
        content: Text(l.resetKeysStartupBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const Key('confirm-reset-keys'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.reset),
          ),
        ],
      ),
    );
    if (accepted == true) await _run(c.resetDeviceKeys);
  }

  Future<void> _confirmRepair() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.repairQuestion),
        content: Text(l.repairBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const Key('confirm-repair-journal'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.repair),
          ),
        ],
      ),
    );
    if (accepted == true) await _run(c.repairStorage);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: scheme.error,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l.startupFailedTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    c.errorMessage ?? '',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  if (_working)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    )
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('startup-retry'),
                        onPressed: () => _run(c.retryStartup),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(l.retry),
                      ),
                    ),
                    if (c.startupIssue == StartupIssue.secureStorage) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          key: const Key('startup-reset-keys'),
                          onPressed: _confirmReset,
                          child: Text(l.resetKeys),
                        ),
                      ),
                    ],
                    if (c.startupIssue == StartupIssue.journal) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          key: const Key('startup-repair'),
                          onPressed: _confirmRepair,
                          child: Text(l.repairJournal),
                        ),
                      ),
                    ],
                    if (c.capabilities.diagnostics) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => _run(c.exportDiagnostics),
                        child: Text(l.sendDiagnostics),
                      ),
                    ],
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
