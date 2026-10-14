import 'package:flutter/material.dart';

import '../constants.dart';

class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.title, required this.children})
    : body = null;

  /// Keeps a scrolling or flex-based body bounded by the sheet height.
  const AppSheet.body({super.key, required this.title, required Widget child})
    : body = child,
      children = const [];

  final String title;
  final List<Widget> children;
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final content = [
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
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kSpace16, kSpace8, kSpace16, kSpace24),
        child: body != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...content, Flexible(child: body!)],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...content, ...children],
                ),
              ),
      ),
    );
  }
}
