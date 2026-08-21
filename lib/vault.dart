import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:tylog_core/index_donor.dart';
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

class Vault {
  Vault(Directory root) : storage = LocalVaultStorage(root);
  Vault.withStorage(this.storage);

  final VaultStorage storage;

  /// Notes written through [saveNote] since the last completed scan. The scan
  /// cache keys on mtime+size, which SAF reports at second granularity, so a
  /// same-size edit landing in the same second would otherwise be skipped.
  final _staleNotes = <String>{};

  /// Snapshot of the pending stale paths. The worker isolate scans through its
  /// *own* [Vault] instance, which never saw this one's [saveNote] calls, so the
  /// set has to travel with the rebuild command — see [rebuildIndex]'s `stale`.
  Set<String> get staleNotes => Set<String>.of(_staleNotes);

  /// Drops paths a completed scan covered. Only the ones it was handed: a save
  /// landing mid-scan must stay queued for the next one.
  void clearStaleNotes(Iterable<String> paths) => _staleNotes.removeAll(paths);

  /// Reads and writes `_system/index/` donors — shared with the CLI.
  late final IndexDonorStore _donors = IndexDonorStore(storage);

  /// sha256 of the last index-cache bytes this process wrote; a rebuild that
  /// re-derives identical bytes skips the multi-megabyte rewrite.
  String? _lastIndexDigest;

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
    // Gzip via the shared codec (readers accept the old plain JSON), and skip
    // the write entirely when this process already wrote identical bytes —
    // the encoded index was ~6.7 MB plain and is rewritten on every rebuild.
    final encoded = encodeVaultIndexBytes(index);
    final digest = sha256.convert(encoded).toString();
    // The existence check keeps an externally-deleted `_index/` from being
    // treated as already-written just because this process wrote the same
    // bytes earlier.
    if (digest != _lastIndexDigest || !await storage.exists(indexPath)) {
      await storage.writeBytes(indexPath, encoded);
      _lastIndexDigest = digest;
    }
    if (deviceId != null && deviceId.isNotEmpty) {
      await _writeIndexDonor(deviceId, index, ownPrevious);
    }
    return index;
  }

  /// Publishes this device's notes for its peers. Implementation lives in
  /// tylog_core's [IndexDonorStore] so the CLI publishes the same format.
  Future<void> _writeIndexDonor(
    String deviceId,
    VaultIndex index,
    VaultIndex? previous,
  ) => _donors.publish(deviceId, index, previous: previous);

  /// Merges every *other* device's donor into one index the scanner can use
  /// as its cache. See tylog_core's [IndexDonorStore].
  Future<VaultIndex?> _loadDonatedIndex(String? deviceId) =>
      _donors.load(deviceId);

  /// What the last donor load actually reused, for the status line.
  DonorReuse get donorReuse => _donors.lastReuse;

  Future<VaultIndex?> loadIndex() async {
    if (!await storage.exists(indexPath)) return null;
    try {
      return decodeVaultIndexBytes(await storage.readBytes(indexPath));
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
