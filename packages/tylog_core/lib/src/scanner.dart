import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'storage.dart';

enum TylogHelperKind { current, legacy, custom }

TylogHelperKind classifyTylogHelper(
  String source, {
  String? current,
  String? legacy,
}) {
  final normalized = source.replaceAll('\r\n', '\n').trim();
  if (current != null &&
      normalized == current.replaceAll('\r\n', '\n').trim()) {
    return TylogHelperKind.current;
  }
  if (legacy != null && normalized == legacy.replaceAll('\r\n', '\n').trim()) {
    return TylogHelperKind.legacy;
  }
  if (normalized.contains('// tylog-package: 0.1.0')) {
    return TylogHelperKind.current;
  }
  return TylogHelperKind.custom;
}

final _quoted = RegExp(r'"((?:\\.|[^"\\])*)"');

enum LinkResolutionStatus { resolved, unresolved, ambiguous }

class LinkResolution {
  const LinkResolution({
    required this.target,
    required this.status,
    this.path,
    this.candidates = const [],
  });

  final String target;
  final LinkResolutionStatus status;
  final String? path;
  final List<String> candidates;
}

class LinkResolver {
  LinkResolver(Iterable<NoteRef> notes) {
    for (final note in notes) {
      _add(_ids, note.id, note.path);
      _add(_titles, note.title, note.path);
      _add(
        _stems,
        note.path.split('/').last.replaceFirst(RegExp(r'\.typ$'), ''),
        note.path,
      );
      for (final alias in note.aliases) {
        _add(_aliases, alias, note.path);
      }
    }
  }

  final _ids = <String, Set<String>>{};
  final _aliases = <String, Set<String>>{};
  final _titles = <String, Set<String>>{};
  final _stems = <String, Set<String>>{};

  LinkResolution resolve(String target) {
    for (final map in [_ids, _aliases, _titles, _stems]) {
      final candidates = map[target];
      if (candidates != null) return _resolveCandidates(target, candidates);
    }
    return LinkResolution(
      target: target,
      status: LinkResolutionStatus.unresolved,
    );
  }
}

class TypstCall {
  const TypstCall(this.name, this.start, this.end, this.source);

  final String name;
  final int start;
  final int end;
  final String source;
}

class IndexBuildCancelled implements Exception {
  const IndexBuildCancelled();
}

class NoteMetadataDraft {
  const NoteMetadataDraft({
    required this.id,
    required this.title,
    this.kind = 'note',
    this.project,
    this.date,
    this.tags = const [],
    this.aliases = const [],
    this.properties = const {},
  });

  final String id;
  final String title;
  final String kind;
  final String? project;
  final String? date;
  final List<String> tags;
  final List<String> aliases;
  final Map<String, Object?> properties;

  /// Rebuilds a managed-header draft from an already-parsed [NoteRef] — used to
  /// upgrade a legacy/fallback-parsed note to a `tylog.note.with(...)` header
  /// (`replaceNoteHeader`) without changing its metadata.
  factory NoteMetadataDraft.fromNote(NoteRef note) => NoteMetadataDraft(
    id: note.id,
    title: note.title,
    kind: note.kind,
    project: note.project,
    date: note.date,
    tags: note.tags,
    aliases: note.aliases,
    properties: note.properties,
  );
}

class QueriedMetadata {
  const QueriedMetadata({
    required this.note,
    required this.links,
    required this.tags,
    required this.dates,
    required this.attachments,
    required this.tasks,
  });

  final Map<String, Object?>? note;
  final List<String> links;
  final List<String> tags;
  final List<Map<String, Object?>> dates;
  final List<Map<String, Object?>> attachments;
  final List<Map<String, Object?>> tasks;
}

class TypstDocumentInput {
  const TypstDocumentInput({
    required this.path,
    required this.source,
    this.files = const {},
  });

  final String path;
  final String source;
  final Map<String, Uint8List> files;
}

class TypstMetadataRecord {
  const TypstMetadataRecord({required this.label, required this.value});

  final String label;
  final Object? value;
}

abstract interface class TypstInspector {
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input);
}

/// An inspector whose underlying worker can be torn down and rebuilt after it
/// wedges. The device inspector shares one stateful native Typst engine behind
/// a write lock; a single compile that spins forever holds that lock and makes
/// every later note time out too (a contiguous fallback tail). Recreating the
/// engine gives the rest of the pass a fresh, unlocked worker. A separate
/// interface so the CLI/test inspectors (which spawn per note and never wedge)
/// don't have to implement it.
abstract interface class RecoverableInspector {
  Future<void> recover();
}

/// Upper bound for a single note's metadata query. A pathological document
/// can make the Typst compile spin forever (device-verified: one synced
/// article froze the whole scan, and with it index + search, until app
/// restart); on timeout the note falls back to the source-based scan and a
/// `metadata-query-failed` problem names it.
Duration typstInspectTimeout = const Duration(seconds: 30);

/// Upper bound on how many cached fallback notes a single scan re-queries.
/// Re-inspection is a per-note Typst compile (seconds each on device); an
/// uncapped pass over a large backlog pins the CPU for hours and starves
/// sync. Capped, the backlog drains a slice per scan instead.
int maxMetadataReinspectionsPerScan = 50;

/// Consecutive inspect timeouts tolerated before the native worker is
/// treated as wedged. A single transient timeout skips only its own note (it
/// still records a metadata-query-failed problem); on a sustained run the
/// worker is recovered ([RecoverableInspector.recover]) so the rest of the
/// pass keeps querying, or — for a non-recoverable inspector — abandoned to
/// the source-scan fallback. Test-overridable.
int maxConsecutiveInspectTimeouts = 3;

/// How many times a wedged worker is rebuilt within one scan before the
/// inspector is abandoned outright. Bounds the pathological case where every
/// note wedges even a fresh engine (each recovery still burns
/// [maxConsecutiveInspectTimeouts] × [typstInspectTimeout]); the counter
/// resets whenever any query succeeds, so a vault with a few bad notes
/// recovers indefinitely. Test-overridable.
int maxInspectorRecoveriesPerScan = 3;

List<TypstMetadataRecord> decodeTypstMetadataRecords(String json) {
  final elements = (jsonDecode(json) as List).cast<Object?>();
  return [
    for (final element in elements)
      if (element is Map && element['label'] != null)
        TypstMetadataRecord(
          label: element['label'].toString(),
          value: element['value'],
        ),
  ];
}

List<Object?> decodeTypstMetadata(String json) =>
    (jsonDecode(json) as List).map((element) {
      if (element is Map && element.containsKey('value')) {
        return element['value'];
      }
      return element;
    }).toList();

