part of '../app_mobile.dart';

extension _ModuleFlow on _HomeScreenState {
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
        final result = await uninstallModule(v.storage, pack.id);
        await workspace.refreshIndex(updateStatus: false, always: true);
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
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          title: Text('Installing module'),
          content: LinearProgressIndicator(),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    String message;
    try {
      final result = await installModule(v.storage, pack, start);
      await workspace.refreshIndex(updateStatus: false, always: true);
      message =
          'Installed ${pack.name}: ${result.written.length} files'
          '${result.skipped.isEmpty ? '' : ', ${result.skipped.length} kept (edited)'}';
    } catch (error) {
      message = 'Install failed: $error';
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    showSnack(context, message);
  }
}
