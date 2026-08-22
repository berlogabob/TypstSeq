import 'dart:io';

import 'package:tylog_core/index_donor.dart';
import 'package:tylog_core/maintenance.dart';
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

  /// Notes written since the last sync pass considered them.
  ///
  /// Deliberately a *second* set rather than a reader of [staleNotes]: the scan
  /// clears those when the index catches up, which says nothing about whether
  /// the bytes reached the server. Sync's no-change shortcut compares mtime and
  /// size, and SAF reports mtime at second granularity — so a same-size edit
  /// landing in the same second as the cursor's recorded mtime is invisible to
  /// it, and permanently, because the shortcut writes nothing and the cursor is
  /// therefore never updated. The scanner has carried a set for exactly this
  /// hazard since the beginning; sync had none.
  final _pendingSyncWrites = <String>{};

  /// Whether a local write is waiting for a sync pass to look at it.
  bool get hasPendingSyncWrites => _pendingSyncWrites.isNotEmpty;

  /// Snapshot, for a caller that will clear what it covered.
  Set<String> get pendingSyncWrites => Set<String>.of(_pendingSyncWrites);

  /// Records a local write this app made outside [saveNote] — a sync download.
  ///
  /// The scan cache keys on mtime+size at second granularity, and a peer's edit
  /// arriving as a download is the write *most* likely to collide: a daily note
  /// that changed by a few bytes, landing in the same second as the listing.
  /// The stale set was fed only by the editor, so exactly that write was the
  /// one it could not see.
  ///
  /// Deliberately not added to the sync-pending set: sync itself produced these
  /// bytes, so there is nothing to send back.
  void markLocallyWritten(String path) => _staleNotes.add(path);

  /// Whether this path was written since a sync pass last considered it.
  bool isPendingSyncWrite(String path) => _pendingSyncWrites.contains(path);

  /// Drops paths a completed sync pass covered.
  void clearPendingSyncWrites(Iterable<String> paths) =>
      _pendingSyncWrites.removeAll(paths);

  /// Indexing, validation, search and the orphan sweep — the routine all four
  /// contexts share, and the caches that make a repeat pass cheap. Lives in
  /// tylog_core so the CLI and the background service run the same steps in the
  /// same order rather than each keeping their own subset.
  late final VaultMaintenance maintenance = VaultMaintenance(storage);

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
  Future<void> _writeSyncExcludes() => writeSyncExcludes(storage);

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
      index = await maintenance.buildIndex(
        inspector: inspector,
        force: force,
        deviceId: deviceId,
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
    return index;
  }

  /// What the last donor load actually reused, for the status line.
  DonorReuse get donorReuse => maintenance.donorReuse;

  /// Why the last donor publish failed, or null if it succeeded.
  ///
  /// A device that stops publishing makes every peer recompile the whole vault
  /// from scratch. The store has recorded this since the failure stopped being
  /// swallowed silently; nothing read it, so the channel ended in a field.
  Object? get donorPublishError => maintenance.donorPublishError;

  Future<VaultIndex?> loadIndex() => loadVaultIndex(storage);

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
      // Refusing the write protects a real note from being blanked. It also
      // used to strand the exact case that produced it: a stray character
      // typed into the Today editor materialises the daily file, and removing
      // that character then fails forever. The 2-byte file stays on disk with
      // nothing able to clean it up, and — because `dirty` only clears on a
      // successful save — the editor stays dirty, which in turn disables idle
      // maintenance and the midnight rollover. One keystroke, permanently.
      //
      // So: if what is on disk was never a real note, emptying it removes it.
      // Anything carrying a note header is real content and still refuses.
      if (await _isDisposableNote(path)) {
        await storage.delete(path);
        _staleNotes.add(path);
        _pendingSyncWrites.add(path);
        return;
      }
      throw ArgumentError('A TyLog note cannot be empty');
    }
    await storage.writeText(path, text);
    _staleNotes.add(path);
    _pendingSyncWrites.add(path);
  }

  /// Whether the note at [path] holds nothing worth keeping: absent, blank, an
  /// untouched starter daily, or a file with no TyLog note header at all (what
  /// a stray keystroke leaves behind). Unreadable counts as *not* disposable —
  /// never delete on the strength of a failed read.
  Future<bool> _isDisposableNote(String path) async {
    try {
      if (!await storage.exists(path)) return true;
      final source = await storage.readText(path);
      return source.trim().isEmpty ||
          !source.contains(noteHeaderMarker) ||
          isPristineStarterNote(path, source);
    } catch (_) {
      return false;
    }
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

/// The line every TyLog-written note carries. Its absence means the file was
/// never a structured note — an empty buffer saved over a path, or foreign
/// content that has not been converted.
const noteHeaderMarker = '#show: tylog.note';

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