QueriedMetadata decodeTylogMetadataRecords(
  Iterable<TypstMetadataRecord> records,
) {
  final noteValues = _recordValues(records, '<tylog-note>', 'note');
  return QueriedMetadata(
    note: noteValues.whereType<Map>().firstOrNull?.cast<String, Object?>(),
    links: _targets(_recordValues(records, '<tylog-link>', 'link'), 'target'),
    tags: _targets(_recordValues(records, '<tylog-tag>', 'tag'), 'name'),
    dates: _maps(_recordValues(records, '<tylog-date>', 'date')),
    attachments: _maps(
      _recordValues(records, '<tylog-attachment>', 'attachment'),
    ),
    tasks: _maps(_recordValues(records, '<tylog-task>', 'task')),
  );
}

List<Object?> _recordValues(
  Iterable<TypstMetadataRecord> records,
  String label,
  String entity,
) => records
    .where((record) => record.label == label)
    .map((record) {
      final value = record.value;
      if (value is! Map || value['schema'] == null) return value;
      return value['schema'] == 1 && value['entity'] == entity ? value : null;
    })
    .where((value) => value != null)
    .cast<Object?>()
    .toList();

List<TypstCall> locateTypstCalls(
  String source, {
  Set<String> names = const {
    'tylog.ref-note',
    'tylog.tag',
    'tylog.task',
    'tylog.date-ref',
    'tylog.attachment',
  },
}) {
  final calls = <TypstCall>[];
  var i = 0;
  while (i < source.length) {
    if (_starts(source, i, '//')) {
      i = source.indexOf('\n', i);
      if (i < 0) break;
      continue;
    }
    if (_starts(source, i, '/*')) {
      i = _skipBlockComment(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 34) {
      i = _skipString(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 96) {
      i = _skipRaw(source, i);
      continue;
    }
    if (source.codeUnitAt(i) != 35) {
      i++;
      continue;
    }
    final start = i++;
    final nameStart = i;
    while (i < source.length && _identifier(source.codeUnitAt(i))) {
      i++;
    }
    var name = source.substring(nameStart, i);
    if (i < source.length && source.codeUnitAt(i) == 46) {
      final memberStart = ++i;
      while (i < source.length && _identifier(source.codeUnitAt(i))) {
        i++;
      }
      name = '$name.${source.substring(memberStart, i)}';
    }
    while (i < source.length && _space(source.codeUnitAt(i))) {
      i++;
    }
    if (!names.contains(name) ||
        i >= source.length ||
        source.codeUnitAt(i) != 40) {
      continue;
    }
    final end = _balancedEnd(source, i);
    if (end == null) continue;
    var callEnd = end;
    var contentStart = end;
    while (contentStart < source.length &&
        _space(source.codeUnitAt(contentStart))) {
      contentStart++;
    }
    if (contentStart < source.length && source.codeUnitAt(contentStart) == 91) {
      callEnd = _balancedContentEnd(source, contentStart) ?? end;
    }
    calls.add(
      TypstCall(name, start, callEnd, source.substring(start, callEnd)),
    );
    i = callEnd;
  }
  return calls;
}

TypstCall? _noteHeader(String source) {
  final match = RegExp(
    r'#show\s*:\s*tylog\.note\.with\s*\(',
  ).firstMatch(source);
  if (match == null) return null;
  final open = source.indexOf('(', match.start);
  final end = _balancedEnd(source, open);
  if (end == null) return null;
  return TypstCall(
    'tylog.note.with',
    match.start,
    end,
    source.substring(match.start, end),
  );
}

NoteRef scanNote(String relativePath, String source, {String? fingerprint}) =>
    _fallbackNote(relativePath, source, fingerprint: fingerprint);

Future<VaultIndex> scanVault(
  Directory root, {
  TypstInspector? inspector,
  VaultIndex? previous,
  bool force = false,
  void Function(int complete, int total)? onProgress,
  bool Function()? isCancelled,
}) => scanVaultStorage(
  LocalVaultStorage(root),
  inspector: inspector,
  previous: previous,
  force: force,
  onProgress: onProgress,
  isCancelled: isCancelled,
);

Future<VaultIndex> scanVaultStorage(
  VaultStorage storage, {
  TypstInspector? inspector,
  VaultIndex? previous,
  bool force = false,
  void Function(int complete, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final files = <VaultStorageEntry>[];
  for (final entity in await storage.list(recursive: true)) {
    if (entity.isDirectory || !entity.path.endsWith('.typ')) continue;
    final relative = entity.path;
    if (!_noteRoots.any(relative.startsWith)) {
      continue;
    }
    files.add(entity);
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  Map<String, Uint8List>? inspectionFiles;
  // A poisoned note can wedge the inspector's single native worker, so a
  // single timeout only skips its own note (still recorded as a
  // metadata-query-failed problem). After [maxConsecutiveInspectTimeouts]
  // consecutive timeouts the worker is treated as wedged: a recoverable
  // inspector is rebuilt so the rest of the pass keeps querying (a wedged
  // native engine holds its lock forever, so nulling alone would strand the
  // whole tail as fallback); a non-recoverable one drops to the source scan.
  var activeInspector = inspector;
  var reinspected = 0;
  var consecutiveTimeouts = 0;
  var recoveries = 0;

  final notes = <String, NoteRef>{};
  final tasks = <TaskRef>[];
  final problems = <PkmsProblem>[];
  for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
    if (isCancelled?.call() ?? false) throw const IndexBuildCancelled();
    final file = files[fileIndex];
    final relative = file.path;
    final fingerprint =
        '${file.modified?.millisecondsSinceEpoch ?? 0}:${file.size ?? 0}';
    final cached = previous?.notesByPath[relative];
    // A cached fallback note (dead inspector during some earlier scan) is
    // re-queried when an inspector is available so it can upgrade to real
    // metadata and drop its metadata-fallback problem — but only up to
    // [maxMetadataReinspectionsPerScan] per pass: each re-query is a Typst
    // compile, and an uncapped backlog pins the device CPU for hours.
    final reinspect =
        cached?.metadataSource != 'typst-query' &&
        activeInspector != null &&
        reinspected < maxMetadataReinspectionsPerScan;
    if (reinspect && cached?.fingerprint == fingerprint) reinspected++;
    if (!force &&
        previous?.version == 5 &&
        cached?.fingerprint == fingerprint &&
        !reinspect) {
      notes[relative] = cached!;
      tasks.addAll(
        previous?.tasks.where((task) => task.notePath == relative) ?? const [],
      );
      if (cached.metadataSource != 'typst-query') {
        problems.add(_fallbackProblem(relative));
      }
      onProgress?.call(fileIndex + 1, files.length);
      continue;
    }
    final source = await storage.readText(relative);
    inspectionFiles ??= activeInspector == null
        ? const <String, Uint8List>{}
        : await _inspectionFiles(storage);
    try {
      final queried = activeInspector == null
          ? null
          : decodeTylogMetadataRecords(
              await activeInspector
                  .inspect(
                    TypstDocumentInput(
                      path: relative,
                      source: source,
                      files: inspectionFiles,
                    ),
                  )
                  .timeout(typstInspectTimeout),
            );
      if (activeInspector != null) {
        // A query got through: the worker is healthy, so reset both the
        // timeout streak and the recovery budget (a handful of bad notes
        // scattered through the vault should each get the full allowance).
        consecutiveTimeouts = 0;
        recoveries = 0;
      }
      notes[relative] = queried?.note == null
          ? _fallbackNote(
              relative,
              source,
              fingerprint: fingerprint,
              modifiedMillis: file.modified?.millisecondsSinceEpoch ?? 0,
            )
          : _queriedNote(
              relative,
              source,
              queried!,
              fingerprint,
              file.modified?.millisecondsSinceEpoch ?? 0,
            );
      tasks.addAll(
        queried == null
            ? _fallbackTasks(relative, locateTypstCalls(source))
            : _taskRefs(relative, queried.tasks),
      );
      if (queried?.note == null) {
        problems.add(_fallbackProblem(relative));
      }
    } catch (error) {
      if (error is TimeoutException) {
        consecutiveTimeouts++;
        if (consecutiveTimeouts >= maxConsecutiveInspectTimeouts) {
          if (activeInspector is RecoverableInspector &&
              recoveries < maxInspectorRecoveriesPerScan) {
            recoveries++;
            consecutiveTimeouts = 0;
            try {
              await (activeInspector as RecoverableInspector).recover();
            } catch (_) {
              activeInspector = null;
            }
          } else {
            activeInspector = null;
          }
        }
      }
      final fallback = _fallbackNote(
        relative,
        source,
        fingerprint: fingerprint,
        modifiedMillis: file.modified?.millisecondsSinceEpoch ?? 0,
      );
      notes[relative] = cached?.copyWith(fingerprint: fingerprint) ?? fallback;
      tasks.addAll(_fallbackTasks(relative, locateTypstCalls(source)));
      problems.add(
        PkmsProblem(
          code: 'metadata-query-failed',
          severity: PkmsSeverity.warning,
          subject: relative,
          message: "A note's formatting couldn't be read.",
          fix: 'Fix the metadata header or convert it to managed metadata.',
          detail: 'Typst metadata query failed: $error',
        ),
      );
    }
    onProgress?.call(fileIndex + 1, files.length);
  }
  return buildVaultIndex(notes, problems: problems, tasks: tasks);
}

const _noteRoots = ['daily/', 'notes/', 'projects/', 'articles/'];

Future<Map<String, Uint8List>> _inspectionFiles(VaultStorage storage) async {
  final files = <String, Uint8List>{};
  for (final entry in await storage.list(recursive: true)) {
    if (entry.isDirectory ||
        entry.path.startsWith('_index/') ||
        entry.path.startsWith('.tylog/')) {
      continue;
    }
    // Other notes' sources are not compile inputs — loading them meant ~1600
    // serial SAF reads (minutes of stall) and the whole vault held in RAM
    // before the first metadata query could run. Keep _system (package,
    // template, bibliography) and attachments only.
    // ponytail: cross-note #include loses metadata and falls back with a
    // problem; pass the included note explicitly if that ever matters.
    if (_noteRoots.any(entry.path.startsWith) && entry.path.endsWith('.typ')) {
      continue;
    }
    final bytes = await storage.readBytes(entry.path);
    files[entry.path] = bytes;
    files['/${entry.path}'] = bytes;
  }
  return files;
}

PkmsProblem _fallbackProblem(String path) => PkmsProblem(
  code: 'metadata-fallback',
  severity: PkmsSeverity.warning,
  subject: path,
  message: 'Typst metadata was unavailable; using legacy parsing.',
  fix: 'Convert this note to the managed metadata header.',
);

VaultIndex buildVaultIndex(
  Map<String, NoteRef> notes, {
  List<PkmsProblem> problems = const [],
  List<TaskRef> tasks = const [],
}) {
  final resolver = LinkResolver(notes.values);
  final backlinks = <String, Set<String>>{};
  final attachmentBacklinks = <String, Set<String>>{};
  final allProblems = [...problems];
  for (final source in notes.values) {
    for (final target in source.outgoingLinks) {
      final resolved = resolver.resolve(target);
      if (resolved.status == LinkResolutionStatus.resolved) {
        backlinks.putIfAbsent(resolved.path!, () => {}).add(source.path);
      } else {
        allProblems.add(
          PkmsProblem(
            code: resolved.status == LinkResolutionStatus.ambiguous
                ? 'ambiguous-link'
                : 'broken-link',
            severity: PkmsSeverity.warning,
            subject: source.path,
            message: '${resolved.status.name} link: $target',
            fix: 'Choose a unique note ID or create the missing note.',
          ),
        );
      }
    }
    for (final attachment in source.attachments) {
      attachmentBacklinks
          .putIfAbsent(attachment.path, () => {})
          .add(source.path);
    }
  }
  return VaultIndex(
    notesByPath: notes,
    backlinksByTarget: _setsToSortedLists(backlinks),
    attachmentBacklinksByPath: _setsToSortedLists(attachmentBacklinks),
    problems: allProblems,
    tasks: tasks,
  );
}

String? resolveLinkPath(VaultIndex index, String target) {
  final resolved = LinkResolver(index.notes).resolve(target);
  return resolved.status == LinkResolutionStatus.resolved
      ? resolved.path
      : null;
}

LinkResolution resolveLink(VaultIndex index, String target) =>
    LinkResolver(index.notes).resolve(target);

/// Other vault notes [note] plausibly relates to, found by matching its
/// own tags/citations/string properties against the same exact-match
/// id/alias/title/stem maps [LinkResolver] already uses to resolve
/// `#tylog.ref-note(...)` targets. No fuzzy matching.
List<String> suggestLinkTargets(NoteRef note, VaultIndex index) {
  final resolver = LinkResolver(index.notes);
  final candidates = <String>{
    ...note.tags,
    ...note.citations,
    for (final value in note.properties.values)
      if (value is String)
        value
      else if (value is List)
        ...value.whereType<String>(),
  };
  final targets = <String>{};
  for (final candidate in candidates) {
    final resolved = resolver.resolve(candidate);
    if (resolved.status == LinkResolutionStatus.resolved &&
        resolved.path != note.path) {
      targets.add(resolved.path!);
    }
  }
  return targets.toList()..sort();
}

String replaceNoteHeader(String source, NoteMetadataDraft draft) {
  final header = serializeNoteHeader(draft);
  final call = _noteHeader(source);
  final String withHeader;
  if (call != null) {
    withHeader = source.replaceRange(call.start, call.end, header);
  } else {
    final importEnd = source.startsWith('#import ')
        ? source.indexOf('\n') + 1
        : 0;
    withHeader = source.replaceRange(importEnd, importEnd, '$header\n\n');
  }
  // `tylog.note.with(...)` is meaningless without the helper import — a legacy
  // note that never had it (e.g. a hand-authored `.typ`) would fail to compile
  // once we add the managed header. Guarantee the import is present.
  if (withHeader.contains('/_system/tylog.typ')) return withHeader;
  return '#import "/_system/tylog.typ" as tylog\n\n$withHeader';
}

/// Repairs markdown-import artifacts that break Typst compilation — so a note's
/// metadata query stops failing (`metadata-query-failed` / "formatting couldn't
/// be read"). Conservative and idempotent: only rewrites the exact patterns the
/// vault audit found, never touching well-formed content.
String repairArticleTypst(String source) {
  var out = source;
  // Inline-function field access: a closing `]`/`)` immediately followed by
  // `.<letter>` (e.g. `#emph[confident guessing].Instead`) re-parses as member
  // access on the function. Insert a space after the dot so the period is prose.
  out = out.replaceAllMapped(
    RegExp(r'([\]\)])\.(\p{L}|_)', unicode: true),
    (m) => '${m[1]}. ${m[2]}',
  );
  // A content block `]` abutting `(` or `[` (e.g. `#link("u")[label](2024)`)
  // re-parses as a call/second-content on the function. Space them apart.
  // (Only `]` — never `)`, so legit `#link("u")[label]` call syntax is kept.)
  out = out.replaceAllMapped(
    RegExp(r'\]([(\[])'),
    (m) => '] ${m[1]}',
  );
  // Bare `word@domain.tld` in prose parses as a Typst `@label` ref (e.g.
  // `20251186@iade.pt` -> `<iade.pt>` does not exist). Escape the `@` outside
  // quoted strings (mailto: URLs stay intact) and skip already-escaped `\@`.
  out = out.splitMapJoin(
    RegExp(r'"(?:\\.|[^"\\])*"'),
    onMatch: (m) => m[0]!,
    onNonMatch: (text) => text.replaceAllMapped(
      RegExp(r'(\w)@(\w[\w.-]*\.\w+)'),
      (m) => '${m[1]}\\@${m[2]}',
    ),
  );
  return out;
}

String serializeNoteHeader(NoteMetadataDraft draft) {
  final fields = <String>[
    '  id: ${_typstString(draft.id)},',
    '  title: ${_typstString(draft.title)},',
    '  kind: ${_typstString(draft.kind)},',
    '  date: ${draft.date == null || draft.date!.isEmpty ? 'none' : _typstString(draft.date!)},',
    '  tags: ${_typstList(draft.tags)},',
    '  aliases: ${_typstList(draft.aliases)},',
    '  project: ${draft.project == null || draft.project!.isEmpty ? 'none' : _typstString(draft.project!)},',
    '  properties: ${_typstDictionary(draft.properties)},',
  ];
  return '#show: tylog.note.with(\n${fields.join('\n')}\n)';
}

/// Migrates the legacy `properties["type"]` entity classifier into `kind`.
///
/// Historically "entities" (people/places/orgs) were modeled as notes with a
/// generic `kind: "note"` and a `properties["type"]` value carrying the real
/// classification. That's a duplicated classifier — this folds `type` into
/// `kind` (the single classifier going forward) and drops it from
/// `properties`. Only touches notes that are still on the generic `kind:
/// "note"` default with a non-empty `properties["type"]`; already-specific
/// kinds are left untouched so this is safe to run repeatedly (idempotent)
/// and never clobbers a deliberately-set kind.
String migrateEntityTypeToKind(String source) {
  final call = _noteHeader(source);
  if (call == null) return source;
  final header = call.source;
  final kind = _field(header, 'kind') ?? 'note';
  final properties = _parseProperties(header);
  final type = properties['type'];
  if (kind != 'note' || type is! String || type.isEmpty) {
    return source;
  }
  final newProperties = Map<String, Object?>.from(properties)..remove('type');
  final draft = NoteMetadataDraft(
    id: _field(header, 'id') ?? '',
    title: _field(header, 'title') ?? '',
    kind: type,
    project: _field(header, 'project'),
    date: _field(header, 'date'),
    tags: _parseList(header, 'tags'),
    aliases: _parseList(header, 'aliases'),
    properties: newProperties,
  );
  return replaceNoteHeader(source, draft);
}

/// The `[start, end)` byte range of a `"key": value` entry inside a
/// dictionary's source text (parens included), trimmed of any leading
/// whitespace/newline so callers can replace it without disturbing
/// formatting around it.
class _DictEntry {
  const _DictEntry(this.start, this.end);
  final int start;
  final int end;
}

/// Locates the top-level `"key": value` entry for [key] inside [dictSource]
/// (a full `(...)` dictionary literal). TyLog writes quoted keys (see
/// [_typstDictionary]), but hand-edited Typst commonly uses bare identifier
/// keys (`status: "read"`), so both spellings match — otherwise a write
/// would append a duplicate key. Reuses [_splitTopLevel], the same
/// nesting-aware comma splitter [_parseProperties] already relies on to read
/// this shape, so strings/comments/nested `(...)`/`[...]` can't be mistaken
/// for a top-level boundary. Returns null if [key] isn't present.
_DictEntry? _locateDictEntry(String dictSource, String key) {
  if (!dictSource.startsWith('(') || !dictSource.endsWith(')')) return null;
  final inner = dictSource.substring(1, dictSource.length - 1);
  final quotedPattern = RegExp(r'^(\s*)"((?:\\.|[^"\\])*)"\s*:', dotAll: true);
  final barePattern = RegExp(r'^(\s*)([A-Za-z_][A-Za-z0-9_-]*)\s*:');
  var offset = 1;
  for (final part in _splitTopLevel(inner)) {
    final quoted = quotedPattern.firstMatch(part);
    final match = quoted ?? barePattern.firstMatch(part);
    if (match != null) {
      final rawKey = match.group(2)!;
      final decodedKey = quoted != null
          ? rawKey.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!)
          : rawKey;
      if (decodedKey == key) {
        final leading = match.group(1)!.length;
        return _DictEntry(offset + leading, offset + part.length);
      }
    }
    offset += part.length + 1;
  }
  return null;
}

/// Surgically sets `properties[key] = value` inside a note header's
/// `properties: (...)` dictionary, leaving the rest of the header
/// (including comments/formatting on unrelated fields) untouched — unlike
/// [replaceNoteHeader], which regenerates the whole call.
String replaceNoteProperty(String source, String key, Object? value) {
  final call = _noteHeader(source);
  if (call == null) {
    throw StateError('No tylog.note header found');
  }
  final header = call.source;
  final encodedValue = _typstValue(value);
  final propsField = _locateTopLevelField(header, 'properties');
  if (propsField == null) {
    final newHeader = header.replaceFirst(
      RegExp(r'\)\s*$'),
      '  properties: (${_typstString(key)}: $encodedValue,),\n)',
    );
    return source.replaceRange(call.start, call.end, newHeader);
  }
  final dictSource = header.substring(
    propsField.valueStart,
    propsField.valueEnd,
  );
  final entry = _locateDictEntry(dictSource, key);
  final String newDict;
  if (entry != null) {
    newDict = dictSource.replaceRange(
      entry.start,
      entry.end,
      '${_typstString(key)}: $encodedValue',
    );
  } else if (dictSource.trim() == '(:)') {
    newDict = '(${_typstString(key)}: $encodedValue,)';
  } else {
    newDict = dictSource.replaceFirst(
      RegExp(r'\)\s*$'),
      '${_typstString(key)}: $encodedValue,)',
    );
  }
  final newHeader = header.replaceRange(
    propsField.valueStart,
    propsField.valueEnd,
    newDict,
  );
  return source.replaceRange(call.start, call.end, newHeader);
}

/// Parses the `properties: (...)` dictionary out of a `tylog.note.with(...)`
/// header's source text. Keys are always quoted strings (see
/// [_typstDictionary]); values are decoded when they're strings, numbers,
/// booleans, or `none`, and otherwise kept as their raw Typst source text.
Map<String, Object?> _parseProperties(String callSource) {
  final field = _locateTopLevelField(callSource, 'properties');
  if (field == null) return const {};
  final value = callSource.substring(field.valueStart, field.valueEnd).trim();
  if (!value.startsWith('(') || !value.endsWith(')')) return const {};
  final inner = value.substring(1, value.length - 1).trim();
  if (inner.isEmpty || inner == ':') return const {};
  final entryKeyValue = RegExp(
    r'^\s*"((?:\\.|[^"\\])*)"\s*:\s*(.*)$',
    dotAll: true,
  );
  final result = <String, Object?>{};
  for (final entry in _splitTopLevel(inner)) {
    if (entry.trim().isEmpty) continue;
    final match = entryKeyValue.firstMatch(entry);
    if (match == null) continue;
    final key = match
        .group(1)!
        .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
    result[key] = _parsePropertyValue(match.group(2)!.trim());
  }
  return result;
}

/// Splits a Typst argument/dictionary body on top-level commas, skipping
/// commas nested inside strings, raw blocks, comments, or `(...)`/`[...]`.
List<String> _splitTopLevel(String source) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  var i = 0;
  while (i < source.length) {
    if (_starts(source, i, '//')) {
      final nl = source.indexOf('\n', i);
      i = nl < 0 ? source.length : nl;
      continue;
    }
    if (_starts(source, i, '/*')) {
      i = _skipBlockComment(source, i);
      continue;
    }
    final code = source.codeUnitAt(i);
    if (code == 34) {
      i = _skipString(source, i);
      continue;
    }
    if (code == 96) {
      i = _skipRaw(source, i);
      continue;
    }
    if (code == 40 || code == 91) {
      depth++;
      i++;
      continue;
    }
    if (code == 41 || code == 93) {
      depth--;
      i++;
      continue;
    }
    if (code == 44 && depth == 0) {
      parts.add(source.substring(start, i));
      i++;
      start = i;
      continue;
    }
    i++;
  }
  if (start < source.length) parts.add(source.substring(start));
  return parts;
}

Object? _parsePropertyValue(String raw) {
  final trimmed = raw.trim();
  if (trimmed == 'none') return null;
  if (trimmed == 'true') return true;
  if (trimmed == 'false') return false;
  final quoted = RegExp(
    r'^"((?:\\.|[^"\\])*)"$',
  ).firstMatch(trimmed);
  if (quoted != null) {
    return quoted
        .group(1)!
        .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
  }
  final number = num.tryParse(trimmed);
  if (number != null) return number;
  return trimmed;
}

String replaceTaskStatus(String source, String id, String status) {
  final call = _locateTaskCall(source, id);
  final field = _locateTopLevelField(call.source, 'status');
  final replacement = field == null
      ? call.source.replaceFirst(RegExp(r'\)\s*$'), '  status: "$status",\n)')
      : call.source.replaceRange(
          field.start,
          field.end,
          'status: "$status"',
        );
  return source.replaceRange(call.start, call.end, replacement);
}

String completeTaskOccurrence(String source, String id, String timestamp) {
  final call = _locateTaskCall(source, id);
  final field = _locateTopLevelField(call.source, 'completed');
  final replacement = field == null
      ? call.source.replaceFirst(
          RegExp(r'\)\s*$'),
          '  completed: ("$timestamp",),\n)',
        )
      : call.source.replaceRange(
          field.start,
          field.end,
          'completed: (${call.source.substring(field.valueStart + 1, field.valueEnd - 1)}"$timestamp",)',
        );
  return source.replaceRange(call.start, call.end, replacement);
}

String replaceTaskText(String source, String id, String text) {
  final call = _locateTaskCall(source, id);
  final quoted =
      '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  final field = _locateTopLevelField(call.source, 'text');
  final replacement = field == null
      ? call.source.replaceFirst(
          RegExp(r'\)\s*$'),
          '  text: $quoted,\n)',
        )
      : call.source.replaceRange(
          field.start,
          field.end,
          'text: $quoted',
        );
  return source.replaceRange(call.start, call.end, replacement);
}

/// Structurally reads the top-level string field [name] from a single call's
/// source (e.g. `#tylog.task(...)`). Returns the unescaped string value, or
/// null when the field is absent or its value isn't a double-quoted string
/// literal (e.g. `due: none`).
String? taskField(String callSource, String name) {
  final field = _locateTopLevelField(callSource, name);
  if (field == null) return null;
  final value = callSource.substring(field.valueStart, field.valueEnd);
  final quoted = RegExp(r'^"((?:\\.|[^"\\])*)"$').firstMatch(value);
  if (quoted == null) return null;
  return quoted
      .group(1)!
      .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
}

/// Locates the single `tylog.task(...)` call whose `id` field equals [id].
///
/// Throws a [StateError] if no task with that id exists, or if more than
/// one task shares the id (rather than silently mutating a random match).
TypstCall _locateTaskCall(String source, String id) {
  final matches = locateTypstCalls(
    source,
    names: const {'tylog.task'},
  ).where((call) => _field(call.source, 'id') == id).toList();
  if (matches.isEmpty) throw StateError('Task $id not found');
  if (matches.length > 1) {
    throw StateError('Duplicate task id "$id" (${matches.length} matches)');
  }
  return matches.single;
}

/// The `[start, end)` byte range of a `name: value` pair, plus the
/// `[valueStart, valueEnd)` range of just the value, as found at the top
/// level of a single Typst call's argument list (depth 1, i.e. directly
/// inside the call's outer parens, outside any string/comment/raw block and
/// outside any nested `(...)`/`[...]`).
class _TopLevelField {
  const _TopLevelField(this.start, this.end, this.valueStart, this.valueEnd);

  final int start;
  final int end;
  final int valueStart;
  final int valueEnd;
}

/// Structurally locates the top-level `name: value` field inside a single
/// call's source (e.g. `#tylog.task(...)`), reusing the same char-scanning
/// primitives as [locateTypstCalls] so strings, comments, raw blocks, and
/// nested parens/brackets can't be mistaken for a field boundary.
///
/// Returns null if the field isn't present at the top level of the call.
_TopLevelField? _locateTopLevelField(String callSource, String name) {
  final open = callSource.indexOf('(');
  if (open < 0) return null;
  var i = open + 1;
  const outerDepth = 1;
  var depth = outerDepth;
  while (i < callSource.length && depth > 0) {
    if (_starts(callSource, i, '//')) {
      final nl = callSource.indexOf('\n', i);
      i = nl < 0 ? callSource.length : nl;
      continue;
    }
    if (_starts(callSource, i, '/*')) {
      i = _skipBlockComment(callSource, i);
      continue;
    }
    final code = callSource.codeUnitAt(i);
    if (code == 34) {
      i = _skipString(callSource, i);
      continue;
    }
    if (code == 96) {
      i = _skipRaw(callSource, i);
      continue;
    }
    if (code == 40 || code == 91) {
      depth++;
      i++;
      continue;
    }
    if (code == 41 || code == 93) {
      depth--;
      i++;
      continue;
    }
    if (depth == outerDepth && _identifierStart(code)) {
      final identStart = i;
      while (i < callSource.length && _identifier(callSource.codeUnitAt(i))) {
        i++;
      }
      final ident = callSource.substring(identStart, i);
      var j = i;
      while (j < callSource.length && _space(callSource.codeUnitAt(j))) {
        j++;
      }
      if (ident != name || j >= callSource.length || callSource.codeUnitAt(j) != 58) {
        continue;
      }
      var k = j + 1;
      while (k < callSource.length && _space(callSource.codeUnitAt(k))) {
        k++;
      }
      final valueStart = k;
      var valueDepth = outerDepth;
      while (k < callSource.length) {
        if (_starts(callSource, k, '//')) {
          final nl = callSource.indexOf('\n', k);
          k = nl < 0 ? callSource.length : nl;
          continue;
        }
        if (_starts(callSource, k, '/*')) {
          k = _skipBlockComment(callSource, k);
          continue;
        }
        final vcode = callSource.codeUnitAt(k);
        if (vcode == 34) {
          k = _skipString(callSource, k);
          continue;
        }
        if (vcode == 96) {
          k = _skipRaw(callSource, k);
          continue;
        }
        if (vcode == 40 || vcode == 91) {
          valueDepth++;
          k++;
          continue;
        }
        if (vcode == 41 || vcode == 93) {
          if (valueDepth == outerDepth) break;
          valueDepth--;
          k++;
          continue;
        }
        if (vcode == 44 && valueDepth == outerDepth) break;
        k++;
      }
      var valueEnd = k;
      while (valueEnd > valueStart &&
          _space(callSource.codeUnitAt(valueEnd - 1))) {
        valueEnd--;
      }
      return _TopLevelField(identStart, valueEnd, valueStart, valueEnd);
    }
    i++;
  }
  return null;
}

bool _identifierStart(int code) =>
    code >= 65 && code <= 90 || code >= 97 && code <= 122 || code == 95;

NoteRef _queriedNote(
  String path,
  String source,
  QueriedMetadata metadata,
  String fingerprint,
  int modifiedMillis,
) {
  final note = metadata.note!;
  final stem = path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
  return NoteRef(
    id: _text(note['id']) ?? '',
    path: path,
    title: _text(note['title']) ?? stem,
    kind: _text(note['kind']) ?? _kindFromPath(path),
    project: _text(note['project']),
    date: _text(note['date']),
    tags: _sorted({
      ..._strings(note['tags']),
      ...metadata.tags,
      ..._legacyTags(source),
    }),
    aliases: _sorted(_strings(note['aliases']).toSet()),
    outgoingLinks: _sorted({...metadata.links, ..._legacySources(source)}),
    fileRefs: _sorted(
      metadata.attachments
          .map((item) => item['path']?.toString() ?? '')
          .where((path) => path.isNotEmpty)
          .toSet(),
    ),
    citations: _citations(source),
    dateRefs: [
      ...metadata.dates
          .where((item) => item['date'] != null)
          .map(
            (item) => DateRef(
              date: item['date'].toString(),
              text: _cleanContentText(item['text']),
            ),
          ),
      ..._legacyDates(source),
    ],
    attachments: [
      for (final item in metadata.attachments)
        if (item['path'] != null)
          AttachmentRef(
            path: item['path'].toString(),
            kind: item['kind']?.toString() ?? 'file',
            title: _cleanContentText(item['title']),
          ),
    ],
    properties: (note['properties'] as Map? ?? const {})
        .cast<String, Object?>(),
    fingerprint: fingerprint,
    modifiedMillis: modifiedMillis,
    metadataSource: 'typst-query',
  );
}

NoteRef _fallbackNote(
  String path,
  String source, {
  String? fingerprint,
  int? modifiedMillis,
}) {
  final stem = path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');
  final calls = locateTypstCalls(source);
  final header = _noteHeader(source)?.source ?? '';
  final dateCalls = calls.where((call) => call.name == 'tylog.date-ref');
  final attachmentCalls = calls.where(
    (call) => call.name == 'tylog.attachment',
  );
  return NoteRef(
    id: _field(header, 'id') ?? stem,
    path: path,
    title: _field(header, 'title') ?? stem,
    kind: _field(header, 'kind') ?? _kindFromPath(path),
    project: _field(header, 'project'),
    date: _field(header, 'date'),
    tags: _sorted({
      ..._parseList(header, 'tags'),
      ..._firstArguments(calls, 'tylog.tag'),
      ..._legacyTags(source),
    }),
    aliases: _sorted(_parseList(header, 'aliases').toSet()),
    outgoingLinks: _sorted({
      ..._firstArguments(calls, 'tylog.ref-note'),
      ..._legacySources(source),
    }),
    fileRefs: _sorted({..._firstArguments(calls, 'tylog.attachment')}),
    citations: _citations(source),
    dateRefs: [
      ...dateCalls
          .map(
            (call) => DateRef(
              date: _quoted.firstMatch(call.source)?.group(1) ?? '',
              text: _bracketBody(call.source),
            ),
          )
          .where((item) => item.date.isNotEmpty),
      ..._legacyDates(source),
    ],
    attachments: [
      for (final call in attachmentCalls)
        if (_quoted.firstMatch(call.source)?.group(1) case final path?)
          AttachmentRef(
            path: path,
            kind: _field(call.source, 'kind') ?? 'file',
            title: _bracketBody(call.source),
          ),
    ],
    properties: _parseProperties(header),
    fingerprint: fingerprint,
    modifiedMillis: modifiedMillis,
    metadataSource: 'fallback',
  );
}

List<TaskRef> _taskRefs(String path, List<Map<String, Object?>> values) =>
    values
        .map(
          (value) => TaskRef(
            id: _text(value['id']) ?? '',
            notePath: path,
            text: _text(value['text']) ?? '',
            status: value['status']?.toString() ?? 'todo',
            priority: value['priority']?.toString() ?? 'normal',
            project: _text(value['project']),
            scheduled: _text(value['scheduled']),
            due: _text(value['due']),
            remind: _text(value['remind']),
            timezone: _text(value['timezone']),
            recurrence: _text(value['recurrence']),
            dependencies: _strings(value['dependencies']),
            assignees: _strings(value['assignees']),
            tags: _strings(value['tags']),
            completed: _strings(value['completed']),
            properties: (value['properties'] as Map? ?? const {})
                .cast<String, Object?>(),
          ),
        )
        .toList();

List<TaskRef> _fallbackTasks(String path, List<TypstCall> calls) => calls
    .where((call) => call.name == 'tylog.task')
    .map(
      (call) => TaskRef(
        id: _field(call.source, 'id') ?? '',
        notePath: path,
        text: _field(call.source, 'text') ?? '',
        status: _field(call.source, 'status') ?? 'todo',
        priority: _field(call.source, 'priority') ?? 'normal',
        project: _field(call.source, 'project'),
        scheduled: _field(call.source, 'scheduled'),
        due: _field(call.source, 'due'),
        remind: _field(call.source, 'remind'),
        timezone: _field(call.source, 'timezone'),
        recurrence: _field(call.source, 'recurrence'),
        dependencies: _parseList(call.source, 'dependencies'),
        assignees: _parseList(call.source, 'assignees'),
        tags: _parseList(call.source, 'tags'),
        completed: _parseList(call.source, 'completed'),
      ),
    )
    .where((task) => task.id.isNotEmpty && task.text.isNotEmpty)
    .toList();

String? _field(String source, String name) =>
    RegExp('$name\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"')
        .firstMatch(source)
        ?.group(1)
        ?.replaceAllMapped(RegExp(r'\\(.)'), (match) => match.group(1)!);

final _legacyTagLine = RegExp(r'^\s*tags::\s*(.+)$', multiLine: true);
final _legacyDateLine = RegExp(r'^\s*journal-day::\s*(.+)$', multiLine: true);
final _legacySourceLine = RegExp(r'^\s*source::\s*(.+)$', multiLine: true);
final _wikiLink = RegExp(r'\[\[([^\]]+)\]\]');
final _isoDate = RegExp(r'\d{4}-\d{2}-\d{2}');

/// Recovers date refs from legacy `journal-day:: [[YYYY-MM-DD]]` lines so an
/// imported article still shows up on that day's calendar/timeline.
List<DateRef> _legacyDates(String source) => [
  for (final line in _legacyDateLine.allMatches(source))
    for (final m in _isoDate.allMatches(line.group(1)!))
      DateRef(date: m.group(0)!),
];

/// Recovers `source:: [[origin]]` legacy lines as outgoing links (an article's
/// source entity), so the relationship is not lost.
Set<String> _legacySources(String source) {
  final result = <String>{};
  for (final line in _legacySourceLine.allMatches(source)) {
    final value = line.group(1)!;
    final links = _wikiLink
        .allMatches(value)
        .map((m) => m.group(1)!.trim())
        .where((s) => s.isNotEmpty);
    if (links.isNotEmpty) {
      result.addAll(links);
    } else if (value.trim().isNotEmpty) {
      result.add(value.trim());
    }
  }
  return result;
}

/// Recovers tags from legacy Logseq-style `tags:: [[A]] [[B]]` (or
/// `tags:: A, B`) lines that the Typst parser never sees. Imported articles keep
/// these instead of canonical `tylog.note.with(tags: ...)`, so without this
/// their tags are silently lost and never reach the concept graph.
Set<String> _legacyTags(String source) {
  final result = <String>{};
  for (final line in _legacyTagLine.allMatches(source)) {
    final value = line.group(1)!;
    final links = _wikiLink
        .allMatches(value)
        .map((match) => match.group(1)!.trim())
        .where((tag) => tag.isNotEmpty);
    if (links.isNotEmpty) {
      result.addAll(links);
    } else {
      result.addAll(
        value.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty),
      );
    }
  }
  return result;
}

/// Migrates legacy Logseq `tags:: [[..]]` lines into the canonical note header:
/// merges the recovered tags into `tags: (...)` and strips the legacy lines.
/// Returns the source unchanged if there is nothing to migrate or no `tags:`
/// field to merge into (`source::`/`journal-day::` are left for read-side
/// recovery). Pure and idempotent, so it is safe to re-run.
String migrateLegacyLinks(String source) {
  final legacy = _legacyTags(source);
  if (legacy.isEmpty) return source;
  final header = RegExp(r'tags\s*:\s*\(([^)]*)\)').firstMatch(source);
  if (header == null) return source;
  final existing = _quoted
      .allMatches(header.group(1)!)
      .map((m) => m.group(1)!)
      .toSet();
  final merged = {...existing, ...legacy}.toList()..sort();
  final rendered = 'tags: (${merged.map((t) => '"$t"').join(', ')},)';
  final withTags = source.replaceRange(header.start, header.end, rendered);
  return withTags.replaceAll(
    RegExp(r'^[ \t]*tags::.*(?:\r?\n)?', multiLine: true),
    '',
  );
}

List<String> _parseList(String source, String field) {
  final match = RegExp(
    '$field\\s*:\\s*\\(([^)]*)\\)',
    dotAll: true,
  ).firstMatch(source);
  if (match == null) return const [];
  return _quoted
      .allMatches(match.group(1)!)
      .map((match) => match.group(1)!.replaceAll(r'\"', '"'))
      .toSet()
      .toList();
}

List<String> _firstArguments(List<TypstCall> calls, String name) => calls
    .where((call) => call.name == name)
    .map((call) => _quoted.firstMatch(call.source)?.group(1))
    .whereType<String>()
    .toList();

List<String> _citations(String source) {
  final masked = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (_starts(source, i, '//')) {
      final end = source.indexOf('\n', i);
      masked.write(''.padRight((end < 0 ? source.length : end) - i));
      i = end < 0 ? source.length : end;
    } else if (_starts(source, i, '/*')) {
      final end = _skipBlockComment(source, i);
      masked.write(''.padRight(end - i));
      i = end;
    } else if (source.codeUnitAt(i) == 34) {
      final end = _skipString(source, i);
      masked.write(''.padRight(end - i));
      i = end;
    } else if (source.codeUnitAt(i) == 96) {
      final end = _skipRaw(source, i);
      masked.write(''.padRight(end - i));
      i = end;
    } else if (source.codeUnitAt(i) == 92 && i + 1 < source.length) {
      masked.write('  ');
      i += 2;
    } else {
      masked.writeCharCode(source.codeUnitAt(i++));
    }
  }
  return _sorted(
    RegExp(r'@([A-Za-z0-9_:.+-]+)')
        .allMatches(masked.toString())
        .map((match) => match.group(1)!.replaceFirst(RegExp(r'[.,;:!?]+$'), ''))
        .toSet(),
  );
}

