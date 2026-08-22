import 'dart:async';

import 'package:crypto/crypto.dart';

import 'index_donor.dart';
import 'models.dart';
import 'scanner.dart';
import 'search_index.dart';
import 'storage.dart';
import 'validation.dart';
import 'vault.dart';

/// Everything a vault needs done after its files change, in one place.
///
/// Four processes write this vault — the UI isolate, the worker isolate, the
/// Android background service and the CLI — and each grew its own version of
/// the same routine. That is not a tidiness problem: the most frequent bug
/// shape in this codebase is a fix landing in one of the four and being
/// invisible in the other three. The identity guard that stops a no-op scan
/// rewriting twelve megabytes of gzip lived only in the worker for months; the
/// orphan sweep only in the UI, which is the process *least* likely to be
/// killed mid-write; the donor load only in the app, so the CLI — running on
/// the one machine fast enough to index in seconds — recompiled everything
/// every time and consumed nothing its peers had published.
///
/// So the routine lives here, and the genuine differences are parameters. A
/// stream rather than a future because the order matters and one step must not
/// gate another: the index is published the moment it exists, before validation
/// and the search build, which on a SAF vault read thousands of files and would
/// otherwise keep the Journal empty for minutes after the data was ready.
sealed class VaultMaintenanceEvent {
  const VaultMaintenanceEvent();
}

class MaintenanceProgress extends VaultMaintenanceEvent {
  const MaintenanceProgress(this.complete, this.total);

  final int complete;
  final int total;
}

/// The scan's result, emitted as soon as the index is on disk and donated.
class MaintenanceIndexed extends VaultMaintenanceEvent {
  const MaintenanceIndexed(
    this.index, {
    required this.donorReuse,
    this.donorPublishError,
  });

  final VaultIndex index;

  /// What this scan took from other devices' donors.
  final DonorReuse donorReuse;

  /// Why this device could not share its own index, if it could not.
  final Object? donorPublishError;
}

class MaintenanceValidated extends VaultMaintenanceEvent {
  const MaintenanceValidated(this.report);

  final PkmsValidationReport report;
}

class MaintenanceSearchBuilt extends VaultMaintenanceEvent {
  const MaintenanceSearchBuilt(this.search, {required this.written});

  final PkmsSearchIndex search;

  /// False when the build returned the previous instance unchanged, so nothing
  /// was written. Reported because "we skipped a 12 MB rewrite" and "we failed
  /// to write" look identical from outside otherwise.
  final bool written;
}

class MaintenanceSwept extends VaultMaintenanceEvent {
  const MaintenanceSwept(this.deleted);

  final int deleted;
}

/// Holds the caches that make a repeat pass cheap, so it is created once per
/// process and reused — not per call.
class VaultMaintenance {
  VaultMaintenance(this.storage);

  final VaultStorage storage;

  late final IndexDonorStore donors = IndexDonorStore(storage);

  /// The index this instance built last: byte-equivalent to what is on disk, so
  /// the next pass never re-reads and re-decodes it.
  VaultIndex? _lastBuiltIndex;

  /// sha256 of the last index bytes written, so a pass that re-derives
  /// identical bytes skips the multi-megabyte rewrite.
  String? _lastIndexDigest;

  /// The search index this instance built last, so a warm pass skips the
  /// gzip-decode/jsonDecode round trip through disk.
  PkmsSearchIndex? _lastSearch;

  /// What the last donor load actually reused, for the status line.
  DonorReuse get donorReuse => donors.lastReuse;

  /// Why the last donor publish failed, or null if it succeeded.
  Object? get donorPublishError => donors.lastPublishError;

  VaultIndex? get lastBuiltIndex => _lastBuiltIndex;

