import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tylog_core/tylog_core.dart' show Mount, MountSource;

import '../../workspace_controller.dart';
import '../ds/app_tile.dart';
import 'settings_page.dart';

class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({
    super.key,
    required this.workspace,
    this.pickDirectory,
  });

  final WorkspaceController? workspace;
  final Future<String?> Function()? pickDirectory;

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  DateTime? _lastRefresh;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update extensions: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFolder() => _run(() async {
    final path =
        await (widget.pickDirectory?.call() ?? FilePicker.getDirectoryPath());
    if (path == null) return;
    final workspace = widget.workspace!;
    final segments = Directory(
      path,
    ).uri.pathSegments.where((s) => s.isNotEmpty);
    final name = segments.isEmpty ? path : segments.last;
    var base = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
    base = base.replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.isEmpty) base = 'extension';
    if (base.length > 35) {
      base = base.substring(0, 35).replaceAll(RegExp(r'-+$'), '');
    }
    var id = base;
    var suffix = 2;
    while (workspace.mounts.any((mount) => mount.id == id)) {
      id = '$base-${suffix++}';
    }
    await workspace.addMount(
      Mount(
        id: id,
        name: name,
        source: MountSource(kind: 'folder', path: path),
        push: false,
      ),
    );
  });

  Future<void> _remove(Mount mount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${mount.name}?'),
        content: const Text('The source files will not be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => widget.workspace!.removeMount(mount.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    return ListenableBuilder(
      listenable: Listenable.merge([?workspace]),
      builder: (context, _) => SettingsPage(
        title: 'Extensions',
        children: [
          if (workspace != null)
            for (final mount in workspace.mounts)
              AppTile(
                icon: Icons.extension_outlined,
                title: mount.name,
                subtitle:
                    '${mount.source.path ?? mount.source.repo ?? mount.source.kind} · '
                    '${workspace.index?.notes.where((note) => note.path.startsWith('ext/${mount.id}/')).length ?? 0} notes · '
                    'Last refresh: ${_lastRefresh == null ? 'not yet' : _lastRefresh!.toLocal().toString().substring(0, 16)}',
                trailing: IconButton(
                  tooltip: 'Remove ${mount.name}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _remove(mount),
                ),
              ),
          if (Platform.isLinux || Platform.isMacOS || Platform.isWindows)
            AppTile(
              icon: Icons.create_new_folder_outlined,
              title: 'Add folder',
              onTap: workspace == null || _busy ? null : _addFolder,
            ),
          const AppTile(icon: Icons.code, title: 'Add GitHub repo (soon)'),
          AppTile(
            icon: Icons.refresh,
            title: 'Refresh',
            onTap: workspace == null || _busy
                ? null
                : () => _run(() async {
                    await workspace.reloadMounts();
                    if (mounted) setState(() => _lastRefresh = DateTime.now());
                  }),
          ),
        ],
      ),
    );
  }
}
