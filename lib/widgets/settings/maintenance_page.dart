import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tylog_core/tylog_core.dart' show VaultIndex, findDuplicates;
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
      AppTile(
        icon: Icons.content_copy,
        title: 'Duplicates',
        onTap: settings.workspace?.index == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _DuplicatesPage(index: settings.workspace!.index!),
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

class _DuplicatesPage extends StatelessWidget {
  const _DuplicatesPage({required this.index});
  final VaultIndex index;

  @override
  Widget build(BuildContext context) {
    final groups = findDuplicates(index);
    return Scaffold(
      appBar: AppBar(title: const Text('Duplicates')),
      body: groups.isEmpty
          ? const Center(child: Text('No duplicates found'))
          : ListView.builder(
              itemCount: groups.length,
              itemBuilder: (context, i) => Card(
                child: Column(
                  children: [
                    for (final note in groups[i])
                      ListTile(
                        title: Text(note.title),
                        subtitle: Text(
                          '${note.path} · ${(index.backlinksByTarget[note.path] ?? const []).length} backlinks',
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
