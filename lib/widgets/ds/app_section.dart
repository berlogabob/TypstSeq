import 'package:material_ui/material_ui.dart';

import '../constants.dart';

/// A titled group of rows in a settings page or sheet: a divider, a small
/// `labelMedium` header announced as a heading, then [children] (usually
/// [AppTile]s).
///
/// Pass `divider: false` for the first section so the page does not open with
/// a rule.
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
        child: Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      ...children,
    ],
  );
}
