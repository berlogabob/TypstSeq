import 'package:flutter/material.dart';

const taskCheckedGlyph = '☑';
const taskUncheckedGlyph = '☐';

class TaskCheckbox extends StatelessWidget {
  const TaskCheckbox({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) => Checkbox(
    value: value,
    onChanged: onChanged,
    activeColor: Theme.of(context).colorScheme.primary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    visualDensity: VisualDensity.standard,
  );
}
