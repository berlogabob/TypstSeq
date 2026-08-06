import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:tylog_core/models.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';
import 'package:tylog_core/values.dart';
import 'package:tylog_core/vault.dart';

import 'flutter_typst_inspector.dart';
import 'widgets/date_format.dart';
import 'tylog_assets.dart';

export 'package:tylog_core/vault.dart'
    show VaultStorageInspection, VaultStorageKind, inspectVaultStorage;

/// Shape of `_system/index/<deviceId>.json`.
///
/// 2 added `tasks`. A schema-1 donor is skipped rather than read: it carries
/// every note, so every note hits the scanner's cached branch, and the tasks
/// it does not carry are never re-derived.
///
/// 3 stopped publishing user-authored note properties. Schema-2 donors are
/// skipped for the same reason *and* because they contain the values this
/// change exists to stop shipping — see [_donorSafeProperties].
const _indexDonorSchema = 3;

/// Property keys TyLog or article-pipeline writes, and therefore the only ones
/// a donor may carry off-device.
///
/// A donor is published to `_system/index/`, which is inside the sync allowlist
/// (`isSyncableVaultPath`), so every key here is uploaded to the server and
/// handed to every other device. `NoteRef.toJson` serialises `properties`
/// verbatim, so before this list a note's hand-written `pswrd:`/`login:` values
/// travelled with it. Allowlist, never denylist: an unknown key is by
/// definition one we did not write and cannot vouch for.
const _donorSafeProperties = {
  'import_format',
  'import_source_name',
  'import_source_path',
  'import_sha256',
  'status',
  'relevance',
  'rating',
  'citation-key',
  'type',
  'icon',
  'llm_provider',
  'llm_model',
  'extraction',
  'processed',
  'url',
  'source',
  'source_url',
  'share_url',
  'author',
  'updated',
  'week',
};

/// Whether [note] may be published to peers.
///
/// A note carrying any key outside [_donorSafeProperties] is left out of the
/// donor entirely rather than published with its properties stripped: the
/// scanner's cached branch reuses a donor entry wholesale when the content hash
/// matches, so a half-populated entry would read as authoritative and the note
/// would lose its properties on every peer. Omitting it costs that one note a
/// re-parse and keeps the result correct. Measured on the real vault: 3323 of
/// 3345 notes still ship (99.3%); 22 are re-parsed.
bool _isDonorSafe(NoteRef note) =>
    note.properties.keys.every(_donorSafeProperties.contains);

class Vault {
  Vault(Directory root) : storage = LocalVaultStorage(root);
  Vault.withStorage(this.storage);

  final VaultStorage storage;

  /// Notes written through [saveNote] since the last completed scan. The scan
  /// cache keys on mtime+size, which SAF reports at second granularity, so a
  /// same-size edit landing in the same second would otherwise be skipped.
  final _staleNotes = <String>{};

  /// Whether this instance has confirmed the donor on disk is current-schema.
  ///
  /// The unchanged-vault early-out in [_writeIndexDonor] never encodes and
  /// never reads, so on its own it would leave a device that upgraded but
  /// whose vault has not changed serving its old schema-1 donor forever — and
  /// peers now skip those. Clearing this each launch costs one encode per app
  /// run and lets the upgrade actually happen.
  bool _donorSchemaConfirmed = false;

  /// Snapshot of the pending stale paths. The worker isolate scans through its
  /// *own* [Vault] instance, which never saw this one's [saveNote] calls, so the
  /// set has to travel with the rebuild command — see [rebuildIndex]'s `stale`.
  Set<String> get staleNotes => Set<String>.of(_staleNotes);

  /// Drops paths a completed scan covered. Only the ones it was handed: a save
  /// landing mid-scan must stay queued for the next one.
  void clearStaleNotes(Iterable<String> paths) => _staleNotes.removeAll(paths);

