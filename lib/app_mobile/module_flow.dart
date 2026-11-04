part of '../app_mobile.dart';

extension _ModuleFlow on _HomeScreenState {
  Future<void> _showModules() async {
    if (dirty && !await _save(syncAfter: false)) return;
    final v = vault;
    if (!mounted || v == null) return;
    try {
      final modules = await listInstalledModules(v.storage);
      if (!mounted) return;
      final progress = <String, ModuleProgress>{};
      for (final module in modules) {
        progress[module.id] = await moduleProgress(v.storage, module.id);
      }
      if (!mounted) return;
      final choice =
          await showModalBottomSheet<
            ({String action, InstalledModule? module})
          >(
            context: context,
            isScrollControlled: true,
            showDragHandle: false,
            builder: (context) => AppSheet(
              title: 'Modules',
              children: [
                for (final module in modules) ...[
                  AppTile(
                    icon: Icons.school_outlined,
                    title: module.name,
                    subtitle:
                        '${progress[module.id]!.done}/${progress[module.id]!.total} ${module.unit}'
                        '${progress[module.id]!.scores.isEmpty ? '' : ' · ${progress[module.id]!.scores.length} scores'}',
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Module actions',
                      onSelected: (action) => Navigator.pop(context, (
                        action: action,
                        module: module,
                      )),
                      itemBuilder: (_) => [
                        if (module.start != null)
                          const PopupMenuItem(
                            value: 'reschedule',
                            child: Text('Reschedule…'),
                          ),
                        const PopupMenuItem(
                          value: 'source',
                          child: Text('Updates from GitHub…'),
                        ),
                        const PopupMenuItem(
                          value: 'uninstall',
                          child: Text('Uninstall'),
                        ),
                      ],
                    ),
                  ),
                  AppTile(
                    icon: Icons.link,
                    title: 'Updates from GitHub',
                    subtitle: module.github ?? 'Not configured',
                    onTap: () => Navigator.pop(context, (
                      action: 'source',
                      module: module,
                    )),
                  ),
                  if (module.updateAvailableVersion case final update?
                      when module.updateCheckedAt != null &&
                          DateTime.now().difference(module.updateCheckedAt!) <
                              const Duration(days: 7))
                    AppTile(
                      icon: Icons.system_update,
                      title: 'Update available ${module.version} -> $update',
                      trailing: TextButton(
                        onPressed: () => Navigator.pop(context, (
                          action: 'update',
                          module: module,
                        )),
                        child: const Text('Update'),
                      ),
                    ),
                ],
                AppTile(
                  icon: Icons.cloud_download_outlined,
                  title: 'Install from GitHub',
                  onTap: () =>
                      Navigator.pop(context, (action: 'github', module: null)),
                ),
                AppTile(
                  icon: Icons.refresh,
                  title: 'Check for updates',
                  onTap: () =>
                      Navigator.pop(context, (action: 'check', module: null)),
                ),
                AppTile(
                  icon: Icons.file_open_outlined,
                  title: 'Install from file…',
                  onTap: () =>
                      Navigator.pop(context, (action: 'install', module: null)),
                ),
              ],
            ),
          );
      if (choice == null || !mounted) return;
      if (choice.action == 'install') {
        await _installModule();
        return;
      }
      if (choice.action == 'check') {
        await workspace.checkModuleUpdates();
        if (mounted) await _showModules();
        return;
      }
      if (choice.action == 'github') {
        final repo = await _moduleRepoDialog('Install from GitHub');
        if (repo == null || !mounted) return;
        final pack = await downloadGitHubModule(
          await workspace.githubClient(),
          repo,
        );
        if (mounted) await _installModulePack(pack, github: repo);
        return;
      }
      final module = choice.module!;
      if (choice.action == 'source') {
        final repo = await _moduleRepoDialog(
          'Updates from GitHub',
          initial: module.github,
        );
        if (repo == null) return;
        if (repo.isNotEmpty &&
            !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo)) {
          throw const FormatException('Enter owner/repo');
        }
        final path = moduleRecordPath(module.id);
        final record =
            jsonDecode(await v.storage.readText(path)) as Map<String, dynamic>;
        final source = Map<String, dynamic>.from(
          record['source'] is Map ? record['source'] as Map : {},
        );
        if (repo.isEmpty) {
          source.remove('github');
        } else {
          source['github'] = repo;
        }
        if (source.isEmpty) {
          record.remove('source');
        } else {
          record['source'] = source;
        }
        record.remove('updateAttemptedAt');
        record.remove('updateCheckedAt');
        record.remove('updateAvailableVersion');
        await v.storage.writeText(path, jsonEncode(record));
        workspace.moduleUpdates.remove(module.id);
        if (mounted) await _showModules();
        return;
      }
      if (choice.action == 'update') {
        await _updateModule(module);
        return;
      }
      String message;
      if (choice.action == 'reschedule') {
        final oldStart = module.start!;
        final start = await showDatePicker(
          context: context,
          initialDate: oldStart,
          firstDate: DateTime(oldStart.year - 1),
          lastDate: DateTime(oldStart.year + 3),
          helpText: '${module.name}: first lesson on',
          confirmText: 'Reschedule',
        );
        if (start == null || !mounted) return;
        await _withModuleProgress(
          'Rescheduling module',
          () => rescheduleModule(v.storage, module.id, start, oldStart),
        );
        message = 'Rescheduled ${module.name}';
      } else {
        final confirmed = await showConfirmDialog(
          context,
          title: 'Uninstall ${module.name}?',
          message:
              'Only unedited files will be removed. Edited files are kept.',
          confirmLabel: 'Uninstall',
          destructive: true,
        );
        if (!confirmed || !mounted) return;
        final result = await _withModuleProgress(
          'Removing module',
          () => uninstallModule(v.storage, module.id),
        );
        message =
            'Removed ${result.written.length} files'
            '${result.skipped.isEmpty ? '' : ', ${result.skipped.length} kept (edited)'}';
      }
      if (mounted) showSnack(context, message);
    } catch (error) {
      if (mounted) showSnack(context, 'Module operation failed: $error');
    }
  }

  Future<void> _updateModule(InstalledModule module) async {
    try {
      final pack = await downloadGitHubModuleUpdate(
        await workspace.githubClient(),
        module,
      );
      await _installModulePack(pack, github: module.github);
    } catch (error) {
      if (mounted) showSnack(context, 'Module operation failed: $error');
    }
  }

  /// Settings -> Modules: pick a `.tylogpack`, choose a start date, install.
  Future<void> _installModule() async {
    if (dirty && !await _save(syncAfter: false)) return;
    final v = vault;
    if (!mounted || v == null) return;
    final picked = await FilePicker.pickFiles();
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    final ModulePack pack;
    try {
      pack = await readModulePack(File(path));
    } on FormatException catch (error) {
      if (mounted) showSnack(context, 'Not a valid module: ${error.message}');
      return;
    }
    await _installModulePack(pack);
  }

  Future<void> _installModulePack(ModulePack pack, {String? github}) async {
    final v = vault;
    if (v == null || !mounted) return;
    final size = pack.files.values.fold<int>(0, (sum, b) => sum + b.length);
    final notes = pack.files.keys.where((p) => p.startsWith('notes/')).length;
    final installed = await v.storage.exists(moduleRecordPath(pack.id));
    if (!mounted) return;
    if (installed) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${pack.name} is installed'),
          content: const Text(
            'Update rewrites unedited files. Uninstall removes only files '
            'you have not edited.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'uninstall'),
              child: const Text('Uninstall'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'update'),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      if (action == null || !mounted) return;
      if (action == 'uninstall') {
        final result = await _withModuleProgress(
          'Removing module',
          () => uninstallModule(v.storage, pack.id),
        );
        if (mounted) {
          showSnack(
            context,
            'Removed ${result.written.length} files'
            '${result.skipped.isEmpty ? '' : ', ${result.skipped.length} kept (edited)'}',
          );
        }
        return;
      }
    }
    final start = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      helpText:
          '${pack.name} v${pack.version}: $notes notes, '
          '${(size / 1e6).toStringAsFixed(1)} MB. First lesson on',
      confirmText: installed ? 'Update' : 'Install',
    );
    if (start == null || !mounted) return;
    String message;
    try {
      final result = await _withModuleProgress(
        'Installing module',
        () => installModule(v.storage, pack, start, github: github),
      );
      workspace.moduleUpdates.remove(pack.id);
      message =
          'Installed ${pack.name}: ${result.written.length} files'
          '${result.skipped.isEmpty ? '' : ', ${result.skipped.length} kept (edited)'}';
    } catch (error) {
      message = 'Install failed: $error';
    }
    if (!mounted) return;
    showSnack(context, message);
  }

  Future<String?> _moduleRepoDialog(String title, {String? initial}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'owner/repo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<T> _withModuleProgress<T>(
    String title,
    Future<T> Function() operation,
  ) async {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(title),
            content: const LinearProgressIndicator(),
          ),
        ),
      ),
    );
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final result = await operation();
      await workspace.refreshIndex(updateStatus: false, always: true);
      return result;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
