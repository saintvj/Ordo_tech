import 'package:flutter/material.dart';

/// Asks before leaving a screen with unsaved changes. Returns true only if
/// the user chose to discard them.
Future<bool> confirmDiscardChanges(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep Editing'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return discard ?? false;
}