  static const indexPath = TylogVaultPaths.index;
  static const searchIndexPath = TylogVaultPaths.searchIndex;
  static const helperPath = TylogVaultPaths.helper;
  static const themePath = TylogVaultPaths.theme;
  static const exportPath = TylogVaultPaths.export;
  static const bibliographyPath = TylogVaultPaths.bibliography;
  static const zoteroBibPath = TylogVaultPaths.zoteroBib;
  static const settingsPath = TylogVaultPaths.settings;
  static const indexDonorsPath = TylogVaultPaths.indexDonors;

  Future<void> ensureCreated({bool createIfMissing = true}) async {
    final bundled = await TylogAssets.load();
    await initializeVaultStorage(
      storage,
      managedFiles: bundled.managedVaultFiles,
      currentHelper: bundled.text('typst/vault/tylog.typ'),
      legacyHelper: bundled.text('typst/vault/legacy-v5-tylog.typ'),
      createIfMissing: createIfMissing,
    );
    await _writeSyncExcludes();
  }

  /// Keeps the device-local caches out of a desktop client's upload.
  ///
  /// `_index/` is derived data — the note index, the search index, the tag
  /// embeddings — and TyLog never syncs it: it is not in `isSyncableVaultPath`.
  /// But the vault commonly *lives inside* `~/Nextcloud`, and the desktop
  /// client uploads whatever it finds there. On this vault that is ~27 MB of
  /// cache, and because the search index tokenises whole note bodies it also
  /// carries note text — including, verifiably, values from `pswrd:` lines.
  ///
  /// The Nextcloud/ownCloud desktop client reads a `.sync-exclude.lst` from a
  /// synced directory, so one file keeps the caches local. Written for every
  /// vault, not just detected-managed ones: a vault can be moved into a synced
  /// folder later, and a stray exclude file in a folder no client watches is
  /// inert.
  ///
  /// It does not remove what has already been uploaded — that is a deliberate
  /// deletion, not something to do behind the user's back.
  Future<void> _writeSyncExcludes() async {
    const path = '.sync-exclude.lst';
    const contents = '''
# Written by TyLog. Device-local caches — rebuildable, and large.
# The search index contains note text, so this also keeps note contents out of
# a desktop client's upload.
_index
.tylog
''';
    try {
      if (await storage.exists(path)) return;
      await storage.writeText(path, contents);
    } catch (_) {
      // A read-only or restricted vault still opens; this is a hardening step,
      // not a precondition.
    }
  }

  Future<String> todayNote([DateTime? now]) async {
    final instant = now ?? DateTime.now();
    final day = isoDay(instant);
    final month =
        'daily/${instant.year.toString().padLeft(4, '0')}/${instant.month.toString().padLeft(2, '0')}';
    await storage.createDirectory(month);
    final path = '$month/$day.typ';
    if (!await storage.exists(path)) {
      await storage.writeText(
        path,
        _noteSource(
          id: day,
          title: day,
          kind: 'daily',
          date: day,
          tags: const ['journal'],
        ),
      );
    }
    return path;
  }

  /// Opens (creating if missing) the journal file for an arbitrary day.
  Future<String> dailyNote(DateTime day) => todayNote(day);

  Future<String> page(
    String title, {
    String kind = 'note',
    String? template,
    DateTime? now,
    Set<String>? knownIds,
  }) async {
    final safe = title.trim().replaceAll(RegExp(r'[\\/]'), '-');
    if (safe.isEmpty) throw ArgumentError('Page title is empty');
    final directory = switch (kind) {
      'project' => 'projects',
      'article' => 'articles',
      _ => 'notes',
    };
    final path = '$directory/$safe.typ';
    if (!await storage.exists(path)) {
      final id = await nextNoteId(title, now: now, knownIds: knownIds);
      final source = template == null
          ? _noteSource(id: id, title: title.trim(), kind: kind)
          : replaceNoteHeader(
              await storage.readText(template),
              NoteMetadataDraft(id: id, title: title.trim(), kind: kind),
            );
      await storage.writeText(path, source);
    }
    return path;
  }

