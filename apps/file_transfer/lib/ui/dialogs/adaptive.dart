// Keep the bundled Material API for compatibility with Flutter stable clients.
// ignore: deprecated_member_use
import 'package:flutter/cupertino.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../widgets/common.dart';

/// Confirmation dialog: Cupertino alert on iOS/macOS, Material elsewhere.
/// Returns true only when the confirm action was chosen.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  Widget? content,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  Key? confirmKey,
}) async {
  final cancel = cancelLabel ?? context.l10n.cancel;
  final contentWidget =
      content ?? (body == null ? null : Text(body));
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      if (context.isCupertino) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: contentWidget == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SingleChildScrollView(child: contentWidget),
                ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: Text(cancel),
            ),
            CupertinoDialogAction(
              key: confirmKey,
              isDestructiveAction: destructive,
              isDefaultAction: !destructive,
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        );
      }
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: contentWidget == null
            ? null
            : SizedBox(
                width: 440,
                child: SingleChildScrollView(child: contentWidget),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancel),
          ),
          FilledButton(
            key: confirmKey,
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result == true;
}

/// Destructive confirmation: an action sheet on iOS, a dialog elsewhere.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  Key? confirmKey,
}) async {
  if (!context.isCupertino) {
    return confirmDialog(
      context,
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      destructive: true,
      confirmKey: confirmKey,
    );
  }
  final result = await showCupertinoModalPopup<bool>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: Text(title),
      message: Text(body),
      actions: [
        CupertinoActionSheetAction(
          key: confirmKey,
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context, false),
        child: Text(context.l10n.cancel),
      ),
    ),
  );
  return result == true;
}

/// A menu of actions: action sheet on iOS, bottom sheet list elsewhere.
class SheetAction<T> {
  const SheetAction({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
    this.key,
  });
  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
  final Key? key;
}

Future<T?> chooseAction<T>(
  BuildContext context, {
  String? title,
  required List<SheetAction<T>> actions,
}) {
  if (context.isCupertino) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (final action in actions)
            CupertinoActionSheetAction(
              key: action.key,
              isDestructiveAction: action.destructive,
              onPressed: () => Navigator.pop(context, action.value),
              child: Text(action.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            for (final action in actions)
              ListTile(
                key: action.key,
                leading: Icon(
                  action.icon,
                  color: action.destructive ? scheme.error : null,
                ),
                title: Text(
                  action.label,
                  style: TextStyle(
                    color: action.destructive ? scheme.error : null,
                  ),
                ),
                onTap: () => Navigator.pop(context, action.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Single- or multi-line text input dialog.
class TextEntryDialog extends StatefulWidget {
  const TextEntryDialog({
    super.key,
    required this.title,
    required this.description,
    required this.label,
    required this.button,
    this.initialValue = '',
    this.multiline = false,
    this.maxLength,
  });
  final String title;
  final String description;
  final String label;
  final String button;
  final String initialValue;
  final bool multiline;
  final int? maxLength;

  @override
  State<TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<TextEntryDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.description),
            const SizedBox(height: 16),
            TextField(
              key: const Key('dialog-text-input'),
              controller: _text,
              autofocus: true,
              minLines: widget.multiline ? 3 : 1,
              maxLines: widget.multiline ? 6 : 1,
              maxLength: widget.maxLength,
              autocorrect: false,
              enableSuggestions: !widget.multiline,
              decoration: InputDecoration(
                labelText: widget.label,
                alignLabelWithHint: widget.multiline,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: widget.multiline ? null : (_) => _submit(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: _text.text.trim().isEmpty ? null : _submit,
        child: Text(widget.button),
      ),
    ],
  );
}
