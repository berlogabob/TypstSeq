import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:tylog_core/graph.dart';

import 'models.dart';
import 'nextcloud_sync.dart';
import 'pkms_registry.dart';
import 'scanner.dart';
import 'search_index.dart';
import 'task_scheduler.dart';
import 'tylog_assets.dart';
import 'vault.dart';
import 'vault_lock.dart';
import 'vault_registry.dart';
import 'vault_storage.dart';
import 'vault_worker.dart';

class WorkspaceSyncNotConfigured implements Exception {
  const WorkspaceSyncNotConfigured();
}

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required this.taskScheduler,
    this.isComposing = _notComposing,
    this.inspector,
    Future<void> Function(Iterable<TaskRef>)? reconcileTasks,
  }) : _reconcileTasks = reconcileTasks ?? taskScheduler.reconcile;

  final TaskScheduler taskScheduler;
  final bool Function() isComposing;
  final TypstInspector? inspector;
  final Future<void> Function(Iterable<TaskRef>) _reconcileTasks;

  Vault? vault;
  VaultEntry? entry;
  VaultIndex? index;
  String? note;
  String source = '';
  String status = 'Opening vault...';
  bool dirty = false;

  /// Mirrors [dirty] so the title bar's "•" indicator can rebuild on its
  /// own without the whole screen (incl. the rich editor) rebuilding on
  /// every keystroke via the general [ChangeNotifier] channel.
  final ValueNotifier<bool> dirtyNotifier = ValueNotifier<bool>(false);

  void _setDirty(bool value) {
    dirty = value;
    dirtyNotifier.value = value;
  }

  /// Fires once per sync-progress tick (see [syncNow]'s `onProgress`),
  /// separately from the general channel — a sync run can tick tens to
  /// hundreds of times and would otherwise force a full-screen rebuild
  /// on every file/stage transition.
  final ChangeNotifier syncProgressTick = ChangeNotifier();

  int editRevision = 0;
  int savedRevision = 0;
  int indexedRevision = 0;

  /// The exact text this controller last wrote to disk. The post-sync
  /// divergence check uses it to tell "disk holds our own mid-sync
  /// autosave" (benign, even when the buffer has since moved on) apart
  /// from genuinely foreign disk content (a real conflict).
  String? _lastSavedSource;
  DateTime? lastEditAt;
  String helperSource = '';
  Map<String, Uint8List> typstPackageFiles = const {};
  String bibliographySource = '';
  String zoteroBibSource = '';

  /// Reading recents/progress merged from every device's
  /// `_system/reading/<deviceId>.json` (newest openedAt wins per path).
  List<RecentNote> mergedReading = const [];

  /// Increments on every index assignment. The invalidation key for everything
  /// derived from the index — see [_retainIndex]. Distinct from
  /// [indexedRevision], which tracks *editor* revisions, not index content.
  int indexRevision = 0;

  /// Community assignment for the current index, or null until the first one
  /// finishes. Computed once per index in a background isolate rather than per
  /// build: it is O(promoted tags²) and the shell rebuilds on every notify.
  CommunityMap? communities;

  /// Link resolver for the current index, rebuilt once per index. O(n), so it
  /// stays on the main thread — it just must not run on every frame.
  LinkResolver? linkResolver;

  int _derivedRevision = -1;

  /// The isolate in [refreshDerived] can land after the controller is gone —
  /// closing a vault, or a hot restart. Notifying then throws.
  bool _disposed = false;

  /// Indexing and sync are async and deliberately unawaited, so a vault close,
  /// a hot restart or a test teardown can land between an await and the notify
  /// that follows it. [_disposed] already existed for that hazard in
  /// [refreshDerived]; enforcing it here covers every path instead of forty call
  /// sites. Nothing is lost — a disposed controller has no listeners left.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  /// Refreshes [communities] for the current index.
  ///
  /// Cheap to call repeatedly: it returns immediately once the current
  /// revision has been derived. Fire-and-forget — callers do not await it, and
  /// the UI renders with the previous (or null) values until it lands.
  ///
  /// [linkResolver] is *not* built here — it is built wherever the index is
  /// published ([_retainIndex] and [openVault]), because its consumers run inside
  /// build and cannot wait for a fire-and-forget pass to land.
  ///
  /// [precomputed] short-circuits the community pass for the worker path, which
  /// already ran it next to the scan that produced the index. That matters more
  /// than it looks: `compute()` copies the *whole* `VaultIndex` onto this
  /// isolate to hand it to the other one, and on a 1800-note vault that copy was
  /// itself a visible stall.
  Future<void> refreshDerived({CommunityMap? precomputed}) async {
    final revision = indexRevision;
    final current = index;
    if (_disposed || current == null || _derivedRevision == revision) return;
    final CommunityMap next;
    try {
      next = precomputed ?? await compute(computeCommunitiesIsolate, current);
    } catch (_) {
      return; // Derived state is an optimization; the UI degrades to null.
    }
    // A newer index landed while the isolate was working — its own
    // refreshDerived call owns the result now, so drop this one.
    if (_disposed || indexRevision != revision || index == null) return;
    communities = next;
    _derivedRevision = revision;
    notifyListeners();
  }

  /// This install's [VaultRegistry.deviceId], set once the registry loads.
  /// Names the index donor this device publishes and the one it must not read
  /// back as a peer's. Null before the registry is available — the rebuild
  /// then just stays local.
  String? deviceId;
  NextcloudConfig? cloud;
  PkmsSearchIndex searchIndex = PkmsSearchIndex.empty();
  PkmsValidationReport? validation;
  SyncResult? lastSync;
  List<SyncConflict> syncConflicts = const [];
  DateTime? lastSyncAt;
  String? syncError;
  bool syncing = false;
  String? syncStage;
  bool? storageHealthy;
  bool rebuilding = false;
  bool cancelRebuild = false;
  double? rebuildProgress;

  /// Owns the vault's indexing work on its own isolate. Null while no vault is
  /// open, and null for the whole lifetime of a controller built with an
  /// explicit [inspector] — see [_useWorker].
  VaultWorkerClient? _worker;

  /// Tests supply a fake [inspector], which cannot cross an isolate boundary,
  /// and some also override the storage in [openVault]; both keep the original
  /// in-process path. Production supplies neither.
  bool get _useWorker => inspector == null;

  /// Mutual exclusion for the scan, whichever path runs it. [rebuilding] can't
  /// serve: it drives the progress UI, and a background [refreshIndex] must not
  /// light that up. Two concurrent scans would race on `index.json` (and the
  /// worker is single-flight by design).
  bool _indexing = false;

  /// A scan asked for while one was already running. Coalesced rather than
  /// dropped — see [_scan].
  bool _rescanQueued = false;

  /// Completes when the running [_scan] (including its queued repeats) exits,
  /// so a coalesced caller can await real results instead of stale state.
  Future<void>? _activeScan;

  Timer? _autosave;
  Timer? _cloudAutosave;
  Timer? _cloudPoll;
  DateTime? _lastForegroundNotice;

  Directory? get localDirectory =>
      entry?.storageKind == 'local-path' ? Directory(entry!.path) : null;

  bool get hasSyncConflicts => syncConflicts.isNotEmpty;

  /// Exposed for tests only, to verify [startCloudPolling]/[stopCloudPolling]
  /// actually toggle the background poll timer.
  @visibleForTesting
  bool get hasActiveCloudPoll => _cloudPoll?.isActive ?? false;

  bool get editingRecently {
    if (dirty || isComposing()) return true;
    final edited = lastEditAt;
    return edited != null &&
        DateTime.now().difference(edited) < const Duration(seconds: 10);
  }

  void close(String message, {NextcloudConfig? nextCloud}) {
    _cancelTimers();
    _shutdownWorker();
    vault = null;
    entry = null;
    note = null;
    index = null;
    // Tied to the index it was built from — a closed vault must not leave a
    // resolver behind that still answers for the old one.
    linkResolver = null;
    validation = null;
    searchIndex = PkmsSearchIndex.empty();
    helperSource = '';
    typstPackageFiles = const {};
    bibliographySource = '';
    zoteroBibSource = '';
    mergedReading = const [];
    cloud = nextCloud;
    lastSync = null;
    syncConflicts = const [];
    lastSyncAt = null;
    syncError = null;
    storageHealthy = false;
    _setDirty(false);
    savedRevision = editRevision;
    indexedRevision = editRevision;
    lastEditAt = null;
    source = '';
    status = message;
    notifyListeners();
  }

  Future<void> openVault(
    VaultEntry next, {
    String? trigger,
    VaultStorage? storage,
  }) async {
    _cancelTimers();
    _shutdownWorker();
    try {
      final opened = Vault.withStorage(storage ?? next.storage);
      await opened.ensureCreated(
        createIfMissing:
            next.storageKind != 'android-tree' &&
            !vaultNeedsAndroidTreeMigration(next),
      );
      final today = await opened.todayNote();
      final loadedFiles = <String, Uint8List>{};
      // Load user-vendored Typst packages (e.g. @preview/<name>:<ver> dropped
      // into _system/packages/<name>/<ver>/...) so notes can import them.
      // Managed tylog files are loaded afterward and take precedence on any
      // key collision. Walked one directory level at a time (never
      // `recursive: true`) so this stays part of the fast path: a full
      // recursive scan is the slow operation on SAF vaults that the fast
      // path/background-index split exists to avoid.
      if (await opened.storage.exists('_system/packages')) {
        final directories = <String>['_system/packages'];
        while (directories.isNotEmpty) {
          final dir = directories.removeLast();
          List<VaultStorageEntry> entries;
          try {
            entries = await opened.storage.list(path: dir);
          } catch (_) {
            continue;
          }
          for (final entry in entries) {
            if (entry.isDirectory) {
              directories.add(entry.path);
              continue;
            }
            try {
              final bytes = await opened.storage.readBytes(entry.path);
              loadedFiles[entry.path] = bytes;
              loadedFiles['/${entry.path}'] = bytes;
            } catch (_) {
              // Skip unreadable vendored package files; don't abort open.
            }
          }
        }
      }
      for (final asset
          in (await TylogAssets.load()).managedVaultFiles.entries) {
        final bytes = await opened.storage.readBytes(asset.key);
        loadedFiles[asset.key] = bytes;
        loadedFiles['/${asset.key}'] = bytes;
      }
      // Fast path: assign what a handful of reads can give us right away so
      // the UI is usable immediately, instead of waiting on a full index +
      // search-index rebuild (thousands of sequential reads on SAF vaults).
      vault = opened;
      entry = next;
      note = today;
      final loaded = await opened.loadIndex();
      index = loaded;
      // Not via _retainIndex — a new vault must not inherit the previous one's
      // index object. But the resolver still has to exist from the moment the
      // index does: this is the fast path, so the editor starts rendering
      // mention chips well before the first scan finishes, and until now
      // linkResolver stayed null for all of that window.
      linkResolver = loaded == null ? null : LinkResolver(loaded.notes);
      validation = null;
      searchIndex = PkmsSearchIndex.empty();
      helperSource = await opened.storage.readText(Vault.helperPath);
      typstPackageFiles = loadedFiles;
      bibliographySource = await opened.storage.exists(Vault.bibliographyPath)
          ? await opened.storage.readText(Vault.bibliographyPath)
          : '';
      zoteroBibSource = await opened.storage.exists(Vault.zoteroBibPath)
          ? await opened.storage.readText(Vault.zoteroBibPath)
          : '';
      cloud = next.cloud;
      lastSync = null;
      syncConflicts = await loadSyncConflicts(opened);
      lastSyncAt = null;
      syncError = null;
      storageHealthy = null;
      savedRevision = editRevision;
      indexedRevision = editRevision;
      lastEditAt = null;
      _setDirty(false);
      source = await opened.storage.readText(today);
      status = 'Vault opened — indexing…';
      notifyListeners();
      unawaited(_sweepSafBackups(opened));
      unawaited(reloadReadingState());
      // No usable cache on disk: this open faces a full Typst pass over the
      // whole vault unless another device's index donor is already here.
      final coldIndex = index == null || index!.version != kVaultIndexVersion;
      Future<void>? firstSync;
      if (next.cloud?.isReady ?? false) {
        if (trigger != null) {
          firstSync = syncNow(trigger: trigger);
          unawaited(firstSync);
        }
        startCloudPolling();
      }
      // Heavy index + search-index build runs in the background, using the
      // on-disk cache/fingerprints (force: false) so it's much faster than a
      // full rebuild.
      //
      // A cold index waits for that first sync, because the sync is what
      // carries the peers' donors. Started in parallel it would read an empty
      // donor directory and spend ~17 minutes re-querying Typst for notes
      // another device already inspected. The UI is already usable from the
      // fast path above, so the wait costs nothing visible. whenComplete, not
      // then: a failed sync must still leave the vault indexed.
      // A storage override can't be rebuilt from `next` inside the isolate, so
      // that (test-only) path stays in-process.
      if (_useWorker && storage == null) {
        _worker = await VaultWorkerClient.spawn(
          entry: next,
          deviceId: deviceId,
        );
      }
      unawaited(
        coldIndex && firstSync != null
            ? firstSync.whenComplete(() => rebuildIndex(force: false))
            : rebuildIndex(force: false),
      );
    } catch (error) {
      close('Open failed: $error', nextCloud: next.cloud);
    }
  }

  void edit(String value) {
    source = value;
    editRevision++;
    lastEditAt = DateTime.now();
    final becameDirty = !dirty;
    _setDirty(true);
    if (becameDirty) status = 'Autosave pending...';
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 400), save);
  }

  Future<void> save({bool syncAfter = true}) async {
    _autosave?.cancel();
    final opened = vault;
    final path = note;
    if (opened == null) {
      status = 'Waiting for vault…';
      notifyListeners();
      return;
    }
    if (path == null) return;
    final revision = editRevision;
    final value = source;
    try {
      await opened.saveNote(path, value);
      _lastSavedSource = value;
      if (revision == editRevision && path == note) {
        savedRevision = revision;
        _setDirty(false);
        status = 'Saved $path';
        if (syncAfter) queueCloudSync();
        notifyListeners();
      }
    } catch (error) {
      if (revision == editRevision && path == note) {
        status = 'Save failed: $error';
        notifyListeners();
      }
    }
  }

  /// [always] runs the scan even when the editor-revision guard says nothing
  /// was saved — for vault mutations the editor never sees (imports, deletes,
  /// bulk repairs). It does *not* disable the mtime+size scan cache: an
  /// unchanged note must never be re-compiled just because some other note
  /// changed. `Vault.saveNote` tracks its own writes, so nothing is missed.
  Future<void> refreshIndex({
    bool updateStatus = true,
    bool always = false,
  }) async {
    final opened = vault;
    if (opened == null || (!always && indexedRevision >= savedRevision)) return;
    await _scan(opened, updateStatus: updateStatus);
  }

  /// [force] discards the scan cache and re-compiles every note — the manual
  /// escape hatch for a suspected-bad index, not the routine path.
  Future<void> rebuildIndex({bool force = false}) async {
    final opened = vault;
    if (opened == null) return;
    if (rebuilding || _indexing) {
      cancelRebuild = true;
      _worker?.cancel();
      return;
    }
    rebuilding = true;
    cancelRebuild = false;
    rebuildProgress = 0;
    status = 'Rebuilding index...';
    notifyListeners();
    try {
      await _scan(opened, force: force, showProgress: true);
    } finally {
      rebuilding = false;
      rebuildProgress = null;
      notifyListeners();
    }
  }

  /// The one scan driver, for both the routine refresh and the explicit rebuild.
  ///
  /// [showProgress] drives the progress bar and the running status line;
  /// [updateStatus] is the refresh path's quieter switch for callers that own
  /// the status line themselves.
  /// [onProgress] replaces the built-in progress reporting for callers that own
  /// the status line themselves — [syncNow] drives [rebuildProgress] and
  /// [syncProgressTick] instead of `status` + `notifyListeners`.
  Future<void> _scan(
    Vault opened, {
    bool force = false,
    bool showProgress = false,
    bool updateStatus = true,
    void Function(int complete, int total)? onProgress,
  }) async {
    if (_indexing) {
      // Never drop the trigger. A sync that just downloaded files must get a
      // scan even if one was already running when it landed, or those bytes stay
      // unindexed until some unrelated edit happens to schedule another — a
      // download bumps no revision, so the `indexedRevision >= savedRevision`
      // guard in refreshIndex would not re-run on its own.
      //
      // Await the running scan rather than returning: the do-while below runs
      // the queued repeat before _activeScan completes, so when this returns
      // the caller's writes have actually been re-indexed. The Problems-screen
      // fix buttons depend on that — they read the fresh problem list right
      // after refreshIndex(always: true).
      _rescanQueued = true;
      await _activeScan;
      return;
    }
    _indexing = true;
    final done = Completer<void>();
    _activeScan = done.future;
    try {
      // Repeats are never forced: a queued scan is there to pick up new bytes,
      // not to re-compile the whole vault a second time.
      var repeat = false;
      do {
        _rescanQueued = false;
        await _scanOnce(
          opened,
          force: force && !repeat,
          showProgress: showProgress,
          updateStatus: updateStatus,
          onProgress: onProgress,
        );
        repeat = true;
      } while (_rescanQueued && opened == vault && !_disposed);
    } finally {
      _indexing = false;
      _activeScan = null;
      done.complete();
    }
  }

  Future<void> _scanOnce(
    Vault opened, {
    required bool force,
    required bool showProgress,
    required bool updateStatus,
    required void Function(int complete, int total)? onProgress,
  }) async {
    final revision = savedRevision;
    final worker = _worker;
    if (worker == null) {
      await _scanInProcess(
        opened,
        revision: revision,
        force: force,
        showProgress: showProgress,
        updateStatus: updateStatus,
        onProgress: onProgress,
      );
      return;
    }
      // The worker holds its own Vault, which never saw this one's saveNote
      // calls, so the pending set travels with the command and is cleared only
      // once the scan reports back covering it.
      final stale = opened.staleNotes;
      await for (final event in worker.run(
        RebuildIndexCommand(force: force, stale: stale),
      )) {
        // Vault closed (or swapped) under us — the events belong to nothing now.
        if (opened != vault) return;
        switch (event) {
          case IndexProgressEvent(:final complete, :final total):
            if (onProgress != null) {
              onProgress(complete, total);
            } else if (showProgress) {
              rebuildProgress = total == 0 ? 1 : complete / total;
              status = 'Rebuilding index: $complete / $total';
              notifyListeners();
            }
          case IndexBuiltEvent(:final index):
            // Publish notes and tasks now, before the much slower validation +
            // search-index build — on SAF vaults that build reads many files and
            // must never gate the notes the UI needs (Journal, Library, Today).
            // _retainIndex builds linkResolver too; communities arrive below.
            this.index = _retainIndex(index);
            indexedRevision = revision;
            opened.clearStaleNotes(stale);
            if (showProgress) {
              status = 'Indexed · ${index.notes.length} notes · building search…';
            }
            notifyListeners();
            unawaited(_reconcileTasks(index.tasks));
          case CommunitiesBuiltEvent(:final communities):
            unawaited(refreshDerived(precomputed: communities));
          case PkmsBuiltEvent(:final report):
            // No search index to copy — it stays in the worker and is reached
            // through [searchNotes].
            validation = _retainValidation(report);
            if (showProgress) {
              status = 'Index rebuilt · ${report.summary()}';
            } else if (updateStatus) {
              status = 'Indexed · ${report.summary()}';
            }
            notifyListeners();
          case WorkFailedEvent(:final message, :final cancelled):
            if (cancelled) {
              status = 'Index rebuild cancelled';
              notifyListeners();
            } else if (showProgress || updateStatus) {
              status = 'Index refresh failed: $message';
              notifyListeners();
            }
          case WorkDoneEvent():
            break;
        }
      }
  }

  /// Pre-worker path, kept for controllers built with an explicit [inspector]
  /// (tests) and for the storage-override open.
  Future<void> _scanInProcess(
    Vault opened, {
    required int revision,
    required bool force,
    required bool showProgress,
    required bool updateStatus,
    void Function(int complete, int total)? onProgress,
  }) async {
    try {
      final built = await opened.rebuildIndex(
        inspector: inspector,
        force: force,
        deviceId: deviceId,
        isCancelled: showProgress ? () => cancelRebuild : null,
        // Throttled here rather than in the callback so both paths tick at the
        // same rate — the worker path throttles worker-side, before the port.
        onProgress: (onProgress == null && !showProgress)
            ? null
            : (complete, total) {
                if (complete % 100 != 0 && complete != total) return;
                if (onProgress != null) {
                  onProgress(complete, total);
                  return;
                }
                rebuildProgress = total == 0 ? 1 : complete / total;
                status = 'Rebuilding index: $complete / $total';
                notifyListeners();
              },
      );
      if (showProgress) {
        if (opened != vault) return;
        index = _retainIndex(built);
        unawaited(refreshDerived());
        indexedRevision = revision;
        status = 'Indexed · ${built.notes.length} notes · building search…';
        notifyListeners();
        unawaited(_reconcileTasks(built.tasks));
        final pkms = await _readPkms(opened, built);
        validation = _retainValidation(pkms.report);
        searchIndex.replaceWith(pkms.search);
        status = 'Index rebuilt · ${pkms.report.summary()}';
        notifyListeners();
        return;
      }
      final pkms = await _readPkms(opened, built);
      if (opened != vault) return;
      index = _retainIndex(built);
      unawaited(refreshDerived());
      validation = _retainValidation(pkms.report);
      searchIndex.replaceWith(pkms.search);
      indexedRevision = revision;
      if (updateStatus) status = 'Indexed · ${pkms.report.summary()}';
      notifyListeners();
      unawaited(_reconcileTasks(built.tasks));
    } on IndexBuildCancelled {
      status = 'Index rebuild cancelled';
      notifyListeners();
    } catch (error) {
      if (showProgress || updateStatus) {
        status = 'Index refresh failed: $error';
        notifyListeners();
      }
    }
  }

  void queueCloudSync() {
    _cloudAutosave?.cancel();
    final edited = lastEditAt;
    final elapsed = edited == null
        ? Duration.zero
        : DateTime.now().difference(edited);
    final remaining = const Duration(seconds: 10) - elapsed;
    _cloudAutosave = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _runIdleMaintenance,
    );
  }

  void startCloudPolling() {
    _cloudPoll?.cancel();
    if (!(cloud?.isReady ?? false)) return;
    _cloudPoll = Timer.periodic(
      const Duration(seconds: 25),
      (_) => unawaited(pollTick()),
    );
  }

  /// Stops the background cloud poll, e.g. while the app is backgrounded.
  void stopCloudPolling() {
    _cloudPoll?.cancel();
  }

  /// One 25s poll tick's worth of work. Exposed (not just called from the
  /// [Timer] in [startCloudPolling]) so tests can drive it directly instead
  /// of waiting on a real 25-second timer.
  @visibleForTesting
  Future<void> pollTick() async {
    if (syncing || editingRecently) return;
    if (hasSyncConflicts) {
      // A conflict record self-healed on disk (loadSyncConflicts deletes
      // matching snapshots) doesn't refresh this in-memory list on its own,
      // and hasSyncConflicts gates every poll — without this refresh a
      // phantom conflict would suppress auto-sync forever. Cheap: only
      // lists the conflicts directory, no full sync.
      await refreshSyncConflicts();
      return;
    }
    final opened = vault;
    final config = cloud;
    if (opened != null && config != null && config.isReady) {
      final unchanged = await NextcloudSync(
        config,
      ).pollIsUnchanged(opened, dirty: dirty || isComposing());
      // State may have changed while the network probe was in flight.
      if (syncing || editingRecently) return;
      if (unchanged) return;
    }
    await syncNow(trigger: 'poll');
  }

  /// Re-reads conflict records from disk and refreshes [syncConflicts].
  /// Used to clear a phantom in-memory conflict that self-heal already
  /// resolved on disk (see [startCloudPolling]), and to keep the sync
  /// dashboard in sync with disk state when it opens.
  Future<void> refreshSyncConflicts() async {
    final opened = vault;
    if (opened == null) return;
    syncConflicts = await loadSyncConflicts(opened);
    notifyListeners();
  }

  /// Rebuilds [mergedReading] from every `_system/reading/*.json` device
  /// file in the vault: union of all recents, newest openedAt wins per path.
  /// Corrupt or unreadable files are skipped — reading state is best-effort.
  Future<void> reloadReadingState() async {
    final opened = vault;
    if (opened == null) return;
    final byPath = <String, RecentNote>{};
    List<VaultStorageEntry> files;
    try {
      files = await opened.storage.list(path: '_system/reading');
    } catch (_) {
      files = const [];
    }
    for (final file in files) {
      if (file.isDirectory || !file.path.endsWith('.json')) continue;
      try {
        final json =
            jsonDecode(await opened.storage.readText(file.path))
                as Map<String, Object?>;
        for (final item in json['recent'] as List? ?? const []) {
          final recent = RecentNote.fromJson(
            (item as Map).cast<String, Object?>(),
          );
          final existing = byPath[recent.path];
          if (existing == null || recent.openedAt.isAfter(existing.openedAt)) {
            byPath[recent.path] = recent;
          }
        }
      } catch (_) {
        // Skip this device file; the rest still merge.
      }
    }
    mergedReading = byPath.values.toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    notifyListeners();
  }

  Future<bool> syncNow({
    String trigger = 'manual',
    NextcloudConfig? configOverride,
    InitialSyncMode? initialMode,
  }) async {
    final opened = vault;
    final config = configOverride ?? cloud;
    if (opened == null) return false;
    if (config == null || !config.isReady) {
      throw const WorkspaceSyncNotConfigured();
    }
    if (syncing) return false;
    final local = localDirectory;
    if (local != null && isNextcloudManagedVault(local)) {
      status = 'Sync handled by Nextcloud Desktop';
      notifyListeners();
      return true;
    }
    // Single-owner rule: the background worker (vault_service.dart) may be
    // mid-sync in its own engine. Taking the lock as 'ui' both blocks while
    // it holds a fresh lock and keeps it out until we release.
    if (!await VaultLock.acquire(opened.storage, 'ui')) {
      status = 'Background sync in progress';
      notifyListeners();
      return false;
    }
    // 'resume' included: a resume sync starts the instant the app foregrounds,
    // and users routinely background it again mid-run — without the service
    // Android freezes the run at its first network stage ("stuck on
    // prepare-remote-folder") until the next foreground.
    final keepRunningOffscreen =
        Platform.isAndroid &&
        const {'setup', 'manual', 'retry', 'resume'}.contains(trigger);
    syncing = true;
    syncError = null;
    status = 'Syncing…';
    _cloudAutosave?.cancel();
    notifyListeners();
    // Inside the try from here on. `_startSyncForeground` swallows its own
    // throws, but a platform channel that never *completes* would strand
    // `syncing` at true with no sync running — and every Sync-dashboard action
    // refuses to act while that flag is set.
    try {
      if (keepRunningOffscreen) {
        await _startSyncForeground('Preparing Nextcloud sync…');
      }
      if (dirty) {
        await save(syncAfter: false);
        if (dirty) {
          // Without this the status string stays 'Syncing…' forever, which is
          // what made the dashboard claim a sync was running while the banner
          // said sync was paused.
          status = 'Sync postponed — unsaved changes';
          return false;
        }
      }
      final syncedNote = note;
      final sourceBeforeSync = syncedNote == null ? null : source;
      final revisionBeforeSync = editRevision;
      final result = await NextcloudSync(
        config,
        onProgress: (stage, path) {
          syncStage = stage == 'idle'
              ? null
              : path == null
              ? stage
              : '$stage · $path';
          // onProgress fires twice per file; a notification nobody can read
          // that fast isn't worth a platform-channel hop each time.
          if (keepRunningOffscreen && syncStage != null) {
            final now = DateTime.now();
            final last = _lastForegroundNotice;
            if (last == null ||
                now.difference(last) >= const Duration(milliseconds: 500)) {
              _lastForegroundNotice = now;
              unawaited(_updateSyncForeground(syncStage!));
            }
          }
          syncProgressTick.notifyListeners();
        },
        canReplaceLocal: (path) =>
            path != syncedNote ||
            (revisionBeforeSync == editRevision && !dirty),
      ).sync(opened, trigger: trigger, initialMode: initialMode);
      var concurrentConflict = false;
      if (syncedNote != null && syncedNote == note) {
        final diskExists = await opened.storage.exists(syncedNote);
        final diskSource = diskExists
            ? await opened.storage.readText(syncedNote)
            : null;
        final editorChanged = revisionBeforeSync != editRevision || dirty;
        if (editorChanged &&
            diskSource != sourceBeforeSync &&
            diskSource != source &&
            diskSource != _lastSavedSource) {
          await createSyncConflict(
            opened,
            syncedNote,
            localBytes: utf8.encode(source),
            remoteBytes: diskSource == null ? null : utf8.encode(diskSource),
          );
          await opened.saveNote(syncedNote, source);
          _lastSavedSource = source;
          concurrentConflict = true;
        } else if (editorChanged && diskSource != sourceBeforeSync) {
          // The disk holds something this controller itself wrote — either
          // exactly what the editor shows, or the last 400ms autosave that
          // landed mid-sync before the user kept typing. Both versions are
          // this session's own writes: nothing foreign, no conflict. Flush
          // the buffer if it has moved past the autosave on disk.
          if (diskSource != source) {
            await opened.saveNote(syncedNote, source);
            _lastSavedSource = source;
          }
        } else if (!editorChanged && diskSource != sourceBeforeSync) {
          source = diskSource ?? '';
        }
      }
      final conflicts = await loadSyncConflicts(opened);
      // Decoupled from the scan below: a peer's reading file is the whole
      // point of cross-device progress, but pulling it says nothing about the
      // vault's *content*, so it must not drag a full rescan along with it.
      if (result.downloadedReadingState) await reloadReadingState();
      if (result.requiresIndexRefresh ||
          concurrentConflict ||
          indexedRevision < savedRevision) {
        syncStage = 'index-local-changes';
        rebuildProgress = 0;
        notifyListeners();
        try {
          // Through _scan, not opened.rebuildIndex: this is the *most frequent*
          // reindex trigger — any sync that changed anything — so running it
          // inline here would have left the common case on the root isolate and
          // undone the whole point of the worker. Sync owns the status line, so
          // the built-in status updates are suppressed and progress is routed to
          // syncProgressTick instead.
          await _scan(
            opened,
            updateStatus: false,
            onProgress: (complete, total) {
              rebuildProgress = total == 0 ? 1 : complete / total;
              syncProgressTick.notifyListeners();
            },
          );
        } finally {
          rebuildProgress = null;
          syncProgressTick.notifyListeners();
        }
      }
      lastSync = result;
      lastSyncAt = DateTime.now();
      syncConflicts = conflicts;
      final changed =
          result.uploaded +
          result.downloaded +
          result.deletedLocal +
          result.deletedRemote +
          result.repaired +
          result.renamed;
      status = conflicts.isNotEmpty || concurrentConflict
          ? 'Needs attention'
          : changed == 0
          ? 'Up to date'
          : 'Synced';
      notifyListeners();
      return true;
    } on SyncDeferred {
      status = 'Sync deferred while editing';
      queueCloudSync();
      notifyListeners();
      return false;
    } catch (error, stack) {
      debugPrintStack(
        label: 'Nextcloud sync failed: $error',
        stackTrace: stack,
      );
      syncConflicts = await loadSyncConflicts(opened);
      await refreshIndex(updateStatus: false, always: true);
      syncError = syncConflicts.isEmpty ? friendlySyncError(error) : null;
      status = syncConflicts.isEmpty ? syncError! : 'Needs attention';
      notifyListeners();
      return false;
    } finally {
      // Clear the flag *before* the two awaits, not after: a hang in either
      // would otherwise leave `syncing` true with no sync running, which locks
      // every action on the Sync dashboard.
      syncing = false;
      syncStage = null;
      notifyListeners();
      await VaultLock.release(opened.storage, 'ui');
      if (keepRunningOffscreen) await _stopSyncForeground();
    }
  }

  Future<void> resolveConflict(
    SyncConflict conflict,
    SyncConflictResolution resolution, {
    String? mergedText,
  }) async {
    final opened = vault;
    final config = cloud;
    if (opened == null || config == null || !config.isReady) return;
    try {
      await NextcloudSync(
        config,
      ).resolveConflict(opened, conflict, resolution, mergedText: mergedText);
      await refreshIndex(updateStatus: false, always: true);
      // Refresh from disk rather than just filtering out this one id: a
      // resolve can also self-heal other now-matching records.
      syncConflicts = await loadSyncConflicts(opened);
      syncError = null;
      status = syncConflicts.isEmpty ? 'Conflict resolved' : 'Needs attention';
    } catch (error) {
      // Keep the conflict in the list rather than silently dropping it —
      // an error here (e.g. the remote moved again) must stay visible, not
      // leave the user thinking it resolved when it didn't.
      syncError = friendlySyncError(error);
      status = 'Needs attention';
    }
    notifyListeners();
  }

  Future<bool> probeStorage() async {
    final storage = vault?.storage;
    if (storage == null) return false;
    const path = '.tylog/.storage-health';
    try {
      await storage.writeText(path, 'ok');
      final valid = await storage.readText(path) == 'ok';
      await storage.delete(path);
      storageHealthy = valid;
      return valid;
    } catch (_) {
      try {
        await storage.delete(path);
      } catch (_) {}
      storageHealthy = false;
      return false;
    }
  }

  void updateStatus(String value) {
    status = value;
    notifyListeners();
  }

  void cancelPendingWork() => _cancelTimers();

  Future<void> _startSyncForeground(String detail) => _syncForeground(
    () => AndroidTreeVaultStorage.startSyncForeground(detail: detail),
  );

  Future<void> _updateSyncForeground(String detail) => _syncForeground(
    () => AndroidTreeVaultStorage.updateSyncForeground(detail: detail),
  );

  Future<void> _stopSyncForeground() =>
      _syncForeground(AndroidTreeVaultStorage.stopSyncForeground);

  Future<void> _syncForeground(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      // Checkpoints still make the sync resumable if Android rejects a
      // foreground-service start (for example, from a background context).
      debugPrint('Android sync foreground service unavailable: $error');
    }
  }

  void replaceNote(String path, String value) {
    note = path;
    source = value;
    _setDirty(false);
    savedRevision = editRevision;
    notifyListeners();
  }

  /// Full-text search, wherever the index happens to live.
  ///
  /// On the worker path it is a message round-trip; on the in-process path (an
  /// explicit [inspector], i.e. tests) it queries the local [searchIndex]. Async
  /// either way so callers do not have to know which.
  Future<List<PkmsSearchResult>> searchNotes(
    String query, {
    String? tag,
    String? status,
    int limit = 50,
  }) async {
    final worker = _worker;
    if (worker == null) {
      return searchIndex.search(query, tag: tag, status: status, limit: limit);
    }
    return worker.search(query, tag: tag, status: status, limit: limit);
  }

  Future<({PkmsValidationReport report, PkmsSearchIndex search})> _readPkms(
    Vault opened,
    VaultIndex built,
  ) async {
    final report = await validatePkmsStorage(opened.storage, built);
    // Surface unparseable task recurrence rules (rrule lives in the app layer,
    // not tylog_core) into the same Problems report the UI already shows.
    report.problems.addAll(validateTaskRecurrences(built.tasks));
    final cached = await PkmsSearchIndex.loadStorage(
      opened.storage,
      Vault.searchIndexPath,
    );
    final search = await PkmsSearchIndex.buildStorage(
      opened.storage,
      built,
      previous: cached,
    );
    await search.saveStorage(opened.storage, Vault.searchIndexPath);
    return (report: report, search: search);
  }

  PkmsValidationReport _retainValidation(PkmsValidationReport next) {
    final current = validation;
    if (current == null) return next;
    current.problems
      ..clear()
      ..addAll(next.problems);
    return current;
  }

  VaultIndex _retainIndex(VaultIndex next) {
    // Bumped for every index assignment, including the in-place path below.
    // Anything derived from the index caches against this, and must not cache
    // against the index *object*: the whole point of retaining is that the
    // identity never changes, so `identical(index, cached)` would be true
    // forever and the cache would never invalidate.
    indexRevision++;
    // Every index assignment funnels through here, which makes this the one
    // place that can guarantee the resolver is never stale-or-absent while an
    // index exists. That matters because the callers that need it run inside
    // build: without a retained resolver they each construct a whole-vault one
    // per link (O(vault) per mention chip per repaint).
    linkResolver = LinkResolver(next.notes);
    final current = index;
    if (current == null || current.version != next.version) return next;
    current.notesByPath
      ..clear()
      ..addAll(next.notesByPath);
    current.backlinksByTarget
      ..clear()
      ..addAll(next.backlinksByTarget);
    current.attachmentBacklinksByPath
      ..clear()
      ..addAll(next.attachmentBacklinksByPath);
    current.problems
      ..clear()
      ..addAll(next.problems);
    current.tasks
      ..clear()
      ..addAll(next.tasks);
    return current;
  }

  Future<void> _runIdleMaintenance() async {
    if (dirty || isComposing()) return;
    if (editingRecently) {
      queueCloudSync();
      return;
    }
    if (syncing) {
      _cloudAutosave = Timer(const Duration(seconds: 1), _runIdleMaintenance);
      return;
    }
    if ((cloud?.isReady ?? false) && !hasSyncConflicts) {
      await syncNow(trigger: 'autosave');
      return;
    }
    await refreshIndex();
  }

  Future<void> _sweepSafBackups(Vault opened) async {
    try {
      for (final item in await opened.storage.list(recursive: true)) {
        if (!item.isDirectory &&
            (isSafBackupPath(item.path) ||
                isForkedVaultLockPath(item.path))) {
          await opened.storage.delete(item.path);
        }
      }
    } catch (_) {}
  }

  void _cancelTimers() {
    _autosave?.cancel();
    _cloudAutosave?.cancel();
    _cloudPoll?.cancel();
  }

  void _shutdownWorker() {
    final worker = _worker;
    _worker = null;
    _indexing = false;
    unawaited(worker?.dispose() ?? Future<void>.value());
  }

  @override
  void dispose() {
    _disposed = true;
    dirtyNotifier.dispose();
    syncProgressTick.dispose();
    _cancelTimers();
    _shutdownWorker();
    super.dispose();
  }
}

