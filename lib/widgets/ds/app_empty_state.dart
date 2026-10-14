import 'package:flutter/material.dart';

import '../constants.dart';
import '../loading.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.loading = false,
    this.primaryAction,
    this.secondaryAction,
  });

  final IconData icon;
  final String title;
  final String hint;
  final bool loading;
  final Widget? primaryAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(kSpace24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const LoadingIndicator(size: kIconSmall)
            else
              Icon(
                icon,
                size: kIcon,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            const SizedBox(height: kSpace12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (!loading) ...[
              const SizedBox(height: kSpace8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (!loading &&
                (primaryAction != null || secondaryAction != null)) ...[
              const SizedBox(height: kSpace16),
              Wrap(
                spacing: kSpace8,
                runSpacing: kSpace8,
                alignment: WrapAlignment.center,
                children: [?primaryAction, ?secondaryAction],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
