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
    this.readScreenshotsWanted,
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
  final Future<(String, String)?> Function()? readScreenshotsWanted;
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
    final feeds = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CalendarsPage(
        feeds: [
          for (final feed
              in (widget.calendarSettings['feeds'] as List? ?? const []))
            if (feed is Map) Map<String, dynamic>.from(feed),
        ],
        cache:
            (widget.calendarSettings['cache'] as Map?)
                ?.cast<String, dynamic>() ??
            const {},
      ),
    );
    if (feeds != null) {
      await widget.onConfigureCalendars!({'feeds': feeds});
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
                subtitle:
                    ((widget.calendarSettings['feeds'] as List?) ?? const [])
                        .isEmpty
                    ? 'None'
                    : '${((widget.calendarSettings['feeds'] as List?) ?? const []).length} calendars',
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
                readWanted: widget.readScreenshotsWanted,
                // Any device can change it: the Mac applies it after sync.
                editable: true,
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

class _CalendarsPage extends StatefulWidget {
  const _CalendarsPage({required this.feeds, required this.cache});
  final List<Map<String, dynamic>> feeds;
  final Map<String, dynamic> cache;
  @override
  State<_CalendarsPage> createState() => _CalendarsPageState();
}

class _CalendarsPageState extends State<_CalendarsPage> {
  late final _feeds = [...widget.feeds];

  Future<void> _add(String kind) async {
    if (kind == 'iade') {
      final choices = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (_) => const _IadeCalendarDialog(),
      );
      if (choices != null) setState(() => _feeds.addAll(choices));
      return;
    }
    final feed = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CalendarEditor(kind: 'ics', preset: kind),
    );
    if (feed != null) setState(() => _feeds.add(feed));
  }

  Future<void> _edit(int index) async {
    final feed = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CalendarEditor(feed: _feeds[index]),
    );
    if (feed != null) setState(() => _feeds[index] = feed);
  }

  Future<void> _delete(int index) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete calendar?'),
        content: Text('Remove ${_feeds[index]['name']} from TyLog?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) setState(() => _feeds.removeAt(index));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(kSpace16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Calendars',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _feeds),
                child: const Text('Done'),
              ),
            ],
          ),
          if (_feeds.isEmpty)
            const Padding(
              padding: EdgeInsets.all(kSpace24),
              child: Text('No calendars configured'),
            ),
          for (final (index, feed) in _feeds.indexed)
            ListTile(
              leading: const Icon(AppIcons.calendars),
              title: Text(feed['name']?.toString() ?? ''),
              subtitle: Text(_status(feed)),
              trailing: IconButton(
                icon: const Icon(AppIcons.delete),
                onPressed: () => _delete(index),
              ),
              onTap: () => _edit(index),
            ),
          PopupMenuButton<String>(
            onSelected: _add,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'google', child: Text('Google Calendar')),
              PopupMenuItem(value: 'outlook', child: Text('Microsoft Outlook')),
              PopupMenuItem(value: 'iade', child: Text('IADE')),
              PopupMenuItem(value: 'other', child: Text('Other (ICS link)')),
            ],
            child: const Chip(
              avatar: Icon(Icons.add),
              label: Text('Add calendar'),
            ),
          ),
        ],
      ),
    ),
  );

  String _status(Map<String, dynamic> feed) {
    final cache = widget.cache[feed['id']];
    if (cache is Map && cache['error'] != null) {
      return 'Error: ${cache['error']}';
    }
    final fetched = cache is Map ? cache['fetched'] : null;
    return '${feed['kind'] == 'iade-timetable' ? 'IADE timetable' : 'ICS'} · ${fetched == null ? 'Not refreshed' : 'Last refreshed $fetched'}';
  }
}

class _CalendarEditor extends StatefulWidget {
  const _CalendarEditor({this.feed, this.kind = 'ics', this.preset = 'other'});
  final Map<String, dynamic>? feed;
  final String kind;
  final String preset;
  @override
  State<_CalendarEditor> createState() => _CalendarEditorState();
}