  /// Copies each of [paths] as it is right now under `.tylog/undo/<stamp>/`,
  /// and returns that directory.
  ///
  /// The safety net for bulk rewrites. TyLog has no vault-level undo — the
  /// editor's history is an in-memory stack cleared on every note switch — so
  /// a maintenance pass over 3,351 notes was previously recoverable only from
  /// the server's own versioning.
  ///
  /// Throws if any copy fails. A caller that cannot snapshot must not write:
  /// the copy exists precisely so that it is there *before* anything is
  /// overwritten. `.tylog/` is outside the sync allowlist, so snapshots stay on
  /// the device that made them.
  Future<String> snapshotNotes(Iterable<String> paths, {DateTime? now}) async {
    final stamp = (now ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-');
    final directory = '.tylog/undo/$stamp';
    for (final path in paths) {
      final parent = path.lastIndexOf('/');
      await storage.createDirectory(
        parent < 0 ? directory : '$directory/${path.substring(0, parent)}',
      );
      await storage.writeText('$directory/$path', await storage.readText(path));
    }
    return directory;
  }

  Future<String> project(String title, {DateTime? now}) =>
      page(title, kind: 'project', now: now);

  Future<String> article(String title, {DateTime? now}) =>
      page(title, kind: 'article', now: now);

  /// [deviceId] enables the cross-device cache: this device's notes are
  /// published to `_system/index/<deviceId>.json` after the scan, and a scan
  /// that has no usable local index seeds itself from the other devices'
  /// donors instead of re-querying Typst for every note. Omit it and the
  /// rebuild is purely local.
  ///
  /// [stale] overrides this instance's own pending set, for the worker isolate:
  /// it holds a different [Vault] than the one whose [saveNote] recorded the
  /// edits, so the caller passes the snapshot in and clears it via
  /// [clearStaleNotes] once the scan reports back.
  Future<VaultIndex> rebuildIndex({
    TypstInspector? inspector,
    bool force = false,
    String? deviceId,
    Set<String>? stale,
    void Function(int complete, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var previous = await loadIndex();
    // Only *our own* last index says anything about what our donor holds; a
    // peer's donated index does not, so it must not suppress a republish.
    final ownPrevious = previous?.version == kVaultIndexVersion
        ? previous
        : null;
    if (previous == null || previous.version != kVaultIndexVersion) {
      previous = await _loadDonatedIndex(deviceId) ?? previous;
    }
    final staleNow = stale ?? Set<String>.of(_staleNotes);
    FlutterTypstInspector? ownedInspector;
    if (inspector == null) {
      try {
        ownedInspector = await FlutterTypstInspector.create();
        inspector = ownedInspector;
      } catch (_) {
        // Native Typst is optional in unit tests; core safely falls back.
      }
    }
    final VaultIndex index;
    try {
      index = await scanVaultStorage(
        storage,
        inspector: inspector,
        previous: previous,
        force: force,
        stale: staleNow,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } finally {
      ownedInspector?.dispose();
    }
    // Only the paths this scan actually covered; a save landing mid-scan stays
    // queued for the next one. A no-op when `stale` came from outside — that
    // caller owns the clearing.
    _staleNotes.removeAll(staleNow);
    // Compact: nothing reads index.json by eye, and pretty-printing roughly
    // doubled the bytes encoded and written for a ~2.5 MB file.
    await storage.writeText(indexPath, jsonEncode(index.toJson()));
    if (deviceId != null && deviceId.isNotEmpty) {
      await _writeIndexDonor(deviceId, index, ownPrevious);
    }
    return index;
  }

  /// Publishes this device's notes for its peers.
  ///
  /// [VaultIndex.notes] is path-sorted and [NoteRef.toJson] is stable, so an
  /// unchanged vault re-renders to identical bytes — and those bytes are
  /// compared before writing. Skipping the write, not just producing equal
  /// content, is what keeps this quiet: on desktop the vault belongs to the
  /// Nextcloud client, which detects changes by mtime+size, and an atomic
  /// write renames a fresh temp file into place. Rewriting an identical donor
  /// would re-upload megabytes after every save.
  ///
  /// Notes *and* tasks. Backlinks and problems really are recomputed from
  /// scratch every scan, but tasks are not: the scanner's cached branch reuses
  /// `previous.tasks` for any note whose bytes still match, so a donor without
  /// them hands a fresh device a complete note index and an empty task list —
  /// every note matches by content hash, every one contributes zero tasks, and
  /// the Tasks view comes up blank until a forced rebuild.
  ///
  /// Notes carrying properties we did not write are held back entirely — see
  /// [_isDonorSafe]. This file leaves the device, so what goes into it is a
  /// privacy decision, not a caching one.
  Future<void> _writeIndexDonor(
    String deviceId,
    VaultIndex index,
    VaultIndex? previous,
  ) async {
    try {
      final path = '${TylogVaultPaths.indexDonors}/$deviceId.json';
      final published = await storage.exists(path);
      // Cheapest early-out, and the one that matters most on a phone: if we
      // already published and the scan changed nothing, don't encode ~2 MB of
      // JSON and read the same amount back over SAF just to discover the bytes
      // are identical. O(n) over maps already in memory.
      if (published && _donorSchemaConfirmed && _sameNotes(previous, index)) {
        return;
      }
      final publishable = <String>{
        for (final note in index.notes)
          if (_isDonorSafe(note)) note.path,
      };
      // Compact, unlike index.json: nothing reads this by eye, and it is the
      // one index artifact that crosses the network.
      final donor = jsonEncode({
        'schema': _indexDonorSchema,
        'indexVersion': index.version,
        // Which synonym map produced these tags. A peer whose map differs must
        // re-derive rather than inherit tags folded by rules it no longer uses.
        'synonymsHash': await _synonymsHash(),
        'notes': [
          for (final note in index.notes)
            if (publishable.contains(note.path)) note.toJson(),
        ],
        // A task rides with its note or not at all: the peer only consults
        // donated tasks for a note it also took from the donor, so tasks for an
        // omitted note are dead weight that would still cross the network.
        'tasks': [
          for (final task in index.tasks)
            if (publishable.contains(task.notePath)) task.toJson(),
        ],
      });
      // Second guard, for the cases the note comparison can't settle: a first
      // publish after a version bump, or a donor whose file drifted from what
      // the index says. Byte-identical means don't touch the file at all —
      // on desktop the Nextcloud client watches mtime, so a redundant rewrite
      // re-uploads megabytes.
      if (published && await storage.readText(path) == donor) {
        _donorSchemaConfirmed = true;
        return;
      }
      await storage.writeText(path, donor);
      _donorSchemaConfirmed = true;
    } catch (_) {
      // A donor is a cache. Failing to publish one must never fail a rebuild.
    }
  }

  /// Fingerprint of `_system/tag-synonyms.json`, or '' when there is none.
  ///
  /// Cheap and read once per rebuild; it only gates donor reuse.
  Future<String> _synonymsHash() async {
    try {
      if (!await storage.exists(TylogVaultPaths.tagSynonyms)) return '';
      return sha256
          .convert(await storage.readBytes(TylogVaultPaths.tagSynonyms))
          .toString();
    } catch (_) {
      return '';
    }
  }

  /// Whether two indexes describe the same notes, as far as a donor cares.
  ///
  /// Only path and content hash matter: those are what a peer matches against
  /// its own files. A note whose mtime moved but whose bytes did not is the
  /// same note to everyone else.
  static bool _sameNotes(VaultIndex? previous, VaultIndex next) {
    if (previous == null) return false;
    if (previous.version != next.version) return false;
    if (previous.notesByPath.length != next.notesByPath.length) return false;
    for (final entry in next.notesByPath.entries) {
      final before = previous.notesByPath[entry.key];
      if (before == null) return false;
      // A null hash on either side means "unknown", which is never a match —
      // republish so the peer gets an entry it can actually use.
      if (before.contentHash == null ||
          before.contentHash != entry.value.contentHash) {
        return false;
      }
    }
    return true;
  }

  /// Merges every *other* device's donor into one index the scanner can use as
  /// its cache. Best-effort throughout: an unreadable, corrupt or
  /// wrong-version donor is skipped, never fatal.
  ///
  /// ponytail: merged by path only. A note renamed on another device arrives
  /// already renamed (sync issues a MOVE), so a content-hash reverse map would
  /// buy nothing yet — add one if renames start showing up as cache misses.
  Future<VaultIndex?> _loadDonatedIndex(String? deviceId) async {
    final own = deviceId == null || deviceId.isEmpty
        ? null
        : '${TylogVaultPaths.indexDonors}/$deviceId.json';
    List<VaultStorageEntry> files;
    try {
      files = await storage.list(path: TylogVaultPaths.indexDonors);
    } catch (_) {
      return null;
    }
    final notes = <String, NoteRef>{};
    // Tasks follow whichever donor won each note: they are derived from that
    // note's bytes, so mixing one donor's note with another's tasks would put
    // the scanner's cached branch out of step with the file on disk.
    final tasksByPath = <String, List<TaskRef>>{};
    for (final file in files) {
      if (file.isDirectory ||
          !file.path.endsWith('.json') ||
          file.path == own) {
        continue;
      }
      try {
        final json =
            (jsonDecode(await storage.readText(file.path)) as Map)
                .cast<String, Object?>();
        if (json['indexVersion'] != kVaultIndexVersion) continue;
        // schema 1 donors carry notes but no tasks. Reusing one seeds a full
        // note index whose every entry hits the cached branch, so no note is
        // ever re-queried and the task list stays empty. Skipping it costs one
        // slow first scan; using it costs a silently empty Tasks view.
        if (json['schema'] != _indexDonorSchema) continue;
        final donorTasks = <String, List<TaskRef>>{};
        for (final item in (json['tasks'] as List? ?? const []).cast<Map>()) {
          final task = TaskRef.fromJson(item.cast<String, Object?>());
          (donorTasks[task.notePath] ??= <TaskRef>[]).add(task);
        }
        // The donor's tags were folded by whatever map its author had. If ours
        // differs, its NoteRefs are as stale as an old-schema entry — the
        // content hashes would still match and the change would be invisible.
        if (json['synonymsHash'] != await _synonymsHash()) continue;
        for (final item in (json['notes'] as List).cast<Map>()) {
          final note = NoteRef.fromJson(item.cast<String, Object?>());
          final existing = notes[note.path];
          // Whichever device saw the note last wins. The scanner verifies
          // every entry against the bytes on disk regardless, so a wrong guess
          // costs one re-parse, not a wrong index.
          if (existing == null ||
              (note.modifiedMillis ?? 0) >= (existing.modifiedMillis ?? 0)) {
            notes[note.path] = note;
            tasksByPath[note.path] = donorTasks[note.path] ?? const [];
          }
        }
      } catch (_) {
        continue;
      }
    }
    if (notes.isEmpty) return null;
    return VaultIndex(
      notesByPath: notes,
      backlinksByTarget: const {},
      tasks: [for (final list in tasksByPath.values) ...list],
    );
  }

  Future<VaultIndex?> loadIndex() async {
    if (!await storage.exists(indexPath)) return null;
    try {
      return VaultIndex.fromJson(
        (jsonDecode(await storage.readText(indexPath)) as Map)
            .cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  /// [knownIds] lets a caller creating several notes at once own the id
  /// namespace for the whole batch. Without it each call re-reads the on-disk
  /// index, which cannot know about the note written a millisecond ago — and
  /// since the slug drops every non-ASCII character, a run of Cyrillic titles
  /// collapses to the bare second-resolution timestamp and mints *the same id*
  /// every time. Ids chosen here are added back to the set, the way
  /// [nextTaskId] uses `reserved`.
  Future<String> nextNoteId(
    String title, {
    DateTime? now,
    Set<String>? knownIds,
  }) async {
    final instant = now ?? DateTime.now();
    final stamp =
        '${instant.year.toString().padLeft(4, '0')}'
        '${instant.month.toString().padLeft(2, '0')}'
        '${instant.day.toString().padLeft(2, '0')}-'
        '${instant.hour.toString().padLeft(2, '0')}'
        '${instant.minute.toString().padLeft(2, '0')}'
        '${instant.second.toString().padLeft(2, '0')}';
    final slug = title
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = slug.isEmpty ? stamp : '$stamp-$slug';
    final ids =
        knownIds ??
        (await loadIndex())?.notes.map((note) => note.id).toSet() ??
        <String>{};
    var id = base;
    var suffix = 2;
    while (ids.contains(id)) {
      id = '$base-${suffix++}';
    }
    ids.add(id);
    return id;
  }

  Future<String> nextTaskId(String text, {DateTime? now, Set<String> reserved = const {}}) async {
    final instant = now ?? DateTime.now();
    final stamp =
        '${instant.year.toString().padLeft(4, '0')}'
        '${instant.month.toString().padLeft(2, '0')}'
        '${instant.day.toString().padLeft(2, '0')}-'
        '${instant.hour.toString().padLeft(2, '0')}'
        '${instant.minute.toString().padLeft(2, '0')}'
        '${instant.second.toString().padLeft(2, '0')}';
    final slug = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = slug.isEmpty ? stamp : '$stamp-$slug';
    final ids = {...?(await loadIndex())?.tasks.map((task) => task.id), ...reserved};
    var id = base;
    var suffix = 2;
    while (ids.contains(id)) {
      id = '$base-${suffix++}';
    }
    return id;
  }

  Future<void> saveNote(String path, String text) async {
    if (path.endsWith('.typ') && text.trim().isEmpty) {
      throw ArgumentError('A TyLog note cannot be empty');
    }
    await storage.writeText(path, text);
    _staleNotes.add(path);
  }

  Future<String> readText(String path) => storage.readText(path);
  Future<List<int>> readBytes(String path) => storage.readBytes(path);
  Future<bool> exists(String path) => storage.exists(path);
}

Directory defaultVaultDirectory(
  Directory appDocuments, {
  Map<String, String>? environment,
  bool? desktop,
}) {
  final env = environment ?? Platform.environment;
  final configured = env['TYLOG_VAULT_DIR']?.trim();
  if (configured != null && configured.isNotEmpty) return Directory(configured);

  final home = env['HOME'];
  if ((desktop ?? (Platform.isMacOS || Platform.isLinux)) && home != null) {
    final direct = Directory('$home/Nextcloud');
    if (direct.existsSync()) return Directory('${direct.path}/TyLogVault');

    final cloudStorage = Directory('$home/Library/CloudStorage');
    if (cloudStorage.existsSync()) {
      for (final entry in cloudStorage.listSync()) {
        if (entry is Directory &&
            entry.path.split('/').last.toLowerCase().contains('nextcloud')) {
          return Directory('${entry.path}/TyLogVault');
        }
      }
    }
  }

  return Directory('${appDocuments.path}/TyLogVault');
}

/// The starter source for a brand-new note.
///
/// Every interpolation is escaped. This used to write `title: "$title"` raw, so
/// a page called `He said "hi"` produced Typst that could not compile — and
/// because the fallback parser reads a broken header back as a valid note,
/// nothing reported it; the note just never regained real metadata. The heading
/// is markup rather than a string literal, so it takes [escapeMarkup] instead:
/// a `#` or `[` in the title breaks it the same way.
///
/// The templated path in [Vault.page] goes through `replaceNoteHeader`, which
/// has always escaped correctly. These two are the same operation and must not
/// disagree.
String _noteSource({
  required String id,
  required String title,
  String kind = 'note',
  String? date,
  List<String> tags = const [],
}) =>
    '''#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: ${typstString(id)},
  title: ${typstString(title)},
  kind: ${typstString(kind)},${date == null ? '' : '\n  date: ${typstString(date)},'}
  tags: ${_typstList(tags)},
)

= ${escapeMarkup(title)}

''';

bool isPristineStarterNote(String path, String source) {
  final match = RegExp(
    r'^daily/\d{4}/\d{2}/(\d{4}-\d{2}-\d{2})\.typ$',
  ).firstMatch(path);
  final day = match?.group(1);
  return day != null &&
      source ==
          _noteSource(
            id: day,
            title: day,
            kind: 'daily',
            date: day,
            tags: const ['journal'],
          );
}

String _typstList(List<String> values) =>
    values.isEmpty ? '()' : '(${values.map(typstString).join(', ')},)';
