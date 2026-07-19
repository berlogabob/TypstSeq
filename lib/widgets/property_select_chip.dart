import 'package:flutter/material.dart';

/// Reading-triage pipeline stages, in order. Free-form legacy/custom status
/// values are folded onto these five by `articleStatusStage`.
const articleStatusOptions = [
  'unread',
  'skimmed',
  'read',
  'extracted',
  'cited',
];
const articleStatusLabels = {
  'unread': 'Unread',
  'skimmed': 'Skimmed',
  'read': 'Read',
  'extracted': 'Extracted',
  'cited': 'Cited',
};

/// Collapses any stored status string onto one of the five pipeline stages.
/// Legacy import default `processed` and empty status are unread; the older
/// `reading` in-progress state and unknown completion values count as read;
/// `summarized` (a custom extraction value) maps to extracted.
String articleStatusStage(String? status) => switch (status ?? 'unread') {
  'unread' || 'processed' || '' => 'unread',
  'skimmed' => 'skimmed',
  'extracted' || 'summarized' => 'extracted',
  'cited' => 'cited',
  _ => 'read',
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
