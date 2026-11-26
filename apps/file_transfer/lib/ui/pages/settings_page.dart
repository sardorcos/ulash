// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../dialogs/adaptive.dart';
import '../ui_format.dart';
import '../widgets/common.dart';

const _languages = [
  (null, null),
  ('ru', 'Русский'),
  ('uz', 'Oʻzbekcha'),
  ('en', 'English'),
];

/// iOS-style grouped settings. Rarely used items live in "Advanced".
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.embedded = false,
  });
  final AppController controller;

  /// Inline in the wide layout (no own Scaffold/back button).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final page = ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _SettingsBody(controller: controller),
    );
    return embedded ? page : Scaffold(body: page);
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.controller});
  final AppController controller;
  AppController get c => controller;

  String _themeLabel(AppLocalizations l, ThemeMode mode) => switch (mode) {
    ThemeMode.system => l.themeSystem,
    ThemeMode.light => l.themeLight,
    ThemeMode.dark => l.themeDark,
  };

  Future<void> _rename(BuildContext context) async {
    final l = context.l10n;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TextEntryDialog(
        title: l.deviceName,
        description: l.renameHint,
        label: l.name,
        button: l.save,
        initialValue: c.deviceName,
        maxLength: 80,
      ),
    );
    if ((name?.trim().isNotEmpty ?? false) && context.mounted) {
      await runAction(context, c, () => c.renameDevice(name!.trim()));
    }
  }

  Future<void> _chooseTheme(BuildContext context) async {
    final l = context.l10n;
    final mode = await chooseAction<ThemeMode>(
      context,
      title: l.theme,
      actions: [
        for (final (mode, icon) in const [
          (ThemeMode.system, Icons.brightness_auto_outlined),
          (ThemeMode.light, Icons.light_mode_outlined),
          (ThemeMode.dark, Icons.dark_mode_outlined),
        ])
          SheetAction(
            value: mode,
            label: _themeLabel(l, mode),
            icon: c.themeMode == mode ? Icons.check_rounded : icon,
            key: Key('theme-${mode.name}'),
          ),
      ],
    );
    if (mode != null && context.mounted) {
      Haptics.selection();
      await runAction(context, c, () => c.setThemeMode(mode));
    }
  }

  Future<void> _chooseLanguage(BuildContext context) async {
    final l = context.l10n;
    final code = await chooseAction<String>(
      context,
      title: l.language,
      actions: [
        for (final (code, label) in _languages)
          SheetAction(
            value: code ?? 'system',
            label: label ?? l.languageSystem,
            icon: (c.locale?.languageCode ?? 'system') == (code ?? 'system')
                ? Icons.check_rounded
                : Icons.language_rounded,
            key: Key('locale-${code ?? 'system'}'),
          ),
      ],
    );
    if (code != null && context.mounted) {
      Haptics.selection();
      await runAction(
        context,
        c,
        () => c.setLocale(code == 'system' ? null : Locale(code)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final caps = c.capabilities;
    final languageLabel =
        _languages
            .where((e) => e.$1 != null && e.$1 == c.locale?.languageCode)
            .firstOrNull
            ?.$2 ??
        l.languageSystem;

    return LargeTitlePage(
      title: l.navSettings,
      storageKey: 'settings',
      slivers: [
        SliverToBoxAdapter(
          child: Section(
            title: l.thisDevice,
            children: [
              SettingTile(
                tileKey: const Key('rename-device'),
                icon: Icons.smartphone_rounded,
                title: c.deviceName,
                subtitle: c.deviceCode == null
                    ? l.deviceName
                    : '${l.deviceCode}: ${c.deviceCode}',
                chevron: caps.rename,
                onTap: caps.rename && !c.isBusy ? () => _rename(context) : null,
              ),
              if (c.saveLocationLabel.isNotEmpty)
                SettingTile(
                  tileKey: const Key('save-location'),
                  icon: Icons.folder_outlined,
                  title: l.saveDestination,
                  subtitle: c.saveLocationLabel,
                  chevron: caps.saveLocation,
                  onTap: caps.saveLocation && !c.isBusy
                      ? () => runAction(context, c, c.chooseSaveLocation)
                      : null,
                ),
            ],
          ),
        ),
        if (caps.photosSave)
          SliverToBoxAdapter(
            child: Section(
              title: l.receiving,
              footer: l.autoSaveHint,
              children: [
                SwitchListTile.adaptive(
                  key: const Key('auto-save-photos'),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    Icons.photo_library_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  value: c.autoSaveToPhotos,
                  onChanged: c.isBusy
                      ? null
                      : (value) => runAction(
                          context,
                          c,
                          () => c.setAutoSaveToPhotos(value),
                        ),
                  title: Text(l.autoSaveToPhotos),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: Section(
            title: l.appearance,
            children: [
              SettingTile(
                tileKey: const Key('settings-theme'),
                icon: Icons.contrast_rounded,
                title: l.theme,
                value: _themeLabel(l, c.themeMode),
                chevron: true,
                onTap: () => _chooseTheme(context),
              ),
              SettingTile(
                tileKey: const Key('settings-language'),
                icon: Icons.language_rounded,
                title: l.language,
                value: languageLabel,
                chevron: true,
                onTap: () => _chooseLanguage(context),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Section(
            title: l.privacyAndSupport,
            children: [
              SettingTile(
                tileKey: const Key('privacy-details'),
                icon: Icons.shield_outlined,
                title: l.howDataHandled,
                subtitle: l.privacySummary,
                chevron: true,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l.privacy),
                    content: SingleChildScrollView(child: Text(l.privacyBody)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l.close),
                      ),
                    ],
                  ),
                ),
              ),
              SettingTile(
                tileKey: const Key('privacy-policy'),
                icon: Icons.privacy_tip_outlined,
                title: l.privacyPolicy,
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => runAction(
                  context,
                  c,
                  () => c.openExternalUrl(c.privacyPolicyUrl),
                ),
              ),
              SettingTile(
                tileKey: const Key('support'),
                icon: Icons.help_outline_rounded,
                title: l.support,
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () =>
                    runAction(context, c, () => c.openExternalUrl(c.supportUrl)),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Section(
            children: [
              SettingTile(
                tileKey: const Key('settings-advanced'),
                icon: Icons.tune_rounded,
                title: l.advanced,
                subtitle: l.advancedHint,
                chevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdvancedSettingsPage(controller: c),
                  ),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: Column(
                children: [
                  const BrandMark(size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'Ulash ${c.versionLabel}'.trim(),
                    key: const Key('version-label'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Storage, connection details, diagnostics and key reset.
class AdvancedSettingsPage extends StatelessWidget {
  const AdvancedSettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _AdvancedBody(controller: controller),
    ),
  );
}

class _AdvancedBody extends StatelessWidget {
  const _AdvancedBody({required this.controller});
  final AppController controller;
  AppController get c => controller;

  Future<void> _confirmResetKeys(BuildContext context) async {
    final l = context.l10n;
    final accepted = await confirmDestructive(
      context,
      title: l.resetKeysQuestion,
      body: l.resetKeysBody,
      confirmLabel: l.reset,
      confirmKey: const Key('confirm-reset-keys'),
    );
    if (accepted && context.mounted) {
      await runAction(context, c, c.resetDeviceKeys);
    }
  }

  Future<void> _confirmCleanup(BuildContext context) async {
    final l = context.l10n;
    final files = List<TemporaryFileItem>.of(
      c.storageOverview?.unusedFiles ?? const [],
    );
    if (files.isEmpty) return;
    final bytes = files.fold<int>(0, (sum, file) => sum + file.bytes);
    final accepted = await confirmDialog(
      context,
      title: l.deleteTemporaryQuestion,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.deleteTemporaryBody(files.length, formatBytes(l, bytes))),
          const SizedBox(height: 14),
          for (final file in files.take(10))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(l.fileWithSize(file.name, formatBytes(l, file.bytes))),
            ),
          if (files.length > 10) Text(l.andMoreFilesDot(files.length - 10)),
        ],
      ),
      cancelLabel: l.keep,
      confirmLabel: l.deleteCopies,
      confirmKey: const Key('confirm-cleanup-temporary'),
    );
    if (accepted && context.mounted) {
      await runAction(
        context,
        c,
        () => c.clearUnusedTemporary(files.map((file) => file.id).toList()),
      );
    }
  }

  Future<void> _confirmIncomingCleanup(BuildContext context) async {
    final l = context.l10n;
    // The preview is fixed when the dialog opens: only these IDs are cleared.
    final transfers = List<IncomingCleanupItem>.of(
      c.storageOverview?.incompleteIncoming ?? const [],
    );
    if (transfers.isEmpty) return;
    final bytes = transfers.fold<int>(0, (sum, i) => sum + i.temporaryBytes);
    final reserved = transfers.fold<int>(0, (sum, i) => sum + i.reservedBytes);
    final accepted = await confirmDialog(
      context,
      title: l.stopIncomingQuestion,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.stopIncomingBody(
              transfers.length,
              formatBytes(l, bytes),
              formatBytes(l, reserved),
            ),
          ),
          const SizedBox(height: 14),
          for (final item in transfers)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                l.incompleteItem(
                  item.title,
                  item.peerName,
                  fileCountLabel(l, item.pendingFileCount),
                  formatBytes(l, item.temporaryBytes),
                  item.completedFileCount,
                ),
              ),
            ),
        ],
      ),
      cancelLabel: l.keep,
      confirmLabel: l.stopAndClear,
      destructive: true,
      confirmKey: const Key('confirm-cleanup-incoming'),
    );
    if (accepted && context.mounted) {
      await runAction(
        context,
        c,
        () => c.clearIncompleteIncoming(transfers.map((i) => i.id).toList()),
      );
    }
  }

  List<Widget> _storage(BuildContext context) {
    final l = context.l10n;
    final storage = c.storageOverview;
    final enabled = c.capabilities.storageManagement && !c.isBusy;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    if (storage == null) {
      return [SettingTile(icon: Icons.storage_rounded, title: l.storageUnavailable)];
    }
    return [
      SettingTile(
        icon: Icons.storage_rounded,
        title: l.freeSpace,
        subtitle: storage.availableBytes == null
            ? l.freeSpaceUnknown
            : l.freeSpaceChecked(
                formatBytes(l, storage.availableBytes!),
                formatDate(l, storage.checkedAt),
              ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.temporaryCopies, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 2),
            Text(
              l.temporaryUsage(
                formatBytes(l, storage.temporaryBytes),
                formatBytes(l, storage.reservedBytes),
              ),
              style: small,
            ),
            if (storage.temporaryQuotaBytes != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value:
                      ((storage.temporaryBytes + storage.reservedBytes) /
                              storage.temporaryQuotaBytes!)
                          .clamp(0.0, 1.0),
                  semanticsLabel: l.quotaUsageSemantics,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(l.quotaTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final gib in const [5, 10, 20, 50])
                  ChoiceChip(
                    key: Key('quota-$gib'),
                    label: Text('$gib ${l.unitGiB}'),
                    selected:
                        storage.temporaryQuotaBytes == gib * 1024 * 1024 * 1024,
                    onSelected: enabled
                        ? (_) => runAction(
                            context,
                            c,
                            () => c.setTemporaryQuota(gib * 1024 * 1024 * 1024),
                          )
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l.quotaHint(formatBytes(l, storage.safetyReserveBytes)),
              style: small,
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.unusedCopies, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 2),
            Text(
              l.unusedCopiesSummary(
                fileCountLabel(l, storage.unusedFiles.length),
                formatBytes(l, storage.unusedBytes),
              ),
              style: small,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('cleanup-temporary'),
              onPressed: enabled && storage.unusedFiles.isNotEmpty
                  ? () => _confirmCleanup(context)
                  : null,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l.clearUnusedCopies),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.incompleteIncoming,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 2),
            Text(
              l.incompleteSummary(
                storage.incompleteIncoming.length,
                formatBytes(l, storage.incompleteTemporaryBytes),
                formatBytes(l, storage.incompleteReservedBytes),
              ),
              style: small,
            ),
            const SizedBox(height: 6),
            Text(l.incompleteHint, style: small),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('cleanup-incoming'),
              onPressed: enabled && storage.incompleteIncoming.isNotEmpty
                  ? () => _confirmIncomingCleanup(context)
                  : null,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l.clearIncomplete),
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final caps = c.capabilities;
    return LargeTitlePage(
      title: l.advanced,
      storageKey: 'advanced',
      slivers: [
        SliverToBoxAdapter(
          child: Section(
            title: l.storage,
            trailing: caps.storageManagement
                ? IconButton(
                    key: const Key('refresh-storage'),
                    tooltip: l.refreshStorage,
                    onPressed: !c.isBusy && !c.storageRefreshing
                        ? () => runAction(context, c, c.refreshStorage)
                        : null,
                    icon: const Icon(Icons.refresh_rounded),
                  )
                : null,
            children: _storage(context),
          ),
        ),
        if (c.journalWarning)
          SliverToBoxAdapter(
            child: Notice(
              icon: Icons.warning_amber_rounded,
              text: l.journalWarningText,
            ),
          ),
        SliverToBoxAdapter(
          child: Section(
            title: l.connection,
            children: [
              SettingTile(
                icon: Icons.wifi_rounded,
                title: l.localNetwork,
                subtitle: c.networkDetail ?? networkLabel(l, c.networkState),
              ),
              SettingTile(
                icon: Icons.verified_user_outlined,
                title: l.trustedDevices,
                subtitle: l.trustedDevicesHint,
              ),
            ],
          ),
        ),
        if (caps.diagnostics)
          SliverToBoxAdapter(
            child: Section(
              title: l.support,
              children: [
                SettingTile(
                  tileKey: const Key('share-diagnostics'),
                  icon: Icons.description_outlined,
                  title: l.diagnosticsLog,
                  subtitle: l.diagnosticsHint,
                  chevron: true,
                  onTap: c.isBusy
                      ? null
                      : () => runAction(context, c, c.exportDiagnostics),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: Section(
            title: l.dangerZone,
            children: [
              SettingTile(
                tileKey: const Key('reset-keys'),
                icon: Icons.key_off_outlined,
                title: l.resetKeys,
                subtitle: l.resetKeysHint,
                destructive: true,
                onTap: c.isBusy ? null : () => _confirmResetKeys(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
