import 'dart:async';

import 'package:flutter/material.dart';

import '../nextcloud_sync.dart';
import '../vault_registry.dart';
import 'loading.dart';
import 'sync_status.dart';

class SyncDashboardData {
  const SyncDashboardData({
    required this.storageName,
    required this.storageLocation,
    required this.cloud,
    required this.syncing,
    required this.vaultOpen,
    required this.desktopManaged,
    required this.storageHealthy,
    required this.conflicts,
    required this.events,
    this.backupPath,
    this.stage,
    this.error,
    this.result,
    this.lastSyncAt,
  });

  final String storageName;
  final String storageLocation;
  final String? backupPath;
  final String? stage;
  final NextcloudConfig? cloud;
  final bool syncing;
  final bool vaultOpen;
  final bool desktopManaged;
  final bool storageHealthy;
  final String? error;
  final SyncResult? result;
  final DateTime? lastSyncAt;
  final List<SyncConflict> conflicts;
  final List<Map<String, Object?>> events;
}

class SyncDashboardScreen extends StatefulWidget {
  const SyncDashboardScreen({
    super.key,
    required this.load,
    required this.onSync,
    required this.onConfigure,
    required this.onResolve,
    required this.onCopyDiagnostics,
  });

  final Future<SyncDashboardData> Function() load;
  final Future<void> Function() onSync;
  final Future<bool> Function() onConfigure;
  final Future<void> Function(SyncConflict) onResolve;
  final Future<void> Function() onCopyDiagnostics;

  @override
  State<SyncDashboardScreen> createState() => _SyncDashboardScreenState();
}

