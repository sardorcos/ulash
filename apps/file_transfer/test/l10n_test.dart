import 'package:file_transfer/l10n/app_localizations.dart';
import 'package:file_transfer/ui/app_controller.dart';
import 'package:file_transfer/ui/file_transfer_app.dart';
import 'package:file_transfer/ui/ui_format.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test.dart' show TestController;

class _LocalizedController extends TestController {
  _LocalizedController(this.chosen);
  final Locale chosen;
  @override
  Locale? get locale => chosen;
}

void main() {
  const expectations = {
    'ru': ('Отправить', 'Настройки', 'Передача завершена'),
    'uz': ('Yuborish', 'Sozlamalar', 'Uzatish yakunlandi'),
    'en': ('Send', 'Settings', 'Transfer complete'),
  };

  for (final MapEntry(key: code, value: (send, settings, done))
      in expectations.entries) {
    testWidgets('interface renders in $code', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = _LocalizedController(Locale(code))
        ..transfers = [
          TransferItem(
            id: 'in:done',
            title: 'report.pdf',
            peerName: 'Laptop',
            direction: TransferDirection.incoming,
            phase: TransferPhase.completed,
            totalBytes: 2048,
            transferredBytes: 2048,
            createdAt: DateTime.utc(2026, 11, 21, 10),
          ),
        ];
      await tester.pumpWidget(FileTransferApp(controller: controller));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(send), findsWidgets);
      expect(find.text(settings), findsWidgets);
      await tester.tap(find.byKey(const Key('nav-history')));
      await tester.pumpAndSettle();
      expect(find.text(done), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav-settings')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  test('every locale has all strings and plural forms', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = lookupAppLocalizations(locale);
      for (final count in [1, 2, 5, 11, 21, 22, 25]) {
        expect(l.filesCount(count), contains('$count'));
      }
      expect(formatBytes(l, 1536), isNotEmpty);
    }
    final ru = lookupAppLocalizations(const Locale('ru'));
    expect(ru.filesCount(1), '1 файл');
    expect(ru.filesCount(3), '3 файла');
    expect(ru.filesCount(5), '5 файлов');
    expect(ru.filesCount(21), '21 файл');
    expect(formatBytes(ru, 1536), '1,5 КиБ');
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.filesCount(1), '1 file');
    expect(en.filesCount(2), '2 files');
    expect(formatBytes(en, 1536), '1.5 KB');
  });
}
