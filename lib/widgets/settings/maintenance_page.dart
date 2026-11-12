import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:tylog_core/tylog_core.dart'
    show findDuplicates, NoteRef, VaultIndex, VaultStorage;
import '../../workspace_controller.dart';
import '../app_icons.dart';
import '../ds/app_tile.dart';
import '../settings_sheet.dart';
import 'settings_page.dart';

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key, required this.settings});
  final SettingsSheet settings;
  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'Maintenance',
    children: [
      AppTile(
        icon: AppIcons.warning,
        title: 'Problems',
        onTap: settings.onProblems,
      ),
      if (settings.storage != null)
        _LatestHealthReportTile(
          storage: settings.storage!,
          onOpenPath: settings.onOpenPath,
        ),
      AppTile(
        icon: Icons.content_copy,
        title: 'Duplicates',
        onTap: settings.workspace == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _DuplicatesPage(workspace: settings.workspace!),
                ),
              ),
      ),
      AppTile(
        icon: Icons.refresh,
        title: 'Rebuild index',
        onTap: settings.onRebuildIndex,
      ),
      AppTile(
        icon: Icons.auto_fix_high,
        title: 'Relink vault',
        onTap: settings.onRelinkVault,
      ),
      AppTile(
        icon: Icons.build_outlined,
        title: 'Migrate entity types',
        subtitle: 'Update older notes to the current format',
        onTap: () => unawaited(settings.onMigrateEntityTypes()),
      ),
      AppTile(
        icon: Icons.account_tree_outlined,
        title: 'Migrate namespace titles',
        subtitle: 'Preview page hierarchy changes',
        onTap: settings.onMigrateNamespaces == null
            ? null
            : () => unawaited(settings.onMigrateNamespaces!()),
      ),
      AppTile(
        icon: Icons.cleaning_services_outlined,
        title: 'Clean up imported notes',
        subtitle: 'Remove empty Logseq drawers and trailing blanks',
        onTap: () => unawaited(settings.onStripImportNoise()),
      ),
      AppTile(
        icon: Icons.drive_folder_upload_outlined,
        title: 'Import vault',
        subtitle: 'Convert a whole vault folder into TyLog notes',
        onTap: () => unawaited(settings.onImportVault()),
      ),
      AppTile(
        icon: Icons.extension_outlined,
        title: 'Modules',
        subtitle: 'Manage courses or install a .tylogpack',
        onTap: () => unawaited(settings.onInstallModule()),
      ),
      AppTile(
        icon: Icons.manage_search,
        title: 'Semantic search',
        onTap: settings.onSemanticSearch,
      ),
    ],
  );
}

class _LatestHealthReportTile extends StatefulWidget {
  const _LatestHealthReportTile({required this.storage, this.onOpenPath});
  final VaultStorage storage;
  final ValueChanged<String>? onOpenPath;

  @override
  State<_LatestHealthReportTile> createState() =>
      _LatestHealthReportTileState();
}

class _LatestHealthReportTileState extends State<_LatestHealthReportTile> {
  late final Future<String?> _report = _latestHealthReport(widget.storage);

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _report,
    builder: (context, snapshot) {
      final path = snapshot.data;
      if (path == null) return const SizedBox.shrink();
      return AppTile(
        icon: Icons.health_and_safety_outlined,
        title: 'Latest health report',
        subtitle: path.split('/').last.split('.').first,
        onTap: widget.onOpenPath == null
            ? null
            : () => widget.onOpenPath!(path),
      );
    },
  );
}

Future<String?> _latestHealthReport(VaultStorage storage) async {
  const root = '_system/health';
  if (!await storage.exists(root)) return null;
  final reports =
      (await storage.list(path: root))
          .where(
            (entry) =>
                !entry.isDirectory &&
                RegExp(
                  r'^_system/health/\d{4}-\d{2}-\d{2}\.json$',
                ).hasMatch(entry.path),
          )
          .map((entry) => entry.path)
          .toList()
        ..sort();
  return reports.isEmpty ? null : reports.last;
}

class _DuplicatesPage extends StatefulWidget {
  const _DuplicatesPage({required this.workspace});
  final WorkspaceController workspace;

  @override
  State<_DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends State<_DuplicatesPage> {
  Future<void> merge(List<NoteRef> group, NoteRef loser) async {
    final survivor = await showDialog<NoteRef>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a page to keep'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('Page to remove: ${loser.title} · ${loser.path}'),
          ),
          for (final n in group.where((n) => n.path != loser.path))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, n),
              child: Text('${n.title} · ${n.path}'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (survivor == null || !mounted) return;
    try {
      final preview = await widget.workspace.previewDuplicateMerge(
        survivor.path,
        loser.path,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Preview merge'),
          content: SingleChildScrollView(
            child: Text(
              'Keep: ${survivor.path}\nRemove: ${loser.path}\n\nOnly indexed #tylog.ref-note links are updated. Check other link forms before merging.\n\nFiles to change:\n${preview.files.join('\n')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Merge'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await widget.workspace.mergeDuplicate(preview);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Merge could not finish: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.workspace,
    builder: (context, _) {
      final index = widget.workspace.index;
      final failed = widget.workspace.status.startsWith(
        'Index refresh failed:',
      );
      return Scaffold(
        appBar: AppBar(title: const Text('Duplicates')),
        body: index == null
            ? Center(
                child: failed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Index could not be loaded'),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => widget.workspace.rebuildIndex(),
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    : widget.workspace.awaitingIndex
                    ? const CircularProgressIndicator()
                    : const Text('No index available'),
              )
            : _duplicateList(index),
      );
    },
  );

  Widget _duplicateList(VaultIndex index) {
    final groups = findDuplicates(index);
    if (groups.isEmpty) return const Center(child: Text('No duplicates found'));
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, i) => Card(
        child: Column(
          children: [
            for (final note in groups[i])
              ListTile(
                title: Text(
                  note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: () => merge(groups[i], note),
                  child: const Text('Merge into…'),
                ),
                subtitle: Text(
                  '${note.path} · ${(index.backlinksByTarget[note.path] ?? const []).length} backlinks',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
