import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'nextcloud_sync.dart';
import 'pkms_registry.dart';
import 'scanner.dart';
import 'search_index.dart';
import 'task_scheduler.dart';
import 'tylog_assets.dart';
import 'vault.dart';
import 'vault_registry.dart';
import 'vault_storage.dart';

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
  int editRevision = 0;
  int savedRevision = 0;
  int indexedRevision = 0;
  DateTime? lastEditAt;
  String helperSource = '';
  Map<String, Uint8List> typstPackageFiles = const {};
  String bibliographySource = '';
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

  Timer? _autosave;
  Timer? _cloudAutosave;
  Timer? _cloudPoll;

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
    vault = null;
    entry = null;
    note = null;
    index = null;
    validation = null;
    searchIndex = PkmsSearchIndex.empty();
    helperSource = '';
    typstPackageFiles = const {};
    bibliographySource = '';
    cloud = nextCloud;
    lastSync = null;
    syncConflicts = const [];
    lastSyncAt = null;
    syncError = null;
    storageHealthy = false;
    dirty = false;
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
      index = await opened.loadIndex();
      validation = null;
      searchIndex = PkmsSearchIndex.empty();
      helperSource = await opened.storage.readText(Vault.helperPath);
      typstPackageFiles = loadedFiles;
      bibliographySource = await opened.storage.exists(Vault.bibliographyPath)
          ? await opened.storage.readText(Vault.bibliographyPath)
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
      dirty = false;
      source = await opened.storage.readText(today);
      status = 'Vault opened — indexing…';
      notifyListeners();
      unawaited(_sweepSafBackups(opened));
      if (next.cloud?.isReady ?? false) {
        if (trigger != null) unawaited(syncNow(trigger: trigger));
        startCloudPolling();
      }
      // Heavy index + search-index build runs in the background, using the
      // on-disk cache/fingerprints (force: false) so it's much faster than a
      // full rebuild.
      unawaited(rebuildIndex(force: false));
    } catch (error) {
      close('Open failed: $error', nextCloud: next.cloud);
    }
  }

  void edit(String value) {
    source = value;
    editRevision++;
    lastEditAt = DateTime.now();
    final becameDirty = !dirty;
    dirty = true;
    if (becameDirty) status = 'Autosave pending...';
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 400), save);
    notifyListeners();
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
      if (revision == editRevision && path == note) {
        savedRevision = revision;
        dirty = false;
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

  Future<void> ensureIndexed() async {
    if (dirty) await save(syncAfter: false);
    await refreshIndex();
  }

  Future<void> refreshIndex({
    bool updateStatus = true,
    bool force = false,
  }) async {
    final opened = vault;
    if (opened == null || (!force && indexedRevision >= savedRevision)) return;
    final revision = savedRevision;
    try {
      final built = await opened.rebuildIndex(
        inspector: inspector,
        force: force,
      );
      final pkms = await _readPkms(opened, built);
      if (opened != vault) return;
      index = _retainIndex(built);
      validation = _retainValidation(pkms.report);
      searchIndex.replaceWith(pkms.search);
      indexedRevision = revision;
      if (updateStatus) status = 'Indexed · ${pkms.report.summary()}';
      notifyListeners();
      unawaited(_reconcileTasks(built.tasks));
    } catch (error) {
      if (updateStatus) {
        status = 'Index refresh failed: $error';
        notifyListeners();
      }
    }
  }

  Future<void> rebuildIndex({bool force = true}) async {
    final opened = vault;
    if (opened == null) return;
    if (rebuilding) {
      cancelRebuild = true;
      return;
    }
    rebuilding = true;
    cancelRebuild = false;
    rebuildProgress = 0;
    status = 'Rebuilding index...';
    notifyListeners();
    try {
      final built = await opened.rebuildIndex(
        inspector: inspector,
        force: force,
        isCancelled: () => cancelRebuild,
        onProgress: (complete, total) {
          if (complete % 100 != 0 && complete != total) return;
          rebuildProgress = total == 0 ? 1 : complete / total;
          status = 'Rebuilding index: $complete / $total';
          notifyListeners();
        },
      );
      // The scan already has every note and task. Publish them to the UI now,
      // before the much slower validation + search-index build — on SAF vaults
      // that build reads many files and must never gate the notes the UI needs
      // (Journal, Library, Today all read `index`).
      index = _retainIndex(built);
      indexedRevision = savedRevision;
      status = 'Indexed · ${built.notes.length} notes · building search…';
      notifyListeners();
      unawaited(_reconcileTasks(built.tasks));
      // Heavier pass: validation + full-text search index. Refined in place so a
      // slow/stalled search build can't blank out the already-visible notes.
      final pkms = await _readPkms(opened, built);
      validation = _retainValidation(pkms.report);
      searchIndex.replaceWith(pkms.search);
      status = 'Index rebuilt · ${pkms.report.summary()}';
      notifyListeners();
    } on IndexBuildCancelled {
      status = 'Index rebuild cancelled';
      notifyListeners();
    } finally {
      rebuilding = false;
      rebuildProgress = null;
      notifyListeners();
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
    if (keepRunningOffscreen) {
      await _startSyncForeground('Preparing Nextcloud sync…');
    }
    try {
      if (dirty) {
        await save(syncAfter: false);
        if (dirty) return false;
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
          if (keepRunningOffscreen && syncStage != null) {
            unawaited(_updateSyncForeground(syncStage!));
          }
          notifyListeners();
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
            diskSource != source) {
          await createSyncConflict(
            opened,
            syncedNote,
            localBytes: utf8.encode(source),
            remoteBytes: diskSource == null ? null : utf8.encode(diskSource),
          );
          await opened.saveNote(syncedNote, source);
          concurrentConflict = true;
        } else if (editorChanged && diskSource != sourceBeforeSync) {
          // The disk already holds exactly what the editor shows: our own
          // 400ms autosave landed mid-sync. Nothing diverged, nothing to
          // reconcile, and no data is at risk — just move on.
        } else if (!editorChanged && diskSource != sourceBeforeSync) {
          source = diskSource ?? '';
        }
      }
      final indexedThroughRevision = savedRevision;
      final conflicts = await loadSyncConflicts(opened);
      if (result.requiresIndexRefresh ||
          concurrentConflict ||
          indexedRevision < savedRevision) {
        syncStage = 'index-local-changes';
        notifyListeners();
        final built = await opened.rebuildIndex(inspector: inspector);
        final pkms = await _readPkms(opened, built);
        index = _retainIndex(built);
        validation = _retainValidation(pkms.report);
        searchIndex.replaceWith(pkms.search);
        indexedRevision = indexedThroughRevision;
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
      await refreshIndex(updateStatus: false, force: true);
      syncError = syncConflicts.isEmpty ? friendlySyncError(error) : null;
      status = syncConflicts.isEmpty ? syncError! : 'Needs attention';
      notifyListeners();
      return false;
    } finally {
      if (keepRunningOffscreen) await _stopSyncForeground();
      syncing = false;
      syncStage = null;
      notifyListeners();
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
      await refreshIndex(updateStatus: false, force: true);
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

  void updateCloud(NextcloudConfig? value) {
    cloud = value;
    notifyListeners();
  }

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
    dirty = false;
    savedRevision = editRevision;
    notifyListeners();
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
        if (!item.isDirectory && isSafBackupPath(item.path)) {
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

  @override
  void dispose() {
    _cancelTimers();
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
