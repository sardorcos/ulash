import 'dart:io';

import 'package:file_transfer/services/platform_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final source = File('/private/test/inbox/received/transfer/file/report.pdf');

  tearDown(() {
    messenger.setMockMethodCallHandler(PlatformStorage.channel, null);
  });

  test(
    'capacity preserves 64-bit values and sends the actual volume path',
    () async {
      MethodCall? observed;
      messenger.setMockMethodCallHandler(PlatformStorage.channel, (call) async {
        observed = call;
        return 11 * 1024 * 1024 * 1024;
      });
      final directory = Directory('/private/test/inbox');
      expect(await PlatformStorage.freeBytes(directory), 11811160064);
      expect(observed?.method, 'freeBytes');
      expect(observed?.arguments, {'path': directory.absolute.path});
    },
  );

  test(
    'missing capacity adapter is unknown instead of unlimited space',
    () async {
      expect(
        await PlatformStorage.freeBytes(Directory('/private/test')),
        isNull,
      );
    },
  );

  test(
    'native capacity failure is unknown and invalid capacity is rejected',
    () async {
      messenger.setMockMethodCallHandler(PlatformStorage.channel, (call) async {
        throw PlatformException(code: 'STORAGE_UNAVAILABLE');
      });
      expect(
        await PlatformStorage.freeBytes(Directory('/private/test')),
        isNull,
      );
      for (final invalid in [-1, 4.5, '1000000', true]) {
        messenger.setMockMethodCallHandler(
          PlatformStorage.channel,
          (call) async => invalid,
        );
        await expectLater(
          PlatformStorage.freeBytes(Directory('/private/test')),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'export sends references only and requires a completed native receipt',
    () async {
      MethodCall? observed;
      messenger.setMockMethodCallHandler(PlatformStorage.channel, (call) async {
        observed = call;
        return {
          'status': 'exported',
          'destinationLabel': 'report (2).pdf',
          'platformReference': 'content://provider/document/123',
        };
      });
      final result = await PlatformStorage.exportFile(
        source: source,
        displayName: 'report.pdf',
        mimeType: 'application/pdf',
      );
      expect(result?.destinationLabel, 'report (2).pdf');
      expect(result?.platformReference, 'content://provider/document/123');
      expect(observed?.method, 'exportFile');
      expect(observed?.arguments, {
        'sourcePath': source.absolute.path,
        'displayName': 'report.pdf',
        'mimeType': 'application/pdf',
      });
    },
  );

  test('cancelled system picker is not a successful export', () async {
    messenger.setMockMethodCallHandler(
      PlatformStorage.channel,
      (call) async => null,
    );
    expect(
      await PlatformStorage.exportFile(
        source: source,
        displayName: 'report.pdf',
      ),
      isNull,
    );
  });

  test(
    'native copy failure and interruption are preserved as errors',
    () async {
      for (final code in [
        'EXPORT_FAILED',
        'EXPORT_INTERRUPTED',
        'EXPORT_DESTINATION_EXISTS',
      ]) {
        messenger.setMockMethodCallHandler(PlatformStorage.channel, (
          call,
        ) async {
          throw PlatformException(code: code);
        });
        await expectLater(
          PlatformStorage.exportFile(source: source, displayName: 'report.pdf'),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
        );
      }
    },
  );

  test('missing export adapter does not claim success', () async {
    await expectLater(
      PlatformStorage.exportFile(source: source, displayName: 'report.pdf'),
      throwsA(isA<MissingPluginException>()),
    );
  });

  test(
    'partial or malformed native receipts cannot mark export complete',
    () async {
      final invalid = <Object>[
        true,
        'saved',
        {'destinationLabel': 'report.pdf'},
        {'status': 'copying', 'destinationLabel': 'report.pdf'},
        {'status': 'exported', 'destinationLabel': ''},
        {'status': 'exported', 'destinationLabel': '   '},
        {
          'status': 'exported',
          'destinationLabel': 'report.pdf',
          'platformReference': 42,
        },
        {
          'status': 'exported',
          'destinationLabel': 'report.pdf',
          'platformReference': '',
        },
      ];
      for (final value in invalid) {
        messenger.setMockMethodCallHandler(
          PlatformStorage.channel,
          (call) async => value,
        );
        await expectLater(
          PlatformStorage.exportFile(source: source, displayName: 'report.pdf'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'unsafe names and malformed MIME types never reach the system picker',
    () async {
      var requests = 0;
      messenger.setMockMethodCallHandler(PlatformStorage.channel, (call) async {
        requests++;
        return null;
      });
      for (final name in [
        '',
        '.',
        '..',
        '../private',
        r'C:\secret',
        'bad\u0000name',
      ]) {
        await expectLater(
          PlatformStorage.exportFile(source: source, displayName: name),
          throwsArgumentError,
        );
      }
      await expectLater(
        PlatformStorage.exportFile(
          source: source,
          displayName: 'report.pdf',
          mimeType: 'pdf\nanything',
        ),
        throwsArgumentError,
      );
      expect(requests, 0);
    },
  );
}
