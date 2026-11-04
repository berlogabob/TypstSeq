import 'dart:io';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tylog_core/tylog_core.dart'
    show Mount, MountSource, InstalledModule, listInstalledModules;

import '../../workspace_controller.dart';
import '../ds/app_tile.dart';
import 'settings_page.dart';
import 'github_sign_in.dart';
import 'olt_page.dart';

class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({
    super.key,
    required this.workspace,
    this.pickDirectory,
    this.onUpdateModule,
  });

  final WorkspaceController? workspace;
  final Future<String?> Function()? pickDirectory;
  final Future<void> Function(InstalledModule)? onUpdateModule;

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  List<InstalledModule> _modules = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadModules());
  }

  Future<void> _loadModules() async {
    final workspace = widget.workspace;
    final storage = workspace?.vault?.storage;
    if (workspace == null || storage == null) return;
    Future<void> load() async {
      final modules = await listInstalledModules(storage);
      if (mounted) setState(() => _modules = modules);
    }

    try {
      await load();
      await workspace.checkModuleUpdates(automatic: true);
      await load();
    } catch (_) {
      // Extensions remain usable when a pack record cannot be read.
    }
  }

  DateTime? _lastRefresh;
  bool _busy = false;
  final Map<String, Future<bool>> _permissions = {};

  Future<bool> _canPush(String repo) =>
      _permissions.putIfAbsent(repo, () async {
        try {
          return (await (await widget.workspace!.githubClient())
                  .repoPermissions(repo))['push'] ==
              true;
        } catch (_) {
          return false;
        }
      });

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

  Future<void> _addGitHub() async {
    final repo = TextEditingController();
    final ref = TextEditingController();
    final subdir = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add GitHub repo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: repo,
              decoration: const InputDecoration(labelText: 'owner/repo'),
            ),
            TextField(
              controller: ref,
              decoration: const InputDecoration(labelText: 'Ref (optional)'),
            ),
            TextField(
              controller: subdir,
              decoration: const InputDecoration(
                labelText: 'Subdirectory (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, [
              repo.text.trim(),
              ref.text.trim(),
              subdir.text.trim(),
            ]),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _run(() async {
      final name = result[0];
      if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(name)) {
        throw const FormatException('Enter owner/repo');
      }
      final branch = await (await widget.workspace!.githubClient())
          .defaultBranch(name);
      var base = name
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      if (base.isEmpty) base = 'extension';
      if (base.length > 35) {
        base = base.substring(0, 35).replaceAll(RegExp(r'-+$'), '');
      }
      var id = base;
      var suffix = 2;
      while (widget.workspace!.mounts.any((m) => m.id == id)) {
        id = '$base-${suffix++}';
      }
      final mount = Mount(
        id: id,
        name: name,
        source: MountSource(
          kind: 'github',
          repo: name,
          ref: result[1].isEmpty ? branch : result[1],
          subdir: result[2].isEmpty ? null : result[2],
        ),
        push: false,
      );
      await widget.workspace!.addMount(mount);
      await widget.workspace!.refreshMount(mount);
    });
  }

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
          if (_modules.any((m) => m.github != null))
            const ListTile(title: Text('Packs')),
          if (!_modules.any((m) => m.github != null))
            const ListTile(
              title: Text('Packs'),
              subtitle: Text('No GitHub packs installed'),
            ),
          for (final module in _modules.where((m) => m.github != null)) ...[
            AppTile(
              icon: Icons.school_outlined,
              title: module.name,
              subtitle: 'Version ${module.version}',
            ),
            if (module.updateAvailableVersion != null &&
                widget.onUpdateModule != null)
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => widget.onUpdateModule!(module)),
                    child: Text('Update to ${module.updateAvailableVersion}'),
                  ),
                ),
              ),
          ],
          const ListTile(title: Text('Sources')),
          const OltSection(),
          GitHubSignIn(onChanged: () => setState(_permissions.clear)),
          if (workspace != null)
            for (final mount in workspace.mounts)
              AppTile(
                icon: Icons.extension_outlined,
                title: mount.name,
                subtitle: mount.source.kind == 'github'
                    ? [mount.source.repo, mount.source.ref, mount.source.subdir]
                          .whereType<String>()
                          .where((value) => value.isNotEmpty)
                          .join(' · ')
                    : '${mount.source.path ?? mount.source.repo ?? mount.source.kind} · '
                          '${workspace.index?.notes.where((note) => note.path.startsWith('ext/${mount.id}/')).length ?? 0} notes · '
                          'Last refresh: ${_lastRefresh == null ? 'not yet' : _lastRefresh!.toLocal().toString().substring(0, 16)}',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (mount.source.kind == 'github')
                      IconButton(
                        tooltip: 'Refresh ${mount.name}',
                        icon: const Icon(Icons.refresh),
                        onPressed: _busy
                            ? null
                            : () => _run(() => workspace.refreshMount(mount)),
                      ),
                    IconButton(
                      tooltip: 'Remove ${mount.name}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy ? null : () => _remove(mount),
                    ),
                  ],
                ),
              ),
          if (workspace != null)
            for (final mount in workspace.mounts.where(
              (m) => m.source.kind == 'github',
            )) ...[
              FutureBuilder<bool>(
                future: _canPush(mount.source.repo!),
                builder: (context, snapshot) => SwitchListTile(
                  title: Text('${mount.name}: Allow editing (push to GitHub)'),
                  value: mount.push,
                  onChanged: _busy || snapshot.data != true
                      ? null
                      : (value) =>
                            _run(() => workspace.setMountPush(mount, value)),
                ),
              ),
              FutureBuilder(
                future: workspace.githubOutbox.then(
                  (box) => box.entriesFor(mount.id),
                ),
                builder: (context, snapshot) {
                  final entries = snapshot.data ?? [];
                  final conflicts = entries
                      .where((e) => e.state == 'conflict')
                      .length;
                  return ListTile(
                    title: Text(
                      '${mount.name}: ${entries.length - conflicts} pending · $conflicts conflicts',
                    ),
                    trailing: TextButton(
                      onPressed: _busy || !mount.push
                          ? null
                          : () => _run(workspace.pushPending),
                      child: const Text('Push now'),
                    ),
                  );
                },
              ),
              FutureBuilder<Map<String, dynamic>?>(
                future: workspace.mountFetcher.then((f) => f.metadata(mount)),
                builder: (context, snapshot) {
                  final meta = snapshot.data;
                  final sha = meta?['sha']?.toString() ?? '';
                  return Text(
                    '${mount.name}: ${sha.isEmpty ? 'not fetched' : sha.substring(0, sha.length < 7 ? sha.length : 7)} · ${meta?['fetchedAt'] ?? ''}',
                  );
                },
              ),
            ],
          if (Platform.isLinux || Platform.isMacOS || Platform.isWindows)
            AppTile(
              icon: Icons.create_new_folder_outlined,
              title: 'Add folder',
              onTap: workspace == null || _busy ? null : _addFolder,
            ),
          AppTile(
            icon: Icons.code,
            title: 'Add GitHub repo',
            onTap: workspace == null || _busy ? null : _addGitHub,
          ),
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
