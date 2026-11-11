part of '../app_mobile.dart';

extension _SyncFlow on _HomeScreenState {
  Future<void> _syncNow({String trigger = 'manual'}) async {
    try {
      await workspace.syncNow(trigger: trigger);
    } on WorkspaceSyncNotConfigured {
      await _showSyncSettings();
    }
  }

  Future<bool> _showSyncSettings() async {
    if (workspace.syncing) {
      showSnack(context, 'Sync already in progress');
      return false;
    }
    final vaultId = vaultRegistry?.activeId;
    var cfg =
        await NextcloudConfig.load(vaultId: vaultId) ??
        cloud ??
        await NextcloudConfig.load();
    if (!mounted) return false;
    while (true) {
      if (!mounted) return false;
      if (workspace.syncing) {
        showSnack(context, 'Sync already in progress');
        return false;
      }
      final saved = await showDialog<NextcloudConfig>(
        context: context,
        builder: (context) => NextcloudConnectDialog(config: cfg),
      );
      if (saved == null || !mounted) return false;
      cfg = saved;
      final opened = vault;
      final registry = vaultRegistry;
      if (opened == null || registry == null) return false;
      try {
        final local = await inspectLocalSync(opened);
        final remote = await NextcloudSync(saved).inspectRemoteVault();
        if (!mounted) return false;
        if (remote.kind == RemoteVaultKind.nonVault) {
          await _showNextcloudSetupError(
            'This cloud folder contains files but is not a TyLog vault. Choose another folder.',
          );
          continue;
        }
        final mode = await _confirmInitialSync(local, remote);
        if (mode == null || !mounted) return false;
        await registry.setCloud(registry.active, saved);
        if (!mounted) return false;
        _rebuild(() {
          cloud = saved;
          status = 'Nextcloud connected · starting initial sync';
        });
        final connected = await workspace.syncNow(
          trigger: 'setup',
          configOverride: saved,
          initialMode: mode,
        );
        if (!connected) return false;
        _rebuild(() {
          status = 'Nextcloud connected';
        });
        _startCloudPolling();
        return true;
      } catch (error) {
        if (!mounted) return false;
        await _showNextcloudSetupError(friendlySyncError(error));
      }
    }
  }

