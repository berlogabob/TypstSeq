import 'dart:async';

import 'package:flutter/material.dart';

import '../nextcloud_sync.dart';
import 'app_version.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({
    super.key,
    required this.vaultPath,
    required this.cloud,
    required this.syncing,
    required this.syncStatusSubtitle,
    required this.onNextcloud,
    required this.vaultCount,
    required this.onManageVaults,
    required this.onEnableReminders,
    required this.onMigrateEntityTypes,
  });

  final String vaultPath;
  final NextcloudConfig? cloud;
  final bool syncing;
  final String syncStatusSubtitle;
  final VoidCallback onNextcloud;
  final int vaultCount;
  final VoidCallback onManageVaults;
  final Future<void> Function() onEnableReminders;
  final Future<void> Function() onMigrateEntityTypes;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              SettingsTile(
                icon: Icons.folder_open,
                title: 'Local folder',
                subtitle: vaultPath,
              ),
              SettingsTile(
                icon: Icons.create_new_folder,
                title: 'Vaults',
                subtitle: '$vaultCount vaults · manage and switch',
                onTap: onManageVaults,
              ),
              SettingsTile(
                icon: Icons.sync,
                title: 'Sync',
                subtitle: syncStatusSubtitle,
                onTap: onNextcloud,
              ),
              SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Task reminders',
                subtitle: 'Enable local scheduled notifications',
                onTap: () => unawaited(onEnableReminders()),
              ),
              SettingsTile(
                icon: Icons.build_outlined,
                title: 'Migrate entity types',
                subtitle: 'Fold legacy properties["type"] entities into kind',
                onTap: () => unawaited(onMigrateEntityTypes()),
              ),
              FutureBuilder<String>(
                future: appVersion(),
                builder: (context, snapshot) => SettingsTile(
                  icon: Icons.info_outline,
                  title: 'App version',
                  subtitle: snapshot.data ?? '...',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        child: Icon(icon),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    ),
  );
}
