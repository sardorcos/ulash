import 'app_controller.dart';

String formatBytes(num bytes) {
  if (bytes < 0) return '—';
  const units = ['Б', 'КиБ', 'МиБ', 'ГиБ', 'ТиБ'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final digits = index == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits).replaceAll('.', ',')} ${units[index]}';
}

String fileCountLabel(int count) {
  final mod100 = count % 100;
  if (mod100 >= 11 && mod100 <= 14) return '$count файлов';
  return switch (count % 10) {
    1 => '$count файл',
    2 || 3 || 4 => '$count файла',
    _ => '$count файлов',
  };
}

String platformLabel(DevicePlatform platform) => switch (platform) {
  DevicePlatform.ios => 'iOS',
  DevicePlatform.android => 'Android',
  DevicePlatform.windows => 'Windows',
  DevicePlatform.macos => 'macOS',
  DevicePlatform.linux => 'Linux',
  DevicePlatform.unknown => 'Устройство',
};

String phaseLabel(TransferPhase phase) => switch (phase) {
  TransferPhase.preparing => 'Подготавливаем файлы',
  TransferPhase.queued => 'В очереди',
  TransferPhase.waitingForConsent => 'Ждём подтверждения',
  TransferPhase.transferring => 'Передаём файлы',
  TransferPhase.verifying => 'Проверяем файл',
  TransferPhase.completed => 'Передача завершена',
  TransferPhase.paused => 'Передача приостановлена',
  TransferPhase.failed => 'Не удалось завершить',
  TransferPhase.cancelled => 'Передача отменена',
};

String formatDate(DateTime date) {
  final local = date.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(local.day)}.${pad(local.month)}.${local.year} · '
      '${pad(local.hour)}:${pad(local.minute)}';
}