class _SyncDashboardScreenState extends State<SyncDashboardScreen> {
  SyncDashboardData? data;
  Object? loadError;
  bool running = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final loaded = await widget.load();
      if (mounted) setState(() => data = loaded);
    } catch (error) {
      if (mounted) setState(() => loadError = error);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (running || data?.syncing == true) return;
    setState(() => running = true);
    final refresh = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_reload()),
    );
    try {
      await action();
    } finally {
      refresh.cancel();
      await _reload();
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = data;
    final busy = running || (value?.syncing ?? false);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('Sync'),
        actions: [
          IconButton(
            tooltip: 'Configure Nextcloud',
            onPressed: busy
                ? null
                : () => _run(() async {
                    await widget.onConfigure();
                  }),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: value == null
          ? Center(
              child: loadError == null
                  ? const LoadingIndicator()
                  : Text('Could not load sync dashboard: $loadError'),
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if ((running || value.syncing) && value.stage != null) ...[
                    LinearProgressIndicator(semanticsLabel: 'Sync progress'),
                    const SizedBox(height: 8),
                    Text(value.stage!),
                    const SizedBox(height: 12),
                  ],
                  _SyncStatusCard(
                    syncing: running || value.syncing,
                    vaultOpen: value.vaultOpen,
                    storageHealthy: value.storageHealthy,
                    cloudConfigured: value.cloud?.isReady ?? false,
                    desktopManaged: value.desktopManaged,
                    result: value.result,
                    lastSyncAt: value.lastSyncAt,
                    error: value.error,
                    conflicts: value.conflicts.length,
                    onSync:
                        running ||
                            value.syncing ||
                            !value.vaultOpen ||
                            !value.storageHealthy ||
                            value.conflicts.isNotEmpty
                        ? null
                        : () => unawaited(_run(widget.onSync)),
                    onReview: value.conflicts.isEmpty
                        ? () {}
                        : () => unawaited(
                            _run(() => widget.onResolve(value.conflicts.first)),
                          ),
                    onSetup: busy
                        ? null
                        : () => unawaited(
                            _run(() async {
                              await widget.onConfigure();
                            }),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.folder_open),
                      title: Text(value.storageName),
                      subtitle: Text(
                        [
                          readableVaultLocation(value.storageLocation),
                          value.storageHealthy
                              ? 'Permission and safe writes verified'
                              : 'Folder access or safe writes unavailable',
                          if (value.backupPath != null)
                            'Recovery backup: ${value.backupPath}',
                        ].join('\n'),
                      ),
                      isThreeLine: true,
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(
                        value.cloud?.isReady ?? false
                            ? value.cloud!.serverUrl
                            : 'Nextcloud not configured',
                      ),
                      subtitle: value.cloud?.isReady ?? false
                          ? Text(
                              '${value.cloud!.username} · ${value.cloud!.remoteFolder}',
                            )
                          : const Text(
                              'Local folder remains available offline.',
                            ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy
                          ? null
                          : () => _run(() async {
                              await widget.onConfigure();
                            }),
                    ),
                  ),
                  if (value.conflicts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Conflicts',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final conflict in value.conflicts)
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: ListTile(
                          leading: const Icon(Icons.warning_amber_rounded),
                          title: Text(conflict.path),
                          subtitle: Text(
                            conflict.localExists && conflict.remoteExists
                                ? 'Both copies changed'
                                : conflict.localExists
                                ? 'Nextcloud deleted; this device changed'
                                : 'This device deleted; Nextcloud changed',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _run(() => widget.onResolve(conflict)),
                        ),
                      ),
                  ],
                  if (value.result != null) ...[
                    const SizedBox(height: 16),
                    _SyncDistribution(result: value.result!),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Diagnostics log',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (value.events.isEmpty)
                    const ListTile(title: Text('No sync events recorded')),
                  for (final event in value.events)
                    ExpansionTile(
                      title: Text(
                        '${event['event'] ?? 'event'} · ${event['trigger'] ?? 'unknown'}',
                      ),
                      subtitle: Text(event['timestamp']?.toString() ?? ''),
                      children: [
                        if (event['stage'] != null)
                          ListTile(
                            title: Text('Stage: ${event['stage']}'),
                            subtitle: event['path'] == null
                                ? null
                                : Text(event['path'].toString()),
                          ),
                        if (event['errorMessage'] != null)
                          ListTile(
                            leading: const Icon(Icons.error_outline),
                            title: Text(event['errorMessage'].toString()),
                          ),
                        for (final decision
                            in event['decisions'] is List
                                ? event['decisions']! as List
                                : const [])
                          ListTile(
                            dense: true,
                            title: Text((decision as Map)['path'].toString()),
                            subtitle: Text(
                              '${decision['action']} · ${decision['reason']}',
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: widget.onCopyDiagnostics,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy diagnostics'),
                  ),
                ],
              ),
            ),
    );
  }
}

class SyncIconButton extends StatelessWidget {
  const SyncIconButton({
    super.key,
    required this.syncing,
    required this.vaultOpen,
    required this.storageHealthy,
    required this.configured,
    required this.desktopManaged,
    required this.error,
    required this.conflicts,
    required this.result,
    required this.onPressed,
  });

  final bool syncing;
  final bool vaultOpen;
  final bool storageHealthy;
  final bool configured;
  final bool desktopManaged;
  final String? error;
  final int conflicts;
  final SyncResult? result;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final kind = syncStatusKind(
      vaultOpen: vaultOpen,
      storageHealthy: storageHealthy,
      cloudConfigured: configured,
      desktopManaged: desktopManaged,
      syncing: syncing,
      error: error,
      conflicts: conflicts,
      result: result,
    );
    final label = syncStatusTitle(kind, conflicts: conflicts);
    final icon = switch (kind) {
      SyncStatusKind.vaultClosed => Icons.folder_open,
      SyncStatusKind.storageUnavailable => Icons.cloud_off_outlined,
      SyncStatusKind.desktopManaged => Icons.cloud_done_outlined,
      SyncStatusKind.notConfigured => Icons.cloud_off_outlined,
      SyncStatusKind.syncing => Icons.sync,
      SyncStatusKind.paused => Icons.cloud_off_outlined,
      SyncStatusKind.conflicts => Icons.warning_amber_rounded,
      SyncStatusKind.ready => Icons.cloud_outlined,
      SyncStatusKind.upToDate ||
      SyncStatusKind.synced => Icons.cloud_done_outlined,
    };
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      icon: syncing
          ? const LoadingIndicator(size: 22, strokeWidth: 2.5)
          : Icon(icon),
    );
  }
}

class _SyncDistribution extends StatelessWidget {
  const _SyncDistribution({required this.result});

