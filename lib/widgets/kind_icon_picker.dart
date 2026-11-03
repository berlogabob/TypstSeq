import 'package:flutter/material.dart';

import 'constants.dart';

class KindIconPicker extends StatelessWidget {
  const KindIconPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    height: 144,
    child: GridView.count(
      crossAxisCount: 6,
      children: [
        for (final entry in kindIconPalette.entries)
          IconButton(
            key: ValueKey('kind-icon-${entry.key}'),
            tooltip: entry.key.replaceAll('_', ' '),
            isSelected: selected == entry.key,
            selectedIcon: Icon(
              entry.value,
              color: Theme.of(context).colorScheme.primary,
            ),
            icon: Icon(entry.value),
            onPressed: () => onSelected(entry.key),
          ),
      ],
    ),
  );
}

Future<String?> showKindIconPicker(BuildContext context, String? selected) =>
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kind icon'),
        content: KindIconPicker(
          selected: selected,
          onSelected: (icon) => Navigator.pop(context, icon),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
