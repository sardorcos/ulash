import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

// Kept for plugin compatibility during the Flutter 3.50 Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'l10n/app_localizations.dart';
import 'services/diagnostics_log.dart';
import 'services/platform_permissions.dart';
import 'services/transfer_app_controller.dart';
import 'ui/file_transfer_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Uncaught errors are recorded locally (types and codes only) instead of
  // disappearing; App Store / Play crash reports cover native crashes.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    DiagnosticsLog.instance.error('flutter', details.exception, details.stack);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    DiagnosticsLog.instance.error('uncaught', error, stack);
    return true;
  };
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
    appBar: AppBar(title: Text(AppLocalizations.of(context).scannerTitle)),
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
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.no_photography_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context).cameraUnavailable,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: PlatformPermissions.openSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(AppLocalizations.of(context).openSettings),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 32,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                AppLocalizations.of(context).scannerHint,
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
