import 'package:flutter/material.dart';

import 'app_icons.dart';
import '../vault_registry.dart';
import 'settings_sheet.dart';
import 'ds/app_sheet.dart';

class VaultsSheet extends StatelessWidget {
  const VaultsSheet({
    super.key,
    required this.vaults,
    required this.activeVaultId,
    required this.onAddVault,
    required this.onSwitchVault,
    required this.onForgetVault,
    required this.onDeleteVault,
  });

  final List<VaultEntry> vaults;
  final String? activeVaultId;
  final VoidCallback onAddVault;
  final ValueChanged<VaultEntry> onSwitchVault;
  final ValueChanged<VaultEntry> onForgetVault;
  final ValueChanged<VaultEntry> onDeleteVault;

  @override
  Widget build(BuildContext context) => AppSheet(
    title: 'Vaults',
    children: [
      for (final entry in vaults)
        ListTile(
          leading: Icon(
            entry.id == activeVaultId
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
          ),
          title: Text(entry.name),
          subtitle: Text(
            friendlyVaultPath(entry.treeUri ?? entry.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: entry.id == activeVaultId
              ? null
              : () {
                  Navigator.pop(context);
                  onSwitchVault(entry);
                },
          trailing: PopupMenuButton<String>(
            onSelected: (action) {
              Navigator.pop(context);
              if (action == 'forget') onForgetVault(entry);
              if (action == 'delete') onDeleteVault(entry);
            },
            itemBuilder: (context) {
              final errorColor = Theme.of(context).colorScheme.error;
              return [
                const PopupMenuItem(
                  value: 'forget',
                  child: Text('Disconnect (keep files)'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete permanently…',
                    style: TextStyle(color: errorColor),
                  ),
                ),
              ];
            },
          ),
        ),
      SettingsTile(
        icon: AppIcons.folderAdd,
        title: 'Add or create vault',
        subtitle: 'Choose an existing or empty folder',
        onTap: () {
          Navigator.pop(context);
          onAddVault();
        },
      ),
    ],
  );
}

/// `content://…/tree/primary%3ADownload%2FTyLog` → `Internal storage/Download/TyLog`.
String friendlyVaultPath(String location) {
  if (!location.startsWith('content://')) return location;
  final tree = location.split('/tree/').last.split('/document/').first;
  final decoded = Uri.decodeComponent(tree);
  final colon = decoded.indexOf(':');
  if (colon < 0) return decoded;
  final volume = decoded.substring(0, colon);
  final rest = decoded.substring(colon + 1);
  if (volume == 'raw') {
    // Downloads provider: `raw:/storage/emulated/0/Download/X`.
    final trimmed = rest.replaceFirst(RegExp(r'^/storage/emulated/\d+/?'), '');
    return trimmed.isEmpty ? 'Internal storage' : 'Internal storage/$trimmed';
  }
  final root = volume == 'primary' ? 'Internal storage' : 'SD card';
  return rest.isEmpty ? root : '$root/$rest';
}
