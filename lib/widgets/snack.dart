import 'package:material_ui/material_ui.dart';

/// Shows a simple text [SnackBar] via the nearest [ScaffoldMessenger].
void showSnack(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Tells the user once, after the next frame, that a settings file was
/// unreadable and moved aside (e.g. `VaultRegistry.loadWarning`).
void showLoadWarning(BuildContext context, String? warning) {
  if (warning == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) showSnack(context, warning);
  });
}