  Future<InitialSyncMode?> _confirmInitialSync(
    LocalSyncInspection local,
    RemoteVaultInspection remote,
  ) async {
    final localHasData = local.hasUserContent;
    final remoteHasData =
        remote.kind == RemoteVaultKind.validVault && remote.userFileCount > 0;
    final mode = initialSyncModeFor(
      localHasData: localHasData,
      remoteHasData: remoteHasData,
    );
    final (title, message, action) = switch ((localHasData, remoteHasData)) {
      (false, false) => (
        'Start new cloud sync?',
        'Both vaults are empty. TyLog will create the cloud folder and upload the starter vault.',
        'Start sync',
      ),
      (true, false) => (
        'Upload local vault?',
        'The local vault has ${local.userFileCount} user files and the cloud folder is empty.',
        'Upload local vault',
      ),
      (false, true) => (
        'Use cloud vault?',
        'The cloud vault has ${remote.userFileCount} user files. TyLog will download them and replace only untouched starter notes.',
        'Use cloud vault',
      ),
      (true, true) => (
        'Merge both vaults?',
        'Unique files will copy both ways. Different files at the same path become conflicts; nothing is deleted.',
        'Safe merge',
      ),
    };
    final confirmed = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: action,
      barrierDismissible: false,
    );
    return confirmed ? mode : null;
  }

  Future<void> _showNextcloudSetupError(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nextcloud not connected'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to setup'),
        ),
      ],
    ),
  );

  Future<void> _showSyncDashboard() async {
    // A conflict may have self-healed on disk since the last sync without
    // this screen's data being refreshed; catch it up before showing.
    await workspace.refreshSyncConflicts();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SyncDashboardScreen(
          load: _loadSyncDashboard,
          onSync: () => _syncNow(),
          onConfigure: _showSyncSettings,
          onResolve: _resolveSyncConflict,
          onResolveAll: _resolveAllSyncConflicts,
          onCopyDiagnostics: _copySyncDiagnostics,
        ),
      ),
    );
  }

  Future<SyncDashboardData> _loadSyncDashboard() async {
    final v = vault;
    if (v == null) {
      final active = _activeRegistryEntry;
      final error = syncError ?? (status == 'Opening vault...' ? null : status);
      return SyncDashboardData(
        storageName: active?.name ?? 'Vault not open',
        storageLocation: vaultEntryLocation(active) ?? '',
        cloud: active?.cloud ?? cloud,
        syncing: syncing,
        stage: syncStage == null ? null : syncStageLabel(syncStage!),
        error: error,
        result: lastSync,
        lastSyncAt: lastSyncAt,
        vaultOpen: false,
        desktopManaged: false,
        storageHealthy: false,
        conflicts: const [],
        events: const [],
      );
    }
    const tracePath = '.tylog/sync_trace.jsonl';
    final events = <Map<String, Object?>>[];
    final local = await deviceLocalStorage(v.storage);
    if (await local.exists(tracePath)) {
      for (final line in (await local.readText(tracePath)).split('\n')) {
        if (line.trim().isEmpty) continue;
        try {
          events.add((jsonDecode(line) as Map).cast<String, Object?>());
        } catch (_) {}
      }
    }
    final entry = vaultRegistry!.active;
    final healthy = storageHealthy ?? await workspace.probeStorage();
    return SyncDashboardData(
      storageName: entry.name,
      storageLocation: switch (entry.storageKind) {
        'android-tree' => entry.treeUri ?? entry.name,
        'app-local' => 'App storage',
        _ => entry.path,
      },
      backupPath: await _existingBackup(entry.backupPath),
      cloud: cloud,
      syncing: syncing,
      stage: syncStage == null ? null : syncStageLabel(syncStage!),
      error: syncError,
      result: lastSync,
      lastSyncAt: lastSyncAt,
      vaultOpen: true,
      desktopManaged:
          _localVaultDirectory != null &&
          isNextcloudManagedVault(_localVaultDirectory!),
      storageHealthy: healthy,
      conflicts: syncConflicts,
      events: events.reversed.toList(),
    );
  }

  Future<void> _resolveAllSyncConflicts(
    SyncConflictResolution resolution,
  ) async {
    final pending = workspace.syncConflicts.length;
    if (pending == 0) return;
    final keepingLocal = resolution == SyncConflictResolution.keepLocal;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Resolve $pending conflicts?',
      message: keepingLocal
          ? "This uploads this device's copy of $pending files, replacing what "
                'is on Nextcloud. Anything the other side added to them is lost.'
          : 'This overwrites this device\'s copy of $pending files with what '
                'is on Nextcloud. Anything you changed here is lost.',
      confirmLabel: 'Resolve $pending',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final resolved = await workspace.resolveAllConflicts(resolution);
    if (!mounted) return;
    final left = workspace.syncConflicts.length;
    showSnack(
      context,
      left == 0
          ? 'Resolved $resolved conflicts'
          : 'Resolved $resolved; $left still need review',
    );
  }

  Future<void> _resolveSyncConflict(SyncConflict conflict) async {
    final v = vault;
    final cfg = cloud;
    if (v == null || cfg == null || !cfg.isReady) return;
    if (note == conflict.path && dirty && !await _save(syncAfter: false)) {
      if (mounted) showSnack(context, 'Could not save the open note.');
      return;
    }
    final localBytes = await v.storage.exists(conflict.path)
        ? await v.storage.readBytes(conflict.path)
        : null;
    // The record decides whether a remote side exists at all; the snapshot of a
    // deleted remote must never be presented as "the Nextcloud version".
    final remoteBytes = conflictRemoteBytesToShow(
      conflict,
      conflict.remoteSnapshot == null
          ? null
          : await v.storage.readBytes(conflict.remoteSnapshot!),
    );
    final localText = conflict.isText && localBytes != null
        ? utf8.decode(localBytes, allowMalformed: true)
        : null;
    final remoteText = conflict.isText && remoteBytes != null
        ? utf8.decode(remoteBytes, allowMalformed: true)
        : null;
    if (!mounted) return;
    final shape = conflictShape(local: localText, remote: remoteText);
    // Null preselects nothing, forcing an explicit choice wherever a default
    // could discard the other side. See defaultResolution.
    final selected = ValueNotifier<SyncConflictResolution?>(
      defaultResolution(shape),
    );
    final merged = TextEditingController(text: localText ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Resolve sync conflict'),
            leading: IconButton(
              tooltip: 'Cancel',
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(AppIcons.close),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(kSpace16),
            children: [
              Text(
                conflict.path,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: kSpace8),
              if (conflictShapeHint(shape) case final hint?) ...[
                Text(hint, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: kSpace8),
              ],
              ValueListenableBuilder<SyncConflictResolution?>(
                valueListenable: selected,
                builder: (context, value, _) =>
                    RadioGroup<SyncConflictResolution>(
                      groupValue: value,
                      onChanged: (next) {
                        if (next == null) return;
                        selected.value = next;
                        if (next == SyncConflictResolution.keepLocal &&
                            localText != null) {
                          merged.text = localText;
                        } else if (next == SyncConflictResolution.keepRemote &&
                            remoteText != null) {
                          merged.text = remoteText;
                        }
                      },
                      child: Column(
                        children: [
                          RadioListTile<SyncConflictResolution>(
                            value: SyncConflictResolution.keepLocal,
                            title: Text(
                              localBytes != null
                                  ? 'Keep this device version'
                                  : 'Keep deletion from this device',
                            ),
                            subtitle: Text(
                              conflictSideLabel(
                                shape,
                                isLocal: true,
                                text: localText,
                                byteLength: localBytes?.length,
                              ),
                            ),
                          ),
                          RadioListTile<SyncConflictResolution>(
                            value: SyncConflictResolution.keepRemote,
                            title: Text(
                              conflict.remoteExists
                                  ? 'Keep Nextcloud version'
                                  : 'Keep deletion from Nextcloud',
                            ),
                            subtitle: Text(
                              conflictSideLabel(
                                shape,
                                isLocal: false,
                                text: remoteText,
                                byteLength: remoteBytes?.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ),
              if (localText != null && remoteText != null) ...[
                const SizedBox(height: kSpace16),
                Text(
                  'Final version',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: kSpace8),
                TextField(
                  controller: merged,
                  minLines: 12,
                  maxLines: null,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) =>
                      selected.value = SyncConflictResolution.merge,
                ),
              ],
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(kSpace12),
              child: ValueListenableBuilder<SyncConflictResolution?>(
                valueListenable: selected,
                builder: (context, value, _) => FilledButton.icon(
                  // Disabled until a side is chosen: with nothing preselected
                  // there is no safe action to take on the user's behalf.
                  onPressed: value == null
                      ? null
                      : () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check),
                  label: Text(
                    value == null
                        ? 'Choose a version to keep'
                        : 'Save resolution',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final resolution = selected.value;
    if (save == true && resolution != null) {
      try {
        await workspace.resolveConflict(
          conflict,
          resolution,
          mergedText: resolution == SyncConflictResolution.merge
              ? merged.text
              : null,
        );
      } catch (error) {
        if (mounted) _rebuild(() => syncError = friendlySyncError(error));
      }
    }
  }

  Future<void> _copySyncDiagnostics() async {
    final v = vault;
    if (v == null) return;
    const path = '.tylog/sync_trace.jsonl';
    final local = await deviceLocalStorage(v.storage);
    final trace = await local.exists(path)
        ? await local.readText(path)
        : 'No sync trace is available.\n';
    // A hung run never finishes, so the trace file is never written for it;
    // surface the live state up front so a stuck sync is still diagnosable.
    final state =
        'state: syncing=$syncing stage=${syncStage ?? '-'} '
        'lastSyncAt=${lastSyncAt ?? '-'}\n\n';
    await Clipboard.setData(
      ClipboardData(
        text:
            'TyLog ${await appVersion()}\n'
            'Platform: ${Platform.operatingSystem}\n'
            '$state$trace',
      ),
    );
    if (!mounted) return;
    showSnack(context, 'Sync diagnostics copied');
  }
}
