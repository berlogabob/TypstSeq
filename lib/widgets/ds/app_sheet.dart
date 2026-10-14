import 'package:flutter/material.dart';

import '../constants.dart';

class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(kSpace16, kSpace8, kSpace16, kSpace24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: kMinTapTarget,
              height: kSpace4,
              margin: const EdgeInsets.only(bottom: kSpace16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(kRadiusSmall),
              ),
            ),
          ),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: kSpace12),
          ...children,
        ],
      ),
    ),
  );
}
