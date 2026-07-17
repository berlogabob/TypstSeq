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
  if (syncing) return SyncStatusKind.syncing;
  if (!cloudConfigured) return SyncStatusKind.notConfigured;
  if (error != null) return SyncStatusKind.paused;
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
