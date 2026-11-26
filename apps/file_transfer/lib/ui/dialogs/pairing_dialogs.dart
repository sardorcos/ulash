// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../ui_format.dart';
import '../widgets/common.dart';

/// Host side of pairing: "Do the codes match?" (like Bluetooth pairing).
class PairingRequestDialog extends StatefulWidget {
  const PairingRequestDialog({
    super.key,
    required this.controller,
    required this.request,
  });
  final AppController controller;
  final PairingRequest request;

  @override
  State<PairingRequestDialog> createState() => _PairingRequestDialogState();
}

class _PairingRequestDialogState extends State<PairingRequestDialog> {
  bool _working = false;

  Future<void> _answer(bool accept) async {
    setState(() => _working = true);
    if (accept) Haptics.success();
    try {
      await widget.controller.respondToPairing(widget.request.id, accept);
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final l = context.l10n;
      final request = widget.request;
      final stillPending = widget.controller.pendingPairings.any(
        (item) => item.id == request.id,
      );
      final hasCode = request.code != null;
      return AlertDialog(
        icon: Icon(platformIcon(request.platform)),
        title: Text(hasCode ? l.codesMatchTitle : l.pairingRequest),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasCode
                      ? l.sasHostBody(request.deviceName)
                      : l.pairingConfirmGeneric,
                  textAlign: TextAlign.center,
                ),
                if (!hasCode) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${request.deviceName} · ${platformLabel(l, request.platform)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
                if (hasCode) ...[
                  const SizedBox(height: 18),
                  PairingCode(
                    code: request.code!,
                    codeKey: const Key('pairing-request-code'),
                  ),
                ],
                if (!stillPending) ...[
                  const SizedBox(height: 12),
                  Text(
                    l.requestNoLongerActive,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: Key('dialog-decline-pair-${request.id}'),
            onPressed: _working || !stillPending ? null : () => _answer(false),
            child: Text(hasCode ? l.codesDiffer : l.decline),
          ),
          FilledButton(
            key: Key('dialog-approve-pair-${request.id}'),
            onPressed: _working || !stillPending ? null : () => _answer(true),
            child: Text(hasCode ? l.codesMatch : l.connect),
          ),
        ],
      );
    },
  );
}

/// Joiner side: shows the same code while the other device decides.
/// Closes itself when the controller drops the outgoing request.
Future<void> showOutgoingPairingSheet(
  BuildContext context,
  AppController controller,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _OutgoingPairingSheet(controller: controller),
);

class _OutgoingPairingSheet extends StatefulWidget {
  const _OutgoingPairingSheet({required this.controller});
  final AppController controller;

  @override
  State<_OutgoingPairingSheet> createState() => _OutgoingPairingSheetState();
}

class _OutgoingPairingSheetState extends State<_OutgoingPairingSheet> {
  OutgoingPairing? _last;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _last = widget.controller.outgoingPairing;
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final current = widget.controller.outgoingPairing;
    if (current == null && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    if (current != null) setState(() => _last = current);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final pairing = _last;
    if (pairing == null) return const SizedBox(height: 120);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                l.sasJoinerTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.sasJoinerBody(pairing.hostName),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            PairingCode(
              code: pairing.code,
              codeKey: const Key('outgoing-pairing-code'),
            ),
            const SizedBox(height: 20),
            if (pairing.waitingForApproval)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      l.waitingForApprovalOn(pairing.hostName),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
