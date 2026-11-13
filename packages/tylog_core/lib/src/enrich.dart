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

import 'enrich_alias.dart';
import 'loan.dart';
import 'models.dart';
import 'scanner.dart';
import 'storage.dart';
import 'values.dart';

const autoEntitiesMarker = '// tylog:auto-entities';

/// Appends a user line above the generated entities block, never inside it.
String appendAboveAutoBlock(String source, String line) {
  final auto = source.indexOf(autoEntitiesMarker);
  if (auto < 0) return '${source.trimRight()}\n$line\n';
  return '${source.substring(0, auto).trimRight()}\n$line\n\n'
      '${source.substring(auto)}';
}

const enrichMentionsDir = '_system/enrich/mentions';
const enrichFeedbackDir = '_system/enrich/feedback';
const enrichShownDir = '_system/enrich/shown';
const enrichSkippedDir = '_system/enrich/skipped';
const enrichIgnoreEntity = 'mention:ignore';

/// Ledger `entity` for a decision about an auto-added tag.
String enrichTagEntity(String tag) => 'tag:$tag';

/// Mention types worth a new page when nothing in the vault matches.
const _pageTypes = {'person', 'place', 'organization', 'project', 'event'};

/// Kinds a mention may resolve to.
/// Plain `note` pages count: people imported from Logseq or created by hand
/// are often kind `note`, and proposing a new page for them is the noise.
bool isEnrichTarget(NoteRef note) =>
    note.kind == 'note' ||
    note.kind == 'equipment' ||
    entityNoteKinds.contains(note.kind);

/// Groups pages that share a normalized title or alias.
List<List<NoteRef>> findDuplicates(VaultIndex index) {
  final byKey = <String, List<NoteRef>>{};
  for (final note in index.notes.where(isEnrichTarget)) {
    final keys = {
      for (final name in [note.title, ...note.aliases]) enrichKey(name),
    };
    for (final key in keys.where((key) => key.isNotEmpty)) {
      (byKey[key] ??= []).add(note);
    }
  }
  final seen = <String>{};
  return [
    for (final group in byKey.values)
      if (group.length > 1 &&
          seen.add(group.map((note) => note.path).join('\x00')))
        group,
  ];
}

/// `_system/enrich/mentions/<note path without .typ>.json`.
String enrichMentionsPath(String notePath) =>
    '$enrichMentionsDir/${notePath.replaceFirst(RegExp(r'\.typ$'), '')}.json';

/// Must equal `content_sha` in tool/enrich_worker.py, including legacy blocks.
String enrichContentSha(String source) {
  return sha256
      .convert(
        utf8.encode('${source.replaceFirst(RegExp(r'[ \t\r\n]+$'), '')}\n'),
      )
      .toString();
}