  final SyncResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final values = [
      ('Uploaded', result.uploaded, colors.primary),
      ('Downloaded', result.downloaded, colors.tertiary),
      ('Deleted here', result.deletedLocal, colors.secondary),
      ('Deleted remote', result.deletedRemote, colors.secondary),
      ('Renamed', result.renamed, colors.secondary),
      ('Unchanged', result.skipped, colors.outlineVariant),
      ('Repaired', result.repaired, colors.secondary),
      ('Conflicts', result.conflicts, colors.error),
    ];
    final visible = values.where((item) => item.$2 > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Latest sync', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          const Text('No files needed changes.')
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final item in visible)
                    Expanded(
                      flex: item.$2,
                      child: ColoredBox(color: item.$3),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            for (final item in visible)
              _SyncMetric(label: item.$1, value: item.$2, color: item.$3),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${result.remoteCount} files on Nextcloud',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SyncMetric extends StatelessWidget {
  const _SyncMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text('$label $value'),
    ],
  );
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.syncing,
    required this.vaultOpen,
    required this.storageHealthy,
    required this.cloudConfigured,
    required this.desktopManaged,
    required this.result,
    required this.lastSyncAt,
    required this.error,
    required this.conflicts,
    required this.onSync,
    required this.onReview,
    required this.onSetup,
  });

  final bool syncing;
  final bool vaultOpen;
  final bool storageHealthy;
  final bool cloudConfigured;
  final bool desktopManaged;
  final SyncResult? result;
  final DateTime? lastSyncAt;
  final String? error;
  final int conflicts;
  final VoidCallback? onSync;
  final VoidCallback onReview;
  final VoidCallback? onSetup;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kind = syncStatusKind(
      vaultOpen: vaultOpen,
      storageHealthy: storageHealthy,
      cloudConfigured: cloudConfigured,
      desktopManaged: desktopManaged,
      syncing: syncing,
      error: error,
      conflicts: conflicts,
      result: result,
    );
    final icon = switch (kind) {
      SyncStatusKind.vaultClosed => Icons.folder_open,
      SyncStatusKind.storageUnavailable => Icons.cloud_off_outlined,
      SyncStatusKind.desktopManaged => Icons.cloud_done_outlined,
      SyncStatusKind.notConfigured => Icons.cloud_off_outlined,
      SyncStatusKind.syncing => Icons.sync,
      SyncStatusKind.paused => Icons.cloud_off_outlined,
      SyncStatusKind.conflicts => Icons.warning_amber_rounded,
      SyncStatusKind.ready => Icons.cloud_done_outlined,
      SyncStatusKind.upToDate ||
      SyncStatusKind.synced => Icons.cloud_done_outlined,
    };
    final title = syncStatusTitle(kind, conflicts: conflicts);
    final subtitle = switch (kind) {
      SyncStatusKind.vaultClosed =>
        error ?? 'Choose a vault folder before syncing.',
      SyncStatusKind.storageUnavailable =>
        error ?? 'Reselect the vault folder before syncing.',
      SyncStatusKind.desktopManaged => 'This folder syncs through the system.',
      SyncStatusKind.notConfigured => 'Connect Nextcloud to sync this vault.',
      SyncStatusKind.syncing => 'Checking this device and Nextcloud.',
      SyncStatusKind.paused => error!,
      SyncStatusKind.conflicts =>
        'Sync is paused until you review the conflicts. Your files are safe.',
      SyncStatusKind.ready => 'No sync has completed in this session.',
      SyncStatusKind.upToDate => _lastChecked(lastSyncAt),
      SyncStatusKind.synced =>
        '${result!.uploaded} uploaded · ${result!.downloaded} downloaded · ${_lastChecked(lastSyncAt).toLowerCase()}',
    };
    final color = switch (kind) {
      SyncStatusKind.vaultClosed ||
      SyncStatusKind.storageUnavailable => colors.errorContainer,
      SyncStatusKind.desktopManaged ||
      SyncStatusKind.notConfigured => colors.surfaceContainerHighest,
      SyncStatusKind.syncing => colors.secondaryContainer,
      SyncStatusKind.paused => colors.errorContainer,
      SyncStatusKind.conflicts => colors.tertiaryContainer,
      SyncStatusKind.ready ||
      SyncStatusKind.upToDate ||
      SyncStatusKind.synced => colors.primaryContainer,
    };
    final action = syncStatusAction(kind);
    final onAction = switch (kind) {
      SyncStatusKind.notConfigured => onSetup,
      SyncStatusKind.paused => onSync,
      SyncStatusKind.conflicts => onReview,
      SyncStatusKind.ready ||
      SyncStatusKind.upToDate ||
      SyncStatusKind.synced => onSync,
      _ => null,
    };

    return Semantics(
      liveRegion: true,
      label: '$title. $subtitle',
      child: Card(
        color: color,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  syncing
                      ? const LoadingIndicator(size: 22, strokeWidth: 2.5)
                      : Icon(icon, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (action != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: onAction, child: Text(action)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _lastChecked(DateTime? value) {
    if (value == null) return 'Ready to sync';
    final minutes = DateTime.now().difference(value).inMinutes;
    if (minutes < 1) return 'Checked just now';
    if (minutes == 1) return 'Checked 1 minute ago';
    return 'Checked $minutes minutes ago';
  }
}
