import 'package:flutter/material.dart';

const articleStatusOptions = ['unread', 'reading', 'read'];
const articleStatusLabels = {
  'unread': 'Inbox',
  'reading': 'Reading',
  'read': 'Read',
};

/// A tappable chip that opens a popup menu to pick one of [options] — the
/// Notion-style "select" property control, generalized beyond article
/// status so any single-value enum property can reuse it.
class PropertySelectChip extends StatelessWidget {
  const PropertySelectChip({
    super.key,
    required this.value,
    required this.options,
    required this.labels,
    required this.onChanged,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String? value;
  final List<String> options;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tooltip ?? 'Change',
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final option in options)
        PopupMenuItem(value: option, child: Text(labels[option] ?? option)),
    ],
    child: Builder(
      builder: (context) {
        final foreground =
            foregroundColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:
                backgroundColor ??
                Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border.all(color: foreground.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            labels[value] ?? value ?? labels[options.first]!,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: foreground),
          ),
        );
      },
    ),
  );
}
