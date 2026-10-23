import 'package:flutter/material.dart';
import 'package:tylog_core/enrich.dart';

import '../models.dart';
import 'constants.dart';

/// The day's mentions, one chip each, below the day note:
/// linked ones can be undone, ambiguous ones confirmed or rejected, unknown
/// people and places turned into pages. Hidden when there is nothing to show.
class EnrichReview extends StatelessWidget {
  const EnrichReview({
    super.key,
    required this.decisions,
    this.tags = const [],
    required this.onAccept,
    required this.onReject,
    required this.onCreate,
    this.onRejectTag,
  });

  final List<EnrichDecision> decisions;

  /// Tags the block adds from the day's keywords; removing one is remembered.
  final List<String> tags;
  final ValueChanged<String>? onRejectTag;
  final void Function(EnrichMention mention, NoteRef target) onAccept;
  final void Function(EnrichMention mention, NoteRef target) onReject;
  final void Function(EnrichMention mention) onCreate;

  @override
  Widget build(BuildContext context) {
    if (decisions.isEmpty && tags.isEmpty) return const SizedBox.shrink();
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpace16, kSpace4, kSpace16, kSpace8),
      child: Wrap(
        spacing: kSpace8,
        runSpacing: kSpace4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Mentions', style: small),
          for (final decision in decisions) _chip(context, decision),
          for (final tag in tags)
            InputChip(
              key: ValueKey('enrich-tag-$tag'),
              avatar: const Icon(Icons.tag, size: 16),
              label: Text(tag),
              tooltip: 'Tag added from this day. Remove to stop adding it.',
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: onRejectTag == null ? null : () => onRejectTag!(tag),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, EnrichDecision decision) {
    final mention = decision.mention;
    final target = decision.target;
    return switch (decision.status) {
      EnrichStatus.linked => InputChip(
        key: ValueKey('enrich-linked-${mention.surface}'),
        avatar: const Icon(Icons.link, size: 16),
        label: Text(mention.surface),
        tooltip: 'Linked to ${target!.title}. Remove to unlink.',
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: () => onReject(mention, target),
      ),
      EnrichStatus.review => InputChip(
        key: ValueKey('enrich-review-${mention.surface}'),
        avatar: const Icon(Icons.help_outline, size: 16),
        label: Text('${mention.surface} → ${target!.title}?'),
        tooltip: decision.candidates.length > 1
            ? 'Tap to link. Not them? Remove to see the next match.'
            : 'Tap to link',
        onPressed: () => onAccept(mention, target),
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: () => onReject(mention, target),
        deleteButtonTooltipMessage: 'Not ${target.title}',
      ),
      EnrichStatus.propose => ActionChip(
        key: ValueKey('enrich-new-${mention.surface}'),
        avatar: const Icon(Icons.add, size: 16),
        label: Text(mention.surface),
        tooltip: 'Create a ${mention.type} page',
        onPressed: () => onCreate(mention),
      ),
    };
  }
}
