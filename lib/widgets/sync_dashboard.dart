import 'dart:async';

import 'package:flutter/material.dart';

import '../nextcloud_sync.dart';
import '../vault_registry.dart';
import 'constants.dart';
import 'loading.dart';
import 'snack.dart';
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
    required this.onResolveAll,
    required this.onCopyDiagnostics,
  });

  final Future<SyncDashboardData> Function() load;
  final Future<void> Function() onSync;
  final Future<bool> Function() onConfigure;
  final Future<void> Function(SyncConflict) onResolve;

  /// Applies one choice across every listed conflict. The caller owns the
  /// confirmation and the batching; this screen only asks which side.
  final Future<void> Function(SyncConflictResolution) onResolveAll;
  final Future<void> Function() onCopyDiagnostics;

  @override
  State<SyncDashboardScreen> createState() => _SyncDashboardScreenState();
}

class _SyncDashboardScreenState extends State<SyncDashboardScreen> {
  SyncDashboardData? data;
  Object? loadError;
  bool running = false;
  bool _reloading = false;
  Timer? _refresh;

  /// Conflicts whose resolve is in flight, keyed by id.
  ///
  /// Lives on the State, not on [SyncDashboardData]: `_reload` replaces that
  /// snapshot wholesale twice a second, so anything stored there is destroyed
  /// on the next tick — while the row itself stays until the record is gone
  /// from disk, which is exactly the span the user needs to see.
  final Set<String> _resolving = {};

