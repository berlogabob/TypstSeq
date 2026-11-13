import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tylog_core/tylog_core.dart';

import 'constants.dart';

Future<void> _runDirect(Future<void> Function() body) async => await body();

String ellipsizeMiddle(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  if (maxLength <= 1) return maxLength == 1 ? '…' : '';
  final start = maxLength ~/ 2;
  final end = maxLength - 1 - start;
  return '${text.substring(0, start)}…${text.substring(text.length - end)}';
}

class EnrichReview extends StatefulWidget {
  const EnrichReview({
    super.key,
    required this.decisions,
    this.pages = const [],
    this.source = '',
    this.tags = const [],
    this.markers = const [],
    this.loans = const [],
    this.openLoans = const {},
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
    this.dayLabel,
    this.skipped = const {},
    this.onSkipLine,
    this.batch = _runDirect,
  });

  final List<EnrichDecision> decisions;
  final List<NoteRef> pages;
  final String source;
  final List<String> tags;
  final List<EnrichMarkerOffer> markers;
  final List<EnrichLoanOffer> loans;
  final Map<String, List<TaskRef>> openLoans;
  final Set<String> appliedTags;
  final FutureOr<void> Function(EnrichMention, NoteRef) onAccept;
  final FutureOr<void> Function(EnrichMention, NoteRef) onReject;
  final FutureOr<void> Function(EnrichMention) onCreate;
  final FutureOr<void> Function(EnrichMention) onIgnore;
  final FutureOr<dynamic> Function(EnrichLoanOffer)? onAcceptLoan;
  final FutureOr<void> Function(EnrichLoanOffer)? onRejectLoan;
  final FutureOr<void> Function(EnrichMarkerOffer)? onAcceptMarker;
  final FutureOr<void> Function(EnrichMarkerOffer)? onRejectMarker;
  final FutureOr<void> Function(String)? onRejectTag;
  final FutureOr<void> Function(String)? onAcceptTag;
  final String? dayLabel;
  final Set<String> skipped;
  final ValueChanged<String>? onSkipLine;
  final Future<void> Function(Future<void> Function()) batch;

  @override
  State<EnrichReview> createState() => _EnrichReviewState();
}

class _EnrichReviewState extends State<EnrichReview> {
  final Set<String> _skipped = {};
  final Set<EnrichDecision> _hidden = {};
  final Set<String> _accepted = {};

