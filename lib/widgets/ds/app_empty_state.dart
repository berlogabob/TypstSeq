import 'package:material_ui/material_ui.dart';

import '../app_icons.dart';
import '../constants.dart';
import '../loading.dart';

/// What a whole surface shows when it has nothing to list: icon, title, a
/// one-line [hint] that says what would fill it, and up to two actions.
///
/// Use it when the empty message is the only content of a tab, page or pane.
/// An empty section inside a longer list stays a one-line [ListTile], so the
/// list does not jump when the section fills.
///
/// [loading] swaps the icon for a spinner and hides the hint and actions; use
/// it while the index is still building so "empty" is not claimed too early.
///
/// [AppEmptyState.error] is the same surface when loading failed: a warning
/// icon in the error colour, a short title, the reason as the hint, and
/// usually a Retry action.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.loading = false,
    this.primaryAction,
    this.secondaryAction,
  }) : error = false,
       details = null;

  /// [hint] says in plain words what failed and what to try. [details] holds
  /// the raw exception: it stays out of the way behind a "Details" button
  /// (unless [secondaryAction] is given) and can be selected and copied.
  const AppEmptyState.error({
    super.key,
    required this.title,
    required this.hint,
    this.details,
    this.primaryAction,
    this.secondaryAction,
  }) : icon = AppIcons.warning,
       loading = false,
       error = true;

  final IconData icon;
  final String title;
  final String hint;
  final bool loading;

  /// True for [AppEmptyState.error].
  final bool error;

  /// Technical text for [AppEmptyState.error], shown on request.
  final String? details;
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
            // The spinner sits in a box the icon's size, so the title does not
            // move when loading ends.
            if (loading)
              const SizedBox.square(
                dimension: kIconLarge,
                child: Center(child: LoadingIndicator(size: kIcon)),
              )
            else
              Icon(
                icon,
                size: kIconLarge,
                color: error
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            const SizedBox(height: kSpace16),
            // An error appears after the surface was shown, so announce it.
            Semantics(
              liveRegion: error,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
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
                (primaryAction != null || _secondary(context) != null)) ...[
              const SizedBox(height: kSpace16),
              Wrap(
                spacing: kSpace8,
                runSpacing: kSpace8,
                alignment: WrapAlignment.center,
                children: [?primaryAction, ?_secondary(context)],
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget? _secondary(BuildContext context) =>
      secondaryAction ??
      (details == null
          ? null
          : TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(title),
                  content: SingleChildScrollView(
                    child: SelectableText(details!),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
              child: const Text('Details'),
            ));
}
