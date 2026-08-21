import '../nextcloud_sync.dart';

enum SyncStatusKind {
  vaultClosed,
  storageUnavailable,
  desktopManaged,
  notConfigured,
  syncing,
  paused,
  conflicts,
  ready,
  upToDate,
  synced,
}

SyncStatusKind syncStatusKind({
  required bool vaultOpen,
  required bool storageHealthy,
  required bool cloudConfigured,
  required bool desktopManaged,
  required bool syncing,
  required String? error,
  required int conflicts,
  required SyncResult? result,
}) {
  if (!vaultOpen) return SyncStatusKind.vaultClosed;
  if (!storageHealthy) return SyncStatusKind.storageUnavailable;
  if (desktopManaged) return SyncStatusKind.desktopManaged;
  // Above `syncing` deliberately. syncNow clears syncError as it starts, so an
  // error present while a sync is in flight is a *fresh* one — a resolve that
  // just failed, say — and ranking the spinner above it meant it was never
  // rendered at all. A failure the user cannot see is indistinguishable from a
  // button that did nothing.
  if (error != null) return SyncStatusKind.paused;
  // Still above `notConfigured`: during first-run setup the config is a draft
  // while its sync is already running (see the test named for it).
  if (syncing) return SyncStatusKind.syncing;
  if (!cloudConfigured) return SyncStatusKind.notConfigured;
  if (conflicts > 0) return SyncStatusKind.conflicts;
  if (result == null) return SyncStatusKind.ready;
  final changed =
      result.uploaded +
      result.downloaded +
      result.deletedLocal +
      result.deletedRemote +
      result.renamed;
  return changed == 0 ? SyncStatusKind.upToDate : SyncStatusKind.synced;
}

String syncStatusTitle(
  SyncStatusKind kind, {
  int conflicts = 0,
}) => switch (kind) {
  SyncStatusKind.vaultClosed => 'Vault not open',
  SyncStatusKind.storageUnavailable => 'Folder access unavailable',
  SyncStatusKind.desktopManaged => 'Nextcloud Desktop',
  SyncStatusKind.notConfigured => 'Sync not connected',
  SyncStatusKind.syncing => 'Syncing…',
  SyncStatusKind.paused => 'Sync paused',
  SyncStatusKind.conflicts =>
    '$conflicts ${conflicts == 1 ? 'conflict needs' : 'conflicts need'} review',
  SyncStatusKind.ready => 'Ready to sync',
  SyncStatusKind.upToDate => 'Up to date',
  SyncStatusKind.synced => 'Synced',
};

String? syncStatusAction(SyncStatusKind kind) => switch (kind) {
  SyncStatusKind.notConfigured => 'Set up',
  SyncStatusKind.paused => 'Retry',
  SyncStatusKind.conflicts => 'Review',
  SyncStatusKind.ready ||
  SyncStatusKind.upToDate ||
  SyncStatusKind.synced => 'Sync now',
  _ => null,
};
