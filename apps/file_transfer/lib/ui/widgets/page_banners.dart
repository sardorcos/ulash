// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'common.dart';

/// Persistent state that needs the user's attention, shown at the top of
/// every page (transient messages are snackbars).
class PageBanners extends StatelessWidget {
  const PageBanners({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final l = context.l10n;
    final children = <Widget>[];
    if (c.localNetworkDenied ||
        c.networkState == NetworkState.permissionRequired) {
      children.add(
        Notice(
          key: const Key('local-network-notice'),
          icon: Icons.wifi_off_rounded,
          error: true,
          text: l.localNetworkNotice,
          action: Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => runAction(context, c, c.openSystemSettings),
                child: Text(l.openSettingsShort),
              ),
              TextButton(
                onPressed: () => runAction(context, c, c.refreshPeers),
                child: Text(l.retry),
              ),
            ],
          ),
        ),
      );
    } else if (c.errorMessage?.isNotEmpty ?? false) {
      children.add(
        Notice(
          icon: Icons.error_outline_rounded,
          text: c.errorMessage!,
          error: true,
        ),
      );
    }
    if (c.journalWarning) {
      children.add(
        Notice(
          key: const Key('journal-warning'),
          icon: Icons.warning_amber_rounded,
          text: l.journalWarningText,
        ),
      );
    }
    if (c.isBusy && c.busyLabel != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.busyLabel!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (c.canCancelPreparation)
                TextButton(
                  key: const Key('cancel-preparation'),
                  onPressed: () => runAction(context, c, c.cancelPreparation),
                  child: Text(l.cancel),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
