import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';
import 'storage.dart';
import 'vault.dart';

/// Shape of `_system/index/<deviceId>.json`.
///
/// 2 added `tasks`. A schema-1 donor is skipped rather than read: it carries
/// every note, so every note hits the scanner's cached branch, and the tasks
/// it does not carry are never re-derived.
///
/// 3 stopped publishing user-authored note properties. Schema-2 donors are
/// skipped for the same reason *and* because they contain the values this
/// change exists to stop shipping — see [donorSafeProperties].
///
/// 4 carries `queryVersion` and each note's [NoteRef.queryFacts], so a donor
/// survives a derive-only index bump instead of being thrown away with the
/// whole vault's compiled metadata. Schema-3 donors are skipped: they have no
/// facts, so nothing in them can be re-derived.
const indexDonorSchema = 4;

/// Property keys TyLog or article-pipeline writes, and therefore the only ones
/// a donor may carry off-device.
///
/// A donor is published to `_system/index/`, which is inside the sync allowlist
/// (`isSyncableVaultPath`), so every key here is uploaded to the server and
/// handed to every other device. `NoteRef.toJson` serialises `properties`
/// verbatim, so before this list a note's hand-written `pswrd:`/`login:` values
/// travelled with it. Allowlist, never denylist: an unknown key is by
/// definition one we did not write and cannot vouch for.
const donorSafeProperties = {
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
/// A note carrying any key outside [donorSafeProperties] is left out of the
/// donor entirely rather than published with its properties stripped: the
/// scanner's cached branch reuses a donor entry wholesale when the content hash
/// matches, so a half-populated entry would read as authoritative and the note
/// would lose its properties on every peer. Omitting it costs that one note a
/// re-parse and keeps the result correct.
bool isDonorSafe(NoteRef note) =>
    note.properties.keys.every(donorSafeProperties.contains);

/// How many notes and tasks the scanner took from peers on the last load.
///
/// Published so a caller can *say* whether sharing worked. The donor mechanism
/// was dead for days without anyone noticing precisely because a silent
/// fallback to recompiling looks identical to a cache hit.
class DonorReuse {
  const DonorReuse({
    required this.notes,
    required this.tasks,
    required this.devices,
    required this.skipped,
  });

  final int notes;
  final int tasks;

  /// Donor files selected.
  final int devices;

  /// Donor files skipped as unusable (wrong schema/version, corrupt, or a
  /// synonym map that no longer matches), expired, or superseded.
  final int skipped;

  bool get isEmpty => notes == 0;

  @override
  String toString() =>
      'reused $notes notes and $tasks tasks from $devices device(s)'
      '${skipped > 0 ? ', skipped $skipped unusable donor(s)' : ''}';
}

/// Whether two indexes describe the same notes — same paths, same content
/// hashes, same schema version.
///
/// Everything else in a [VaultIndex] (backlinks, problems, tasks) is derived
/// from those bytes, so an unchanged answer here means an unchanged index. Used
/// to skip work that would otherwise re-encode the whole index just to discover
/// nothing moved.
bool sameIndexedContent(VaultIndex? previous, VaultIndex next) =>
    IndexDonorStore._sameNotes(previous, next);

/// Reads and writes the per-device index donors under `_system/index/`.
///
/// Lives in tylog_core, not the app, so the CLI can publish one too: the
/// machine that does the expensive Typst inspection is usually the desktop,
/// and until this moved here `tylog index` scanned a whole vault and published
/// nothing, leaving every phone to recompile the same notes for itself.
class IndexDonorStore {
  IndexDonorStore(this.storage);

  final VaultStorage storage;

  /// Whether this instance has confirmed the donor on disk is current-schema.
  ///
  /// The unchanged-vault early-out in [publish] never encodes and so never
  /// notices a stale schema; without this a device whose vault has not changed
  /// serves its old donor forever.
  bool _schemaConfirmed = false;

  String _pathFor(String deviceId) =>
      '${TylogVaultPaths.indexDonors}/$deviceId.json';

  /// Publishes this device's notes for its peers.
  ///
  /// [VaultIndex.notes] is path-sorted and [NoteRef.toJson] is stable, so an
  /// unchanged vault re-renders to identical bytes — and those bytes are
  /// compared before writing. Skipping the write, not just producing equal
  /// content, is what keeps this quiet: on desktop the vault belongs to the
  /// Nextcloud client, which detects changes by mtime+size, and an atomic
  /// write renames a fresh temp file into place.
  ///
  /// Notes *and* tasks: the scanner's cached branch reuses `previous.tasks`
  /// for any note whose bytes still match, so a donor without them hands a
  /// fresh device a complete note index and an empty task list.
  Future<void> publish(
    String deviceId,
    VaultIndex index, {
    VaultIndex? previous,
  }) async {
    try {
      final path = _pathFor(deviceId);
      final stamp = await storage.stat(path);
      final published = stamp != null;
      final fresh =
          stamp?.modified != null &&
          DateTime.now().difference(stamp!.modified!) < freshDonorAge;
      await pruneUnusable(deviceId);
      // Cheapest early-out, for repeat desktop passes: if we
      // already published and the scan changed nothing, don't encode ~2 MB of
      // JSON and read the same amount back over SAF just to discover the bytes
      // are identical.
      if (published &&
          fresh &&
          _schemaConfirmed &&
          _sameNotes(previous, index)) {
        return;
      }
      final publishable = <String>{
        for (final note in index.notes)
          if (isDonorSafe(note)) note.path,
      };
      final donor = jsonEncode({
        'schema': indexDonorSchema,
        'indexVersion': index.version,
        // The half that costs a Typst compile. A peer on a newer index version
        // can still use this donor if this matches — see load().
        'queryVersion': index.queryVersion,
        // Which synonym map produced these tags. A peer whose map differs must
        // re-derive rather than inherit tags folded by rules it no longer uses.
        'synonymsHash': await _synonymsHash(),
        'notes': [
          for (final note in index.notes)
            if (publishable.contains(note.path)) note.toJson(),
        ],
        // A task rides with its note or not at all.
        'tasks': [
          for (final task in index.tasks)
            if (publishable.contains(task.notePath)) task.toJson(),
        ],
      });
      if (published && fresh && await storage.readText(path) == donor) {
        _schemaConfirmed = true;
        return;
      }
      await storage.writeText(path, donor);
      _schemaConfirmed = true;
    } catch (error) {
      // A donor is a cache. Failing to publish one must never fail a rebuild —
      // but it must not be invisible either. This file's own history is the
      // argument: the mechanism was dead for days precisely because a silent
      // fallback to recompiling looks exactly like a cache hit. `load` reports
      // through DonorReuse; this is the write half of the same channel.
      lastPublishError = error;
      return;
    }
    lastPublishError = null;
  }

  /// Why the last [publish] failed, or null if it succeeded.
  ///
  /// A device that stops sharing makes every peer recompile the whole vault,
  /// so the failure has to be reportable rather than merely survivable.
  Object? lastPublishError;

  /// Retired installs must stop shipping their shards to every device.
  /// Never delete our own shard or one with an unknown timestamp.
  static const staleDonorAge = Duration(days: 30);
  static const readableDonorAge = Duration(days: 14);
  static const freshDonorAge = Duration(hours: 24);

  Future<int> pruneUnusable(String? ownDeviceId) async {
    final own = ownDeviceId == null || ownDeviceId.isEmpty
        ? null
        : _pathFor(ownDeviceId);
    var deleted = 0;
    try {
      for (final file in await storage.list(
        path: TylogVaultPaths.indexDonors,
      )) {
        if (file.isDirectory ||
            !file.path.endsWith('.json') ||
            file.path == own) {
          continue;
        }
        // Someone else's file. Only once nothing has rewritten it for 30 days,
        // and never on the strength of an unknown timestamp.
        final modified = file.modified;
        if (modified == null ||
            DateTime.now().difference(modified) < staleDonorAge) {
          continue;
        }
        try {
          await storage.delete(file.path);
          deleted++;
        } catch (_) {
          // Per item. One undeletable donor used to abort the whole pass
          // through the outer catch, leaving every donor after it in place —
          // silently, and forever, since the count is discarded by the caller.
        }
      }
    } catch (_) {
      // Listing the directory failed; nothing to do this pass.
    }
    return deleted;
  }

  /// Selects the newest usable peer donor as
  /// its cache. Best-effort throughout: an unreadable, corrupt or
  /// wrong-version donor is skipped, never fatal.
  /// What the last [load] took from peers, for callers that report it.
  DonorReuse lastReuse = const DonorReuse(
    notes: 0,
    tasks: 0,
    devices: 0,
    skipped: 0,
  );

  Future<VaultIndex?> load(
    String? deviceId, {
    Duration maxAge = readableDonorAge,
  }) async {
    lastReuse = const DonorReuse(notes: 0, tasks: 0, devices: 0, skipped: 0);
    final own = deviceId == null || deviceId.isEmpty
        ? null
        : _pathFor(deviceId);
    List<VaultStorageEntry> files;
    try {
      files = await storage.list(path: TylogVaultPaths.indexDonors);
    } catch (_) {
      return null;
    }
    files.sort(
      (a, b) =>
          (b.modified ?? DateTime(0)).compareTo(a.modified ?? DateTime(0)),
    );
    final notes = <String, NoteRef>{};
    // Set when any merged donor predates the current index version, so the
    // returned index reports the older one and the scanner re-derives.
    var staleDerivation = false;
    // Tasks follow whichever donor won each note: they are derived from that
    // note's bytes, so mixing one donor's note with another's tasks would put
    // the scanner's cached branch out of step with the file on disk.
    final tasksByPath = <String, List<TaskRef>>{};
    var merged = 0;
    var skipped = 0;
    for (final file in files) {
      if (file.isDirectory ||
          !file.path.endsWith('.json') ||
          file.path == own) {
        continue;
      }
      if (merged > 0 ||
          file.modified == null ||
          DateTime.now().difference(file.modified!) >= maxAge) {
        skipped++;
        continue;
      }
      try {
        final json = (jsonDecode(await storage.readText(file.path)) as Map)
            .cast<String, Object?>();
        if (json['schema'] != indexDonorSchema) {
          skipped++;
          continue;
        }
        // A donor from an older index version is still worth having when its
        // queried half is current: the scanner re-derives those entries
        // against the bytes on disk instead of recompiling them. Every index
        // bump so far (6, 7, 8, 9) was derive-only, and each one made every
        // device recompile the entire vault for nothing.
        // Unconditional, not only when the index version differs. Whatever
        // the index version says, entries produced by a different Typst query
        // carry queryFacts we cannot re-derive from — and merging them would
        // launder those facts into this device's own index, stamped with our
        // current query version.
        if (json['queryVersion'] != kVaultQueryVersion) {
          skipped++;
          continue;
        }
        final sameIndex = json['indexVersion'] == kVaultIndexVersion;

        final donorTasks = <String, List<TaskRef>>{};
        for (final item in (json['tasks'] as List? ?? const []).cast<Map>()) {
          final task = TaskRef.fromJson(item.cast<String, Object?>());
          (donorTasks[task.notePath] ??= <TaskRef>[]).add(task);
        }
        // The donor's tags were folded by whatever map its author had. If ours
        // differs, its NoteRefs are as stale as an old-schema entry.
        if (json['synonymsHash'] != await _synonymsHash()) {
          skipped++;
          continue;
        }
        final donorNotes = <String, NoteRef>{};
        for (final item in (json['notes'] as List).cast<Map>()) {
          final note = NoteRef.fromJson(item.cast<String, Object?>());
          donorNotes[note.path] = note;
        }
        notes.addAll(donorNotes);
        tasksByPath.addAll(donorTasks);
        staleDerivation = !sameIndex;
        merged++;
      } catch (_) {
        skipped++;
        continue;
      }
    }
    final tasks = [for (final list in tasksByPath.values) ...list];
    lastReuse = DonorReuse(
      notes: notes.length,
      tasks: tasks.length,
      devices: merged,
      skipped: skipped,
    );
    if (notes.isEmpty) return null;
    return VaultIndex(
      // Reporting the older version is what routes these entries through the
      // scanner's re-derivation branch rather than its straight-reuse one.
      version: staleDerivation ? kVaultIndexVersion - 1 : kVaultIndexVersion,
      // Stated, not left to the default. It is only true because of the gate
      // above, and an implicit "current" that some other line has to keep
      // honest is the exact shape of the bug this pair of versions exists to
      // prevent — `version` is threaded through explicitly two lines up.
      queryVersion: kVaultQueryVersion,
      notesByPath: notes,
      backlinksByTarget: const {},
      tasks: tasks,
    );
  }

  /// Fingerprint of `_system/tag-synonyms.json`, or '' when there is none.
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
  /// its own files.
  static bool _sameNotes(VaultIndex? previous, VaultIndex next) {
    if (previous == null) return false;
    if (previous.version != next.version) return false;
    if (previous.notesByPath.length != next.notesByPath.length) return false;
    for (final entry in next.notesByPath.entries) {
      final before = previous.notesByPath[entry.key];
      if (before == null) return false;
      // A null hash on either side means "unknown", which is never a match.
      if (before.contentHash == null ||
          before.contentHash != entry.value.contentHash) {
        return false;
      }
    }
    return true;
  }
}
