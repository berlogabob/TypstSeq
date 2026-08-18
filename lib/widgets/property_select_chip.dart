import 'package:flutter/material.dart';

import 'constants.dart';

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

/// Relevance rating for triage — how much an article matters to the user's work.
const relevanceOptions = ['high', 'medium', 'low'];
const relevanceLabels = {'high': 'High', 'medium': 'Medium', 'low': 'Low'};

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

/// The further-along of two stored status values, folded onto the pipeline.
///
/// Imports can carry two competing claims — a bookkeeping `status` and a
/// separate `read_status` — and they disagree in both directions in real data.
/// Taking the later stage means merging them never walks a genuinely-read
/// article back to unread.
String laterArticleStatusStage(String? a, String? b) {
  final left = articleStatusStage(a);
  final right = articleStatusStage(b);
  return articleStatusOptions.indexOf(left) >= articleStatusOptions.indexOf(right)
      ? left
      : right;
}

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
    this.placeholder,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String? value;
  final List<String> options;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;
  final String? tooltip;

  /// Shown when [value] is null/unknown (e.g. an unrated article), instead of
  /// defaulting to the first option's label.
  final String? placeholder;
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
        final pill = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:
                backgroundColor ??
                Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border.all(color: foreground.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(kRadiusSmall),
          ),
          child: Text(
            labels[value] ?? value ?? placeholder ?? labels[options.first]!,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: foreground),
          ),
        );
        // PopupMenuButton sizes its gesture area to `child`, and two of these
        // pills sit side by side (status + relevance) in every article row —
        // the worst case for mis-taps. Constrain the child to the 48dp
        // minimum tap target (Material/WCAG target-size guidance) while
        // centering the unchanged pill inside it, so the hit area grows
        // without inflating what's painted.
        return ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kMinTapTarget,
            minHeight: kMinTapTarget,
          ),
          child: Center(widthFactor: 1, heightFactor: 1, child: pill),
        );
      },
    ),
  );
}
