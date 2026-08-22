import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'models.dart';
import 'storage.dart';
import 'values.dart';

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
        note.path.split('/').last.replaceFirst(_typExtension, ''),
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
  TypstInspector? inspector,
  VaultIndex? previous,
  bool force = false,
  Set<String> stale = const {},
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
  final synonyms = await loadTagSynonyms(storage);

  // Grouped once. Filtering `previous.tasks` per note made the cached path
  // quadratic — a full pass over every task in the vault, 1700 times.
  final cachedTasks = <String, List<TaskRef>>{};
  for (final task in previous?.tasks ?? const <TaskRef>[]) {
    (cachedTasks[task.notePath] ??= <TaskRef>[]).add(task);
  }

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
    final cached = previous?.notesByPath[relative];
    // [stale] carries the paths this process just wrote. SAF reports mtime at
    // second granularity, so a same-size edit inside the same second as the
    // previous scan looks unchanged to both gates below — a writer must never
    // depend on the clock to be seen.
    final reusable =
        !force &&
        previous?.version == kVaultIndexVersion &&
        cached != null &&
        !stale.contains(relative);
    // An entry from an older index version whose *query* half is current: the
    // derivation moved, not the expensive part. Re-derived below against the
    // note's bytes instead of recompiling it. This is the difference between a
    // schema bump costing a file read per note and costing 14 minutes of Typst.
    final rederivable =
        !force &&
        !reusable &&
        cached?.queryFacts != null &&
        previous?.queryVersion == kVaultQueryVersion &&
        !stale.contains(relative);

    // Does the cached entry still describe the bytes on disk? mtime+size is
    // the cheap answer, but it is device-local — SAF and APFS stamp the same
    // bytes differently — so an index seeded from another device misses on
    // every note. Falling back to the content hash costs one streamed read
    // and saves a Typst query, which is orders of magnitude more expensive.
    String? contentHash;
    var matchesDisk = false;
    if ((reusable || rederivable) && cached != null) {
      if (cached.fingerprint == fingerprint) {
        matchesDisk = true;
      } else if (cached.contentHash != null) {
        contentHash = await storage.hash(relative);
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
        cached!.metadataSource == 'fallback-inspected' &&
        activeInspector != null &&
        failedReinspected < maxFailedReinspectionsPerScan &&
        reinspected < maxMetadataReinspectionsPerScan;
    final reinspect =
        retryFailed ||
        (matchesDisk &&
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
        notes[relative] = rederived;
        tasks.addAll(cachedTasks[relative] ?? const []);
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
      final trustFacts = previous?.queryVersion == kVaultQueryVersion;
      notes[relative] = cached!.fingerprint == fingerprint && trustFacts
          ? cached
          : cached.copyWith(
              fingerprint: fingerprint,
              clearQueryFacts: !trustFacts,
            );
      tasks.addAll(cachedTasks[relative] ?? const []);
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
        final shared = await _inspectionFiles(storage);
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
        );
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
  return _buildVaultIndex(notes, problems: problems, tasks: tasks);
}

const _noteRoots = ['daily/', 'notes/', 'projects/', 'articles/'];

Future<Map<String, Uint8List>> _inspectionFiles(VaultStorage storage) async {
  final files = <String, Uint8List>{};
  for (final entry in await storage.list(recursive: true)) {
    if (entry.isDirectory ||
        entry.path.startsWith('_index/') ||
        // TylogVaultPaths.indexDonors — index caches, not compile inputs, and
        // megabytes each. Held twice in this map, they are the same
        // whole-vault-in-RAM stall the note filter below exists to prevent.
        entry.path.startsWith('_system/index/') ||
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
  final segments = <String>[
    ...dir.split('/').where((s) => s.isNotEmpty),
  ];
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
///
/// Pass [resolver] to reuse one across many notes — building it is O(vault), so
/// calling this in a loop without it is quadratic. [suggestLinkTargetsForNotes]
/// does that for you and is what batch callers should use.
List<String> suggestLinkTargets(
  NoteRef note,
  VaultIndex index, {
  LinkResolver? shared,
}) {
  final resolver = shared ?? LinkResolver(index.notes);
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

/// [suggestLinkTargets] for many notes, sharing one [LinkResolver].
///
/// Batch callers must use this rather than looping: the resolver is O(vault) to
/// build, so a per-note loop is quadratic — Relink vault over ~1700 articles was
/// tens of seconds of frozen UI before this existed. Returns note path → targets.
Map<String, List<String>> suggestLinkTargetsForNotes(
  Iterable<NoteRef> notes,
  VaultIndex index,
) {
  final shared = LinkResolver(index.notes);
  return {
    for (final note in notes)
      note.path: suggestLinkTargets(note, index, shared: shared),
  };
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
    '  id: ${typstString(draft.id)},',
    '  title: ${typstString(draft.title)},',
    '  kind: ${typstString(draft.kind)},',
    '  date: ${draft.date == null || draft.date!.isEmpty ? 'none' : typstString(draft.date!)},',
    '  tags: ${_typstList(draft.tags)},',
    '  aliases: ${_typstList(draft.aliases)},',
    '  project: ${draft.project == null || draft.project!.isEmpty ? 'none' : typstString(draft.project!)},',
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

/// Removes the org-mode bookkeeping a Logseq export carries into a note:
/// `:LOGBOOK:` drawers with their `CLOCK:` records and state-change lines, and
/// the empty block every page trails.
///
/// Repairs notes imported before the converter learned to drop these — a
/// re-import cannot, because the wizard skips a source whose SHA is unchanged.
/// Returns [source] unchanged when there is nothing to strip, so it is
/// idempotent and safe to run repeatedly.
///
/// Matches by line shape rather than parsing the drawer, exactly like
/// `strip_logseq_noise` in the Rust converter: a real vault has orphan `:END:`
/// lines and unclosed openers, and a state machine would either leak those or
/// swallow real content past an unclosed opener. Only *trailing* empty bullets
/// go; an empty item between two others is deliberate spacing.
String stripLogseqNoise(String source) {
  final lines = source.split('\n');
  // A trailing newline leaves an empty final element. That is the terminator,
  // not a line — leaving it in blocked the trailing sweep below on every file
  // whose only noise was the empty end block.
  final endsWithNewline = lines.isNotEmpty && lines.last.isEmpty;
  if (endsWithNewline) lines.removeLast();

  // A CLOCK: record is the user's time tracking, not noise — the converter
  // captures it into properties("clocked") now. If any survives in this note
  // the drawer is left completely alone rather than deleted, because deleting
  // it is unrecoverable and this runs from a one-tap Settings action. Only
  // genuinely empty drawers are cleaned.
  final holdsTime = lines.any((line) => line.trim().startsWith('CLOCK:'));

  final kept = <String>[];
  var removed = 0;
  for (final line in lines) {
    final trimmed = line.trim();
    final isDrawer =
        trimmed == ':LOGBOOK:' ||
        trimmed == ':END:' ||
        trimmed.startsWith('- State "');
    if (!holdsTime && isDrawer) {
      removed++;
      continue;
    }
    kept.add(line);
  }

  // Trailing empty blocks, plus any blank lines tangled up with them. Blanks
  // alone never count as noise, so a file that merely ends in whitespace is
  // returned untouched.
  var pending = 0;
  while (kept.isNotEmpty) {
    final trimmed = kept.last.trim();
    if (trimmed == '-' || trimmed == '+' || trimmed == r'\-') {
      kept.removeLast();
      removed += 1 + pending;
      pending = 0;
      continue;
    }
    if (trimmed.isEmpty) {
      kept.removeLast();
      pending++;
      continue;
    }
    break;
  }
  // Put back any blanks that turned out not to precede an empty block.
  for (var i = 0; i < pending; i++) {
    kept.add('');
  }

  if (removed == 0) return source;
  return endsWithNewline ? '${kept.join('\n')}\n' : kept.join('\n');
}

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
  const _DictEntry(this.start, this.end, this.valueStart);

  /// Bounds of the whole `"key": value` entry.
  final int start;
  final int end;

  /// Where the value begins, for readers that want it without the key.
  final int valueStart;
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
        var valueStart = match.end;
        while (valueStart < part.length && _space(part.codeUnitAt(valueStart))) {
          valueStart++;
        }
        return _DictEntry(
          offset + leading,
          offset + part.length,
          offset + valueStart,
        );
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
    // Must go through the same separator-aware append as every other writer:
    // a blind splice before `)` drops the comma on a single-line header
    // (`kind: "note"  properties: (…)`), which is exactly the defect that made
    // 406 task calls unparseable. `_noteSource` only ever writes multi-line
    // headers today, so this is the latent half of that bug, not a live one.
    final newHeader = _appendCallField(
      header,
      'properties',
      '(${typstString(key)}: $encodedValue,)',
      allowed: writableNoteFields,
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
      '${typstString(key)}: $encodedValue',
    );
  } else {
    newDict = _appendDictEntry(dictSource, key, encodedValue);
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
  // Typst allows a bare identifier as a dictionary key, and hand-written and
  // imported headers use it: `properties: (type: "person",)`. Reading only
  // quoted keys made those properties invisible — which silently disabled
  // `migrateEntityTypeToKind` on exactly the notes it exists to fix, and let
  // `replaceNoteHeader` drop the key on the next write. `_locateDictEntry`
  // already accepts both forms; this is the reader catching up.
  final entryKeyValue = RegExp(
    r'^\s*(?:"((?:\\.|[^"\\])*)"|([A-Za-z_][A-Za-z0-9_\-]*))\s*:\s*(.*)$',
    dotAll: true,
  );
  final result = <String, Object?>{};
  for (final entry in _splitTopLevel(inner)) {
    if (entry.trim().isEmpty) continue;
    final match = entryKeyValue.firstMatch(entry);
    if (match == null) continue;
    final key = (match.group(1) ?? match.group(2)!).replaceAllMapped(
      RegExp(r'\\(.)'),
      (m) => m.group(1)!,
    );
    result[key] = _parsePropertyValue(match.group(3)!.trim());
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
    if (source.startsWith('//', i)) {
      final nl = source.indexOf('\n', i);
      i = nl < 0 ? source.length : nl;
      continue;
    }
    if (source.startsWith('/*', i)) {
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
      ? _appendCallField(
            call.source,
            'status',
            '"$status"',
            allowed: writableTaskFields,
          )
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
      ? _appendCallField(
            call.source,
            'completed',
            '("$timestamp",)',
            allowed: writableTaskFields,
          )
      : call.source.replaceRange(
          field.start,
          field.end,
          'completed: (${call.source.substring(field.valueStart + 1, field.valueEnd - 1)}"$timestamp",)',
        );
  return source.replaceRange(call.start, call.end, replacement);
}

/// Field names TyLog may write into a `#tylog.task(...)` call.
///
/// Bound to `typst/tylog/lib.typ` by `package_contract_test.dart`: every name
/// here must be a parameter the shipped package actually declares. That test
/// exists because this is the failure that cost 167 notes — the app started
/// writing `clocked:` as a named argument the package had never declared, so
/// every note carrying one stopped compiling. Nothing caught it, because the
/// fallback parser reads a broken call back as a perfectly good task.
///
/// Adding a field here without adding it to the package fails the test. Adding
/// it to neither means the writer cannot emit it at all.
const writableTaskFields = {'status', 'completed', 'text', 'properties'};

/// Field names TyLog may write into a `tylog.note.with(...)` header.
/// Same contract as [writableTaskFields].
const writableNoteFields = {
  'id',
  'title',
  'kind',
  'date',
  'tags',
  'aliases',
  'project',
  'properties',
};

/// Inserts `name: value` just before a Typst call's closing paren — used for
/// both `#tylog.task(...)` fields and `tylog.note.with(...)` header fields.
///
/// The separator depends on how the call was written: the multi-line form ends
/// `,\n)` and needs none, while a single-line `#tylog.task(id: "x", text: "y")`
/// ends on a value and needs `, `. Getting this wrong produces
/// `priority: "normal"  clocked: (...)`, which is not valid Typst and silently
/// makes the whole task unreadable.
String _appendCallField(
  String callSource,
  String name,
  String value, {
  required Set<String> allowed,
}) {
  // A field the package does not declare is a hard Typst error, and the
  // fallback parser will happily read the broken call back as valid.
  assert(
    allowed.contains(name),
    'TyLog may not write "$name" — see writableTaskFields/writableNoteFields',
  );
  final close = callSource.lastIndexOf(')');
  if (close < 0) return callSource;
  var before = close - 1;
  while (before >= 0 && _isSpace(callSource.codeUnitAt(before))) {
    before--;
  }
  if (before < 0) return callSource;
  final previous = callSource[before];
  final multiline = callSource.substring(before + 1, close).contains('\n');
  if (previous == ',') {
    return callSource.replaceRange(
      before + 1,
      close,
      multiline ? '\n  $name: $value,\n' : ' $name: $value,',
    );
  }
  if (previous == '(') {
    return callSource.replaceRange(before + 1, close, '$name: $value,');
  }
  return callSource.replaceRange(before + 1, close, ', $name: $value,');
}

bool _isSpace(int code) => code == 32 || code == 9 || code == 10 || code == 13;

/// Appends `"key": value` to a Typst dictionary literal, supplying the comma
/// the previous entry may not have.
///
/// `("status": "read")` has no trailing comma, so a blind splice before the
/// closing paren yields `("status": "read""clocked": …)` — the same
/// missing-separator defect that made 406 task calls unreadable, one level
/// down.
String _appendDictEntry(String dict, String key, String rawValue) {
  final entry = '${typstString(key)}: $rawValue,';
  if (dict.trim() == '(:)' || dict.trim() == '()') return '($entry)';
  final close = dict.lastIndexOf(')');
  if (close < 0) return dict;
  var before = close - 1;
  while (before >= 0 && _space(dict.codeUnitAt(before))) {
    before--;
  }
  if (before < 0) return dict;
  final separator = dict[before] == ',' || dict[before] == '(' ? '' : ', ';
  return dict.replaceRange(before + 1, close, '$separator$entry');
}

/// Sets [id]'s tracked sessions, stored as `properties("clocked")`.
///
/// Duplicate `(start, end)` pairs collapse — the imported data holds 171 exact
/// repeats — and order is preserved otherwise.
String setTaskClocked(String source, String id, List<ClockEntry> entries) {
  final seen = <String>{};
  final unique = <ClockEntry>[];
  for (final entry in entries) {
    if (seen.add('${entry.start}|${entry.end}')) unique.add(entry);
  }
  final rendered = unique
      .map(
        (entry) =>
            '("${entry.start}", ${entry.end == null ? 'none' : '"${entry.end}"'})',
      )
      .join(', ');
  final call = _locateTaskCall(source, id);
  return source.replaceRange(
    call.start,
    call.end,
    // Also drops a legacy top-level `clocked:` argument, so a note written
    // before the data moved into properties migrates the first time it is
    // touched — and stops failing to compile on packages that never had that
    // argument.
    _removeTaskField(
      _setTaskProperty(
        call.source,
        'clocked',
        unique.isEmpty ? null : '($rendered,)',
      ),
      'clocked',
    ),
  );
}

/// Removes a top-level named argument from a task call, tidying the comma.
String _removeTaskField(String callSource, String name) {
  final field = _locateTopLevelField(callSource, name);
  if (field == null) return callSource;
  var end = field.end;
  while (end < callSource.length && _space(callSource.codeUnitAt(end))) {
    end++;
  }
  if (end < callSource.length && callSource[end] == ',') end++;
  var start = field.start;
  // If nothing follows, take the comma that preceded it instead.
  if (end >= callSource.length || callSource.substring(end).trim() == ')') {
    while (start > 0 && _space(callSource.codeUnitAt(start - 1))) {
      start--;
    }
    if (start > 0 && callSource[start - 1] == ',') start--;
  }
  return callSource.replaceRange(start, end, '');
}

/// Sets (or removes, when [rawValue] is null) `properties[key]` on a task
/// call, leaving every other argument byte-identical.
///
/// Time tracking lives here rather than in a named argument because a dict
/// tolerates keys an older Typst package has never seen, while an unknown
/// named argument is a hard compile error — and the package syncs between
/// devices that may be on different builds.
String _setTaskProperty(String callSource, String key, String? rawValue) {
  final field = _locateTopLevelField(callSource, 'properties');
  if (field == null) {
    if (rawValue == null) return callSource;
    return _appendCallField(
      callSource,
      'properties',
      '(${typstString(key)}: $rawValue,)',
      allowed: writableTaskFields,
    );
  }
  final dict = callSource.substring(field.valueStart, field.valueEnd);
  final entry = _locateDictEntry(dict, key);
  final String next;
  if (entry != null) {
    next = rawValue == null
        ? _stripDictEntry(dict, entry)
        : dict.replaceRange(
            entry.start,
            entry.end,
            '${typstString(key)}: $rawValue',
          );
  } else if (rawValue == null) {
    return callSource;
  } else {
    next = _appendDictEntry(dict, key, rawValue);
  }
  return callSource.replaceRange(field.valueStart, field.valueEnd, next);
}

/// Removes one entry from a dictionary literal, collapsing the comma it left.
String _stripDictEntry(String dict, _DictEntry entry) {
  final without = dict.replaceRange(entry.start, entry.end, '');
  final cleaned = without.replaceAll(RegExp(r',\s*,'), ',').replaceAll(
    RegExp(r'\(\s*,'),
    '(',
  );
  return cleaned.trim() == '()' ? '(:)' : cleaned;
}

/// Opens a new tracked session on [id].
///
/// Closes the session currently running on this task first, so a task can
/// never accumulate two open clocks — Logseq's willingness to do exactly that
/// is how 107 of this vault's sessions ended with no end at all. Older strays
/// are left open for the flagging path rather than back-dated.
///
/// Stopping a clock running on a *different* task is the caller's job; see the
/// one-running-clock rule in the app layer.
String startTaskClock(String source, String id, String startIso) {
  final closed = stopTaskClock(source, id, startIso);
  final call = _locateTaskCall(closed, id);
  return setTaskClocked(closed, id, [
    ...parseClockedField(call.source),
    ClockEntry(start: startIso),
  ]);
}

/// Closes the session running on [id]. A no-op when nothing is running.
///
/// Only the most recent open session closes. Four tasks in the real vault
/// carry two, and closing both to one timestamp invented a second session of
/// identical length and double-counted the time.
String stopTaskClock(String source, String id, String endIso) {
  final call = _locateTaskCall(source, id);
  final entries = parseClockedField(call.source);
  final index = entries.lastIndexWhere((entry) => entry.isRunning);
  if (index < 0) return source;
  final next = [...entries];
  next[index] = ClockEntry(start: next[index].start, end: endIso);
  return setTaskClocked(source, id, next);
}

String replaceTaskText(String source, String id, String text) {
  final call = _locateTaskCall(source, id);
  final quoted =
      '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  final field = _locateTopLevelField(call.source, 'text');
  final replacement = field == null
      ? _appendCallField(
            call.source,
            'text',
            quoted,
            allowed: writableTaskFields,
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
    if (callSource.startsWith('//', i)) {
      final nl = callSource.indexOf('\n', i);
      i = nl < 0 ? callSource.length : nl;
      continue;
    }
    if (callSource.startsWith('/*', i)) {
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
        if (callSource.startsWith('//', k)) {
          final nl = callSource.indexOf('\n', k);
          k = nl < 0 ? callSource.length : nl;
          continue;
        }
        if (callSource.startsWith('/*', k)) {
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
            path: path,
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
    final value = line.group(1)!;
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
Iterable<String> _kindTag(String kind) =>
    kind == 'note' ? const [] : [kind];

List<String> _normalizedTags(
  Set<String> values, [
  Map<String, String> synonyms = const {},
]) => _sorted({
  for (final tag in values) normalizeTag(tag, synonyms),
}..remove(''));

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
