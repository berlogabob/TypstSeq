import 'package:flutter/material.dart';
import '../app_icons.dart';
import '../constants.dart';
import '../ds/app_tile.dart';
import '../settings_sheet.dart';
import '../../vault_registry.dart' show readableVaultLocation;
import 'scope_note.dart';
import 'settings_page.dart';

class SyncStoragePage extends StatelessWidget {
  const SyncStoragePage({super.key, required this.settings});
  final SettingsSheet settings;
  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'Sync and storage',
    children: [
      Padding(
        padding: const EdgeInsets.all(kSpace8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Local folder', style: Theme.of(context).textTheme.bodyLarge),
            const ScopeNote('This device'),
            const SizedBox(height: kSpace4),
            Text(readableVaultLocation(settings.vaultPath)),
          ],
        ),
      ),
      AppTile(
        icon: AppIcons.folder,
        title: 'Vaults',
        subtitle: '${settings.vaultCount} vaults · manage and switch',
        onTap: settings.onManageVaults,
      ),
      AppTile(
        icon: AppIcons.sync,
        title: 'Sync',
        subtitle: settings.syncStatusSubtitle,
        onTap: settings.onNextcloud,
      ),
    ],
  );
}
