/// Day-log enrichment: turns the mentions `tool/enrich_worker.py` extracts
/// into links, and learns from the user's accept/reject decisions.
///
/// The model only says "this line mentions *Катя*". Which note that means is
/// decided here, from evidence in the vault (which entities appear together,
/// in which projects) and the feedback ledger, so it is deterministic,
/// testable, and improves without retraining anything.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'models.dart';
import 'scanner.dart';
import 'values.dart';

const autoEntitiesMarker = '// tylog:auto-entities';
const enrichMentionsDir = '_system/enrich/mentions';
const enrichFeedbackDir = '_system/enrich/feedback';

/// Ledger `entity` for a decision about an auto-added tag.
String enrichTagEntity(String tag) => 'tag:$tag';

/// Mention types worth a new page when nothing in the vault matches.
const _pageTypes = {'person', 'place', 'organization', 'project', 'event'};

/// Kinds a mention may resolve to.
bool isEnrichTarget(NoteRef note) =>
    entityNoteKinds.contains(note.kind) || note.kind == 'project';

/// `_system/enrich/mentions/<note path without .typ>.json`.
String enrichMentionsPath(String notePath) =>
    '$enrichMentionsDir/${notePath.replaceFirst(RegExp(r'\.typ$'), '')}.json';

/// Must equal `content_sha` in tool/enrich_worker.py: the note without our
/// block, trailing blanks ignored (writing the block normalizes them, and
/// that must not look like a user edit).
String enrichContentSha(String source) {
  final index = source.indexOf(autoEntitiesMarker);
  final body = index < 0 ? source : source.substring(0, index);
  return sha256
      .convert(
        utf8.encode('${body.replaceFirst(RegExp(r'[ \t\r\n]+$'), '')}\n'),
      )
      .toString();
}

