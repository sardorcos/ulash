import 'dart:async';
import 'dart:io';

// Kept for plugin compatibility during the Flutter 3.50 Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'services/transfer_app_controller.dart';
import 'ui/file_transfer_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final navigator = GlobalKey<NavigatorState>();
  final controller = TransferAppController(
    scanCode: Platform.isAndroid || Platform.isIOS
        ? () async {
            final state = navigator.currentState;
            if (state == null) return null;
            return state.push<String>(
              MaterialPageRoute(builder: (_) => const _ScannerScreen()),
            );
          }
        : null,
  );
  runApp(FileTransferApp(controller: controller, navigatorKey: navigator));
  unawaited(controller.initialize());
}

class _ScannerScreen extends StatefulWidget {
  const _ScannerScreen();
  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  final _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _found = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Подключить устройство')),
    body: Stack(
      children: [
        MobileScanner(
          controller: _camera,
          onDetect: (capture) {
            if (_found || !mounted) return;
            final payload = capture.barcodes
                .map((barcode) => barcode.rawValue)
                .whereType<String>()
                .where((value) => value.startsWith('xferapp://pair?'))
                .firstOrNull;
            if (payload == null) return;
            _found = true;
            Navigator.of(context).pop(payload);
          },
          errorBuilder: (context, error) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Камера недоступна. Разрешите доступ в настройках или '
                'вернитесь и вставьте код подключения вручную.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 32,
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Наведите камеру на QR-код в разделе «Получить» '
                'на другом устройстве. Оба устройства должны быть в одной сети.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }
}
