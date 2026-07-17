import 'package:flutter/material.dart';

/// Shows a simple text [SnackBar] via the nearest [ScaffoldMessenger].
void showSnack(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message), action: action));
}
