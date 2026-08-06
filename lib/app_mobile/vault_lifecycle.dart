part of '../app_mobile.dart';

extension _VaultLifecycle on _HomeScreenState {
  void _closeVault(String message, {NextcloudConfig? nextCloud}) {
    selectedTag = null;
    workspace.close(message, nextCloud: nextCloud);
  }

  Future<void> _open() async {
    try {
      try {
        await taskScheduler.initialize((path) => unawaited(_openPath(path)));
      } catch (_) {
        // Notifications are optional on unsupported/test platforms.
      }
      final registry = await VaultRegistry.load();
      vaultRegistry = registry;
      workspace.deviceId = registry.deviceId;
      widget.onThemeModeChanged?.call(themeModeFromName(registry.themeMode));
      if (Platform.isAndroid) {
        if (registry.entries.isEmpty) {
          if (!await _pickVault(closeCurrent: false)) {
            if (mounted) {
              _rebuild(() => status = 'Choose a vault folder to continue');
            }
            return;
          }
        } else if (vaultNeedsAndroidTreeMigration(registry.active)) {
          if (!await _migrateAndroidVault(registry.active)) {
            _closeVault('Choose a vault folder to continue');
            return;
          }
        }
      }
      var active = registry.active;
      try {
        final storage = active.storage;
        if (storage is AndroidTreeVaultStorage &&
            (!await storage.hasAccess() ||
                !await storage.exists(Vault.settingsPath))) {
          throw PlatformException(
            code: 'saf_access_lost',
            message: 'Vault folder access must be granted again',
          );
        }
        await Vault.withStorage(storage).ensureCreated(
          createIfMissing:
              active.storageKind != 'android-tree' &&
              !vaultNeedsAndroidTreeMigration(active),
        );
      } on PlatformException {
        if (active.storageKind != 'android-tree') rethrow;
        final selected = await _chooseAndroidVault(
          allowEmpty: false,
          requiredUri: active.treeUri,
        );
        if (selected == null) {
          _closeVault('Folder access is required to open this vault');
          return;
        }
        active = await registry.rebindTree(active, selected.selection);
        await Vault.withStorage(
          active.storage,
        ).ensureCreated(createIfMissing: false);
      } on StateError {
        if (active.storageKind == 'android-tree') rethrow;
        var path = '${active.path}-v5';
        var suffix = 2;
        while (await Directory(path).exists()) {
          try {
            await Vault(Directory(path)).ensureCreated();
            break;
          } on StateError {
            path = '${active.path}-v5-${suffix++}';
          }
        }
        active = await registry.add(path);
        await registry.select(active);
      }
      await _openVault(active, trigger: 'startup');
      if (!registry.onboardingComplete) await registry.completeOnboarding();
    } catch (e) {
      _closeVault('Open failed: $e', nextCloud: _activeRegistryEntry?.cloud);
    }
  }

  Future<void> _openVault(VaultEntry entry, {String? trigger}) async {
    if (vaultNeedsAndroidTreeMigration(entry)) {
      if (!await _migrateAndroidVault(entry)) {
        _closeVault(
          'Choose a vault folder to continue',
          nextCloud: entry.cloud,
        );
        return;
      }
      return _openVault(vaultRegistry!.active, trigger: trigger);
    }
    await workspace.openVault(entry, trigger: trigger);
    if (mounted) {
      _rebuild(() {
        selectedTag = null;
        mode = 'normal';
      });
    }
  }

  Future<void> _switchVault(VaultEntry entry) async {
    final registry = vaultRegistry;
    if (registry == null || registry.activeId == entry.id) return;
    if (dirty) await _save(syncAfter: false);
    var next = entry;
    if (vaultNeedsAndroidTreeMigration(next)) {
      if (!await _migrateAndroidVault(next)) {
        _closeVault('Choose a vault folder to continue', nextCloud: next.cloud);
        return;
      }
      next = registry.active;
    } else {
      await registry.select(next);
    }
    await _openVault(next);
  }

