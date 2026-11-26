import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import 'app_controller.dart';

String formatBytes(AppLocalizations l, num bytes) {
  if (bytes < 0) return '—';
  final units = [l.unitB, l.unitKiB, l.unitMiB, l.unitGiB, l.unitTiB];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final digits = index == 0 || value >= 100 ? 0 : 1;
  final text = value.toStringAsFixed(digits);
  // Russian and Uzbek use a decimal comma.
  final localized = l.localeName.startsWith('en')
      ? text
      : text.replaceAll('.', ',');
  return '$localized ${units[index]}';
}

String fileCountLabel(AppLocalizations l, int count) => l.filesCount(count);

String platformLabel(AppLocalizations l, DevicePlatform platform) =>
    switch (platform) {
      DevicePlatform.ios => 'iOS',
      DevicePlatform.android => 'Android',
      DevicePlatform.windows => 'Windows',
      DevicePlatform.macos => 'macOS',
      DevicePlatform.linux => 'Linux',
      DevicePlatform.unknown => l.platformUnknown,
    };

String phaseLabel(AppLocalizations l, TransferPhase phase) => switch (phase) {
  TransferPhase.preparing => l.phasePreparing,
  TransferPhase.queued => l.phaseQueued,
  TransferPhase.retrying => l.phaseRetrying,
  TransferPhase.waitingForConsent => l.phaseWaitingForConsent,
  TransferPhase.transferring => l.phaseTransferring,
  TransferPhase.verifying => l.phaseVerifying,
  TransferPhase.completed => l.phaseCompleted,
  TransferPhase.paused => l.phasePaused,
  TransferPhase.failed => l.phaseFailed,
  TransferPhase.cancelled => l.phaseCancelled,
  TransferPhase.expired => l.phaseExpired,
};

String formatDate(
  AppLocalizations l,
  DateTime date, {
  bool includeSeconds = false,
}) {
  final local = date.toLocal();
  if (l.localeName.startsWith('en')) {
    try {
      final day = DateFormat.yMMMd(l.localeName).format(local);
      final time = includeSeconds
          ? DateFormat.Hms(l.localeName).format(local)
          : DateFormat.Hm(l.localeName).format(local);
      return '$day · $time';
    } catch (_) {
      // Date symbols not loaded (outside a localized widget tree).
    }
  }
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(local.day)}.${pad(local.month)}.${local.year} · '
      '${pad(local.hour)}:${pad(local.minute)}'
      '${includeSeconds ? ':${pad(local.second)}' : ''}';
}

/// Section header for a day in History: "Today", "Yesterday" or a date.
String formatDay(AppLocalizations l, DateTime date, {DateTime? now}) {
  final local = date.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final diff = DateTime(today.year, today.month, today.day).difference(day);
  if (diff.inDays == 0) return l.today;
  if (diff.inDays == 1) return l.yesterday;
  try {
    return local.year == today.year
        ? DateFormat.MMMMd(l.localeName).format(local)
        : DateFormat.yMMMMd(l.localeName).format(local);
  } catch (_) {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(local.day)}.${pad(local.month)}.${local.year}';
  }
}

String formatTime(AppLocalizations l, DateTime date) {
  final local = date.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(local.hour)}:${pad(local.minute)}';
}