class _CalendarEditorState extends State<_CalendarEditor> {
  late final _name = TextEditingController(
    text: widget.feed?['name']?.toString() ?? '',
  );
  late final _url = TextEditingController(
    text: widget.feed?['url']?.toString() ?? '',
  );
  late final _hours = TextEditingController(
    text: '${widget.feed?['hours'] ?? 6}',
  );

  @override
  void initState() {
    super.initState();
    if (widget.preset == 'google') _name.text = 'Google Calendar';
    if (widget.preset == 'outlook') _name.text = 'Microsoft Outlook';
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.feed == null ? 'Add calendar' : 'Edit calendar'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _url,
            decoration: InputDecoration(
              labelText: 'ICS URL',
              helperText: widget.preset == 'google'
                  ? 'Google Calendar > Settings > your calendar > Integrate calendar > Secret address in iCal format'
                  : widget.preset == 'outlook'
                  ? 'Outlook on the web > Settings > Calendar > Shared calendars > Publish a calendar > ICS link'
                  : null,
            ),
          ),
          TextField(
            controller: _hours,
            decoration: const InputDecoration(labelText: 'Refresh hours'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final url = _url.text.trim();
          final hours = int.tryParse(_hours.text.trim());
          if (_name.text.trim().isEmpty ||
              url.isEmpty ||
              !isValidFeedUrl(url) ||
              hours == null ||
              hours < 1) {
            return;
          }
          Navigator.pop(context, {
            ...?widget.feed,
            'id':
                widget.feed?['id'] ??
                'calendar-${DateTime.now().microsecondsSinceEpoch}',
            'kind': widget.kind,
            'name': _name.text.trim(),
            'url': url,
            'hours': hours,
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _IadeCalendarDialog extends StatefulWidget {
  const _IadeCalendarDialog();
  @override
  State<_IadeCalendarDialog> createState() => _IadeCalendarDialogState();
}

class _IadeCalendarDialogState extends State<_IadeCalendarDialog> {
  bool classes = true, lab = true;
  final group = TextEditingController();
  final programme = TextEditingController();
  final degree = TextEditingController();
  @override
  void dispose() {
    group.dispose();
    programme.dispose();
    degree.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('IADE calendars'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            value: classes,
            onChanged: (v) => setState(() => classes = v ?? false),
            title: const Text('My classes'),
            contentPadding: EdgeInsets.zero,
          ),
          if (classes) ...[
            TextField(
              controller: group,
              decoration: const InputDecoration(labelText: 'Group'),
            ),
            TextField(
              controller: programme,
              decoration: const InputDecoration(
                labelText: 'Programme (optional)',
              ),
            ),
            TextField(
              controller: degree,
              decoration: const InputDecoration(labelText: 'Degree (optional)'),
            ),
          ],
          CheckboxListTile(
            value: lab,
            onChanged: (v) => setState(() => lab = v ?? false),
            title: const Text('Lab schedule'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          Navigator.pop(context, [
            if (classes)
              {
                'id': 'classes-${DateTime.now().microsecondsSinceEpoch}',
                'kind': 'iade-timetable',
                'name': 'IADE classes',
                'url':
                    'https://berlogabob.github.io/iade-lab-schedule/all.json',
                'hours': 6,
                'group': group.text.trim(),
                'programme': programme.text.trim(),
                'degree': degree.text.trim(),
              },
            if (lab)
              {
                'id': 'lab-${DateTime.now().microsecondsSinceEpoch}',
                'kind': 'ics',
                'name': 'IADE lab schedule',
                'url':
                    'https://berlogabob.github.io/openlabtwin/calendar/lab.ics',
                'hours': 6,
              },
          ]);
        },
        child: const Text('Save'),
      ),
    ],
  );
}
