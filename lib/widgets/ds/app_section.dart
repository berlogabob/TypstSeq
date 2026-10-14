import 'package:flutter/material.dart';

import '../constants.dart';

class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.children,
    this.divider = true,
  });

  final String title;
  final List<Widget> children;
  final bool divider;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (divider) const Divider(height: kSpace16),
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpace8,
          vertical: kSpace4,
        ),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      ...children,
    ],
  );
}