  /// Scan, write `_index/index.json`, publish this device's donor.
  ///
  /// [deviceId] enables the cross-device cache: this device's notes are
  /// published to `_system/index/<deviceId>.json` after the scan, and a scan
  /// with no usable local index seeds itself from the other devices' donors
  /// instead of re-querying Typst for every note. Omit it and the rebuild is
  /// purely local.
  Future<VaultIndex> buildIndex({
    TypstInspector? inspector,
    bool force = false,
    String? deviceId,
    Set<String> stale = const {},
    void Function(int complete, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var previous = _lastBuiltIndex ?? await loadVaultIndex(storage);
    // Only *our own* last index says anything about what our donor holds; a
    // peer's donated index does not, so it must not suppress a republish.
    final ownPrevious = previous?.version == kVaultIndexVersion
        ? previous
        : null;
    if (previous == null || previous.version != kVaultIndexVersion) {
      previous = await donors.load(deviceId) ?? previous;
    }
    final index = await scanVaultStorage(
      storage,
      inspector: inspector,
      previous: previous,
      force: force,
      stale: stale,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    // Skip the *encode*, not just the write: jsonEncode + gzip of the whole
    // index ran unconditionally just to compute a digest to compare against.
    // Comparing note content hashes answers the same question for the price of
    // one pass over a map already in memory. The existence check keeps an
    // externally-deleted `_index/` from being treated as already-written.
    final unchanged =
        sameIndexedContent(_lastBuiltIndex, index) &&
        await storage.exists(TylogVaultPaths.index);
    if (!unchanged) {
      final encoded = encodeVaultIndexBytes(index);
      final digest = sha256.convert(encoded).toString();
      if (digest != _lastIndexDigest ||
          !await storage.exists(TylogVaultPaths.index)) {
        await storage.writeBytes(TylogVaultPaths.index, encoded);
        _lastIndexDigest = digest;
      }
    }
    _lastBuiltIndex = index;
    if (deviceId != null && deviceId.isNotEmpty) {
      await donors.publish(deviceId, index, previous: ownPrevious);
    }
    return index;
  }

  /// The whole routine: index, validate, search, sweep.
  ///
  /// Every step after the index is opt-out rather than opt-in, so a new context
  /// gets the complete pass by default and has to say what it is dropping. The
  /// four that existed before this each opted *in*, one step at a time, and
  /// between them managed to skip every step at least once.
  ///
  /// [extraProblems] is for validation this package cannot do — task recurrence
  /// rules are parsed with `rrule`, which lives in the app layer — and for a
  /// context reporting its own degradations (a dead Typst engine) through the
  /// same list.
  Stream<VaultMaintenanceEvent> run({
    TypstInspector? inspector,
    bool force = false,
    String? deviceId,
    Set<String> stale = const {},
    bool Function()? isCancelled,
    bool validate = true,
    bool buildSearch = true,
    bool sweep = true,
    List<PkmsProblem> Function(VaultIndex index)? extraProblems,
  }) {
    final out = StreamController<VaultMaintenanceEvent>();
    out.onListen = () async {
      try {
        final index = await buildIndex(
          inspector: inspector,
          force: force,
          deviceId: deviceId,
          stale: stale,
          onProgress: (complete, total) {
            if (!out.isClosed) out.add(MaintenanceProgress(complete, total));
          },
          isCancelled: isCancelled,
        );
        out.add(
          MaintenanceIndexed(
            index,
            donorReuse: donorReuse,
            donorPublishError: donorPublishError,
          ),
        );

        if (validate) {
          final report = await validatePkmsStorage(storage, index);
          report.problems.addAll(extraProblems?.call(index) ?? const []);
          report.problems.addAll(donorProblems(index));
          out.add(MaintenanceValidated(report));
        }

        if (buildSearch) {
          final cached =
              _lastSearch ??
              await PkmsSearchIndex.loadStorage(
                storage,
                TylogVaultPaths.searchIndex,
              );
          final search = await PkmsSearchIndex.buildStorage(
            storage,
            index,
            previous: cached,
          );
          // buildStorage returns the *same instance* when every note hit the
          // cache and the key set is unchanged, so identity is an exact
          // "nothing to write" test. Without it a no-op pass re-encoded ~43 MB
          // of JSON and rewrote ~12 MB of gzip for a file byte-identical to the
          // one already there.
          final written = !identical(search, cached);
          if (written) {
            await search.saveStorage(storage, TylogVaultPaths.searchIndex);
          }
          _lastSearch = search;
          out.add(MaintenanceSearchBuilt(search, written: written));
        }

        if (sweep) {
          out.add(MaintenanceSwept(await sweepVaultLeftovers(storage)));
        }
      } catch (error, stack) {
        out.addError(error, stack);
      } finally {
        await out.close();
      }
    };
    return out.stream;
  }

  /// Problems about the donor mechanism itself — the channel by which one
  /// device saves every other device a full recompile.
  List<PkmsProblem> donorProblems(VaultIndex index) {
    final problems = <PkmsProblem>[];
    final publishError = donorPublishError;
    if (publishError != null) {
      problems.add(
        PkmsProblem(
          code: 'donor-publish-failed',
          severity: PkmsSeverity.warning,
          subject: TylogVaultPaths.indexDonors,
          message:
              'This device could not share its index with your other devices, '
              'so they will each rebuild it from scratch.',
          fix:
              'Usually a full disk or a vault folder this app cannot write to. '
              'Check free space and the folder permission.',
          detail: '$publishError',
        ),
      );
    }
    final reuse = donorReuse;
    // Only when *nothing* was usable. A fleet mid-upgrade always has some
    // skipped donors while peers catch up, and that is a healthy, self-healing
    // state — raising it every scan for a week would be noise, and validation's
    // summary puts warnings in the status line.
    if (reuse.skipped > 0 && reuse.devices == 0) {
      problems.add(
        PkmsProblem(
          code: 'donor-skipped',
          severity: PkmsSeverity.info,
          subject: TylogVaultPaths.indexDonors,
          message:
              'None of your other devices shared a usable index, so this one '
              'rebuilt everything itself.',
          fix:
              'Normal right after an update — it clears once the other devices '
              'reindex. Persisting means their format never caught up.',
          detail: 'skipped ${reuse.skipped} donor(s)',
        ),
      );
    }
    return problems;
  }
}

/// The saved index, or null if there is none or it cannot be decoded.
Future<VaultIndex?> loadVaultIndex(VaultStorage storage) async {
  if (!await storage.exists(TylogVaultPaths.index)) return null;
  try {
    return decodeVaultIndexBytes(
      await storage.readBytes(TylogVaultPaths.index),
    );
  } catch (_) {
    return null;
  }
}

// ── Leftovers ────────────────────────────────────────────────────────────────

/// Deletes what interrupted writes and SAF rename collisions leave behind:
/// `.backup` orphans, forked vault locks, and `.tmp` files old enough to prove
/// no write is still using them.
///
/// Returns how many it removed. Every item is attempted on its own — one locked
/// file used to abort the whole pass through a single `catch (_)` around the
/// loop, so an unlucky third file out of 11,610 meant nothing after it was ever
/// swept, silently, on every open forever.
Future<int> sweepVaultLeftovers(VaultStorage storage) async {
  final tempCutoff = DateTime.now().subtract(orphanTempGrace);
  var deleted = 0;
  List<VaultStorageEntry> items;
  try {
    items = await storage.list(recursive: true);
  } catch (_) {
    return 0;
  }
  for (final item in items) {
    if (item.isDirectory) continue;
    final backup =
        isSafBackupPath(item.path) || isForkedVaultLockPath(item.path);
    // An unknown mtime is never old enough.
    final modified = item.modified;
    final staleTemp =
        isOrphanedTempPath(item.path) &&
        modified != null &&
        modified.isBefore(tempCutoff);
    if (!backup && !staleTemp) continue;
    try {
      await storage.delete(item.path);
      deleted++;
    } catch (_) {
      // This one is in use or gone; the rest of the sweep still runs.
    }
  }
  return deleted;
}

/// Orphan of an interrupted SAF atomic replace: `.<name>.tylog-<nanos>.backup`.
bool isSafBackupPath(String path) {
  final name = path.split('/').last;
  return name.startsWith('.') &&
      name.endsWith('.backup') &&
      name.contains('.tylog-');
}

/// A temp file from an interrupted atomic write: `<name>.<nanos>.tmp`.
bool isOrphanedTempPath(String path) =>
    _orphanTempPattern.hasMatch(path.split('/').last);

final RegExp _orphanTempPattern = RegExp(r'\.(?:tylog-)?\d+\.tmp$');

/// How long a `.tmp` must sit untouched before the sweep will remove it. The
/// background service is a separate process writing the same vault, so a temp
/// file created seconds ago may be an atomic write still in flight.
const orphanTempGrace = Duration(hours: 1);

/// A vault lock forked by a SAF rename collision: `.tylog/vault (1).lock`.
bool isForkedVaultLockPath(String path) => _forkedVaultLock.hasMatch(path);

final RegExp _forkedVaultLock = RegExp(r'^\.tylog/vault \(\d+\)\.lock$');
