import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'models.dart';
import 'storage.dart';
import 'values.dart';

part 'scanner/task_mutation.dart';
part 'scanner/header_repair.dart';
part 'scanner/link_resolution.dart';

/// `outdated` is a managed helper stamped with an older package version:
/// still ours (not `custom`), and due for replacement on repair, exactly
/// like `legacy`. Matching by regex rather than an exact version string is
/// what lets a package version bump ship without every existing vault's
/// helper suddenly classifying as `custom`.
enum TylogHelperKind { current, legacy, outdated, custom }

final _packageMarker = RegExp(
  r'^// tylog-package: (\d+\.\d+\.\d+)$',
  multiLine: true,
);

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
  final marker = _packageMarker.firstMatch(normalized);
  if (marker != null) {
    final currentMarker = current == null
        ? null
        : _packageMarker.firstMatch(current);
    if (currentMarker == null || marker[1] == currentMarker[1]) {
      return TylogHelperKind.current;
    }
    return TylogHelperKind.outdated;
  }
  return TylogHelperKind.custom;
}

final _quoted = RegExp(r'"((?:\\.|[^"\\])*)"');
final _typExtension = RegExp(r'\.typ$');

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
    this.problems = const [],
  });

  final Map<String, Object?>? note;
  final List<String> links;
  final List<String> tags;
  final List<Map<String, Object?>> dates;
  final List<Map<String, Object?>> attachments;
  final List<Map<String, Object?>> tasks;
  final List<PkmsProblem> problems;
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

/// An inspector that can hold the scan-wide support files (package, templates,
/// attachments) as persistent state, so the scanner sends them once per scan
/// instead of attaching the same map to every note's [TypstDocumentInput].
/// For the native engine that map crosses the FFI boundary by copy — hundreds
/// of megabytes of assets serialised once per note was the dominant cost of a
/// cold index. A separate interface so CLI/test inspectors stay untouched.
abstract interface class BaseFilesInspector {
  Future<void> setBaseFiles(Map<String, Uint8List> files);
}

/// Upper bound for a single note's metadata query. A pathological document
/// can make the Typst compile spin forever (device-verified: one synced
/// article froze the whole scan, and with it index + search, until app
/// restart); on timeout the note falls back to the source-based scan and a
/// `metadata-query-failed` problem names it.
Duration typstInspectTimeout = const Duration(seconds: 30);

/// Upper bound on how many cached uninspected fallback or legacy notes a
/// single scan re-queries. Re-inspection is a per-note Typst compile (seconds
/// each on device); an uncapped pass over a large backlog pins the CPU for
/// hours and starves sync. Capped, the backlog drains a slice per scan instead.
int maxMetadataReinspectionsPerScan = 50;

