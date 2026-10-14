import 'package:flutter/material.dart';

/// Shows a two-button confirm/cancel [AlertDialog]. Returns `true` only when
/// the user taps the confirm action; dismissing or cancelling returns `false`.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  WidgetBuilder? contentBuilder,
  Listenable? confirmChanges,
  bool Function()? canConfirm,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  bool barrierDismissible = true,
}) async {
  assert(message != null || contentBuilder != null);
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) {
      Widget dialog() => AlertDialog(
        title: Text(title),
        content: contentBuilder?.call(context) ?? Text(message!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel),
          ),
          if (destructive)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: canConfirm?.call() == false
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            )
          else
            FilledButton(
              onPressed: canConfirm?.call() == false
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
        ],
      );
      return confirmChanges == null
          ? dialog()
          : AnimatedBuilder(
              animation: confirmChanges,
              builder: (context, _) => dialog(),
            );
    },
  );
  return confirmed ?? false;
}
