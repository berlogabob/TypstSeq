import 'package:flutter/material.dart';

const articleStatusOptions = ['unread', 'reading', 'read'];
const articleStatusLabels = {
  'unread': 'Unread',
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
  });

  final String? value;
  final List<String> options;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tooltip ?? 'Change',
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final option in options)
        PopupMenuItem(value: option, child: Text(labels[option] ?? option)),
    ],
    child: Chip(label: Text(labels[value] ?? value ?? labels[options.first]!)),
  );
}