  @override
  void didUpdateWidget(covariant EnrichReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.decisions != widget.decisions ||
        oldWidget.loans != widget.loans ||
        oldWidget.source != widget.source) {
      _accepted.clear();
    }
  }

  List<EnrichCardRow> _rows(EnrichLineCard card) => [
    for (final row in card.rows)
      if (!_hidden.contains(row.decision)) row,
  ];

  String? _label(EnrichLineCard card) => enrichPrimaryLabel(
    _rows(card).where((row) => row.state == EnrichRowState.willLink).length,
    card.loan,
  );

  Future<void> _cardBody(EnrichLineCard card) async {
    try {
      for (final row in _rows(card)) {
        if (row.state == EnrichRowState.willLink) {
          await widget.onAccept(row.decision!.mention, row.target!);
        }
      }
      if (card.loan != null &&
          await widget.onAcceptLoan?.call(card.loan!) == false) {
        if (mounted) setState(() => _accepted.remove(card.key));
      }
    } catch (_) {
      if (mounted) setState(() => _accepted.remove(card.key));
      rethrow;
    }
  }

  Future<void> _runCard(EnrichLineCard card) async {
    setState(() => _accepted.add(card.key));
    await widget.batch(() async => await _cardBody(card));
  }

  Future<void> _acceptAll(List<EnrichLineCard> cards) async {
    cards = cards.where((card) => _label(card) != null).toList();
    final links = cards.fold<int>(
      0,
      (count, card) =>
          count +
          _rows(
            card,
          ).where((row) => row.state == EnrichRowState.willLink).length,
    );
    final loans = cards.where((card) => card.loan != null).length;
    final parts = <String>[
      if (links > 0) 'link $links ${links == 1 ? 'mention' : 'mentions'}',
      if (loans > 0) 'track $loans ${loans == 1 ? 'loan' : 'loans'}',
    ];
    final description = parts.join(' and ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${description[0].toUpperCase()}${description.substring(1)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('enrich-accept-all-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept all'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _accepted.addAll(cards.map((card) => card.key)));
      await widget.batch(() async {
        for (final card in acceptAllOrder(cards)) {
          await _cardBody(card);
        }
      });
    }
  }

  Future<void> _rowMenu(EnrichCardRow row) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('enrich-menu-link'),
              title: Text('Link to ${row.target!.title}'),
              onTap: () => Navigator.pop(context, 'link'),
            ),
            ListTile(
              key: const ValueKey('enrich-menu-other'),
              title: const Text('Other page…'),
              onTap: () => Navigator.pop(context, 'other'),
            ),
            ListTile(
              key: const ValueKey('enrich-menu-reject'),
              title: const Text('Not this'),
              onTap: () => Navigator.pop(context, 'reject'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'other') {
      await _choose(context, row.decision!);
    } else if (choice == 'link') {
      await widget.batch(() async {
        await widget.onAccept(row.decision!.mention, row.target!);
      });
    } else if (choice == 'reject') {
      setState(() => _hidden.add(row.decision!));
      await widget.batch(() async {
        await widget.onReject(row.decision!.mention, row.target!);
      });
    }
  }

  Widget _lineText(EnrichLineCard card) {
    final spans = <InlineSpan>[];
    final color = Theme.of(context).colorScheme.primaryContainer;
    var position = 0;
    for (final row in _rows(card)) {
      if (row.highlightStart < 0 || row.highlightEnd < 0) continue;
      final start = row.highlightStart.clamp(0, card.text.length);
      final end = row.highlightEnd.clamp(0, card.text.length);
      if (end <= position || end <= start) continue;
      if (start > position) {
        spans.add(TextSpan(text: card.text.substring(position, start)));
      }
      final from = start < position ? position : start;
      spans.add(
        TextSpan(
          text: card.text.substring(from, end),
          style: TextStyle(fontWeight: FontWeight.bold, backgroundColor: color),
        ),
      );
      position = end;
    }
    spans.add(TextSpan(text: card.text.substring(position)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _row(EnrichLineCard card, EnrichCardRow row) {
    final scheme = Theme.of(context).colorScheme;
    final target = row.target;
    final fullTarget = target == null
        ? null
        : widget.pages.where((page) => page.id == target.id).firstOrNull ??
              target;
    final label = switch (row.state) {
      EnrichRowState.ambiguous => 'choose…',
      EnrichRowState.propose =>
        row.decision!.mention.type == 'person' ||
                row.decision!.mention.type == 'professor'
            ? 'new person?'
            : 'new page?',
      _ => enrichTargetLabel(
        enrichShortTarget(row.surface, fullTarget!),
        fullTarget.properties['color'],
      ),
    };
    return InkWell(
      key: ValueKey('enrich-row-${card.line}-${row.surface}'),
      onTap: row.state == EnrichRowState.linked
          ? null
          : () async {
              if (row.state == EnrichRowState.willLink) {
                await _rowMenu(row);
              } else {
                await _choose(context, row.decision!);
              }
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: kSpace4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinTapTarget - 2 * kSpace4,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final surface = ellipsizeMiddle(row.surface, 28);
              final linked = row.state == EnrichRowState.linked;
              final painter = TextPainter(
                text: TextSpan(
                  text: '$surface  →  $label${linked ? '  ✓ linked' : ''}',
                  style: DefaultTextStyle.of(context).style,
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final wrap = painter.width + 2 * kSpace8 > constraints.maxWidth;
              painter.dispose();
              final surfaceText = Tooltip(
                message: row.surface,
                child: Text(
                  surface,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
              final destination = Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('→'),
                  const SizedBox(width: kSpace8),
                  Flexible(child: Text(label)),
                  if (linked)
                    Padding(
                      padding: const EdgeInsets.only(left: kSpace8),
                      child: Text(
                        '✓ linked',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              );
              return wrap
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        surfaceText,
                        Padding(
                          padding: const EdgeInsets.only(left: kSpace8),
                          child: destination,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: surfaceText),
                        const SizedBox(width: kSpace8),
                        destination,
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  Widget _card(EnrichLineCard card) {
    final scheme = Theme.of(context).colorScheme;
    final label = _label(card);
    return Container(
      key: ValueKey('enrich-card-${card.line}'),
      margin: const EdgeInsets.only(bottom: kSpace8),
      padding: const EdgeInsets.all(kSpace12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(kRadiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.taskId == null)
            _lineText(card)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _lineText(card)),
                Text('task', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          for (final row in _rows(card)) _row(card, row),
          if (card.warning != null)
            Wrap(
              spacing: kSpace8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.warning_amber_outlined, color: scheme.error),
                Text(
                  card.warning!,
                  key: ValueKey('enrich-warning-${card.line}'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          Wrap(
            spacing: kSpace8,
            children: [
              if (label != null)
                FilledButton.tonal(
                  key: ValueKey('enrich-primary-${card.line}'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget),
                  ),
                  onPressed: () async => await _runCard(card),
                  child: Text(label),
                ),
              TextButton(
                key: ValueKey('enrich-skip-${card.line}'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, kMinTapTarget),
                ),
                onPressed: () async => await widget.batch(() async {
                  setState(() => _skipped.add(card.key));
                  widget.onSkipLine?.call(card.key);
                }),
                child: const Text('Skip line'),
              ),
              if (card.loan != null)
                TextButton(
                  key: ValueKey('enrich-not-loan-${card.line}'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget),
                  ),
                  onPressed: widget.onRejectLoan == null
                      ? null
                      : () async => await widget.batch(() async {
                          await widget.onRejectLoan!(card.loan!);
                        }),
                  child: const Text('Not a loan'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = enrichLineCards(
      decisions: widget.decisions,
      loans: widget.loans,
      lines: widget.source.split('\n'),
      openLoans: widget.openLoans,
    );
    final visible = cards
        .where(
          (card) =>
              !_accepted.contains(card.key) &&
              !_skipped.contains(card.key) &&
              !widget.skipped.contains(card.key) &&
              (_rows(card).isNotEmpty || card.loan != null),
        )
        .toList();
    final count = visible.length;
    final header =
        '${widget.dayLabel == null ? '' : '${widget.dayLabel!} · '}$count ${count == 1 ? 'line' : 'lines'} to review';
    final empty =
        visible.isEmpty && widget.tags.isEmpty && widget.markers.isEmpty;
    return AnimatedSize(
      duration: kMotionStatus,
      alignment: Alignment.topCenter,
      child: empty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                kSpace16,
                kSpace4,
                kSpace16,
                kSpace8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (visible.isNotEmpty ||
                      ((widget.tags.isNotEmpty || widget.markers.isNotEmpty) &&
                          widget.dayLabel != null))
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            visible.isNotEmpty ? header : widget.dayLabel!,
                          ),
                        ),
                        if (visible.any((card) => _label(card) != null))
                          TextButton(
                            key: const ValueKey('enrich-accept-all'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, kMinTapTarget),
                            ),
                            onPressed: () async => await _acceptAll(visible),
                            child: const Text('Accept all'),
                          ),
                      ],
                    ),
                  for (final card in cards)
                    AnimatedSize(
                      key: ValueKey('enrich-card-animation-${card.line}'),
                      duration: kMotionStatus,
                      alignment: Alignment.topCenter,
                      child: visible.contains(card)
                          ? _card(card)
                          : const SizedBox.shrink(),
                    ),
                  if (widget.markers.isNotEmpty)
                    Wrap(
                      spacing: kSpace8,
                      runSpacing: kSpace4,
                      children: [
                        for (final offer in widget.markers)
                          InputChip(
                            key: ValueKey(
                              'enrich-marker-${offer.marker.id}-${offer.line}',
                            ),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            avatar: const Icon(
                              Icons.bookmark_add_outlined,
                              size: 16,
                            ),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: Text(
                                'Tap to link as ${offer.marker.title}: ${offer.text}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            tooltip:
                                'Tap to file this line under ${offer.marker.title}',
                            onPressed: widget.onAcceptMarker == null
                                ? null
                                : () async {
                                    await widget.batch(
                                      () async =>
                                          await widget.onAcceptMarker!(offer),
                                    );
                                  },
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: widget.onRejectMarker == null
                                ? null
                                : () async {
                                    await widget.batch(
                                      () async =>
                                          await widget.onRejectMarker!(offer),
                                    );
                                  },
                            deleteButtonTooltipMessage:
                                'Not ${offer.marker.title}',
                          ),
                      ],
                    ),
                  if (widget.tags.isNotEmpty)
                    Row(
                      key: const ValueKey('enrich-tags'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tags'),
                        const SizedBox(width: kSpace8),
                        Expanded(
                          child: Wrap(
                            spacing: kSpace8,
                            runSpacing: kSpace4,
                            children: [
                              for (final tag in widget.tags)
                                InputChip(
                                  key: ValueKey('enrich-tag-$tag'),
                                  avatar: Icon(
                                    widget.appliedTags.contains(tag)
                                        ? Icons.check
                                        : Icons.tag,
                                    size: 16,
                                  ),
                                  label: Text(tag),
                                  tooltip: widget.appliedTags.contains(tag)
                                      ? 'Tag added to this day'
                                      : 'Suggested tag: tap to add or remove',
                                  onPressed:
                                      widget.onRejectTag == null &&
                                          widget.onAcceptTag == null
                                      ? null
                                      : () async => await _confirmRemoveTag(
                                          context,
                                          tag,
                                        ),
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  onDeleted: widget.onRejectTag == null
                                      ? null
                                      : () async {
                                          await widget.batch(
                                            () async =>
                                                await widget.onRejectTag!(tag),
                                          );
                                        },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _confirmRemoveTag(BuildContext context, String tag) async {
    final add = !widget.appliedTags.contains(tag) && widget.onAcceptTag != null;
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
            if (widget.onRejectTag != null)
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
    if (choice == true) {
      await widget.batch(() async => await widget.onAcceptTag!(tag));
    }
    if (choice == false) {
      await widget.batch(() async => await widget.onRejectTag!(tag));
    }
  }

  Future<void> _choose(BuildContext context, EnrichDecision decision) async {
    final mention = decision.mention;
    final lines = widget.source.split('\n');
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
                                ? widget.pages.where(
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
                                  ? enrichTargetLabel(
                                      page.title.replaceFirst(
                                        RegExp(
                                          '\\s+${RegExp.escape(page.id)}\$',
                                        ),
                                        '',
                                      ),
                                      page.properties['color'],
                                    )
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
                            !widget.pages.any(
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
                            onTap: () async {
                              Navigator.pop(context);
                              await widget.batch(() async {
                                await widget.onIgnore(mention);
                              });
                            },
                          ),
                        if (!searching && !decision.choose)
                          ListTile(
                            title: const Text('New page'),
                            onTap: () async {
                              Navigator.pop(context);
                              await widget.batch(() async {
                                await widget.onCreate(mention);
                              });
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
    if (chosen != null) {
      await widget.batch(() async {
        await widget.onAccept(mention, chosen);
      });
    }
  }

  Widget? _candidateDetails(NoteRef page, EnrichDecision decision) {
    final day = decision.candidates
        .where((candidate) => candidate.note.id == page.id)
        .firstOrNull
        ?.lastSeenDay;
    final details = [...page.partOf, if (day != null) 'Last seen $day'];
    return details.isEmpty ? null : Text(details.join(' · '));
  }
}

/// The target without the name the surface already says: "ESP32 DevKit
/// TL-0102" for "ESP32 DevKit" is just "TL-0102".
String enrichShortTarget(String surface, NoteRef target) {
  final title = target.title;
  final item = target.properties['item'];
  final shortTitle = title.replaceFirst(
    RegExp('\\s+${RegExp.escape(target.id)}\$'),
    '',
  );
  if (target.kind == 'equipment' &&
      item is String &&
      surface.toLowerCase().contains(item.toLowerCase()) &&
      shortTitle.toLowerCase().startsWith(item.toLowerCase())) {
    final suffix = shortTitle.substring(item.length).trim();
    final unit = RegExp(
      r'^(?:unit\s+(\d+)|\[(\d+)\])$',
      caseSensitive: false,
    ).firstMatch(suffix);
    if (unit != null) return 'unit ${unit[1] ?? unit[2]}';
  }
  if (title.endsWith(' ${target.id}')) {
    final head = title.substring(0, title.length - target.id.length).trim();
    if (head.toLowerCase() == surface.toLowerCase() ||
        surface.toLowerCase().contains(head.toLowerCase()) ||
        head.toLowerCase().contains(surface.toLowerCase())) {
      return target.id;
    }
  }
  return target.kind == 'equipment' ? shortTitle : title;
}
