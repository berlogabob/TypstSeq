import 'package:material_ui/material_ui.dart';
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
    this.pages = const [],
    this.source = '',
    this.tags = const [],
    this.markers = const [],
    this.loans = const [],
    this.onAcceptLoan,
    this.onRejectLoan,
    this.onAcceptMarker,
    this.onRejectMarker,
    required this.onAccept,
    required this.onReject,
    required this.onCreate,
    required this.onIgnore,
    this.onRejectTag,
    this.onAcceptTag,
    this.appliedTags = const {},
  });

  final List<EnrichDecision> decisions;
  final List<NoteRef> pages;
  final String source;

  /// Suggested tags from the day's keywords; dismissing one is remembered.
  final List<String> tags;
  final ValueChanged<String>? onRejectTag;

  /// Adds a suggested tag to the day's header (phones never auto-write).
  final ValueChanged<String>? onAcceptTag;

  /// Tags already in the day's header; their chips show a check.
  final Set<String> appliedTags;

  final List<EnrichLoanOffer> loans;
  final ValueChanged<EnrichLoanOffer>? onAcceptLoan;
  final ValueChanged<EnrichLoanOffer>? onRejectLoan;

  /// Lines that look like ones the user files under a marker page (fixit).
  final List<EnrichMarkerOffer> markers;
  final ValueChanged<EnrichMarkerOffer>? onAcceptMarker;
  final ValueChanged<EnrichMarkerOffer>? onRejectMarker;
  final void Function(EnrichMention mention, NoteRef target) onAccept;
  final void Function(EnrichMention mention, NoteRef target) onReject;
  final void Function(EnrichMention mention) onCreate;
  final void Function(EnrichMention mention) onIgnore;

  @override
  Widget build(BuildContext context) {
    if (decisions.isEmpty && tags.isEmpty && markers.isEmpty && loans.isEmpty) {
      return const SizedBox.shrink();
    }
    final small = Theme.of(context).textTheme.bodySmall;
    // No scroll view of its own: the hosting sheet scrolls once. A capped
    // inner scroller hid every chip below the first rows (lines 14-15 and the
    // loan offer of a day never showed).
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpace16, kSpace4, kSpace16, kSpace8),
      child: Wrap(
        spacing: kSpace8,
        runSpacing: kSpace4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Mentions', style: small),
          for (final decision in decisions) _chip(context, decision),
          for (final offer in markers)
            InputChip(
              key: ValueKey('enrich-marker-${offer.marker.id}-${offer.line}'),
              // Tinted like a button: a pale "fixit?" read as a note, not a
              // suggestion, and the line was never filed.
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  'Tap to link as ${offer.marker.title}: ${offer.text}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              tooltip: 'Tap to file this line under ${offer.marker.title}',
              onPressed: onAcceptMarker == null
                  ? null
                  : () => onAcceptMarker!(offer),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: onRejectMarker == null
                  ? null
                  : () => onRejectMarker!(offer),
              deleteButtonTooltipMessage: 'Not ${offer.marker.title}',
            ),
          for (final offer in loans)
            InputChip(
              key: ValueKey('enrich-loan-${offer.line}'),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              avatar: const Icon(Icons.outbox_outlined, size: 16),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  'Track as loan: ${offer.equipment.map((e) => e.title).join(', ')}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              tooltip:
                  'Rewrite this line as a task: issued now, mark it Done when returned',
              onPressed: onAcceptLoan == null
                  ? null
                  : () => onAcceptLoan!(offer),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: onRejectLoan == null
                  ? null
                  : () => onRejectLoan!(offer),
              deleteButtonTooltipMessage: 'Not a loan',
            ),
          for (final tag in tags)
            InputChip(
              key: ValueKey('enrich-tag-$tag'),
              avatar: Icon(
                appliedTags.contains(tag) ? Icons.check : Icons.tag,
                size: 16,
              ),
              label: Text(tag),
              tooltip: appliedTags.contains(tag)
                  ? 'Tag added to this day'
                  : 'Suggested tag: tap to add or remove',
              onPressed: onRejectTag == null && onAcceptTag == null
                  ? null
                  : () => _confirmRemoveTag(context, tag),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: onRejectTag == null ? null : () => onRejectTag!(tag),
            ),
        ],
      ),
    );
  }

  /// The whole chip opens this, not only the small x: a tap on the word did
  /// nothing before, and people read that as "can't remove".
  Future<void> _confirmRemoveTag(BuildContext context, String tag) async {
    final add = !appliedTags.contains(tag) && onAcceptTag != null;
    final choice = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (add)
              ListTile(
                key: const ValueKey('enrich-tag-add'),
                leading: const Icon(Icons.add),
                title: Text('Add tag "$tag" to this day'),
                onTap: () => Navigator.pop(context, true),
              ),
            if (onRejectTag != null)
              ListTile(
                key: const ValueKey('enrich-tag-remove'),
                leading: const Icon(Icons.delete_outline),
                title: Text('Remove tag "$tag"'),
                subtitle: const Text(
                  'It will not be added from your days again',
                ),
                onTap: () => Navigator.pop(context, false),
              ),
          ],
        ),
      ),
    );
    if (choice == true) onAcceptTag?.call(tag);
    if (choice == false) onRejectTag?.call(tag);
  }

  Future<void> _choose(BuildContext context, EnrichDecision decision) async {
    final mention = decision.mention;
    final lines = source.split('\n');
    var searching = false;
    var query = '';
    final chosen = await showModalBottomSheet<NoteRef>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .7,
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      decision.choose
                          ? 'Which \u201c${mention.surface}\u201d?'
                          : 'Who is ${mention.surface}?',
                    ),
                    subtitle: mention.line > 0 && mention.line <= lines.length
                        ? Text(lines[mention.line - 1])
                        : null,
                  ),
                  if (searching)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back to suggestions',
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => setState(() {
                              searching = false;
                              query = '';
                            }),
                          ),
                          Expanded(
                            child: TextField(
                              autofocus: true,
                              decoration: const InputDecoration(
                                labelText: 'Search pages',
                              ),
                              onChanged: (value) =>
                                  setState(() => query = value),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final page
                            in searching && !decision.choose
                                ? pages.where(
                                    (page) =>
                                        isEnrichTarget(page) &&
                                        (page.title.toLowerCase().contains(
                                              query.toLowerCase(),
                                            ) ||
                                            page.aliases.any(
                                              (alias) =>
                                                  alias.toLowerCase().contains(
                                                    query.toLowerCase(),
                                                  ),
                                            )),
                                  )
                                : decision.candidates.map(
                                    (candidate) => candidate.note,
                                  ))
                          ListTile(
                            leading: Icon(switch (page.kind) {
                              'website' => Icons.language,
                              'event' => Icons.event_outlined,
                              _ => iconForKind(page.kind),
                            }),
                            title: Text(
                              decision.choose
                                  ? [
                                      page.title,
                                      if (page.properties['color']
                                          case final String color)
                                        color,
                                    ].join(' \u00b7 ')
                                  : page.title,
                            ),
                            subtitle: _candidateDetails(page, decision),
                            onTap: () => Navigator.pop(context, page),
                          ),
                        if (searching && !decision.choose && query.isEmpty)
                          const ListTile(
                            title: Text('Search by page title or alias'),
                          ),
                        if (searching &&
                            !decision.choose &&
                            query.isNotEmpty &&
                            !pages.any(
                              (page) =>
                                  isEnrichTarget(page) &&
                                  (page.title.toLowerCase().contains(
                                        query.toLowerCase(),
                                      ) ||
                                      page.aliases.any(
                                        (alias) => alias.toLowerCase().contains(
                                          query.toLowerCase(),
                                        ),
                                      )),
                            ))
                          const ListTile(title: Text('No matching pages')),
                        if (!searching && !decision.choose)
                          ListTile(
                            title: const Text('Other page…'),
                            onTap: () => setState(() => searching = true),
                          ),
                        if (!searching && !decision.choose)
                          ListTile(
                            title: const Text('Not a person/ignore'),
                            onTap: () {
                              Navigator.pop(context);
                              onIgnore(mention);
                            },
                          ),
                        if (!searching && !decision.choose)
                          ListTile(
                            title: const Text('New page'),
                            onTap: () {
                              Navigator.pop(context);
                              onCreate(mention);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (chosen != null) onAccept(mention, chosen);
  }

  Widget? _candidateDetails(NoteRef page, EnrichDecision decision) {
    final day = decision.candidates
        .where((candidate) => candidate.note.id == page.id)
        .firstOrNull
        ?.lastSeenDay;
    final details = [...page.partOf, if (day != null) 'Last seen $day'];
    return details.isEmpty ? null : Text(details.join(' · '));
  }

  Widget _chip(BuildContext context, EnrichDecision decision) {
    final mention = decision.mention;
    final target = decision.target;
    // One chip for a name several units share ("Quest 3"): pick the unit.
    if (decision.choose) {
      return ActionChip(
        key: ValueKey('enrich-choose-${mention.surface}'),
        avatar: const Icon(Icons.help_outline, size: 16),
        label: Text('Which \u201c${mention.surface}\u201d?'),
        tooltip: 'Choose which one you mean',
        onPressed: () => _choose(context, decision),
      );
    }
    return switch (decision.status) {
      EnrichStatus.linked => InputChip(
        key: ValueKey('enrich-linked-${mention.surface}'),
        avatar: const Icon(Icons.link, size: 16),
        label: Text(mention.surface),
        tooltip: 'Tap to link to ${target!.title}',
        onPressed: () => onAccept(mention, target),
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: () => onReject(mention, target),
      ),
      EnrichStatus.review => InputChip(
        key: ValueKey('enrich-review-${mention.surface}'),
        avatar: const Icon(Icons.add_link, size: 16),
        label: ConstrainedBox(
          constraints: BoxConstraints(
            // Chip padding, avatar and the x take about 100 px.
            maxWidth: MediaQuery.sizeOf(context).width - 2 * kSpace16 - 100,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Link \u201c${mention.surface}\u201d',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Flexible(
                flex: 2,
                child: Text(
                  ' \u2192 ${enrichShortTarget(mention.surface, target!)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        tooltip:
            'Link \u201c${mention.surface}\u201d to ${target.title}, or choose another page',
        onPressed: () => _choose(context, decision),
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: () => onReject(mention, target),
        deleteButtonTooltipMessage: 'Not ${target.title}',
      ),
      EnrichStatus.propose => ActionChip(
        key: ValueKey('enrich-new-${mention.surface}'),
        avatar: const Icon(Icons.add, size: 16),
        label: Text(mention.surface),
        tooltip: 'Choose a page',
        onPressed: () => _choose(context, decision),
      ),
    };
  }
}

/// The target without the name the surface already says: "ESP32 DevKit
/// TL-0102" for "ESP32 DevKit" is just "TL-0102".
String enrichShortTarget(String surface, NoteRef target) {
  final title = target.title;
  if (title.endsWith(' ${target.id}')) {
    final head = title.substring(0, title.length - target.id.length).trim();
    if (head.toLowerCase() == surface.toLowerCase() ||
        surface.toLowerCase().contains(head.toLowerCase()) ||
        head.toLowerCase().contains(surface.toLowerCase())) {
      return target.id;
    }
  }
  return title;
}
