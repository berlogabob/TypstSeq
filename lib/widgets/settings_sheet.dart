import 'dart:async';

import 'package:flutter/material.dart';
import '../calendar_feeds.dart' show isValidFeedUrl;

import 'app_icons.dart';
import '../ai/ai_settings.dart';
import '../nextcloud_sync.dart';
import '../vault_registry.dart';
import 'app_version.dart';
import '../audio/processing_policy.dart';
import 'audio_processing_settings.dart';
import 'screenshots_settings.dart';
import 'constants.dart';
import 'ds/app_tile.dart';
import 'ds/app_section.dart';
import 'ds/app_sheet.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    this.calendarSettings = const {},
    this.onConfigureCalendars,
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
    required this.onStripImportNoise,
    required this.onImportVault,
    required this.onInstallModule,
    this.onProblems,
    this.onRebuildIndex,
    this.onRelinkVault,
    this.onSemanticSearch,
    this.onTypstHelp,
    this.onCheckForUpdates,
    this.audioPolicyRead,
    this.audioPolicyWrite,
    this.onProcessAudio,
    this.readAi,
    this.writeAi,
    this.readWorkers,
    this.screenshotsMode = 'off',
    this.screenshotsTime = '03:00',
    this.onConfigureScreenshots,
    this.screenshotsFolder,
    this.onScreenshotsFolderChanged,
    this.onProcessScreenshots,
    this.readScreenshotsStatus,
    this.pdfPaper = 'a4',
    this.onPdfPaperChanged,
  });

  final Map<String, dynamic> calendarSettings;
  final Future<void> Function(Map<String, dynamic>)? onConfigureCalendars;
  final Future<AudioPolicy> Function()? audioPolicyRead;
  final Future<void> Function(AudioPolicy)? audioPolicyWrite;
  final Future<void> Function()? onProcessAudio;
  final Future<AiSettings> Function()? readAi;
  final Future<void> Function(AiSettings)? writeAi;
  final Future<List<WorkerStatus>> Function()? readWorkers;
  final String screenshotsMode;
  final String screenshotsTime;
  final Future<void> Function(String, String)? onConfigureScreenshots;
  final String? screenshotsFolder;
  final Future<void> Function(String)? onScreenshotsFolderChanged;
  final Future<void> Function()? onProcessScreenshots;
  final Future<String> Function()? readScreenshotsStatus;
  final String pdfPaper;
  final ValueChanged<String>? onPdfPaperChanged;
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
  final Future<void> Function() onStripImportNoise;
  final Future<void> Function() onImportVault;
  final Future<void> Function() onInstallModule;

  final VoidCallback? onProblems;

  final VoidCallback? onRebuildIndex;

  final VoidCallback? onRelinkVault;

  final VoidCallback? onSemanticSearch;

  final VoidCallback? onTypstHelp;

  /// Desktop-only: check GitHub Releases for a newer build. Null hides the tile.
  final VoidCallback? onCheckForUpdates;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  String? _selectedPaper;
  bool get readScreenshotsStatusAvailable =>
      widget.readScreenshotsStatus != null &&
      widget.onConfigureScreenshots != null &&
      widget.onProcessScreenshots != null;

  Future<void> _calendars() async {
    final config = widget.calendarSettings;
    final defaults = <String, String>{
      'classesUrl': '',
      'group': '',
      'programme': '',
      'degree': '',
      'classesHours': '6',
      'labUrl': '',
      'labHours': '6',
    };
    final labels = [
      'My classes URL',
      'Group',
      'Programme (optional)',
      'Degree (optional)',
      'Classes refresh hours',
      'Lab schedule URL',
      'Lab refresh hours',
    ];
    final controllers = {
      for (final entry in defaults.entries)
        entry.key: TextEditingController(
          text: config[entry.key]?.toString() ?? entry.value,
        ),
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Calendars'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, key) in defaults.keys.indexed)
                TextField(
                  controller: controllers[key],
                  decoration: InputDecoration(labelText: labels[i]),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final next = <String, dynamic>{
                for (final key in defaults.keys)
                  key: controllers[key]!.text.trim(),
              };
              for (final key in ['classesHours', 'labHours']) {
                final hours = int.tryParse(next[key]);
                if (hours == null || hours < 1) return;
                next[key] = hours;
              }
              for (final key in ['classesUrl', 'labUrl']) {
                if (!isValidFeedUrl(next[key])) return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Save & refresh'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final next = <String, dynamic>{
        ...config,
        for (final key in defaults.keys)
          key: key.endsWith('Hours')
              ? int.parse(controllers[key]!.text.trim())
              : controllers[key]!.text.trim(),
      };
      await widget.onConfigureCalendars!(next);
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final readableVaultPath = readableVaultLocation(widget.vaultPath);
    return AppSheet(
      title: 'Settings',
      children: [
        AppSection(
          title: 'General',
          divider: false,
          children: [
            _ThemeModeSelector(
              themeMode: widget.themeMode,
              onChanged: widget.onThemeModeChanged,
            ),
            const SizedBox(height: kSpace8),
            AppTile(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF page size',
              trailing: DropdownButton<String>(
                value: _selectedPaper ?? widget.pdfPaper,
                items: const [
                  DropdownMenuItem(value: 'a4', child: Text('A4')),
                  DropdownMenuItem(value: 'us-letter', child: Text('Letter')),
                  DropdownMenuItem(value: 'a5', child: Text('A5')),
                  DropdownMenuItem(value: 'us-legal', child: Text('Legal')),
                ],
                onChanged: (paper) {
                  if (paper == null) return;
                  setState(() => _selectedPaper = paper);
                  widget.onPdfPaperChanged?.call(paper);
                },
              ),
            ),
            if (widget.onConfigureCalendars != null)
              AppTile(
                icon: AppIcons.calendars,
                title: 'Calendars',
                subtitle: 'My classes · Lab schedule',
                onTap: _calendars,
              ),
            AppTile(
              icon: Icons.notifications_outlined,
              title: 'Task reminders',
              subtitle: 'Enable local scheduled notifications',
              onTap: () => unawaited(widget.onEnableReminders()),
            ),
          ],
        ),
        AppSection(
          title: 'AI and processing',
          children: [
            if (widget.audioPolicyRead != null)
              AudioProcessingSettings(
                read: widget.audioPolicyRead!,
                write: widget.audioPolicyWrite!,
                processNow: widget.onProcessAudio!,
                readAi: widget.readAi,
                writeAi: widget.writeAi,
                readWorkers: widget.readWorkers,
              ),
            if (readScreenshotsStatusAvailable)
              ScreenshotsSettings(
                mode: widget.screenshotsMode,
                time: widget.screenshotsTime,
                onConfigure: widget.onConfigureScreenshots!,
                onProcessNow: widget.onProcessScreenshots!,
                readStatus: widget.readScreenshotsStatus!,
                folder: widget.screenshotsFolder,
                onFolderChanged: widget.onScreenshotsFolderChanged,
              ),
          ],
        ),
        AppSection(
          title: 'Storage and sync',
          children: [
            _InfoRow(title: 'Local folder', value: readableVaultPath),
            AppTile(
              icon: AppIcons.folder,
              title: 'Vaults',
              subtitle: '${widget.vaultCount} vaults · manage and switch',
              onTap: widget.onManageVaults,
            ),
            AppTile(
              icon: AppIcons.sync,
              title: 'Sync',
              subtitle: widget.syncStatusSubtitle,
              onTap: widget.onNextcloud,
            ),
          ],
        ),
        AppSection(
          title: 'Tools',
          children: [
            AppTile(
              icon: AppIcons.warning,
              title: 'Problems',
              onTap: widget.onProblems,
            ),
            AppTile(
              icon: Icons.refresh,
              title: 'Rebuild index',
              onTap: widget.onRebuildIndex,
            ),
            AppTile(
              icon: Icons.auto_fix_high,
              title: 'Relink vault',
              onTap: widget.onRelinkVault,
            ),
            AppTile(
              icon: Icons.build_outlined,
              title: 'Migrate entity types',
              subtitle: 'Update older notes to the current format',
              onTap: () => unawaited(widget.onMigrateEntityTypes()),
            ),
            AppTile(
              icon: Icons.cleaning_services_outlined,
              title: 'Clean up imported notes',
              subtitle: 'Remove empty Logseq drawers and trailing blanks',
              onTap: () => unawaited(widget.onStripImportNoise()),
            ),
            AppTile(
              icon: Icons.drive_folder_upload_outlined,
              title: 'Import vault',
              subtitle: 'Convert a whole vault folder into TyLog notes',
              onTap: () => unawaited(widget.onImportVault()),
            ),
            AppTile(
              icon: Icons.extension_outlined,
              title: 'Modules',
              subtitle: 'Manage courses or install a .tylogpack',
              onTap: () => unawaited(widget.onInstallModule()),
            ),
            AppTile(
              icon: Icons.manage_search,
              title: 'Semantic search',
              onTap: widget.onSemanticSearch,
            ),
          ],
        ),
        AppSection(
          title: 'About',
          children: [
            FutureBuilder<String>(
              future: appVersion(),
              builder: (context, snapshot) =>
                  _InfoRow(title: 'App version', value: snapshot.data ?? '...'),
            ),
            if (widget.onCheckForUpdates case final onTap?)
              AppTile(
                icon: Icons.system_update,
                title: 'Check for updates',
                subtitle: 'Download the latest release from GitHub',
                onTap: onTap,
              ),
            AppTile(
              icon: Icons.help_outline,
              title: 'Typst help',
              onTap: widget.onTypstHelp,
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(kSpace8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: kSpace4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
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
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kRadiusLarge),
    ),
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
      padding: const EdgeInsets.symmetric(horizontal: kSpace8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.brightness_6_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: kSpace12),
              const Text('Appearance'),
            ],
          ),
          const SizedBox(height: kSpace8),
          Row(
            children: [
              for (final (mode, label) in _options)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: kSpace8),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: SizedBox(
                        width: double.infinity,
                        child: Text(label, textAlign: TextAlign.center),
                      ),
                      selected: _mode == mode,
                      onSelected: (_) => _select(mode),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