/// Upper bound on how many *failed* inspections a single scan retries.
///
/// A `fallback-inspected` note is one the inspector ran on and that threw or
/// timed out. Retrying them all every scan would spend the whole re-inspection
/// budget on known-bad notes and starve the never-inspected ones, so for a long
/// time they were never retried at all — which made a transient engine failure
/// (a wedged worker, an OOM-killed inspect, a timeout under load) permanent
/// until the note was next edited or the index was rebuilt by hand. A small
/// separate slice is the middle: a genuine syntax error costs a handful of
/// compiles per scan forever, and a transient failure clears within a few
/// passes.
///
/// A note whose query *succeeded* and found no managed header is `no-metadata`,
/// not this, and is never retried — the answer cannot change while the bytes do
/// not. That distinction is what keeps the cost bounded in practice: six of the
/// seven fallbacks in the real vault are hand-written dailies.
int maxFailedReinspectionsPerScan = 5;

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
  Iterable<TypstMetadataRecord> records, {
  String path = '',
}) {
  records = records.toList();
  final problems = <PkmsProblem>[];
  for (final record in records) {
    final entity = const {
      '<tylog-note>': 'note',
      '<tylog-link>': 'link',
      '<tylog-tag>': 'tag',
      '<tylog-date>': 'date',
      '<tylog-attachment>': 'attachment',
      '<tylog-task>': 'task',
    }[record.label];
    final value = record.value;
    if (entity == null || value is! Map || !value.containsKey('schema')) {
      continue;
    }
    if (value['schema'] != 1 || value['entity'] != entity) {
      problems.add(
        PkmsProblem(
          code: 'invalid-metadata-envelope',
          severity: PkmsSeverity.error,
          subject: path,
          message:
              'Invalid $entity metadata envelope: schema or entity mismatch.',
        ),
      );
    } else {
      final required = switch (entity) {
        'note' => const ['id', 'title', 'kind'],
        'task' => const ['id', 'text', 'status', 'priority'],
        _ => const <String>[],
      };
      for (final key in required) {
        if (value[key] is String && (value[key] as String).trim().isNotEmpty) {
          continue;
        }
        problems.add(
          PkmsProblem(
            code: 'invalid-metadata-required-field',
            severity: PkmsSeverity.error,
            subject: path,
            message: 'V1 $entity requires a non-empty $key string.',
          ),
        );
      }
    }
  }
  final noteValues = _recordValues(records, '<tylog-note>', 'note');
  return QueriedMetadata(
    problems: problems,
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
      if (value is! Map || !value.containsKey('schema')) return value;
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
    // A backslash escapes the next character, so `\`` is a literal backtick and
    // not the start of a raw span. Without this, one escaped backtick made
    // _skipRaw run to end-of-file looking for a closing pair and every call
    // after it — every task in the note — became invisible to this scanner.
    // The importer escapes freely, so a note only has to contain "->`->" once.
    if (source.codeUnitAt(i) == 92) {
      i += 2;
      continue;
    }
    if (source.startsWith('//', i)) {
      i = source.indexOf('\n', i);
      if (i < 0) break;
      continue;
    }
    if (source.startsWith('/*', i)) {
      i = _skipBlockComment(source, i);
      continue;
    }
    // Deliberately NOT skipping `"` here. This loop walks *markup*, where a
    // quote is ordinary text — only inside a call is it a string delimiter, and
    // _balancedEnd/_locateTopLevelField handle it there. Treating it as a
    // delimiter at this level meant one unpaired quote in prose opened a
    // "string" that closed on the `id: "` of a later call, flipping parity and
    // hiding every task after it: notes/bbc___block1.typ has 12 tasks of which
    // the scanner saw 10, and the two it lost threw "Task not found" on every
    // edit while the UI happily listed them.
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

final _noteHeaderStart = RegExp(r'#show\s*:\s*tylog\.note\.with\s*\(');

TypstCall? _noteHeader(String source) {
  final match = _noteHeaderStart.firstMatch(source);
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

NoteRef scanNote(
  String relativePath,
  String source, {
  String? fingerprint,
  Map<String, String> synonyms = const {},
}) => _fallbackNote(
  relativePath,
  source,
  fingerprint: fingerprint,
  synonyms: synonyms,
);

Future<VaultIndex> scanVaultStorage(
  VaultStorage storage, {
  List<VaultStorageEntry>? entries,
  TypstInspector? inspector,
  VaultIndex? previous,
  VaultIndex? donor,
  Map<String, String> knownHashes = const {},
  Map<String, int>? stageMillis,
  void Function()? onParsed,
  void Function(int tasks)? onDonorReused,
  bool force = false,
  Set<String> stale = const {},
  void Function(int complete, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  stageMillis?['support-files'] = 0;
  stageMillis?['support-publish'] = 0;
  final listing = entries ?? await storage.list(recursive: true);
  final prepareTimer = Stopwatch()..start();
  final stageTimer = Stopwatch()..start();
  final recovered = await _recoverStrandedWrites(storage, listing);
  final recoveryMs = stageTimer.elapsedMilliseconds;
  stageMillis?['recover-writes'] = recoveryMs;
  final files = <VaultStorageEntry>[];
  for (final entity in [...listing, ...recovered]) {
    if (entity.isDirectory || !entity.path.endsWith('.typ')) continue;
    final relative = entity.path;
    if (!_noteRoots.any(relative.startsWith)) {
      continue;
    }
    files.add(entity);
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  Map<String, Uint8List>? inspectionFiles;

  /// Which support paths the vault actually holds, so a note referencing one
  /// it does not can be given a placeholder instead of failing to compile.
  var inspectionKeys = const <String>{};
  // A poisoned note can wedge the inspector's single native worker, so a
  // single timeout only skips its own note (still recorded as a
  // metadata-query-failed problem). After [maxConsecutiveInspectTimeouts]
  // consecutive timeouts the worker is treated as wedged: a recoverable
  // inspector is rebuilt so the rest of the pass keeps querying (a wedged
  // native engine holds its lock forever, so nulling alone would strand the
  // whole tail as fallback); a non-recoverable one drops to the source scan.
  var activeInspector = inspector;
  var reinspected = 0;
  var failedReinspected = 0;
  var consecutiveTimeouts = 0;
  var recoveries = 0;
  var inspectorStopped = false;

  // One read per scan, shared by every note. Absent or unusable is normal and
  // simply means no merges.
  stageTimer.reset();
  final synonyms = await loadTagSynonyms(storage);
  final synonymsMs = stageTimer.elapsedMilliseconds;
  stageMillis?['tag-synonyms'] = synonymsMs;

  // Grouped once. Filtering `previous.tasks` per note made the cached path
  // quadratic — a full pass over every task in the vault, 1700 times.
  final cachedTasks = <String, List<TaskRef>>{};
  for (final task in previous?.tasks ?? const <TaskRef>[]) {
    (cachedTasks[task.notePath] ??= <TaskRef>[]).add(task);
  }

  final donorTasks = <String, List<TaskRef>>{};
  for (final task in donor?.tasks ?? const <TaskRef>[]) {
    (donorTasks[task.notePath] ??= <TaskRef>[]).add(task);
  }

  stageMillis?['scan-prepare'] =
      prepareTimer.elapsedMilliseconds - recoveryMs - synonymsMs;
  final notes = <String, NoteRef>{};
  final tasks = <TaskRef>[];
  final problems = <PkmsProblem>[];
  for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
    if (isCancelled?.call() ?? false) throw const IndexBuildCancelled();
    // The cached branch below returns without awaiting anything, so a warm
    // rebuild would otherwise run every note in one synchronous stretch. On the
    // app's worker isolate that stretch is what starves the port listener, so
    // this is the point at which a cancel sent mid-scan actually gets observed
    // (see `isCancelled` above, and lib/vault_worker.dart). On any caller still
    // scanning inline — the CLI, tests — it is what lets a frame render.
    if (fileIndex % 32 == 0) await Future<void>.delayed(Duration.zero);
    final file = files[fileIndex];
    final relative = file.path;
    final fingerprint =
        '${file.modified?.millisecondsSinceEpoch ?? 0}:${file.size ?? 0}';
    final local = previous?.notesByPath[relative];
    // A donor must not replace a current local derivation on every scan.
    final localCurrent =
        !force &&
        !stale.contains(relative) &&
        previous?.version == kVaultIndexVersion &&
        local?.metadataSource == 'typst-query' &&
        local?.fingerprint == fingerprint &&
        (knownHashes[relative] == null ||
            knownHashes[relative] == local?.contentHash);
    final donatedNote = localCurrent ? null : donor?.notesByPath[relative];
    final donorHash = donatedNote?.contentHash == null
        ? null
        : knownHashes[relative] ?? await storage.hash(relative);
    final donated = donorHash != null && donorHash == donatedNote!.contentHash;
    final cachedIndex = donated ? donor : previous;
    final cached = cachedIndex?.notesByPath[relative];
    // [stale] carries the paths this process just wrote. SAF reports mtime at
    // second granularity, so a same-size edit inside the same second as the
    // previous scan looks unchanged to both gates below — a writer must never
    // depend on the clock to be seen.
    final reusable =
        (!force || donated) &&
        cachedIndex?.version == kVaultIndexVersion &&
        cached != null &&
        (donated || !stale.contains(relative));
    // An entry from an older index version whose *query* half is current: the
    // derivation moved, not the expensive part. Re-derived below against the
    // note's bytes instead of recompiling it. This is the difference between a
    // schema bump costing a file read per note and costing 14 minutes of Typst.
    final rederivable =
        (!force || donated) &&
        !reusable &&
        cached?.queryFacts != null &&
        cachedIndex?.queryVersion == kVaultQueryVersion &&
        (donated || !stale.contains(relative));

    // Does the cached entry still describe the bytes on disk? mtime+size is
    // the cheap answer, but it is device-local — SAF and APFS stamp the same
    // bytes differently — so an index seeded from another device misses on
    // every note. Falling back to the content hash costs one streamed read
    // and saves a Typst query, which is orders of magnitude more expensive.
    String? contentHash;
    var matchesDisk = false;
    if ((reusable || rederivable) && cached != null) {
      if (donorHash == null && cached.fingerprint == fingerprint) {
        matchesDisk = true;
      } else if (cached.contentHash != null) {
        contentHash =
            donorHash ?? knownHashes[relative] ?? await storage.hash(relative);
        matchesDisk = contentHash == cached.contentHash;
      }
    }

    // A cached uninspected fallback (dead inspector before this note) or legacy
    // note is re-queried when an inspector is available so it can upgrade to
    // real metadata and drop its metadata-fallback problem — but only up to
    // [maxMetadataReinspectionsPerScan] per pass: each re-query is a Typst
    // compile, and an uncapped backlog pins the device CPU for hours. Only
    // otherwise-reusable notes count against the cap; a genuinely changed note
    // is re-read regardless, so charging it here would starve the upgrades.
    //
    // A note the inspector already failed on ('fallback-inspected') is retried
    // too, but out of its own much smaller slice — see
    // [maxFailedReinspectionsPerScan]. Both draw on the same overall cap, so
    // the worst case per scan is unchanged.
    final retryFailed =
        matchesDisk &&
        !donated &&
        cached!.metadataSource == 'fallback-inspected' &&
        activeInspector != null &&
        failedReinspected < maxFailedReinspectionsPerScan &&
        reinspected < maxMetadataReinspectionsPerScan;
    final reinspect =
        retryFailed ||
        (matchesDisk &&
            !donated &&
            (cached!.metadataSource == 'fallback' ||
                cached.metadataSource == 'legacy') &&
            activeInspector != null &&
            reinspected < maxMetadataReinspectionsPerScan);
    if (retryFailed) failedReinspected++;
    if (reinspect) reinspected++;

    if (matchesDisk && !reinspect && rederivable) {
      // The bytes still match the queried half, so only the derivation is
      // stale. Reading the file is the whole cost; falls through to a full
      // inspection if the entry turns out to have nothing to re-derive from.
      final rederived = rederiveNote(
        cached!,
        utf8.decode(await storage.readBytes(relative)),
        fingerprint,
        file.modified?.millisecondsSinceEpoch ?? 0,
        synonyms,
      );
      if (rederived != null) {
        problems.addAll(
          cachedIndex!.problems.where(
            (p) =>
                p.subject == relative && p.code.startsWith('invalid-metadata-'),
          ),
        );
        notes[relative] = rederived;
        final reusedTasks = donated
            ? donorTasks[relative] ?? const <TaskRef>[]
            : cachedTasks[relative] ?? const <TaskRef>[];
        tasks.addAll(reusedTasks);
        if (donated) onDonorReused?.call(reusedTasks.length);
        onProgress?.call(fileIndex + 1, files.length);
        continue;
      }
    } else if (matchesDisk && !reinspect) {
      // Re-stamp the cheap gate so the next scan on this device short-circuits
      // without hashing again.
      //
      // Reuse is safe here whatever the query version says: a matching
      // *index* version means these derived fields came from the current
      // derivation rules. What is not safe is carrying their queryFacts
      // forward — those came from a query we cannot vouch for, and the built
      // index is stamped with the current query version, so keeping them would
      // launder stale facts into this device's own index and out to every peer
      // through the donor. Dropping them only costs that note its
      // re-derivability until it is next inspected.
      problems.addAll(
        cachedIndex!.problems.where(
          (p) =>
              p.subject == relative && p.code.startsWith('invalid-metadata-'),
        ),
      );
      final trustFacts = cachedIndex.queryVersion == kVaultQueryVersion;
      notes[relative] = cached!.fingerprint == fingerprint && trustFacts
          ? cached
          : cached.copyWith(
              fingerprint: fingerprint,
              clearQueryFacts: !trustFacts,
            );
      final reusedTasks = donated
          ? donorTasks[relative] ?? const <TaskRef>[]
          : cachedTasks[relative] ?? const <TaskRef>[];
      tasks.addAll(reusedTasks);
      if (donated) onDonorReused?.call(reusedTasks.length);
      if (cached.metadataSource != 'typst-query') {
        problems.add(_fallbackProblem(relative));
      }
      onProgress?.call(fileIndex + 1, files.length);
      continue;
    }
    // One read, not two. `readText` followed by `storage.hash` meant two full
    // SAF round trips per note; the bytes needed for both are the same bytes.
    // Byte-compatible with storage.hash: LocalVaultStorage and SafBridge both
    // emit lowercase-hex sha256, so cached hashes still match.
    onParsed?.call();
    final bytes = await storage.readBytes(relative);
    final source = utf8.decode(bytes);
    // Always from *these* bytes, never the earlier probe hash. Reaching here
    // means that probe did not match, so it describes a version of the file we
    // are not about to index — and two SAF round trips is plenty of room for
    // an autosave to land between them. Keeping it stamped an entry with one
    // version's identity and another version's metadata: it then passed every
    // later check, was never re-inspected, and went to peers through the donor
    // as authoritative, since donors match on exactly this hash.
    contentHash = sha256.convert(bytes).toString();
    if (inspectionFiles == null) {
      if (activeInspector == null) {
        inspectionFiles = const <String, Uint8List>{};
      } else {
        final supportTimer = Stopwatch()..start();
        final shared = await _inspectionFiles(storage, entries: entries);
        stageMillis?['support-files'] = supportTimer.elapsedMilliseconds;
        supportTimer.reset();
        inspectionKeys = shared.keys.toSet();
        final inspector = activeInspector;
        if (inspector is BaseFilesInspector) {
          try {
            await (inspector as BaseFilesInspector).setBaseFiles(shared);
            // Base layer installed engine-side; notes carry no files.
            inspectionFiles = const <String, Uint8List>{};
          } catch (_) {
            // Handoff failed: fall back to shipping the map per note.
            inspectionFiles = shared;
          }
        } else {
          inspectionFiles = shared;
        }
        stageMillis?['support-publish'] = supportTimer.elapsedMilliseconds;
      }
    }
    var inspectionAttempted = false;
    try {
      QueriedMetadata? queried;
      if (activeInspector != null) {
        inspectionAttempted = true;
        queried = decodeTylogMetadataRecords(
          await activeInspector
              .inspect(
                TypstDocumentInput(
                  path: relative,
                  source: source,
                  files: _withMissingImages(
                    inspectionFiles,
                    source: source,
                    notePath: relative,
                    available: inspectionKeys,
                  ),
                ),
              )
              .timeout(typstInspectTimeout),
          path: relative,
        );
        problems.addAll(queried.problems);
      }
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
              synonyms: synonyms,
              // The query *succeeded* and the file simply carries no managed
              // header — six of the seven such notes in the real vault are
              // hand-written dailies. That is a stable fact about these bytes,
              // not a failure, so it must not share a marker with one: the
              // retry below would recompile them every scan forever for an
              // answer that cannot change.
              metadataSource: inspectionAttempted ? 'no-metadata' : 'fallback',
            )
          : _queriedNote(
              relative,
              source,
              queried!,
              fingerprint,
              file.modified?.millisecondsSinceEpoch ?? 0,
              synonyms,
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
        if (activeInspector == null && !inspectorStopped) {
          inspectorStopped = true;
          // Without this the death is invisible: every note scanned after
          // this point silently degrades to metadata-fallback, whose fix
          // string blames the note's header — the wrong culprit.
          problems.add(
            PkmsProblem(
              code: 'typst-engine-stopped',
              severity: PkmsSeverity.warning,
              subject: relative,
              message:
                  'Typst stopped responding during the scan; later notes '
                  'fell back to legacy parsing.',
              fix:
                  'Repair the notes that failed to read, then rebuild the '
                  'index.',
            ),
          );
        }
      }
      final fallback = _fallbackNote(
        relative,
        source,
        fingerprint: fingerprint,
        modifiedMillis: file.modified?.millisecondsSinceEpoch ?? 0,
        synonyms: synonyms,
        metadataSource: inspectionAttempted ? 'fallback-inspected' : 'fallback',
      );
      // Keeping the cached note is right for a *transient* inspect failure: a
      // previously-queried note should not be downgraded to a worse source
      // parse just because Typst hiccuped. But only when the cache is still
      // valid. On a schema bump or a forced rebuild the cached entry was
      // derived by rules that no longer apply — it kept pre-merge tags through
      // two version bumps, which quietly un-clustered the notes that carried
      // them.
      //
      // And only when the bytes are the ones it was derived from. Without
      // `matchesDisk` this branch kept metadata describing the *old* content
      // and then stamped it with the new file's fingerprint and content hash
      // below — an entry that describes one version of a note while claiming
      // to be another. It passed every later check, was never re-inspected,
      // and went out to peers through the donor as authoritative. When the
      // bytes really did change, the source-parsed fallback at least describes
      // what is actually in the file, and its 'fallback-inspected' source marks
      // it for another attempt — [maxFailedReinspectionsPerScan] of them per
      // scan, so a wedged worker costs a few passes rather than being final.
      notes[relative] =
          (reusable && matchesDisk && cached.metadataSource == 'typst-query'
              ? cached.copyWith(fingerprint: fingerprint)
              : null) ??
          fallback;
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
    // Stamped once here rather than threaded through _queriedNote and
    // _fallbackNote: every branch above has just parsed exactly these bytes.
    notes[relative] = notes[relative]!.copyWith(contentHash: contentHash);
    onProgress?.call(fileIndex + 1, files.length);
  }
  stageTimer.reset();
  final index = _buildVaultIndex(notes, problems: problems, tasks: tasks);
  stageMillis?['scan-finalize'] = stageTimer.elapsedMilliseconds;
  return index;
}

const _noteRoots = [
  'daily/',
  'notes/',
  'projects/',
  'articles/',
  'screenshots/',
];

/// The hidden temp/backup copies of the Android SAF atomic write
/// (`.<name>.tylog-<nonce>.tmp` / `.backup`).
final _strandedWrite = RegExp(r'^\.(.+)\.tylog-\d+\.(tmp|backup)$');

/// An interrupted SAF atomic write (process death mid-commit, flaky
/// DocumentsProvider) can strand its hidden copy with the real note gone —
/// the "phantom-deleted note" class: the note silently vanishes while its
/// full content sits in an invisible dotfile next to it. Restore the copy
/// when the target is missing; drop it as dead bytes when the target
/// survived. Best-effort per file: a failure leaves the stray for the next
/// scan.
Future<List<VaultStorageEntry>> _recoverStrandedWrites(
  VaultStorage storage,
  List<VaultStorageEntry> listing,
) async {
  final present = {
    for (final entry in listing)
      if (!entry.isDirectory) entry.path,
  };
  final restored = <VaultStorageEntry>[];
  for (final entry in listing) {
    if (entry.isDirectory) continue;
    final slash = entry.path.lastIndexOf('/');
    final dir = slash < 0 ? '' : entry.path.substring(0, slash + 1);
    final match = _strandedWrite.firstMatch(entry.path.substring(dir.length));
    if (match == null) continue;
    final target = '$dir${match.group(1)!}';
    try {
      if (!present.contains(target) && !await storage.exists(target)) {
        await storage.writeBytes(target, await storage.readBytes(entry.path));
        final stat = await storage.stat(target);
        if (stat != null) restored.add(stat);
      }
      await storage.delete(entry.path);
    } catch (_) {
      // Recovery must never break the scan it rides on.
    }
  }
  return restored;
}

Future<Map<String, Uint8List>> _inspectionFiles(
  VaultStorage storage, {
  List<VaultStorageEntry>? entries,
}) async {
  final files = <String, Uint8List>{};
  for (final entry in entries ?? await storage.list(recursive: true)) {
    if (entry.isDirectory ||
        _strandedWrite.hasMatch(entry.path.split('/').last) ||
        entry.path.startsWith('_index/') ||
        // TylogVaultPaths.indexDonors — index caches, not compile inputs, and
        // megabytes each. Held twice in this map, they are the same
        // whole-vault-in-RAM stall the note filter below exists to prevent.
        entry.path.startsWith('_system/index/') ||
        // Revision envelopes: sync bookkeeping no note can name (the file is
        // a content hash). 352 of the 390 files read here on the real vault,
        // 6-8 s of every changed pass on an A24.
        entry.path.startsWith('_system/revisions/') ||
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
    // One key, not two. The Rust side resolves via `get_without_slash()`
    // (rust/src/api/typst.rs vfs_key), so the '/'-prefixed duplicate was never
    // looked up — but flutter_rust_bridge serialises the whole map
    // synchronously on this isolate for *every* note, so it was copying the
    // vault's assets twice per inspect.
    //
    // Images travel as valid same-format 1×1 placeholders instead of their
    // real bytes: a metadata query only needs `#image()` to *resolve* (a
    // missing file is a compile error that silently degrades the note to the
    // fallback parser), and the metadata records it reads are
    // layout-independent, so fake dimensions change nothing. The real bytes —
    // 850 MB of them on the live vault — held twice (Dart map + engine VFS)
    // OOM-killed the app on device, and reading them through SAF was a
    // minute of stall before the first query could run.
    files[entry.path] =
        imagePlaceholder(entry.path) ?? await storage.readBytes(entry.path);
  }
  return files;
}

/// [base] plus placeholders for whatever images [source] references and the
/// vault lacks. Returns [base] itself when nothing is missing, so the common
/// case still ships the const-empty map the base-layer handoff installs.
Map<String, Uint8List> _withMissingImages(
  Map<String, Uint8List> base, {
  required String source,
  required String notePath,
  required Set<String> available,
}) {
  final missing = missingImagePlaceholders(
    source: source,
    notePath: notePath,
    available: available,
  );
  if (missing.isEmpty) return base;
  return <String, Uint8List>{...base, ...missing};
}

/// Placeholders for image paths a note *references* but the vault does not
/// hold yet.
///
/// [imagePlaceholder] only substitutes files that are present in the listing.
/// A note whose `#image("/assets/…")` target has not synced yet is a different
/// case and the one that actually bites: the compile fails outright, so the
/// note degrades to the source-based fallback parser and loses its metadata.
/// On the A24 mid-sync that was 432 of 4,225 notes (10%) against the
/// fully-synced P30's 18 (0.35%) — the fallback was measuring sync progress,
/// not note quality.
///
/// Supplying a 1×1 image lets the metadata query run; it cannot mask a real
/// problem, because a genuinely missing attachment is reported independently
/// by `validatePkms` as `missing-attachment`.
///
/// Typst resolves a leading-slash path from the vault root and anything else
/// relative to the containing file, which is why [notePath] is needed. A key
/// guessed wrong simply goes unused — the note falls back exactly as it does
/// today.
Map<String, Uint8List> missingImagePlaceholders({
  required String source,
  required String notePath,
  required Set<String> available,
}) {
  var files = const <String, Uint8List>{};
  for (final match in _imageRefPattern.allMatches(source)) {
    final raw = match.group(1)!;
    if (raw.isEmpty || raw.contains(r'\')) continue;
    final key = _resolveVfsKey(raw, notePath);
    if (key == null || available.contains(key) || files.containsKey(key)) {
      continue;
    }
    final placeholder = imagePlaceholder(key);
    if (placeholder == null) continue;
    if (files.isEmpty) files = <String, Uint8List>{};
    files[key] = placeholder;
  }
  return files;
}

/// `image("…")`, with or without a leading `#`, and inside `figure(image(…))`.
final RegExp _imageRefPattern = RegExp(r'\bimage\s*\(\s*"([^"\\]*)"');

/// Vault-relative VFS key for a Typst path reference, mirroring the Rust
/// side's `get_without_slash` normalisation. Null if it escapes the root.
String? _resolveVfsKey(String reference, String notePath) {
  if (reference.startsWith('/')) return reference.substring(1);
  final dir = notePath.contains('/')
      ? notePath.substring(0, notePath.lastIndexOf('/'))
      : '';
  final segments = <String>[...dir.split('/').where((s) => s.isNotEmpty)];
  for (final segment in reference.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isEmpty) return null;
      segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.isEmpty ? null : segments.join('/');
}

/// A minimal valid image of the same format as [path], or null for non-image
/// files (data files a note may `read()`/`csv()` keep their real bytes).
Uint8List? imagePlaceholder(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (path.substring(dot + 1).toLowerCase()) {
    'png' => _placeholderPng,
    'jpg' || 'jpeg' => _placeholderJpeg,
    'gif' => _placeholderGif,
    'svg' => _placeholderSvg,
    // 598 files / 38.6 MB of the real vault's 50.4 MB inspect payload. Missing
    // it meant every changed note still pulled all of them through SAF and
    // held them twice. Typst 0.15 decodes webp (verified against the CLI).
    'webp' => _placeholderWebp,
    _ => null,
  };
}

// 1×1 valid images (CRCs intact — Typst decodes them for size).
final Uint8List _placeholderPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGP4DwABAQEAsTj2FAAAAABJRU5ErkJggg==',
);
final Uint8List _placeholderJpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVN//2Q==',
);
final Uint8List _placeholderGif = base64Decode(
  'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
);

/// 1x1 lossless WebP (VP8L).
final Uint8List _placeholderWebp = base64Decode(
  'UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==',
);

final Uint8List _placeholderSvg = Uint8List.fromList(
  utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>'),
);

PkmsProblem _fallbackProblem(String path) => PkmsProblem(
  code: 'metadata-fallback',
  severity: PkmsSeverity.warning,
  subject: path,
  message: 'Typst metadata was unavailable; using legacy parsing.',
  fix: 'Convert this note to the managed metadata header.',
);

VaultIndex _buildVaultIndex(
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
      // External URLs recorded as outgoing links by older scans (the
      // pre-fix _legacySources fallthrough) still sit in the note cache;
      // skipping them here clears the phantom broken-link problems without
      // forcing a full index-version rebuild.
      if (target.contains('://')) continue;
      final resolved = resolver.resolve(target);
      if (resolved.status == LinkResolutionStatus.resolved) {
        backlinks.putIfAbsent(resolved.path!, () => {}).add(source.path);
      } else if (target.contains(r'\[') || _domainLike.hasMatch(target)) {
        // Domain-like targets (`3dnews.ru`) are legacy source-entity refs to
        // websites — external references, not missing notes; they resolve to
        // a backlink above when a matching entity note exists, and stay
        // silent otherwise. `\[` covers raw escaped-garbage targets from
        // pre-fix caches. ponytail: a genuinely missing note titled like a
        // domain (`Node.js`) is also silenced; revisit if that ever bites.
        continue;
      } else {
        allProblems.add(
          PkmsProblem(
            code: resolved.status == LinkResolutionStatus.ambiguous
                ? 'ambiguous-link'
                : 'broken-link',
            severity: PkmsSeverity.warning,
            subject: source.path,
            // The Problems screen parses the target back out of this string
            // (unresolvedLinkTargets) to offer bulk page creation — keep the
            // `<status> link: <target>` shape.
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

String _screenshotDescription(String source) {
  final heading = RegExp(
    r'^=+\s+Description\s*\r?$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(source);
  if (heading == null) return '';
  final body = source.substring(heading.end);
  final nextHeading = RegExp(r'^=+\s+', multiLine: true).firstMatch(body);
  return unescapeMarkup(body.substring(0, nextHeading?.start)).trim();
}

NoteRef _queriedNote(
  String path,
  String source,
  QueriedMetadata metadata,
  String fingerprint,
  int modifiedMillis, [
  Map<String, String> synonyms = const {},
]) {
  final note = metadata.note!;
  final stem = path.split('/').last.replaceFirst(_typExtension, '');
  final kind = _text(note['kind']) ?? _kindFromPath(path);
  return NoteRef(
    id: _text(note['id']) ?? '',
    path: path,
    title: _text(note['title']) ?? stem,
    kind: kind,
    screenshotDescription: kind == 'screenshot'
        ? _screenshotDescription(source)
        : '',
    project: _text(note['project']),
    date: _text(note['date']) ?? _dailyDateFromPath(kind, path),
    tags: _normalizedTags({
      ...stringList(note['tags']),
      ...metadata.tags,
      ..._legacyTags(source),
      ..._kindTag(kind),
    }, synonyms),
    aliases: _sorted(stringList(note['aliases']).toSet()),
    outgoingLinks: _sorted({
      ...metadata.links,
      ..._legacySources(source),
      ..._wikiLinkTargets(source),
    }),
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
            path: item['path'].toString().replaceFirst(RegExp(r'^/'), ''),
            kind: item['kind']?.toString() ?? 'file',
            title: _cleanContentText(item['title']),
          ),
    ],
    properties: (note['properties'] as Map? ?? const {})
        .cast<String, Object?>(),
    fingerprint: fingerprint,
    modifiedMillis: modifiedMillis,
    metadataSource: 'typst-query',
    queryFacts: {
      'tags': _sorted({...stringList(note['tags']), ...metadata.tags}),
      'links': _sorted(metadata.links.toSet()),
      'dates': metadata.dates,
    },
  );
}

/// Rebuilds a cached note's derived fields against its current bytes, without
/// a Typst compile.
///
/// This is what makes a derive-only version bump cheap. Everything here is a
/// pure function of the queried half ([NoteRef.queryFacts]) plus the source and
/// the synonym map — exactly the inputs [_queriedNote] uses — so the result is
/// identical to what a full re-inspection would produce, for a file read
/// instead of seconds of compiling.
///
/// Returns null when the entry predates index version 10 and so has no facts to
/// re-derive from; that note has to be inspected the old way.
NoteRef? rederiveNote(
  NoteRef cached,
  String source,
  String fingerprint,
  int modifiedMillis, [
  Map<String, String> synonyms = const {},
]) {
  final facts = cached.queryFacts;
  if (facts == null) return null;
  final queriedDates = (facts['dates'] as List? ?? const [])
      .cast<Map>()
      .map((item) => item.cast<String, Object?>())
      .toList();
  return cached.copyWith(
    screenshotDescription: cached.kind == 'screenshot'
        ? _screenshotDescription(source)
        : '',
    tags: _normalizedTags({
      ...stringList(facts['tags']),
      ..._legacyTags(source),
      ..._kindTag(cached.kind),
    }, synonyms),
    outgoingLinks: _sorted({
      ...stringList(facts['links']),
      ..._legacySources(source),
      ..._wikiLinkTargets(source),
    }),
    citations: _citations(source),
    dateRefs: [
      ...queriedDates
          .where((item) => item['date'] != null)
          .map(
            (item) => DateRef(
              date: item['date'].toString(),
              text: _cleanContentText(item['text']),
            ),
          ),
      ..._legacyDates(source),
    ],
    date: cached.date ?? _dailyDateFromPath(cached.kind, cached.path),
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
  Map<String, String> synonyms = const {},
  String metadataSource = 'fallback',
}) {
  final stem = path.split('/').last.replaceFirst(_typExtension, '');
  final calls = locateTypstCalls(source);
  final header = _noteHeader(source)?.source ?? '';
  final dateCalls = calls.where((call) => call.name == 'tylog.date-ref');
  final attachmentCalls = calls.where(
    (call) => call.name == 'tylog.attachment',
  );
  final kind = _field(header, 'kind') ?? _kindFromPath(path);
  return NoteRef(
    id: _field(header, 'id') ?? stem,
    path: path,
    title: _field(header, 'title') ?? stem,
    kind: kind,
    screenshotDescription: kind == 'screenshot'
        ? _screenshotDescription(source)
        : '',
    project: _field(header, 'project'),
    date: _field(header, 'date') ?? _dailyDateFromPath(kind, path),
    tags: _normalizedTags({
      ..._parseList(header, 'tags'),
      ..._firstArguments(calls, 'tylog.tag'),
      ..._legacyTags(source),
      ..._kindTag(kind),
    }, synonyms),
    aliases: _sorted(_parseList(header, 'aliases').toSet()),
    outgoingLinks: _sorted({
      ..._firstArguments(calls, 'tylog.ref-note'),
      ..._legacySources(source),
      ..._wikiLinkTargets(source),
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
            path: path.replaceFirst(RegExp(r'^/'), ''),
            kind: _field(call.source, 'kind') ?? 'file',
            title: _bracketBody(call.source),
          ),
    ],
    properties: _parseProperties(header),
    fingerprint: fingerprint,
    modifiedMillis: modifiedMillis,
    metadataSource: metadataSource,
  );
}

/// `clocked` as it arrives from `typst query`: an array of two-element arrays,
/// with `none` decoding to null. Deliberately not [stringList] — that calls
/// `toString()` on each element and would yield the literal
/// `"[2025-12-25T12:33:43, null]"` for every session.
List<ClockEntry> _clockedFromMetadata(Object? value) {
  if (value is! List) return const [];
  final entries = <ClockEntry>[];
  for (final pair in value) {
    if (pair is! List || pair.isEmpty) continue;
    final start = pair.first;
    if (start is! String || start.isEmpty) continue;
    final end = pair.length > 1 ? pair[1] : null;
    entries.add(ClockEntry(start: start, end: end is String ? end : null));
  }
  return entries;
}

/// `clocked` read straight from the call source, for notes whose Typst
/// metadata was unavailable — 399 of them in a real vault, so this path is not
/// an edge case.
///
/// Built on [_locateTopLevelField] rather than `_parseList`. That helper's
/// `([^)]*)` stops at the first inner `)`, so for
/// `clocked: (("a", "b"), ("c", none),)` it captures only `("a", "b"` and every
/// session after the first vanishes with no error; its `.toSet()` would destroy
/// the pairing on top of that.
List<ClockEntry> parseClockedField(String callSource) {
  // `properties: ("clocked": (...))` is where it lives; a bare top-level
  // `clocked:` is the shape written before it moved, still read so notes
  // authored in between keep their time.
  final properties = _locateTopLevelField(callSource, 'properties');
  String? value;
  if (properties != null) {
    final dict = callSource.substring(
      properties.valueStart,
      properties.valueEnd,
    );
    final entry = _locateDictEntry(dict, 'clocked');
    if (entry != null) {
      value = dict.substring(entry.valueStart, entry.end).trim();
    }
  }
  if (value == null) {
    final field = _locateTopLevelField(callSource, 'clocked');
    if (field == null) return const [];
    value = callSource.substring(field.valueStart, field.valueEnd);
  }
  final entries = <ClockEntry>[];
  var depth = 0;
  var groupStart = -1;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == '"') {
      i = _skipString(value, i) - 1;
      continue;
    }
    if (char == '(') {
      if (depth == 1) groupStart = i;
      depth++;
      continue;
    }
    if (char == ')') {
      depth--;
      if (depth == 1 && groupStart >= 0) {
        final entry = _clockPair(value.substring(groupStart + 1, i));
        if (entry != null) entries.add(entry);
        groupStart = -1;
      }
    }
  }
  return entries;
}

/// `"2025-12-25T12:33:43", none` — the inside of one `clocked` pair.
ClockEntry? _clockPair(String group) {
  final quoted = RegExp(r'"((?:\\.|[^"])*)"').allMatches(group).toList();
  if (quoted.isEmpty) return null;
  final start = quoted.first.group(1)!;
  if (start.isEmpty) return null;
  return ClockEntry(
    start: start,
    end: quoted.length > 1 ? quoted[1].group(1) : null,
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
            dependencies: stringList(value['dependencies']),
            assignees: stringList(value['assignees']),
            tags: stringList(value['tags']),
            completed: stringList(value['completed']),
            clocked: _clockedFromMetadata(
              (value['properties'] as Map?)?['clocked'] ?? value['clocked'],
            ),
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
        clocked: parseClockedField(call.source),
        properties: _parseProperties(call.source),
      ),
    )
    .where((task) => task.id.isNotEmpty && task.text.isNotEmpty)
    .toList();

/// Patterns are keyed by field name rather than hoisted, because the pattern
/// depends on the name. _field runs ~6 times per note and ~10 times per task,
/// and compiling a RegExp each time is not free.
final _fieldPatterns = <String, RegExp>{};
final _escapedChar = RegExp(r'\\(.)');

String? _field(String source, String name) =>
    (_fieldPatterns[name] ??= RegExp('$name\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"'))
        .firstMatch(source)
        ?.group(1)
        ?.replaceAllMapped(_escapedChar, (match) => match.group(1)!);

/// A bare domain, optionally with a path — the shape of legacy
/// `source:: [[site.tld]]` entity references.
final _domainLike = RegExp(r'^[\w-]+(\.[\w-]+)+(/\S*)?$');

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

/// Literal `[[Title]]` / `[[Title|shown]]` wikilinks left in note text (typed
/// out fully, so the editor popup never converted them). Indexed as ordinary
/// outgoing links so backlinks, the graph, and dangling-link triage see them —
/// the same exposure the linked-references excerpt matcher already accepts.
/// Index-only: the note's text keeps its literal brackets.
Set<String> _wikiLinkTargets(String source) => {
  for (final match in _wikiLink.allMatches(source))
    match.group(1)!.split('|').first.trim(),
}..remove('');

/// Recovers `source:: [[origin]]` legacy lines as outgoing links (an article's
/// source entity), so the relationship is not lost.
Set<String> _legacySources(String source) {
  final result = <String>{};
  for (final line in _legacySourceLine.allMatches(source)) {
    // The importer escapes Typst markup in body text, so a Logseq
    // `source:: [[habr.com]]` arrives as `source:: \[\[habr.com\]\]` —
    // unescape first or the wiki link never matches (same treatment as
    // _legacyTags).
    final value = unescapeMarkup(line.group(1)!);
    final links = _wikiLink
        .allMatches(value)
        .map((m) => m.group(1)!.trim())
        .where((s) => s.isNotEmpty);
    if (links.isNotEmpty) {
      result.addAll(links);
    } else if (value.trim().isNotEmpty && !value.contains('://')) {
      // A bare URL or an autolinked `#link("https://…")[…]` is an external
      // reference, not a note id — registering it as an outgoing link just
      // manufactures an unresolvable broken-link problem per article.
      result.add(value.trim());
    }
  }
  return result;
}

/// Undoes `tylog_import_core`'s markup escaping.
///
/// The importer escapes Typst's special characters when it writes body text, so
/// a recovered `tags::` line arrives as `\#Python \#разработка`. Left in place
/// the backslashes become part of the tag and it matches nothing.
String unescapeMarkup(String value) =>
    value.replaceAllMapped(RegExp(r'\\([\\#$*_`<>@\[\]~=\-+/])'), (m) => m[1]!);

/// Recovers tags from legacy Logseq-style `tags::` lines that the Typst parser
/// never sees. Imported articles keep these instead of canonical
/// `tylog.note.with(tags: ...)`, so without this their tags are silently lost
/// and never reach the concept graph.
///
/// Three forms, in the order Logseq actually emits them:
/// `tags:: [[A]] [[B]]`, `tags:: #A #B`, and `tags:: A, B`.
Set<String> _legacyTags(String source) {
  final result = <String>{};
  for (final line in _legacyTagLine.allMatches(source)) {
    final value = unescapeMarkup(line.group(1)!);
    final links = _wikiLink
        .allMatches(value)
        .map((match) => match.group(1)!.trim())
        .where((tag) => tag.isNotEmpty);
    if (links.isNotEmpty) {
      result.addAll(links);
      continue;
    }
    if (value.trimLeft().startsWith('#')) {
      // Split on the '#' delimiter, not on whitespace: Logseq tags may contain
      // spaces, so `#библиотеки Python #разработка` is two tags, not three.
      result.addAll(
        value
            .split('#')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty),
      );
      continue;
    }
    result.addAll(
      value.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty),
    );
  }
  return result;
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
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      masked.write(''.padRight((end < 0 ? source.length : end) - i));
      i = end < 0 ? source.length : end;
    } else if (source.startsWith('/*', i)) {
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
  if (path.startsWith('screenshots/')) return 'screenshot';
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

String? _text(Object? value) => value?.toString();

List<String> _sorted(Set<String> values) => values.toList()..sort();

/// Tags, folded to one canonical spelling before they are indexed.
///
/// Tags are compared by exact string everywhere downstream — promotion into a
/// concept, community assignment, the shelf's group-by-cluster — so `AI` and
/// `ai` used to be two unrelated concepts that each fell short of the promotion
/// threshold. [synonyms] extends that to spellings a string comparison cannot
/// reconcile: `искусственный-интеллект` and `ии` are the same concept as `ai`.
///
/// Index-only, both of them: the note's own text is never rewritten, so undoing
/// a bad merge means editing the synonym file, not hundreds of notes.
/// The ISO day a `daily/YYYY/MM/YYYY-MM-DD.typ` note is for, when its header
/// omits `date:`.
///
/// Index-only, like the tag aliases: the note's own text is never rewritten.
/// Without it such a note is invisible on the calendar (which requires a date)
/// and sorts *above* every dated note in the journal feed, because the feed
/// falls back to the path as its key and `daily/…` sorts above `2026-…`
/// descending — five notes on the real vault put today six entries down.
String? _dailyDateFromPath(String kind, String path) {
  if (kind != 'daily') return null;
  final match = _dailyPathDay.firstMatch(path);
  return match?.group(1);
}

final _dailyPathDay = RegExp(r'(\d{4}-\d{2}-\d{2})\.typ$');

/// The kind→tag alias (plan: "Kinds become tags"): non-default kinds join the
/// note's tags so the existing tag filters slice by article/person/daily with
/// no UI changes. Index-only — like tag synonyms, the note's text is never
/// rewritten. The default `note` is not aliased: a mega-tag carried by every
/// plain note filters nothing.
Iterable<String> _kindTag(String kind) => kind == 'note' ? const [] : [kind];

List<String> _normalizedTags(
  Set<String> values, [
  Map<String, String> synonyms = const {},
]) => _sorted(
  {for (final tag in values) normalizeTag(tag, synonyms)}..remove(''),
);

/// Folds a tag to the form the index stores (`3D` → `3d`, `quick capture` →
/// `quick-capture`). Public because callers comparing arbitrary user text
/// against index tags — e.g. deciding whether an unresolved `[[Tutorial]]` is
/// really the existing `tutorial` tag — must fold the same way or they miss
/// most of the overlap.
String normalizeTag(String tag, [Map<String, String> synonyms = const {}]) {
  final folded = tag.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), '-');
  // One hop only. A map that happens to contain `a -> b` and `b -> c` must not
  // drag `a` all the way to `c`: chained merges are how a synonym set drifts
  // into a neighbouring concept, and the proposer never emits chains anyway.
  return synonyms[folded] ?? folded;
}

/// Reads `_system/tag-synonyms.json`, or an empty map if it is absent or
/// unusable. Tag folding is an enhancement, never a reason to fail a scan.
Future<Map<String, String>> loadTagSynonyms(VaultStorage storage) async {
  try {
    // TylogVaultPaths.tagSynonyms — inlined because vault.dart imports this
    // file, so importing it back would be a cycle.
    const path = '_system/tag-synonyms.json';
    if (!await storage.exists(path)) return const {};
    final decoded = jsonDecode(await storage.readText(path));
    if (decoded is! Map) return const {};
    final entries = decoded['synonyms'];
    if (entries is! Map) return const {};
    final synonyms = <String, String>{};
    for (final entry in entries.entries) {
      final from = entry.key.toString().trim().toLowerCase();
      final to = entry.value.toString().trim().toLowerCase();
      // A tag mapped to itself, or to nothing, is a no-op worth dropping so
      // the map stays a statement about real merges.
      if (from.isNotEmpty && to.isNotEmpty && from != to) synonyms[from] = to;
    }
    return synonyms;
  } catch (_) {
    return const {};
  }
}

Map<String, List<String>> _setsToSortedLists(Map<String, Set<String>> value) =>
    {
      for (final key in (value.keys.toList()..sort()))
        key: value[key]!.toList()..sort(),
    };

int? _balancedEnd(String source, int open) {
  var depth = 0;
  var i = open;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      i = source.indexOf('\n', i);
      if (i < 0) return null;
      continue;
    }
    if (source.startsWith('/*', i)) {
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
    if (source.startsWith('//', i)) {
      i = source.indexOf('\n', i);
      if (i < 0) return null;
      continue;
    }
    if (source.startsWith('/*', i)) {
      i = _skipBlockComment(source, i);
      continue;
    }
    // No string-skipping here: `[...]` is markup, where a `"` is literal text
    // like any other character. Treating it as a delimiter makes an odd number
    // of quotes in a task's text swallow the closing `]` and run to the next
    // quote — or to EOF. Same defect as the one removed from
    // `locateTypstCalls`; nothing in the vault trips it yet.
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
    if (source.startsWith('/*', i)) {
      depth++;
      i += 2;
    } else if (source.startsWith('*/', i)) {
      depth--;
      i += 2;
    } else {
      i++;
    }
  }
  return i;
}

bool _identifier(int code) =>
    code >= 65 && code <= 90 ||
    code >= 97 && code <= 122 ||
    code >= 48 && code <= 57 ||
    code == 45 ||
    code == 95;

bool _space(int code) => code == 9 || code == 10 || code == 13 || code == 32;

String _typstList(List<String> values) =>
    values.isEmpty ? '()' : '(${values.map(typstString).join(', ')},)';

String _typstDictionary(Map<String, Object?> values) {
  if (values.isEmpty) return '(:)';
  return '(${values.entries.map((entry) => '${typstString(entry.key)}: ${_typstValue(entry.value)}').join(', ')},)';
}

String _typstValue(Object? value) => switch (value) {
  null => 'none',
  bool() || num() => value.toString(),
  String() => typstString(value),
  List() => value.isEmpty ? '()' : '(${value.map(_typstValue).join(', ')},)',
  Map() => _typstDictionary({
    for (final entry in value.entries) entry.key.toString(): entry.value,
  }),
  _ => typstString(value.toString()),
};
