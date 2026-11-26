// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../ui_format.dart';
import '../widgets/common.dart';

/// Compose a short text or link and send it to one trusted, online device.
Future<void> showTextMessageSheet(
  BuildContext context,
  AppController controller,
  String? initialPeer,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) =>
      _TextMessageSheet(controller: controller, initialPeer: initialPeer),
);

class _TextMessageSheet extends StatefulWidget {
  const _TextMessageSheet({required this.controller, this.initialPeer});
  final AppController controller;
  final String? initialPeer;

  @override
  State<_TextMessageSheet> createState() => _TextMessageSheetState();
}

class _TextMessageSheetState extends State<_TextMessageSheet> {
  final _text = TextEditingController();
  late String? _peer = widget.initialPeer;
  bool _sending = false;

  static const _maxLength = 4000;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String peerId) async {
    setState(() => _sending = true);
    final c = widget.controller;
    final before = c.messageSerial;
    await runAction(context, c, () => c.sendText(peerId, _text.text.trim()));
    if (!mounted) return;
    setState(() => _sending = false);
    // Close only when the controller did not report an error.
    if (c.errorMessage == null || c.messageSerial == before) {
      Haptics.success();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final peers = c.peers.where((p) => p.isTrusted && p.isOnline).toList();
        final selected =
            peers.where((p) => p.id == _peer).firstOrNull ??
            (peers.length == 1 ? peers.single : null);
        final canSend =
            !_sending &&
            !c.isBusy &&
            selected != null &&
            _text.text.trim().isNotEmpty;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l.messageTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('message-input'),
                    controller: _text,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: _maxLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: l.messageHint,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  if (peers.isEmpty)
                    Text(
                      l.peerOpenApp,
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final peer in peers)
                          ChoiceChip(
                            key: Key('message-peer-${peer.id}'),
                            avatar: Icon(platformIcon(peer.platform), size: 18),
                            label: Text(peer.name),
                            selected: selected?.id == peer.id,
                            onSelected: (_) => setState(() => _peer = peer.id),
                            tooltip: platformLabel(l, peer.platform),
                          ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('send-message'),
                    onPressed: canSend ? () => _send(selected.id) : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward_rounded, size: 20),
                    label: Text(
                      selected == null
                          ? l.chooseRecipient
                          : l.sendToDevice(selected.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
