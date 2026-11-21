// Manual screenshot harness, not a pixel-regression test.
// Run with CAPTURE_UI=true and FLUTTER_SDK pointing to the local SDK.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_transfer/ui/app_controller.dart';
import 'package:file_transfer/ui/file_transfer_app.dart';
// Test the bundled Material API used by the compatible application shell.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_core/transfer_core.dart';

import 'ui_test.dart' show TestController;

/// Empty view state with a real temporary TLS host and a real invitation.
/// No device, file, transfer, history, or progress fixtures are inserted.
class CaptureController extends TestController {
  CaptureController(this.host) {
    deviceName = host.identity.displayName;
    networkState = NetworkState.ready;
    receivingEnabled = true;
  }
  final CoreHost host;

  @override
  String get saveLocationLabel => 'Хранилище приложения';

  @override
  Future<void> createInvitation() async {
    final value = host.createInvite();
    invitation = PairingInvitation(
      payload: value.encode(),
      expiresAt: DateTime.now().add(Duration(seconds: value.ttlSeconds)),
    );
    notifyListeners();
  }
}

void main() {
  testWidgets('capture real widget previews with an ephemeral TLS host', (
    tester,
  ) async {
    final sdk = Platform.environment['FLUTTER_SDK'];
    if (sdk == null) throw StateError('FLUTTER_SDK is required.');
    await tester.runAsync(() async {
      final fontRoot = '$sdk/bin/cache/artifacts/material_fonts';
      final roboto = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        roboto.addFont(
          File('$fontRoot/Roboto-$weight.ttf')
              .readAsBytes()
              .then((value) => ByteData.sublistView(value)),
        );
      }
      await roboto.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File('$fontRoot/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then((value) => ByteData.sublistView(value)),
      );
      await icons.load();
    });

    late Directory sessionDirectory;
    late DurableInbox inbox;
    late TrustedPeerStore peers;
    late CoreHost host;
    final secrets = MemorySecretStore();
    await tester.runAsync(() async {
      sessionDirectory = await Directory.systemTemp.createTemp('transfer-ui-');
      final identity = await DeviceIdentity.generate(displayName: 'Linux');
      peers = TrustedPeerStore(secrets);
      inbox = await DurableInbox.open(sessionDirectory);
      host = CoreHost(identity: identity, peers: peers, inbox: inbox);
      await host.start();
    });
    final controller = CaptureController(host);
    final boundary = GlobalKey();
    final output = Directory('../../docs/previews');
    output.createSync(recursive: true);

    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 100));
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }

    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1000);
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: FileTransferApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await capture('desktop-send');
      await tester.tap(find.byKey(const Key('nav-receive')));
      await tester.pumpAndSettle();
      await capture('desktop-receive');
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Показать приглашение'),
      );
      await tester.pumpAndSettle();
      await capture('desktop-invitation');
      await tester.tap(find.widgetWithText(TextButton, 'Закрыть'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 844);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      await capture('mobile-receive');
      await tester.tap(find.byKey(const Key('nav-send')));
      await tester.pumpAndSettle();
      await capture('mobile-send');
      await tester.tap(find.byKey(const Key('nav-devices')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-invitation')));
      await tester.pumpAndSettle();
      await capture('mobile-invitation');
      await tester.tap(find.widgetWithText(TextButton, 'Закрыть'));
      await tester.pumpAndSettle();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
      controller.dispose();
      await tester.runAsync(() async {
        await host.close();
        await inbox.close();
        await peers.close();
        secrets.clear();
        await sessionDirectory.delete(recursive: true);
      });
    }
  }, skip: Platform.environment['CAPTURE_UI'] != 'true');
}