/// Lowercase, no accents, letters and digits only: "Kátia Z." -> "katiaz".
String enrichKey(String s) => unorm
    .nfd(s)
    .replaceAll(RegExp(r'\p{M}', unicode: true), '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// Normalizes equipment names while ignoring unit-number markers.
String enrichEquipmentKey(String s) {
  var value = unorm
      .nfd(s)
      .replaceAll(RegExp(r'\p{M}', unicode: true), '')
      .toLowerCase();
  const ordinals = {
    '1': r'first|primeir[oa]s?|перв(?:ыи|ого|ому|ым|ом|ая|ои|ую|ое|ые|ых|ыми)',
    '2': r'second|segund[oa]s?|втор(?:ои|ого|ому|ым|ом|ая|ую|ое|ые|ых|ыми)',
    '3':
        r'third|terceir[oa]s?|трет(?:ии|ьего|ьему|ьим|ьем|ья|ью|ье|ьи|ьих|ьими)',
    '4':
        r'fourth|quart[oa]s?|четверт(?:ыи|ого|ому|ым|ом|ая|ои|ую|ое|ые|ых|ыми)',
    '5': r'fifth|quint[oa]s?|пят(?:ыи|ого|ому|ым|ом|ая|ои|ую|ое|ые|ых|ыми)',
  };
  for (final entry in ordinals.entries) {
    value = value.replaceAll(
      RegExp(
        '(?<![\\p{L}\\p{N}])(?:${entry.value})(?![\\p{L}\\p{N}])',
        unicode: true,
      ),
      entry.key,
    );
  }
  return value
      .replaceAll(
        RegExp(
          r'(?<![\p{L}\p{N}])(?:unit|number|номер|num|no|nr|n\.?[°º]?|№|#)\.?(?=$|[^\p{L}\p{N}]|\p{N})',
          unicode: true,
        ),
        '',
      )
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
}

class EnrichMention {
  const EnrichMention({
    required this.surface,
    required this.type,
    required this.line,
    this.hints = const [],
    this.entity,
    this.candidateIds,
  });

  /// Set by the alias scan ([EnrichAliasIndex]): the equipment ids the text
  /// names. One id is a unique alias, several ask the user to choose.
  final List<String>? candidateIds;

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

class EnrichLoanHint {
  const EnrichLoanHint({
    required this.line,
    this.borrower,
    this.purpose,
    this.topic,
  });

  final int line;
  final String? borrower;
  final String? purpose;
  final String? topic;
}

class EnrichMentions {
  const EnrichMentions({
    required this.note,
    required this.contentSha,
    this.model,
    this.mentions = const [],
    this.keywords = const [],
    this.markers = const [],
    this.loans = const [],
  });

  final String note;
  final String contentSha;
  final String? model;
  final List<EnrichMention> mentions;
  final List<String> keywords;

  /// Lines the model would file under a marker page (e.g. fixit), as
  /// (line, marker note id).
  final List<(int, String)> markers;
  final List<EnrichLoanHint> loans;

  /// Null when [json] is not a schema-1 mentions file.
  static EnrichMentions? tryParse(Object? json) {
    if (json is! Map || json['schema'] != 1) return null;
    try {
      return EnrichMentions(
        note: json['note'] as String,
        contentSha: json['content_sha'] as String,
        model: json['model'] as String?,
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
        loans: [
          for (final item
              in json['loans'] is List ? json['loans'] as List : const [])
            if (item is Map &&
                item['line'] is int &&
                (item['borrower'] == null || item['borrower'] is String) &&
                (item['purpose'] == null || item['purpose'] is String) &&
                (item['topic'] == null || item['topic'] is String))
              EnrichLoanHint(
                line: item['line'] as int,
                borrower: item['borrower'] as String?,
                purpose: item['purpose'] as String?,
                topic: item['topic'] as String?,
              ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// One display or user decision in the per-device shown or feedback ledger.
/// The ledger is append-only and per device, so sync never has to merge it.
class EnrichFeedback {
  const EnrichFeedback({
    required this.surface,
    required this.entity,
    required this.accepted,
    required this.note,
    required this.at,
    this.context = const [],
    this.shown = false,
    this.proposedBy,
    this.confidence,
  });

  final String surface;
  final String entity;
  final bool accepted;
  final bool shown;
  final String note;
  final String at;

  /// The features ([enrichFeatures]) the note had when the user decided.
  final List<String> context;
  final String? proposedBy;
  final double? confidence;

  Map<String, Object?> toJson() => {
    'at': at,
    'decision': shown ? 'shown' : (accepted ? 'accept' : 'reject'),
    'surface': surface,
    'entity': entity,
    'note': note,
    'context': context,
    if (proposedBy != null) 'proposed_by': proposedBy,
    if (confidence != null) 'confidence': confidence,
  };

  /// Skips malformed lines: one bad line must not discard the ledger.
  static List<EnrichFeedback> parseLedger(String text) => [
    for (final line in const LineSplitter().convert(text)) ?_tryLine(line),
  ];

  static EnrichFeedback? _tryLine(String line) {
    try {
      final json = jsonDecode(line) as Map;
      if (!['accept', 'reject', 'shown'].contains(json['decision'])) {
        return null;
      }
      return EnrichFeedback(
        surface: json['surface'] as String,
        entity: json['entity'] as String,
        accepted: json['decision'] == 'accept',
        shown: json['decision'] == 'shown',
        note: json['note'] as String? ?? '',
        at: json['at'] as String? ?? '',
        context: stringList(json['context']),
        proposedBy: json['proposed_by'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Reads device ledgers with the app's best-effort handling of unavailable files.
Future<List<EnrichFeedback>> loadEnrichFeedback(VaultStorage storage) =>
    _loadEnrichLedger(storage, enrichFeedbackDir, shown: false);

/// Reads displays separately so older apps only see decisions in feedback.
Future<List<EnrichFeedback>> loadEnrichShown(VaultStorage storage) =>
    _loadEnrichLedger(storage, enrichShownDir, shown: true);

Future<List<EnrichFeedback>> _loadEnrichLedger(
  VaultStorage storage,
  String directory, {
  required bool shown,
}) async {
  final events = <EnrichFeedback>[];
  try {
    for (final file in await storage.list(path: directory)) {
      if (file.isDirectory || !file.path.endsWith('.jsonl')) continue;
      events.addAll(
        EnrichFeedback.parseLedger(
          await storage.readText(file.path),
        ).where((event) => event.shown == shown),
      );
    }
  } catch (_) {}
  return events;
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
  const EnrichCandidate(
    this.note,
    this.score, {
    required this.strong,
    this.lastSeenDay,
  });
  final NoteRef note;
  final double score;
  final String? lastSeenDay;

  /// Name matches exactly or the user accepted this surface before: safe to
  /// link without asking when it also clearly wins.
  final bool strong;
}

class EnrichDecision {
  const EnrichDecision(
    this.mention,
    this.status,
    this.candidates, {
    this.choose = false,
  });
  final EnrichMention mention;

  /// A name several equipment units share and nothing longer disambiguates:
  /// shown as "Which ...?" with only [candidates] to pick from.
  final bool choose;
  final EnrichStatus status;
  final List<EnrichCandidate> candidates;
  NoteRef? get target => candidates.firstOrNull?.note;
}

typedef EnrichDayResolution = ({
  List<EnrichDecision> decisions,
  List<String> tags,
  List<EnrichMarkerOffer> markers,
  List<EnrichLoanOffer> loans,
});

/// Everything learned so far. Rebuilt from the vault and the ledgers on
/// demand; never stored, so it can never disagree with them.
class EnrichMemory {
  EnrichMemory._(this.entities, this._idByTarget, this.tags, this.markerNotes);

  /// Every linkable entity note, by id.
  final Map<String, NoteRef> entities;
  final Map<String, String> _idByTarget;

  /// folded surface -> entity id -> accepts.
  final _accepted = <String, Map<String, int>>{};
  final _rejected = <String>{};

  /// entity id -> feature -> notes having both; and notes per entity.
  final _context = <String, Map<String, int>>{};
  final _seen = <String, int>{};
  final _lastSeenDay = <String, String>{};

  /// Every tag in the vault, for [enrichTags] (collected once, not per day).
  final Set<String> tags;

  /// Marker lookup is shared by every day resolved against this index.
  final Map<String, NoteRef> markerNotes;

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
    final memory = EnrichMemory._(
      entities,
      idByTarget,
      {for (final note in index.notesByPath.values) ...note.tags},
      {for (final note in index.notesByPath.values) note.id: note},
    );
    for (final note in index.notesByPath.values) {
      final features = enrichFeatures(note, idByTarget);
      for (final feature in features) {
        if (feature.startsWith('e:')) {
          final id = feature.substring(2);
          memory._observe(id, features);
          final day = RegExp(
            r'\d{4}-\d{2}-\d{2}',
          ).firstMatch(note.kind == 'daily' ? note.path : '')?.group(0);
          if (day != null && day.compareTo(memory._lastSeenDay[id] ?? '') > 0) {
            memory._lastSeenDay[id] = day;
          }
        }
      }
    }
    // ponytail: an accepted mention also becomes an inline link, so once the
    // index catches up its context counts twice; harmless while counts only
    // rank candidates, revisit if scores get calibrated into probabilities.
    for (final event in feedback) {
      memory.addFeedback(event);
    }
    return memory;
  }

  /// Applies one newly persisted decision without rebuilding vault-wide priors.
  void addFeedback(EnrichFeedback event) {
    if (event.shown) return;
    final surface = enrichKey(event.surface);
    final key = '$surface\n${event.entity}';
    if (event.accepted) {
      final counts = _accepted.putIfAbsent(surface, () => {});
      counts[event.entity] = (counts[event.entity] ?? 0) + 1;
      _rejected.remove(key);
      _observe(event.entity, event.context.toSet());
    } else {
      _rejected.add(key);
    }
  }

  void _observe(String entity, Set<String> features) {
    _seen[entity] = (_seen[entity] ?? 0) + 1;
    final counts = _context.putIfAbsent(entity, () => {});
    for (final feature in features) {
      if (feature != 'e:$entity') counts[feature] = (counts[feature] ?? 0) + 1;
    }
  }

  Map<String, String> get entityIdByTarget => _idByTarget;

  /// Equipment titles and aliases for the deterministic body scan.
  late final EnrichAliasIndex aliasIndex = EnrichAliasIndex.build(
    entities.values,
  );

  /// entity id -> (folded names, folded single words). Folding (NFD) is the
  /// expensive part, so it runs once per memory, not per mention.
  late final Map<String, (Set<String>, Set<String>)> nameKeys = {
    for (final entity in entities.values)
      entity.id: (
        {
          for (final name in [entity.title, entity.id, ...entity.aliases])
            enrichKey(name),
          if (entity.kind == 'equipment')
            for (final name in [entity.title, entity.id, ...entity.aliases])
              enrichEquipmentKey(name),
        }..remove(''),
        {
          for (final name in [entity.title, ...entity.aliases])
            for (final word in name.split(RegExp(r'[\s,]+')))
              if (enrichKey(word) case final key when key.length >= 4) key,
        },
      ),
  };

  // The first three characters cover exact, prefix and stem matches; words
  // also need a direct index because they can occur anywhere in a name.
  late final _nameIndex = _buildNameIndex();

  Map<String, Set<String>> _buildNameIndex() {
    final result = <String, Set<String>>{};
    for (final entry in nameKeys.entries) {
      for (final name in entry.value.$1) {
        for (var length = 2; length <= math.min(3, name.length); length++) {
          (result[name.substring(0, length)] ??= {}).add(entry.key);
        }
      }
      for (final word in entry.value.$2) {
        (result['w$word'] ??= {}).add(entry.key);
      }
    }
    return result;
  }

  late final _entityOrder = {
    for (final (i, id) in entities.keys.indexed) id: i,
  };

  bool isRejected(String surface, String entity) {
    final key = enrichKey(surface);
    if (_rejected.contains('$key\n$entity')) return true;
    if (entities[entity]?.kind != 'person') return false;
    return _rejected.any((pair) {
      final split = pair.indexOf('\n');
      return pair.substring(split + 1) == entity &&
          _sameStem(pair.substring(0, split), key);
    });
  }

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
    if (memory.isRejected(mention.surface, enrichIgnoreEntity)) continue;
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
      if (!memory.isRejected(mention.surface, enrichIgnoreEntity))
        if (_decide(mention, candidates[i], context, memory) case final decision
            when decision.status != EnrichStatus.propose ||
                (mention.candidateIds == null &&
                    _pageTypes.contains(mention.type) &&
                    _keys(mention).every(proposed.add)))
          decision,
  ];
}

Set<String> _keys(EnrichMention mention) => {
  for (final form in [mention.surface, ...mention.hints])
    if (enrichKey(form) case final key when key.length >= 2) key,
  if (mention.type == 'equipment')
    for (final form in [mention.surface, ...mention.hints])
      if (enrichEquipmentKey(form) case final key when key.length >= 2) key,
};

/// Entity notes a mention could mean, with whether the name matches exactly.
List<(NoteRef, bool)> _candidates(EnrichMention mention, EnrichMemory memory) {
  if (mention.candidateIds case final ids?) {
    return [
      for (final id in ids)
        if (memory.entities[id] case final entity?) (entity, ids.length == 1),
    ];
  }
  final keys = {..._keys(mention), for (final k in _keys(mention)) _latin(k)};
  final surfaceKey = enrichKey(mention.surface);
  final ids = <String>{
    for (final key in keys)
      if (key.length >= 2)
        ...?memory._nameIndex[key.substring(0, math.min(3, key.length))],
    for (final key in keys) ...?memory._nameIndex['w$key'],
    ...?memory._accepted[surfaceKey]?.keys,
    for (final entry in memory._accepted.entries)
      if (_sameStem(entry.key, surfaceKey))
        for (final id in entry.value.keys)
          if (memory.entities[id]?.kind == 'person') id,
  };
  final pool = [for (final id in ids) ?memory.entities[id]]
    ..sort(
      (a, b) =>
          memory._entityOrder[a.id]!.compareTo(memory._entityOrder[b.id]!),
    );
  List<(NoteRef, bool)> match(Iterable<NoteRef> pool) => [
    for (final entity in pool)
      if (_match(entity, mention, keys, surfaceKey, memory) case final exact?)
        (entity, exact),
  ];
  // Plain `note` pages compete unless a typed entity matches the name
  // exactly: "IADE" has an organization page and two stray notes and must
  // still link, but "Angela" must still find the boss whose page is a note.
  final typed = match(pool.where((e) => e.kind != 'note'));
  var found = typed.any((c) => c.$2)
      ? typed
      : [...typed, ...match(pool.where((e) => e.kind == 'note'))];
  // The model's own guess counts only when no name matched at all.
  if (found.isEmpty) {
    if (memory.entities[mention.entity] case final entity?
        when entity.kind != 'equipment' || mention.type == 'equipment') {
      found = [(entity, false)];
    }
  }
  return found;
}

/// Null: no match. Otherwise whether the name matches exactly.
bool? _match(
  NoteRef entity,
  EnrichMention mention,
  Set<String> keys,
  String surfaceKey,
  EnrichMemory memory,
) {
  if (entity.kind == 'equipment' && mention.type != 'equipment') return null;
  final (names, words) = memory.nameKeys[entity.id]!;
  if (entity.kind == 'equipment' && mention.type == 'equipment') {
    final equipmentKeys = [
      for (final form in [mention.surface, ...mention.hints])
        enrichEquipmentKey(form),
    ];
    final exact =
        names.contains(equipmentKeys.first) && equipmentKeys.first.isNotEmpty;
    final accepted = (memory._accepted[surfaceKey]?[entity.id] ?? 0) > 0;
    if (equipmentKeys.any(
      (key) => RegExp(r'\p{N}', unicode: true).hasMatch(key),
    )) {
      return equipmentKeys.any(
                (key) => key.isNotEmpty && names.contains(key),
              ) ||
              accepted
          ? exact
          : null;
    }
    final prefix = equipmentKeys.any(
      (key) => key.length >= 4 && names.any((name) => name.startsWith(key)),
    );
    return prefix || exact || accepted ? exact : null;
  }
  // Exact only on the user's own words: hints are the model's guesses
  // ("Катя" came back hinted with the surname of a known Катя), so they
  // may find a candidate but never prove one; single words of a name
  // ("Sabino" in "André Sabino") find, never prove.
  final exact = names.contains(surfaceKey);
  // "Катя" for "Катя Жаворонкова", "Katia" for "katiazhavoronkova".
  // Raw name-prefix matching is for typed entities: a plain note whose
  // title merely starts with the same letters ("Заку" -> "Закупка на 2019")
  // is not that person. Case endings still match via _sameStem.
  final prefixOk = entity.kind != 'note';
  final prefix =
      names.any(keys.contains) ||
      words.any(keys.contains) ||
      names.any(
        (name) => keys.any(
          (key) =>
              (prefixOk && key.length >= 4 && name.startsWith(key)) ||
              _sameStem(name, key),
        ),
      );
  final learned =
      entity.kind == 'person' &&
      memory._accepted.entries.any(
        (entry) =>
            entry.value.containsKey(entity.id) &&
            _sameStem(entry.key, surfaceKey),
      );
  return prefix ||
          learned ||
          (memory._accepted[surfaceKey]?[entity.id] ?? 0) > 0
      ? exact
      : null;
}

/// Russian case forms of one name: "Настей", "Насте" ~ "Настя". Only finds
/// a candidate (review), never proves one.
bool _sameStem(String a, String b) {
  if (a.length < 3 || b.length < 3) return false;
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  final endings = {
    '',
    'й',
    'а',
    'я',
    'у',
    'ю',
    'е',
    'ой',
    'ей',
    'ою',
    'ею',
    'ом',
    'ем',
    'ами',
    'ям',
    'ях',
    'ы',
    'и',
    'ь',
    's',
    'a',
    'o',
    'as',
    'os',
  }.map(enrichKey).toSet();
  return i >= 3 &&
      endings.contains(a.substring(i)) &&
      endings.contains(b.substring(i));
}

/// Finds a surface surrounded by non-letter, non-digit characters.
int enrichSurfaceIndex(String text, String surface, [int start = 0]) {
  if (surface.isEmpty) return -1;
  final pattern = RegExp(
    '(?<![\\p{L}\\p{N}])${RegExp.escape(surface)}(?![\\p{L}\\p{N}])',
    unicode: true,
    caseSensitive: false,
  );
  return pattern.allMatches(text, start).firstOrNull?.start ?? -1;
}

const _cyrLatin = {
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ё': 'e',
  'ж': 'zh',
  'з': 'z',
  'и': 'i',
  'й': 'i',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'kh',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'shch',
  'ъ': '',
  'ы': 'y',
  'ь': '',
  'э': 'e',
  'ю': 'iu',
  'я': 'ia',
};

/// "рита" -> "rita", so a Cyrillic mention finds a Latin-titled page.
String _latin(String key) => key.split('').map((c) => _cyrLatin[c] ?? c).join();

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
          lastSeenDay: memory._lastSeenDay[entity.id],
        ),
  ]..sort((a, b) => b.score.compareTo(a.score));
  if (ranked.isEmpty) {
    return EnrichDecision(mention, EnrichStatus.propose, const []);
  }
  final best = ranked.first;
  final ambiguousEquipment =
      mention.type == 'equipment' &&
      found
              .where(
                (c) =>
                    c.$1.kind == 'equipment' &&
                    c.$2 &&
                    !memory.isRejected(mention.surface, c.$1.id),
              )
              .length >
          1;
  final clear =
      !ambiguousEquipment &&
      (ranked.length == 1 || best.score - ranked[1].score >= _margin);
  final linked = best.strong && clear;
  final llmEquipmentChoice = mention.candidateIds == null && ambiguousEquipment;
  final exactEquipmentIds = llmEquipmentChoice
      ? {
          for (final (entity, exact) in found)
            if (entity.kind == 'equipment' && exact) entity.id,
        }
      : <String>{};
  return EnrichDecision(
    mention,
    linked ? EnrichStatus.linked : EnrichStatus.review,
    llmEquipmentChoice
        ? ranked.where((c) => exactEquipmentIds.contains(c.note.id)).toList()
        : ranked,
    choose:
        !linked &&
        (llmEquipmentChoice || (mention.candidateIds?.length ?? 0) > 1),
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

/// Resolves one day-log's extracted suggestions and removes links already in
/// its text. Kept pure so callers can run the vault-wide scans off-isolate.
EnrichDayResolution resolveEnrichDay(
  EnrichMentions mentions,
  NoteRef note,
  EnrichMemory memory,
  VaultIndex index,
  String source,
) {
  final typed = scanNote(note.path, stripAutoEntities(source)).outgoingLinks;
  final lines = source.split('\n');
  mentions = EnrichMentions(
    note: mentions.note,
    contentSha: mentions.contentSha,
    model: mentions.model,
    mentions: [
      for (final mention in mentions.mentions)
        if (mention.line > 0 &&
            mention.line <= lines.length &&
            // Drop only a surface that sits inside a longer word ("Андрей"
            // in "Андрейб"); one absent from the line stays as before.
            (enrichSurfaceIndex(lines[mention.line - 1], mention.surface) >=
                    0 ||
                !lines[mention.line - 1].toLowerCase().contains(
                  mention.surface.toLowerCase(),
                )))
          mention,
    ],
    keywords: mentions.keywords,
    markers: mentions.markers,
    loans: mentions.loans,
  );
  mentions = applyAliasHits(mentions, memory.aliasIndex.scan(source), lines);
  final allDecisions = resolveMentions(mentions, note, memory);
  return (
    decisions: [
      for (final decision in allDecisions)
        if ((decision.status != EnrichStatus.linked ||
                !typed.contains(decision.target!.id)) &&
            !enrichLinkedOnLine(decision.mention, lines))
          decision,
    ],
    tags: enrichTags(mentions.keywords, index, memory: memory),
    markers: enrichMarkerOffers(mentions, source, memory),
    loans: enrichLoanOffers(
      mentions,
      source,
      memory,
      allDecisions,
      noteDate: note.kind == 'daily'
          ? DateTime.tryParse(dailyDayOf(note) ?? '')
          : null,
    ),
  );
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

/// Removes legacy generated mentions while keeping their links as plain text
/// and promoting generated tags into the note header.
String selfHealAutoEntities(String source) {
  if (!source.contains(autoEntitiesMarker)) return source;
  final lines = source.split('\n');
  final kept = <String>[];
  final tags = <String>[];
  var inBlock = false;
  var headingSeen = false;
  for (final line in lines) {
    if (line.trim() == autoEntitiesMarker) {
      inBlock = true;
      headingSeen = false;
      continue;
    }
    if (inBlock &&
        !headingSeen &&
        RegExp(r'^\s*==\s+Mentions\s*$').hasMatch(line)) {
      headingSeen = true;
      continue;
    }
    if (inBlock && RegExp(r'^\s*=+\s').hasMatch(line)) inBlock = false;
    if (inBlock) {
      final tagMatches = RegExp(
        r'#tylog\.tag\("((?:\\.|[^"\\])*)"\)',
      ).allMatches(line);
      if (tagMatches.isNotEmpty) {
        tags.addAll(
          tagMatches.map(
            (tag) =>
                tag.group(1)!.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!),
          ),
        );
        continue;
      }
      final link = RegExp(
        r'^\s*[-+*]\s+(#tylog\.ref-note\(.*)$',
      ).firstMatch(line);
      if (link != null) {
        kept.add(link.group(1)!);
      } else if (line.trim().isNotEmpty) {
        kept.add(line);
      }
      continue;
    }
    kept.add(line);
  }
  final cleaned = kept.join('\n');
  return tags.isEmpty ? cleaned : updateNoteTags(cleaned, add: tags);
}

/// Turns the first plain occurrence of [mention] on its line into a link.
/// Returns [source] unchanged when the line no longer holds the surface
/// outside markup: the user's text wins over our line numbers.
String linkMentionInline(String source, EnrichMention mention, NoteRef target) {
  final lines = source.split('\n');
  final i = mention.line - 1;
  if (i < 0 || i >= lines.length) return source;
  final line = lines[i];
  // A whole word outside URLs, paths and handles: "hermesagent" inside
  // reddit.com/r/hermesagent/... must stay text (a link there breaks the
  // URL and the note stops compiling).
  int at = -1;
  for (var from = 0; ;) {
    final hit = enrichSurfaceIndex(line, mention.surface, from);
    if (hit < 0) break;
    final end = hit + mention.surface.length;
    final start = line.lastIndexOf(RegExp(r'\s'), hit) + 1;
    final stop = line.indexOf(RegExp(r'\s'), end);
    final token = line.substring(start, stop < 0 ? line.length : stop);
    // A token starting with `#` is Typst code (`#tylog.task(`): a link there
    // breaks the call and the whole note stops compiling.
    if (!token.startsWith('#') && !RegExp(r'[/@]|://|www\.').hasMatch(token)) {
      at = hit;
      break;
    }
    from = hit + 1;
  }
  if (at < 0) return source;
  if (line.trimLeft().startsWith('//') ||
      line.substring(0, at).contains('`') ||
      lines.take(i).join('\n').split('```').length.isEven ||
      RegExp(r'[\[\]#\\]').hasMatch(mention.surface)) {
    return source;
  }
  // Already inside a call or its content? Leave it.
  final before = line.substring(0, at);
  // An argument line of a multi-line call (`  text: "..."`) or text after an
  // odd number of quotes is a Typst string: a link there breaks the file, and
  // the editor then reverts every edit (A24, 2026-11-04).
  if (RegExp(r'^\s*[\w-]+:\s').hasMatch(line) ||
      RegExp(r'(?<!\\)"').allMatches(before).length.isOdd) {
    return source;
  }
  if (before.contains('#tylog.') &&
      before.lastIndexOf('#tylog.') > before.lastIndexOf(']')) {
    return source;
  }
  lines[i] =
      '$before#tylog.ref-note(${typstString(target.id)})'
      '[${line.substring(at, at + mention.surface.length)}]${line.substring(at + mention.surface.length)}';
  return lines.join('\n');
}

/// Adds literal tags without rewriting unrelated header fields.
String addEnrichHeaderTags(String source, String path, List<String> tags) {
  if (tags.isEmpty) return source;
  return updateNoteTags(source, add: tags);
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
  EnrichMemory memory,
) {
  if (mentions.markers.isEmpty) return const [];
  final lines = source.split('\n');
  final code = enrichCodeLines(source);
  return [
    for (final (line, id) in mentions.markers)
      // A marker with no page yet ("Купить") links by name, as the user does.
      if (memory.markerNotes[id] ??
              NoteRef(id: id, path: '', title: id, outgoingLinks: const [])
          case final marker)
        if (line >= 1 && line <= lines.length && !code.contains(line))
          if (!_carries(lines[line - 1], marker))
            if (enrichPlainLine(lines[line - 1]) case final text
                when text.isNotEmpty &&
                    !text.startsWith('#') &&
                    !memory.isRejected(text, enrichMarkerEntity(id)))
              EnrichMarkerOffer(marker, line, text),
  ];
}

/// Lines occupied by multi-line Typst calls, shared by enrichment writers.
Set<int> enrichCodeLines(String source) => _enrichCodeLines(source);

Set<int> _enrichCodeLines(String source) {
  // Lines inside a multi-line call (`#tylog.task(` ... `)`) are code: showing
  // them reads as raw Typst, and filing one would put a link inside the call.
  final lines = source.split('\n');
  final code = <int>{};
  var offset = 0;
  final starts = <int>[];
  for (final line in lines) {
    starts.add(offset);
    offset += line.length + 1;
  }
  for (final call in locateTypstCalls(source, anyName: true)) {
    if (!call.source.contains('\n')) continue;
    for (var i = 0; i < lines.length; i++) {
      final lineEnd = starts[i] + lines[i].length;
      if (starts[i] < call.end && lineEnd > call.start && call.end > lineEnd) {
        code.add(i + 1);
      } else if (starts[i] >= call.start && starts[i] < call.end) {
        code.add(i + 1);
      }
    }
  }
  return code;
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
  // "fixit crash": the typed word becomes the link instead of doubling it.
  final typed = RegExp(
    '^${RegExp.escape(marker.title)}(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  ).firstMatch(text.substring(prefix));
  final link =
      '#tylog.ref-note(${typstString(marker.id)})'
      '[${escapeMarkup(marker.title)}]';
  lines[line - 1] = typed == null
      ? '${text.substring(0, prefix)}$link ${text.substring(prefix)}'
      : '${text.substring(0, prefix)}$link'
            '${text.substring(prefix + typed.end)}';
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