List<String> _targets(List<Object?> values, [String? key]) => _sorted(
  values
      .map(
        (value) => key == null
            ? value
            : value is Map
            ? value[key]
            : value,
      )
      .whereType<Object>()
      .map((value) => value.toString())
      .toSet(),
);

List<Map<String, Object?>> _maps(List<Object?> values) => values
    .whereType<Map>()
    .map((value) => value.cast<String, Object?>())
    .toList();

String _kindFromPath(String path) {
  if (path.startsWith('daily/')) return 'daily';
  if (path.startsWith('projects/')) return 'project';
  if (path.startsWith('articles/')) return 'article';
  return 'note';
}

String? _bracketBody(String source) {
  final start = source.indexOf('[');
  final end = source.lastIndexOf(']');
  if (start < 0 || end <= start) return null;
  return source.substring(start + 1, end).trim();
}

String? _cleanContentText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.startsWith('[') && text.endsWith(']')) {
    return text.substring(1, text.length - 1).trim();
  }
  return text;
}

List<String> _strings(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();

String? _text(Object? value) => value?.toString();

List<String> _sorted(Set<String> values) => values.toList()..sort();

Map<String, List<String>> _setsToSortedLists(Map<String, Set<String>> value) =>
    {
      for (final key in (value.keys.toList()..sort()))
        key: value[key]!.toList()..sort(),
    };

void _add(Map<String, Set<String>> map, String key, String path) {
  if (key.isNotEmpty) map.putIfAbsent(key, () => {}).add(path);
}

LinkResolution _resolveCandidates(String target, Set<String> candidates) {
  final sorted = candidates.toList()..sort();
  if (sorted.length == 1) {
    return LinkResolution(
      target: target,
      status: LinkResolutionStatus.resolved,
      path: sorted.first,
      candidates: sorted,
    );
  }
  return LinkResolution(
    target: target,
    status: LinkResolutionStatus.ambiguous,
    candidates: sorted,
  );
}

int? _balancedEnd(String source, int open) {
  var depth = 0;
  var i = open;
  while (i < source.length) {
    if (_starts(source, i, '//')) {
      i = source.indexOf('\n', i);
      if (i < 0) return null;
      continue;
    }
    if (_starts(source, i, '/*')) {
      i = _skipBlockComment(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 34) {
      i = _skipString(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 96) {
      i = _skipRaw(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 40) depth++;
    if (source.codeUnitAt(i) == 41 && --depth == 0) return i + 1;
    i++;
  }
  return null;
}

int? _balancedContentEnd(String source, int open) {
  var depth = 0;
  var i = open;
  while (i < source.length) {
    if (_starts(source, i, '//')) {
      i = source.indexOf('\n', i);
      if (i < 0) return null;
      continue;
    }
    if (_starts(source, i, '/*')) {
      i = _skipBlockComment(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 34) {
      i = _skipString(source, i);
      continue;
    }
    if (source.codeUnitAt(i) == 91) depth++;
    if (source.codeUnitAt(i) == 93 && --depth == 0) return i + 1;
    i++;
  }
  return null;
}

int _skipString(String source, int start) {
  var i = start + 1;
  while (i < source.length) {
    if (source.codeUnitAt(i) == 92) {
      i += 2;
    } else if (source.codeUnitAt(i++) == 34) {
      break;
    }
  }
  return i;
}

int _skipRaw(String source, int start) {
  var ticks = 1;
  while (start + ticks < source.length &&
      source.codeUnitAt(start + ticks) == 96) {
    ticks++;
  }
  final delimiter = List.filled(ticks, '`').join();
  final end = source.indexOf(delimiter, start + ticks);
  return end < 0 ? source.length : end + ticks;
}

int _skipBlockComment(String source, int start) {
  var depth = 1;
  var i = start + 2;
  while (i < source.length && depth > 0) {
    if (_starts(source, i, '/*')) {
      depth++;
      i += 2;
    } else if (_starts(source, i, '*/')) {
      depth--;
      i += 2;
    } else {
      i++;
    }
  }
  return i;
}

bool _starts(String source, int at, String value) =>
    at + value.length <= source.length && source.startsWith(value, at);

bool _identifier(int code) =>
    code >= 65 && code <= 90 ||
    code >= 97 && code <= 122 ||
    code >= 48 && code <= 57 ||
    code == 45 ||
    code == 95;

bool _space(int code) => code == 9 || code == 10 || code == 13 || code == 32;

String _typstString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

String _typstList(List<String> values) =>
    values.isEmpty ? '()' : '(${values.map(_typstString).join(', ')},)';

String _typstDictionary(Map<String, Object?> values) {
  if (values.isEmpty) return '(:)';
  return '(${values.entries.map((entry) => '${_typstString(entry.key)}: ${_typstValue(entry.value)}').join(', ')},)';
}

String _typstValue(Object? value) => switch (value) {
  null => 'none',
  bool() || num() => value.toString(),
  String() => _typstString(value),
  List() => value.isEmpty ? '()' : '(${value.map(_typstValue).join(', ')},)',
  Map() => _typstDictionary({
    for (final entry in value.entries) entry.key.toString(): entry.value,
  }),
  _ => _typstString(value.toString()),
};
