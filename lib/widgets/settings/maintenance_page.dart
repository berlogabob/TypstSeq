import 'dart:async';
import 'package:flutter/material.dart';
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
