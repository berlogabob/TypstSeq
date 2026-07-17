import 'package:flutter/material.dart';

import '../vault_registry.dart';
import 'settings_sheet.dart';

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
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('Vaults', style: Theme.of(context).textTheme.headlineSmall),
        for (final entry in vaults)
          ListTile(
            leading: Icon(
              entry.id == activeVaultId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: Text(entry.name),
            subtitle: Text(
              entry.treeUri ?? entry.path,
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
          icon: Icons.create_new_folder,
          title: 'Add or create vault',
          subtitle: 'Choose an existing or empty folder',
          onTap: () {
            Navigator.pop(context);
            onAddVault();
          },
        ),
      ],
    ),
  );
}
