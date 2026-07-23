import 'dart:async';

import 'package:flutter/material.dart';

import '../nextcloud_sync.dart';
import '../vault_registry.dart';
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
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onManageVaults,
    required this.onEnableReminders,
    required this.onMigrateEntityTypes,
    this.onCheckForUpdates,
  });

  final String vaultPath;
  final NextcloudConfig? cloud;
  final bool syncing;
  final String syncStatusSubtitle;
  final VoidCallback onNextcloud;
  final int vaultCount;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onManageVaults;
  final Future<void> Function() onEnableReminders;
  final Future<void> Function() onMigrateEntityTypes;

  /// Desktop-only: check GitHub Releases for a newer build. Null hides the tile.
  final VoidCallback? onCheckForUpdates;

  @override
  Widget build(BuildContext context) {
    final readableVaultPath = readableVaultLocation(vaultPath);
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
              const SizedBox(height: 12),
              _ThemeModeSelector(
                themeMode: themeMode,
                onChanged: onThemeModeChanged,
              ),
              const SizedBox(height: 8),
              SettingsTile(
                icon: Icons.folder_open,
                title: 'Local folder',
                subtitle: readableVaultPath,
                singleLineSubtitle: !readableVaultPath.contains('\n'),
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
                subtitle: 'Update older notes to the current format',
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
              if (onCheckForUpdates case final onTap?)
                SettingsTile(
                  icon: Icons.system_update,
                  title: 'Check for updates',
                  subtitle: 'Download the latest release from GitHub',
                  onTap: onTap,
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
    this.singleLineSubtitle = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool singleLineSubtitle;

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
      subtitle: Text(
        subtitle,
        softWrap: !singleLineSubtitle,
        maxLines: singleLineSubtitle ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    ),
  );
}

/// Light / Dark / System appearance picker. Tracks the pressed segment locally
/// so it updates instantly inside the sheet while reporting up via [onChanged].
class _ThemeModeSelector extends StatefulWidget {
  const _ThemeModeSelector({required this.themeMode, required this.onChanged});

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  State<_ThemeModeSelector> createState() => _ThemeModeSelectorState();
}

class _ThemeModeSelectorState extends State<_ThemeModeSelector> {
  late ThemeMode _mode = widget.themeMode;

  static const _options = <(ThemeMode, String)>[
    (ThemeMode.system, 'Auto'),
    (ThemeMode.light, 'Light'),
    (ThemeMode.dark, 'Dark'),
  ];

  void _select(ThemeMode mode) {
    setState(() => _mode = mode);
    widget.onChanged(mode);
  }

  @override
  Widget build(BuildContext context) {
    // ChoiceChips (the app's existing selection idiom) rather than
    // SegmentedButton: the latter's selection animation does not reliably
    // settle under pumpAndSettle in this app's widget tests.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(
            Icons.brightness_6_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Appearance')),
          Wrap(
            spacing: 8,
            children: [
              for (final (mode, label) in _options)
                ChoiceChip(
                  label: Text(label),
                  selected: _mode == mode,
                  onSelected: (_) => _select(mode),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
