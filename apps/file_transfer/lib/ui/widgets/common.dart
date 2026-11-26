import 'dart:io';

// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../app_theme.dart';
import '../ui_format.dart';

extension UiContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// iOS/macOS: use Cupertino-style dialogs, sheets and transitions.
  bool get isCupertino {
    final platform = Theme.of(this).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }
}

/// Runs a controller action; a thrown error becomes a snackbar instead of an
/// unhandled exception (the controller usually reports errors itself).
Future<void> runAction(
  BuildContext context,
  AppController controller,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          controller.errorMessage ?? context.l10n.actionFailedRetry,
        ),
      ),
    );
  }
}

abstract final class Haptics {
  static void selection() => HapticFeedback.selectionClick();
  static void success() => HapticFeedback.mediumImpact();
  static void warning() => HapticFeedback.heavyImpact();
}

String formatEta(double seconds) {
  final total = seconds.isFinite ? seconds.ceil().clamp(1, 359999) : 359999;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final sec = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// Max content width so pages read well on iPad and desktop.
const double kContentWidth = 760;

/// A page with a collapsing large title (iOS-style) and constrained content.
class LargeTitlePage extends StatelessWidget {
  const LargeTitlePage({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.bottomPadding = 32,
    this.storageKey,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget> actions;
  final double bottomPadding;
  final String? storageKey;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = width > kContentWidth + 48 ? (width - kContentWidth) / 2 : 16.0;
    return CustomScrollView(
      key: storageKey == null ? null : PageStorageKey(storageKey),
      slivers: [
        SliverAppBar.large(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          centerTitle: false,
          actions: [...actions, const SizedBox(width: 4)],
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
        ),
        for (final sliver in slivers)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: side),
            sliver: sliver,
          ),
        SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
      ],
    );
  }
}

/// Grouped inset section (iOS Settings style) with an optional header/footer.
class Section extends StatelessWidget {
  const Section({
    super.key,
    this.title,
    this.trailing,
    this.footer,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    this.spacing = true,
  });

  final String? title;
  final Widget? trailing;
  final String? footer;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool spacing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: spacing ? 20 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title ?? '',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _withDividers(context, children),
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                footer!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _withDividers(BuildContext context, List<Widget> items) {
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0 && items[i] is! SectionGap && items[i - 1] is! SectionGap) {
        result.add(const Divider(height: 1));
      }
      result.add(items[i]);
    }
    return result;
  }
}

/// Spacer inside a [Section] that suppresses the automatic divider.
class SectionGap extends StatelessWidget {
  const SectionGap({super.key, this.height = 8});
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}

/// One row in a grouped section; wraps long text instead of breaking words.
class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.chevron = false,
    this.tileKey,
    this.value,
  });

  final String title;
  final String? subtitle;

  /// Current value (e.g. the chosen theme): trailing at normal text sizes,
  /// moved under the title when large text would not fit beside it.
  final String? value;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool chevron;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : null;
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 13;
    final valueStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final subtitleText = [
      if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
      if (largeText && value != null) value!,
    ].join('\n');
    return InkWell(
      key: tileKey,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: color ?? scheme.primary),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: color),
                    ),
                    if (subtitleText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitleText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!largeText && value != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (chevron)
                Icon(
                  context.isCupertino
                      ? Icons.chevron_right_rounded
                      : Icons.arrow_forward_ios_rounded,
                  size: context.isCupertino ? 24 : 16,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
    child: Column(
      children: [
        IconTile(icon: icon, size: 56),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          description,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.icon,
    required this.text,
    this.error = false,
    this.action,
  });
  final IconData icon;
  final String text;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error ? scheme.error : scheme.primary;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action!),
        ],
      ),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 44, this.color});
  final IconData icon;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Icon(icon, color: tint, size: size * .5),
    );
  }
}

IconData fileTypeIcon(String name) {
  final extension = name.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' ||
    'jpeg' ||
    'png' ||
    'heic' ||
    'heif' ||
    'webp' ||
    'gif' ||
    'bmp' => Icons.image_outlined,
    'mp4' || 'mov' || 'mkv' || 'avi' || 'm4v' || 'webm' => Icons.movie_outlined,
    'mp3' || 'wav' || 'aac' || 'flac' || 'm4a' || 'ogg' => Icons.music_note_rounded,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'txt' || 'md' || 'rtf' => Icons.notes_rounded,
    _ => Icons.insert_drive_file_outlined,
  };
}

/// Thumbnail for an image file when a local preview path exists, otherwise a
/// file-type icon. Decodes at a small size to keep long lists cheap.
class FileThumb extends StatelessWidget {
  const FileThumb({super.key, required this.name, this.previewPath, this.size = 44});
  final String name;
  final String? previewPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = previewPath;
    if (path == null) return IconTile(icon: fileTypeIcon(name), size: size);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .24),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * ratio).round(),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => IconTile(icon: fileTypeIcon(name), size: size),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00A295), turquoise],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      child: Icon(Icons.swap_horiz_rounded, color: Colors.white, size: size * .66),
    ),
  );
}

String networkLabel(AppLocalizations l, NetworkState state) => switch (state) {
  NetworkState.starting => l.networkStarting,
  NetworkState.ready => l.networkReady,
  NetworkState.unavailable => l.networkUnavailable,
  NetworkState.permissionRequired => l.networkPermissionRequired,
};

/// Compact network indicator used in app bars.
class NetworkIndicator extends StatelessWidget {
  const NetworkIndicator({super.key, required this.state});
  final NetworkState state;
  @override
  Widget build(BuildContext context) {
    final ready = state == NetworkState.ready;
    final scheme = Theme.of(context).colorScheme;
    final label = networkLabel(context.l10n, state);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Icon(
          ready ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          color: ready ? scheme.primary : scheme.error,
          size: 22,
        ),
      ),
    );
  }
}

IconData platformIcon(DevicePlatform platform) => switch (platform) {
  DevicePlatform.ios || DevicePlatform.android => Icons.smartphone_rounded,
  DevicePlatform.windows ||
  DevicePlatform.macos ||
  DevicePlatform.linux => Icons.laptop_rounded,
  DevicePlatform.unknown => Icons.devices_rounded,
};

/// Row describing a device (connected list, nearby list).
class PeerTile extends StatelessWidget {
  const PeerTile({super.key, required this.peer, this.trailing});
  final PeerDevice peer;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconTile(icon: platformIcon(peer.platform)),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: peer.isOnline ? const Color(0xFF2EB872) : scheme.outline,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 2),
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
                  peer.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${platformLabel(l, peer.platform)} · '
                  '${peer.isOnline ? l.peerAvailable : l.peerOffline}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Big, monospaced 6-digit code used for pairing confirmation.
class PairingCode extends StatelessWidget {
  const PairingCode({super.key, required this.code, this.codeKey});
  final String code;
  final Key? codeKey;
  @override
  Widget build(BuildContext context) {
    final grouped = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    return Semantics(
      label: code.split('').join(' '),
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            grouped,
            key: codeKey,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
