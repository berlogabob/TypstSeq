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
        createIfMissing: !vaultNeedsAndroidTreeMigration(next),
      );
      final today = await opened.todayNote();
      final built = await opened.rebuildIndex(inspector: inspector);
      final pkms = await _readPkms(opened, built);
      final loadedFiles = <String, Uint8List>{};
      for (final asset
          in (await TylogAssets.load()).managedVaultFiles.entries) {
        final bytes = await opened.storage.readBytes(asset.key);
        loadedFiles[asset.key] = bytes;
        loadedFiles['/${asset.key}'] = bytes;
      }
      vault = opened;
      entry = next;
      note = today;
      index = _retainIndex(built);
      validation = _retainValidation(pkms.report);
      searchIndex = pkms.search;
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
      status = 'Vault: ${next.name} · ${pkms.report.summary()}';
      notifyListeners();
      unawaited(_reconcileTasks(built.tasks));
      unawaited(_sweepSafBackups(opened));
      if (next.cloud?.isReady ?? false) {
        if (trigger != null) unawaited(syncNow(trigger: trigger));
        startCloudPolling();
      }
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
    _autosave = Timer(const Duration(milliseconds: 700), save);
    notifyListeners();
  }

  Future<void> save({bool syncAfter = true}) async {
    _autosave?.cancel();
    final opened = vault;
    final path = note;
    if (opened == null || path == null) return;
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

  Future<void> rebuildIndex() async {
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
        force: true,
        isCancelled: () => cancelRebuild,
        onProgress: (complete, total) {
          if (complete % 100 != 0 && complete != total) return;
          rebuildProgress = total == 0 ? 1 : complete / total;
          status = 'Rebuilding index: $complete / $total';
          notifyListeners();
        },
      );
      final pkms = await _readPkms(opened, built);
      index = _retainIndex(built);
      validation = _retainValidation(pkms.report);
      searchIndex.replaceWith(pkms.search);
      indexedRevision = savedRevision;
      status = 'Index rebuilt · ${pkms.report.summary()}';
      notifyListeners();
      unawaited(_reconcileTasks(built.tasks));
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
    _cloudPoll = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!syncing && !editingRecently && !hasSyncConflicts) {
        unawaited(syncNow(trigger: 'poll'));
      }
    });
  }

  Future<void> syncNow({String trigger = 'manual'}) async {
    final opened = vault;
    final config = cloud;
    if (opened == null) return;
    if (config == null || !config.isReady) {
      throw const WorkspaceSyncNotConfigured();
    }
    if (syncing) return;
    final local = localDirectory;
    if (local != null && isNextcloudManagedVault(local)) {
      status = 'Sync handled by Nextcloud Desktop';
      notifyListeners();
      return;
    }
    syncing = true;
    syncError = null;
    status = 'Syncing…';
    _cloudAutosave?.cancel();
    notifyListeners();
    try {
      if (dirty) {
        await save(syncAfter: false);
        if (dirty) return;
      }
      final syncedNote = note;
      final sourceBeforeSync = syncedNote == null ? null : source;
      final revisionBeforeSync = editRevision;
      final result = await NextcloudSync(
        config,
        onProgress: (stage, path) {
          syncStage = path == null ? stage : '$stage · $path';
          notifyListeners();
        },
        canReplaceLocal: (path) =>
            path != syncedNote ||
            (revisionBeforeSync == editRevision && !dirty),
      ).sync(opened, trigger: trigger);
      var concurrentConflict = false;
      if (syncedNote != null && syncedNote == note) {
        final diskExists = await opened.storage.exists(syncedNote);
        final diskSource = diskExists
            ? await opened.storage.readText(syncedNote)
            : null;
        final editorChanged = revisionBeforeSync != editRevision || dirty;
        if (editorChanged && diskSource != sourceBeforeSync) {
          await createSyncConflict(
            opened,
            syncedNote,
            localBytes: utf8.encode(source),
            remoteBytes: diskSource == null ? null : utf8.encode(diskSource),
          );
          await opened.saveNote(syncedNote, source);
          concurrentConflict = true;
        } else if (!editorChanged && diskSource != sourceBeforeSync) {
          source = diskSource ?? '';
        }
      }
      final indexedThroughRevision = savedRevision;
      final built = await opened.rebuildIndex(inspector: inspector);
      final pkms = await _readPkms(opened, built);
      final conflicts = await loadSyncConflicts(opened);
      index = _retainIndex(built);
      validation = _retainValidation(pkms.report);
      searchIndex.replaceWith(pkms.search);
      indexedRevision = indexedThroughRevision;
      lastSync = result;
      lastSyncAt = DateTime.now();
      syncConflicts = conflicts;
      final changed =
          result.uploaded +
          result.downloaded +
          result.deletedLocal +
          result.deletedRemote +
          result.repaired;
      status = conflicts.isNotEmpty || concurrentConflict
          ? 'Needs attention'
          : changed == 0
          ? 'Up to date'
          : 'Synced';
      notifyListeners();
    } on SyncDeferred {
      status = 'Sync deferred while editing';
      queueCloudSync();
      notifyListeners();
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
    } finally {
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
    await NextcloudSync(
      config,
    ).resolveConflict(opened, conflict, resolution, mergedText: mergedText);
    await refreshIndex(updateStatus: false, force: true);
    syncConflicts = syncConflicts
        .where((item) => item.id != conflict.id)
        .toList();
    status = 'Conflict resolved';
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

String friendlySyncError(Object error) {
  if (error is SocketException) return 'Cannot reach Nextcloud';
  if (error is HttpException) return error.message;
  return error.toString();
}