  Future<bool> _pickVault({bool closeCurrent = true}) async {
    if (closeCurrent && Navigator.canPop(context)) Navigator.pop(context);
    if (Platform.isAndroid) {
      final selected = await _chooseAndroidVault(allowEmpty: true);
      if (selected == null) return false;
      final selection = selected.selection;
      final storage = AndroidTreeVaultStorage(
        uri: selection.uri,
        name: selection.name,
      );
      try {
        final next = Vault.withStorage(storage);
        await next.ensureCreated();
        final registry = vaultRegistry!;
        final entry = await registry.addTree(selection);
        await registry.select(entry);
        await _openVault(entry);
        return true;
      } catch (error) {
        if (mounted) {
          _rebuild(() => status = 'Could not open selected folder: $error');
        }
        return false;
      }
    }
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose vault folder',
    );
    if (path == null) return false;
    try {
      final probe = File('$path/.tylog-access-test.tmp');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
    } catch (e) {
      if (mounted) {
        _rebuild(() => status = 'Selected folder is not writable: $e');
      }
      return false;
    }
    final registry = vaultRegistry!;
    final entry = await registry.add(path);
    await _switchVault(entry);
    if (registry.activeId != entry.id) {
      await registry.select(entry);
      await _openVault(entry);
    }
    return true;
  }

  Future<bool> _migrateAndroidVault(VaultEntry entry) async {
    final selected = await _chooseAndroidVault(allowEmpty: true);
    if (selected == null) return false;
    final selection = selected.selection;
    try {
      final registry = vaultRegistry!;

      Future<void> adoptSelectedVault() async {
        final storage = AndroidTreeVaultStorage(
          uri: selection.uri,
          name: selection.name,
        );
        await Vault.withStorage(storage).ensureCreated();
        final replacement = await registry.addTree(selection);
        await registry.select(replacement);
        await registry.forget(entry);
      }

      if (selected.inspection.kind == VaultStorageKind.validVault) {
        await adoptSelectedVault();
      } else {
        final source = await inspectVaultStorage(entry.storage);
        if (source.kind == VaultStorageKind.validVault) {
          final migrated = await registry.migrateToTree(entry, selection);
          await registry.select(migrated);
        } else if (source.kind == VaultStorageKind.empty) {
          await adoptSelectedVault();
        } else {
          throw StateError(
            'The previous app vault is not a valid v5 vault; its files were kept.',
          );
        }
      }
      return true;
    } catch (error) {
      if (mounted) {
        _rebuild(
          () => status = 'Vault migration failed; original kept: $error',
        );
      }
      return false;
    }
  }

  Future<({AndroidTreeSelection selection, VaultStorageInspection inspection})?>
  _chooseAndroidVault({required bool allowEmpty, String? requiredUri}) async {
    Future<bool> chooseAgain(String message) async {
      if (!mounted) return false;
      return showConfirmDialog(
        context,
        title: 'Folder cannot be used',
        message: message,
        confirmLabel: 'Choose another folder',
        barrierDismissible: false,
      );
    }

    var explainAccess = true;
    while (mounted) {
      AndroidTreeSelection? selection;
      try {
        selection = explainAccess
            ? await _requestAndroidVaultAccess()
            : await AndroidTreeVaultStorage.pick();
        explainAccess = false;
      } catch (error) {
        if (!await chooseAgain('TyLog could not open this folder: $error')) {
          return null;
        }
        continue;
      }
      if (selection == null) return null;
      final storage = AndroidTreeVaultStorage(
        uri: selection.uri,
        name: selection.name,
      );
      VaultStorageInspection? inspection;
      Object? inspectionError;
      try {
        inspection = await inspectVaultStorage(storage);
        final acceptedKind =
            inspection.kind == VaultStorageKind.validVault ||
            allowEmpty && inspection.kind == VaultStorageKind.empty;
        if (acceptedKind &&
            (requiredUri == null || selection.uri == requiredUri)) {
          if (inspection.kind == VaultStorageKind.empty) {
            if (!mounted) return null;
            if (!await showConfirmDialog(
              context,
              title: 'Empty folder selected',
              message:
                  'This folder looks empty — is this the right vault? '
                  'You can re-pick it or use this folder anyway.',
              confirmLabel: 'Use anyway',
              cancelLabel: 'Choose another folder',
              barrierDismissible: false,
            )) {
              continue;
            }
          }
          await storage.persistAccess();
          return (selection: selection, inspection: inspection);
        }
      } catch (error) {
        inspectionError = error;
      }
      final message = inspectionError != null
          ? 'TyLog could not inspect this folder: $inspectionError'
          : requiredUri != null && selection.uri != requiredUri
          ? 'This is a different folder. Select the original vault folder.'
          : inspection!.kind == VaultStorageKind.incompatibleVault
          ? 'This folder has a malformed or unsupported TyLog vault marker.'
          : allowEmpty
          ? 'This folder contains other files. Choose an empty folder or an existing TyLog vault.'
          : 'This is not the existing TyLog vault. Select its original folder.';
      if (!await chooseAgain(message)) return null;
    }
    return null;
  }

  Future<AndroidTreeSelection?> _requestAndroidVaultAccess() async {
    final allowed = await showConfirmDialog(
      context,
      title: 'Allow vault folder access',
      message:
          'TyLog needs access to one folder to read and save your notes. '
          'An existing synced vault is usually where your sync app stores it. '
          'Android will open its folder picker. Choose your vault, then tap '
          '“Use this folder”. TyLog cannot access other folders.',
      confirmLabel: 'Choose folder',
      barrierDismissible: false,
    );
    if (!allowed || !mounted) return null;
    return AndroidTreeVaultStorage.pick();
  }

  Future<void> _forgetVault(VaultEntry entry) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Disconnect this vault?',
      message:
          '${entry.name} will be removed from this list. Its files stay on disk untouched, and you can re-add the vault later.',
      confirmLabel: 'Disconnect',
    );
    if (!confirmed || !mounted) return;
    final registry = vaultRegistry!;
    try {
      workspace.cancelPendingWork();
      final wasActive = entry.id == registry.activeId;
      await registry.forget(entry);
      if (registry.entries.isEmpty) {
        _closeVault('Forgot ${entry.name}; add a vault to continue');
        return;
      }
      if (wasActive) await _openVault(registry.active);
      if (mounted) _rebuild(() => status = 'Forgot ${entry.name}; files kept');
    } catch (e) {
      if (mounted) _rebuild(() => status = 'Forget failed: $e');
    }
  }

  Future<void> _deleteVault(VaultEntry entry) async {
    final warned = await showConfirmDialog(
      context,
      title: 'Delete vault and files?',
      message:
          'This permanently deletes all notes, pages, assets, metadata, and sync state in ${entry.name}. There is no recovery.',
      confirmLabel: 'Delete permanently',
      destructive: true,
    );
    if (!warned || !mounted) return;
    final typed = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirm permanent deletion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Type ${entry.name} to delete this vault and every file in it.',
              ),
              TextField(
                controller: typed,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'Vault name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: typed.text == entry.name
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    workspace.cancelPendingWork();
    try {
      final registry = vaultRegistry!;
      final wasActive = registry.activeId == entry.id;
      await registry.delete(entry);
      if (shouldCreateDefaultReplacementVault(
        entriesEmpty: registry.entries.isEmpty,
      )) {
        final replacement = defaultVaultDirectory(
          await getApplicationDocumentsDirectory(),
        );
        await Vault(replacement).ensureCreated();
        final replacementEntry = await registry.add(replacement.path);
        await registry.select(replacementEntry);
      }
      if (registry.entries.isEmpty && Platform.isAndroid) {
        _closeVault('Choose a vault folder to continue');
        await _pickVault(closeCurrent: false);
        return;
      }
      if (wasActive && registry.entries.isNotEmpty) {
        await _openVault(registry.active);
      }
      if (mounted) {
        _rebuild(() => status = 'Deleted ${entry.name} and its files');
      }
    } catch (e) {
      if (mounted) {
        _rebuild(
          () => status = entry.storageKind == 'android-tree'
              ? 'Delete failed; use Android Files to delete ${entry.name}: $e'
              : 'Delete failed; vault kept: $e',
        );
      }
    }
  }
}
