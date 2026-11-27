import 'package:material_ui/material_ui.dart';

/// Shows a two-button confirm/cancel [AlertDialog]. Returns `true` only when
/// the user taps the confirm action; dismissing or cancelling returns `false`.
///
/// Every yes/no question goes through here so the dismiss button is always
/// "Cancel" on the left and the primary action is a filled button named after
/// what it does ("Delete", "Merge"), never "OK" or "Yes". Set [destructive]
/// when confirming loses something: the primary button turns error-coloured.
/// Dialogs that collect input (a text field, a picker) build their own
/// [AlertDialog] and follow the same button order.
///
/// Pass [message] for plain text or [contentBuilder] for richer content.
/// [canConfirm] with [confirmChanges] disables the primary button until a
/// condition holds, such as a typed confirmation name.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  WidgetBuilder? contentBuilder,
  Listenable? confirmChanges,
  bool Function()? canConfirm,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  Key? confirmKey,
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
              key: confirmKey,
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
              key: confirmKey,
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
