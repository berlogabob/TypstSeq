import 'package:flutter/material.dart';

/// Small note under a setting's title saying which devices it applies to.
class ScopeNote extends StatelessWidget {
  const ScopeNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
