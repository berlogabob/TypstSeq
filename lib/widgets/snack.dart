import 'package:material_ui/material_ui.dart';

/// Shows a simple text [SnackBar] via the nearest [ScaffoldMessenger].
///
/// [duration] overrides the default display time, for messages the user has to
/// act on elsewhere before they disappear.
void showSnack(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    duration == null
        ? SnackBar(content: Text(message), action: action)
        : SnackBar(content: Text(message), action: action, duration: duration),
  );
}

/// Tells the user once, after the next frame, that a settings file was
/// unreadable and moved aside (e.g. `VaultRegistry.loadWarning`).
void showLoadWarning(BuildContext context, String? warning) {
  if (warning == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) showSnack(context, warning);
  });
}