/// Lowercase, no accents, letters and digits only: "Kátia Z." -> "katiaz".
String enrichKey(String s) => unorm
    .nfd(s)
    .replaceAll(RegExp(r'\p{M}', unicode: true), '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

class EnrichMention {
  const EnrichMention({
    required this.surface,
    required this.type,
    required this.line,
    this.hints = const [],
    this.entity,
  });

  final String surface;
  final String type;
  final int line;
  final List<String> hints;

  /// The model's guess at a known entity id. Unverified: it has been seen
  /// pointing at the wrong person.
  final String? entity;

  factory EnrichMention.fromJson(Map<String, Object?> json) => EnrichMention(
    surface: json['surface'] as String,
    type: json['type'] as String? ?? 'topic',
    line: json['line'] as int,
    hints: stringList(json['hints']),
    entity: json['entity'] as String?,
  );
}

class EnrichMentions {
  const EnrichMentions({
    required this.note,
    required this.contentSha,
    this.mentions = const [],
    this.keywords = const [],
    this.markers = const [],
  });

  final String note;
  final String contentSha;
  final List<EnrichMention> mentions;
  final List<String> keywords;

  /// Lines the model would file under a marker page (e.g. fixit), as
  /// (line, marker note id).
  final List<(int, String)> markers;

  /// Null when [json] is not a schema-1 mentions file.
  static EnrichMentions? tryParse(Object? json) {
    if (json is! Map || json['schema'] != 1) return null;
    try {
      return EnrichMentions(
        note: json['note'] as String,
        contentSha: json['content_sha'] as String,
        mentions: [
          for (final item in json['mentions'] as List? ?? const [])
            if (item is Map) EnrichMention.fromJson(item.cast()),
        ],
        keywords: stringList(json['keywords']),
        markers: [
          for (final item in json['markers'] as List? ?? const [])
            if (item case {'line': final int line, 'marker': final String id})
              (line, id),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// One user decision, as a line of `_system/enrich/feedback/<device>.jsonl`.
/// The ledger is append-only and per device, so sync never has to merge it.
class EnrichFeedback {
  const EnrichFeedback({
    required this.surface,
    required this.entity,
    required this.accepted,
    required this.note,
    required this.at,
    this.context = const [],
  });

  final String surface;
  final String entity;
  final bool accepted;
  final String note;
  final String at;

  /// The features ([enrichFeatures]) the note had when the user decided.
  final List<String> context;

  Map<String, Object?> toJson() => {
    'at': at,
    'decision': accepted ? 'accept' : 'reject',
    'surface': surface,
    'entity': entity,
    'note': note,
    'context': context,
  };

  /// Skips malformed lines: one bad line must not discard the ledger.
  static List<EnrichFeedback> parseLedger(String text) => [
    for (final line in const LineSplitter().convert(text)) ?_tryLine(line),
  ];

  static EnrichFeedback? _tryLine(String line) {
    try {
      final json = jsonDecode(line) as Map;
      return EnrichFeedback(
        surface: json['surface'] as String,
        entity: json['entity'] as String,
        accepted: json['decision'] == 'accept',
        note: json['note'] as String? ?? '',
        at: json['at'] as String? ?? '',
        context: stringList(json['context']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// What a note says about its surroundings: the entities it links, its
/// project and its tags. These are the "with project X, at place Y"
/// evidence that tells two Andrés apart.
Set<String> enrichFeatures(NoteRef note, Map<String, String> entityIdByTarget) {
  return {
    for (final target in note.outgoingLinks)
      if (entityIdByTarget[target] case final id?) 'e:$id',
    if (note.project case final project? when project.isNotEmpty)
      if (entityIdByTarget[project] case final id?) 'e:$id' else 'p:$project',
    for (final tag in note.tags)
      if (tag != 'journal' && tag != note.kind) 't:$tag',
  };
}

enum EnrichStatus { linked, review, propose }

class EnrichCandidate {
  const EnrichCandidate(this.note, this.score, {required this.strong});
  final NoteRef note;
  final double score;

  /// Name matches exactly or the user accepted this surface before: safe to
  /// link without asking when it also clearly wins.
  final bool strong;
}

class EnrichDecision {
  const EnrichDecision(this.mention, this.status, this.candidates);
  final EnrichMention mention;
  final EnrichStatus status;
  final List<EnrichCandidate> candidates;
  NoteRef? get target => candidates.firstOrNull?.note;
}

/// Everything learned so far. Rebuilt from the vault and the ledgers on
/// demand; never stored, so it can never disagree with them.
class EnrichMemory {
  EnrichMemory._(this.entities, this._idByTarget, this.tags);

  /// Every linkable entity note, by id.
  final Map<String, NoteRef> entities;
  final Map<String, String> _idByTarget;

  /// folded surface -> entity id -> accepts.
  final _accepted = <String, Map<String, int>>{};
  final _rejected = <String>{};

  /// entity id -> feature -> notes having both; and notes per entity.
  final _context = <String, Map<String, int>>{};
  final _seen = <String, int>{};

  /// Every tag in the vault, for [enrichTags] (collected once, not per day).
  final Set<String> tags;

  factory EnrichMemory.build(
    VaultIndex index, [
    Iterable<EnrichFeedback> feedback = const [],
  ]) {
    final entities = {
      for (final note in index.notesByPath.values)
        if (isEnrichTarget(note)) note.id: note,
    };
    // Link targets may be written as id, alias, title or file stem.
    final resolver = LinkResolver(index.notesByPath.values);
    final idByTarget = <String, String>{};
    for (final note in index.notesByPath.values) {
      for (final target in [...note.outgoingLinks, ?note.project]) {
        if (idByTarget.containsKey(target)) continue;
        final path = resolver.resolve(target).path;
        final resolved = path == null ? null : index.notesByPath[path];
        if (resolved != null && entities.containsKey(resolved.id)) {
          idByTarget[target] = resolved.id;
        }
      }
    }
    final memory = EnrichMemory._(entities, idByTarget, {
      for (final note in index.notesByPath.values) ...note.tags,
    });
    for (final note in index.notesByPath.values) {
      final features = enrichFeatures(note, idByTarget);
      for (final feature in features) {
        if (feature.startsWith('e:')) {
          memory._observe(feature.substring(2), features);
        }
      }
    }
    // ponytail: an accepted mention also becomes an inline link, so once the
    // index catches up its context counts twice; harmless while counts only
    // rank candidates, revisit if scores get calibrated into probabilities.
    for (final event in feedback) {
      final key = '${enrichKey(event.surface)}\n${event.entity}';
      if (event.accepted) {
        final counts = memory._accepted.putIfAbsent(
          enrichKey(event.surface),
          () => {},
        );
        counts[event.entity] = (counts[event.entity] ?? 0) + 1;
        memory._rejected.remove(key);
        memory._observe(event.entity, event.context.toSet());
      } else {
        memory._rejected.add(key);
      }
    }
    return memory;
  }

  void _observe(String entity, Set<String> features) {
    _seen[entity] = (_seen[entity] ?? 0) + 1;
    final counts = _context.putIfAbsent(entity, () => {});
    for (final feature in features) {
      if (feature != 'e:$entity') counts[feature] = (counts[feature] ?? 0) + 1;
    }
  }

  Map<String, String> get entityIdByTarget => _idByTarget;

  bool isRejected(String surface, String entity) =>
      _rejected.contains('${enrichKey(surface)}\n$entity');

  int acceptedCount(String surface, String entity) =>
      _accepted[enrichKey(surface)]?[entity] ?? 0;

  /// log P(surface -> entity) from accepts, plus, per context feature,
  /// log P(feature | entity) from co-occurrence. Laplace-smoothed, so an
  /// entity with no history scores neutrally rather than impossibly.
  // ponytail: naive Bayes on co-occurrence; add embedding similarity of the
  // surrounding text (lib/retrieval chunks) when precision plateaus.
  double score(String surface, String entity, Set<String> context) {
    final accepted = _accepted[enrichKey(surface)] ?? const {};
    final total = accepted.values.fold(0, (a, b) => a + b);
    var score = math.log(((accepted[entity] ?? 0) + 1) / (total + 2));
    final seen = _seen[entity] ?? 0;
    final counts = _context[entity] ?? const {};
    for (final feature in context) {
      score += math.log(((counts[feature] ?? 0) + 0.5) / (seen + 1));
    }
    return score;
  }
}

/// A clear winner must be at least this many times likelier than the next.
final _margin = math.log(4);

/// Decides every mention in [mentions] for [note].
///
/// Two passes: names that match exactly one entity are settled first and
/// become context for the rest, so "Катя" in a note that also names her
/// project leans toward the Катя of that project.
List<EnrichDecision> resolveMentions(
  EnrichMentions mentions,
  NoteRef note,
  EnrichMemory memory,
) {
  final context = enrichFeatures(note, memory.entityIdByTarget);
  final candidates = [
    for (final mention in mentions.mentions) _candidates(mention, memory),
  ];
  for (final (i, mention) in mentions.mentions.indexed) {
    final exact = candidates[i].where((c) => c.$2).toList();
    if (exact.length == 1 &&
        !memory.isRejected(mention.surface, exact.single.$1.id)) {
      context.add('e:${exact.single.$1.id}');
    }
  }
  // One proposal per new name: "Рома" and "Ромой" (hinted "Роман") are one
  // person, not two pages to create.
  final proposed = <String>{};
  return [
    for (final (i, mention) in mentions.mentions.indexed)
      if (_decide(mention, candidates[i], context, memory) case final decision
          when decision.status != EnrichStatus.propose ||
              (_pageTypes.contains(mention.type) &&
                  _keys(mention).every(proposed.add)))
        decision,
  ];
}

Set<String> _keys(EnrichMention mention) => {
  for (final form in [mention.surface, ...mention.hints])
    if (enrichKey(form) case final key when key.length >= 2) key,
};

/// Entity notes a mention could mean, with whether the name matches exactly.
List<(NoteRef, bool)> _candidates(EnrichMention mention, EnrichMemory memory) {
  final keys = _keys(mention);
  final found = <String, (NoteRef, bool)>{};
  for (final entity in memory.entities.values) {
    final names = {
      for (final name in [entity.title, entity.id, ...entity.aliases])
        enrichKey(name),
    }..remove('');
    // Exact only on the user's own words: hints are the model's guesses
    // ("Катя" came back hinted with the surname of a known Катя), so they
    // may find a candidate but never prove one.
    final exact = names.contains(enrichKey(mention.surface));
    // "Катя" for "Катя Жаворонкова", "Katia" for "katiazhavoronkova".
    final prefix =
        names.any(keys.contains) ||
        names.any(
          (name) => keys.any((key) => key.length >= 4 && name.startsWith(key)),
        );
    if (prefix || memory.acceptedCount(mention.surface, entity.id) > 0) {
      found[entity.id] = (entity, exact);
    }
  }
  // The model's own guess counts only when no name matched at all.
  if (found.isEmpty) {
    if (memory.entities[mention.entity] case final entity?) {
      found[entity.id] = (entity, false);
    }
  }
  return found.values.toList();
}

EnrichDecision _decide(
  EnrichMention mention,
  List<(NoteRef, bool)> found,
  Set<String> context,
  EnrichMemory memory,
) {
  final ranked = [
    for (final (entity, exact) in found)
      if (!memory.isRejected(mention.surface, entity.id))
        EnrichCandidate(
          entity,
          memory.score(
            mention.surface,
            entity.id,
            context.difference({'e:${entity.id}'}),
          ),
          strong: exact || memory.acceptedCount(mention.surface, entity.id) > 0,
        ),
  ]..sort((a, b) => b.score.compareTo(a.score));
  if (ranked.isEmpty) {
    return EnrichDecision(mention, EnrichStatus.propose, const []);
  }
  final best = ranked.first;
  final clear = ranked.length == 1 || best.score - ranked[1].score >= _margin;
  return EnrichDecision(
    mention,
    best.strong && clear ? EnrichStatus.linked : EnrichStatus.review,
    ranked,
  );
}

/// Keywords that are already tags in the vault (after synonym folding),
/// minus tags the user removed from a block ([enrichTagEntity] rejects).
/// New words stay suggestions: auto-adding them would flood the tag list.
List<String> enrichTags(
  List<String> keywords,
  VaultIndex index, {
  Map<String, String> synonyms = const {},
  EnrichMemory? memory,
}) {
  final known =
      memory?.tags ??
      {for (final note in index.notesByPath.values) ...note.tags};
  return {
    for (final keyword in keywords)
      if (normalizeTag(keyword, synonyms) case final tag
          when tag != 'journal' &&
              known.contains(tag) &&
              memory?.isRejected(tag, enrichTagEntity(tag)) != true)
        tag,
  }.toList();
}

/// Removes our block (marker, heading, link and tag items) and keeps
/// anything the user typed after it.
String stripAutoEntities(String source) {
  final marker = RegExp(
    '(?:^|\\n)${RegExp.escape(autoEntitiesMarker)}(?:\\r?\\n|\$)',
  ).firstMatch(source);
  if (marker == null) return source;
  final before = source
      .substring(0, marker.start)
      .replaceFirst(RegExp(r'[\r\n]+$'), '');
  final lines = source.substring(marker.end).split('\n');
  final ours = RegExp(r'^\s*(?:[-+*]\s*)?#tylog\.(?:ref-note|tag)\(');
  var i = 0;
  if (i < lines.length && RegExp(r'^\s*=+\s').hasMatch(lines[i])) i++;
  while (i < lines.length &&
      (lines[i].trim().isEmpty || ours.hasMatch(lines[i]))) {
    i++;
  }
  final tail = lines
      .sublist(i)
      .join('\n')
      .replaceFirst(RegExp(r'^[\r\n]+'), '')
      .trimRight();
  return tail.isEmpty ? '$before\n' : '$before\n\n$tail\n';
}

/// Rewrites the block from [decisions]: linked mentions the note does not
/// already link inline, and [tags]. No block when there is nothing to say.
///
/// "Already" is judged on the text without the block. The indexed [note]
/// includes the block's own links and tags, and trusting it would drop them
/// on the next pass and add them back on the one after, forever.
String writeAutoEntities(
  String source,
  NoteRef note,
  List<EnrichDecision> decisions,
  List<String> tags,
) {
  final stripped = stripAutoEntities(source);
  final own = scanNote(note.path, stripped);
  final inline = {...own.outgoingLinks};
  final seen = <String>{};
  final items = [
    for (final decision in decisions)
      if (decision.status == EnrichStatus.linked)
        if (decision.target case final target?)
          if (!inline.contains(target.id) &&
              !inline.contains(target.title) &&
              seen.add(target.id))
            '- #tylog.ref-note(${typstString(target.id)})'
                '[${escapeMarkup(decision.mention.surface)}]',
  ];
  final newTags = tags.where((tag) => !own.tags.contains(tag)).toList();
  if (items.isEmpty && newTags.isEmpty) return stripped;
  return [
    stripped.trimRight(),
    '',
    autoEntitiesMarker,
    '== Mentions',
    ...items,
    if (newTags.isNotEmpty)
      newTags.map((tag) => '#tylog.tag(${typstString(tag)})').join(' '),
    '',
  ].join('\n');
}

/// Turns the first plain occurrence of [mention] on its line into a link.
/// Returns [source] unchanged when the line no longer holds the surface
/// outside markup: the user's text wins over our line numbers.
String linkMentionInline(String source, EnrichMention mention, NoteRef target) {
  final lines = source.split('\n');
  final i = mention.line - 1;
  if (i < 0 || i >= lines.length) return source;
  final line = lines[i];
  final at = line.indexOf(mention.surface);
  if (at < 0) return source;
  // Already inside a call or its content? Leave it.
  final before = line.substring(0, at);
  if (before.contains('#tylog.') &&
      before.lastIndexOf('#tylog.') > before.lastIndexOf(']')) {
    return source;
  }
  lines[i] =
      '$before#tylog.ref-note(${typstString(target.id)})'
      '[${mention.surface}]${line.substring(at + mention.surface.length)}';
  return lines.join('\n');
}

/// Ledger `entity` for filing a line under a marker page.
String enrichMarkerEntity(String markerId) => 'marker:$markerId';

/// A line as the user reads it: no list marker, time or markup. Also what the
/// ledger stores, so the worker can show rejected lines as counter-examples.
String enrichPlainLine(String line) => line
    .replaceAllMapped(
      RegExp(r'#tylog\.[\w-]+\([^)]*\)(\[([^\]]*)\])?'),
      (m) => m.group(2) ?? '',
    )
    .replaceFirst(RegExp(r'^\s*(?:\\-|[-+*]|\d+\.)\s+'), '')
    .replaceFirst(RegExp(r'^\d{1,2}:\d{2}\s+'), '')
    .trim();

class EnrichMarkerOffer {
  const EnrichMarkerOffer(this.marker, this.line, this.text);
  final NoteRef marker;
  final int line;
  final String text;
}

/// Marker suggestions still worth asking about: the line still exists, does
/// not carry the marker yet, and was not rejected before.
List<EnrichMarkerOffer> enrichMarkerOffers(
  EnrichMentions mentions,
  String source,
  VaultIndex index,
  EnrichMemory memory,
) {
  final lines = source.split('\n');
  final byId = {for (final note in index.notesByPath.values) note.id: note};
  return [
    for (final (line, id) in mentions.markers)
      if (byId[id] case final marker?)
        if (line >= 1 && line <= lines.length)
          if (!_carries(lines[line - 1], marker))
            if (enrichPlainLine(lines[line - 1]) case final text
                when text.isNotEmpty &&
                    !memory.isRejected(text, enrichMarkerEntity(id)))
              EnrichMarkerOffer(marker, line, text),
  ];
}

bool _carries(String line, NoteRef marker) =>
    line.contains('ref-note(${typstString(marker.id)})') ||
    line.contains('ref-note(${typstString(marker.title)})');

/// Files [line] under [marker] the way the user does by hand: the link goes
/// after the list marker and time ("- 21:50 #tylog.ref-note(...)[fixit] ...").
String markLine(String source, int line, NoteRef marker) {
  final lines = source.split('\n');
  if (line < 1 || line > lines.length || _carries(lines[line - 1], marker)) {
    return source;
  }
  final text = lines[line - 1];
  final prefix = RegExp(
    r'^\s*(?:(?:\\-|[-+*]|\d+\.)\s+)?(?:\d{1,2}:\d{2}\s+)?',
  ).firstMatch(text)!.end;
  lines[line - 1] =
      '${text.substring(0, prefix)}#tylog.ref-note(${typstString(marker.id)})'
      '[${escapeMarkup(marker.title)}] ${text.substring(prefix)}';
  return lines.join('\n');
}

/// Whether [mention]'s name is already a link on its line: settled, whatever
/// a (possibly stale) index says. A page created a moment ago is not in the
/// memory yet, and its "+ name" chip came back and got tapped twice.
bool enrichLinkedOnLine(EnrichMention mention, List<String> lines) =>
    mention.line >= 1 &&
    mention.line <= lines.length &&
    RegExp(
      r'#tylog\.ref-note\([^)]*\)\[' + RegExp.escape(mention.surface) + r'\]',
    ).hasMatch(lines[mention.line - 1]);