  /// This screen holds a *snapshot*, not a live view of the controller, and
  /// `_run` refuses to act while that snapshot says a sync is in flight. So a
  /// snapshot that gets stuck on `syncing: true` disables every action on the
  /// screen — conflict resolution included — with no visible cause. Observed on
  /// a real device: the spinner claimed "Syncing…" for nine minutes after the
  /// sync service had stopped, and only force-quitting the app cleared it.
  ///
  /// Refreshing for the life of the screen rather than only during `_run` means
  /// a stale value survives one tick instead of forever.
  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    _refresh = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_reload()),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    // Single-flight. `load()` does several SAF round trips and routinely takes
    // longer than the refresh interval, so without this two loads overlap and
    // the slower one can land last — pinning `data` to the older snapshot.
    if (_reloading) return;
    _reloading = true;
    try {
      final loaded = await widget.load();
      if (mounted) {
        setState(() {
          data = loaded;
          loadError = null;
        });
      }
    } catch (error) {
      // Keep the error visible even when a previous snapshot exists: silently
      // holding on to stale data is how the screen froze without saying so.
      if (mounted) setState(() => loadError = error);
    } finally {
      _reloading = false;
    }
  }

  /// Resolving a conflict is deliberately *not* routed through [_run].
  ///
  /// It contends with nothing the other actions contend with: one Depth:0
  /// probe and one file write. But `workspace.resolveConflict` awaits
  /// `refreshIndex(always: true)`, which awaits any scan already running plus
  /// one queued repeat — a full vault scan, hours on a large vault. Held behind
  /// `running`, that allowed exactly **one resolve per scan cycle**: the second
  /// tap and every tap after it hit the guard and died silently, with the row
  /// still showing its chevron.
  ///
  /// That was the whole reported symptom — "I can resolve one, then nothing
  /// happens until I force-quit the app."
  Future<void> _resolve(SyncConflict conflict) async {
    if (_resolving.contains(conflict.id)) return;
    setState(() => _resolving.add(conflict.id));
    try {
      await widget.onResolve(conflict);
      await _reload();
    } finally {
      if (mounted) {
        setState(() => _resolving.remove(conflict.id));
      } else {
        _resolving.remove(conflict.id);
      }
    }
  }

  /// Asks which side wins, then hands the whole batch to the caller.
  ///
  /// Deliberately not a default: applying "keep this device" across a backlog
  /// can discard whatever the other side added, and that is precisely the
  /// mistake the single-conflict dialog was changed to stop making.
  Future<void> _resolveAll(List<SyncConflict> conflicts) async {
    final count = conflicts.length;
    final choice = await showModalBottomSheet<SyncConflictResolution>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Resolve $count conflicts'),
              subtitle: const Text(
                'One choice, applied to every file listed below.',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.smartphone),
              title: const Text("Keep this device's version"),
              subtitle: const Text('Uploads each local copy to Nextcloud'),
              onTap: () =>
                  Navigator.pop(sheet, SyncConflictResolution.keepLocal),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text("Keep Nextcloud's version"),
              subtitle: const Text('Overwrites each local copy'),
              onTap: () =>
                  Navigator.pop(sheet, SyncConflictResolution.keepRemote),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    // Every row it covers, for the same reason a single resolve marks its own:
    // a batch is N network writes, and without this the whole list sits
    // unchanged exactly as it did before Block A. It also stops the button
    // launching a second batch over the first, and stops a row being resolved
    // individually while the batch already owns it.
    final ids = conflicts.map((conflict) => conflict.id).toList();
    setState(() => _resolving.addAll(ids));
    try {
      await widget.onResolveAll(choice);
      await _reload();
    } finally {
      if (mounted) {
        setState(() => _resolving.removeAll(ids));
      } else {
        _resolving.removeAll(ids);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    // Never refuse silently. The same regression has now been fixed twice in
    // this codebase (`_setTaskStatus`, `_setNoteProperty`); a bare `return`
    // here made it three.
    if (running) {
      showSnack(context, 'Still finishing the last action…');
      return;
    }
    if (data?.syncing == true) {
      showSnack(context, 'Sync is running — try again in a moment');
      return;
    }
    setState(() => running = true);
    try {
      await action();
    } finally {
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
                  // Its own element, above everything. The error used to reach
                  // the screen only through the status card's subtitle, one
                  // contested line that "Syncing…" and "N conflicts need
                  // review" both outrank — so the failure that mattered most
                  // was the one thing that could not be read.
                  if (value.error != null) ...[
                    Card(
                      key: const Key('sync-error-card'),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: const Text('Last action failed'),
                        subtitle: Text(value.error!),
                      ),
                    ),
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
                        : () => unawaited(_resolve(value.conflicts.first)),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Conflicts',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        // Only worth offering for a backlog. One conflict is
                        // a decision, not a chore.
                        if (value.conflicts.length > 1)
                          TextButton(
                            onPressed: _resolving.isEmpty
                                ? () =>
                                      unawaited(_resolveAll(value.conflicts))
                                : null,
                            child: Text('Resolve all ${value.conflicts.length}'),
                          ),
                      ],
                    ),
                    for (final conflict in value.conflicts)
                      Card(
                        // Keyed by id, not by position. The rows rebuild twice
                        // a second from a fresh snapshot; unkeyed, a list that
                        // reorders or shrinks between two reloads moves a
                        // different record under the finger mid-tap.
                        key: ValueKey('conflict-${conflict.id}'),
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: ListTile(
                          leading: const Icon(Icons.warning_amber_rounded),
                          title: Text(conflict.path),
                          subtitle: Text(
                            _resolving.contains(conflict.id)
                                ? 'Resolving… uploading and cleaning up'
                                : conflict.localExists && conflict.remoteExists
                                ? 'Both copies changed'
                                : conflict.localExists
                                ? 'Nextcloud deleted; this device changed'
                                : 'This device deleted; Nextcloud changed',
                          ),
                          trailing: _resolving.contains(conflict.id)
                              ? const LoadingIndicator(size: 24, strokeWidth: 2)
                              : const Icon(Icons.chevron_right),
                          onTap: _resolving.contains(conflict.id)
                              ? null
                              : () => unawaited(_resolve(conflict)),
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
                        // Recorded on every pass since the timings landed, and
                        // rendered nowhere — the numbers that decided what to
                        // optimise had to be read out of the clipboard.
                        if (event['stageMillis'] is Map)
                          for (final stage
                              in (event['stageMillis']! as Map).entries)
                            ListTile(
                              dense: true,
                              title: Text(stage.key.toString()),
                              trailing: Text('${stage.value} ms'),
                            ),
                        if (event['reusedNotes'] != null)
                          ListTile(
                            dense: true,
                            title: Text(
                              'Reused ${event['reusedNotes']} notes from '
                              '${event['reusedDevices']} device(s)',
                            ),
                            subtitle: Text(
                              '${event['notes']} notes indexed · '
                              '${event['skippedDonors']} donor(s) skipped',
                            ),
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
            borderRadius: BorderRadius.circular(kRadiusSmall),
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
      // Not the error text: it has its own card above, and printing it twice
      // just makes the screen noisier without making it clearer.
      SyncStatusKind.paused => 'The last action did not complete.',
      SyncStatusKind.conflicts =>
        'Everything else keeps syncing. Your files are safe.',
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