bool _notComposing() => false;

/// Whether the Today note shown on [openedAt] should be refreshed because
/// [now] falls on a different calendar day (day rollover while backgrounded).
bool shouldRolloverToday({required DateTime openedAt, required DateTime now}) {
  return openedAt.year != now.year ||
      openedAt.month != now.month ||
      openedAt.day != now.day;
}

String friendlySyncError(Object error) {
  if (error is SocketException || error is TimeoutException) {
    return 'Nextcloud connection was interrupted. Progress was saved; Retry resumes.';
  }
  if (error is HandshakeException) {
    return 'Nextcloud security certificate could not be verified.';
  }
  if (error is FileSystemException) {
    return 'TyLog could not update the local vault: '
        '${error.osError?.message ?? error.message}';
  }
  if (error is FormatException) return 'Sync data could not be read.';
  final text = error is HttpException ? error.message : error.toString();
  if (text.contains('401') || text.contains('403')) {
    return 'Nextcloud rejected the login. Re-enter the app password.';
  }
  if (text.contains('404')) {
    return 'The configured Nextcloud folder was not found.';
  }
  if (text.contains('PROPFIND invalid file metadata')) {
    return 'Nextcloud returned invalid file metadata.';
  }
  if (text.contains('507')) return 'Nextcloud is out of storage space.';
  return 'Sync stopped before completion: $text';
}

/// Top-level entry for `compute()` — runs community detection off the UI
/// thread. Mirrors `runForceLayout` in lib/graph.dart. `computeCommunities` is
/// deterministic and touches nothing but its argument, so it is isolate-safe.
CommunityMap computeCommunitiesIsolate(VaultIndex index) =>
    computeCommunities(index);
