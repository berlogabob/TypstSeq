import '../nextcloud_sync.dart';

/// How the two sides of a conflict relate. Most "conflicts" on a vault with a
/// live producer are not disagreements at all — one side is the other plus an
/// appended block, or the same bytes with a different ETag.
enum ConflictShape {
  /// Byte-identical. Either choice is lossless.
  identical,

  /// Local is remote plus more: keeping local loses nothing.
  localSuperset,

  /// Remote is local plus more: keeping remote loses nothing.
  remoteSuperset,

  /// Both sides changed independently. Any choice discards something.
  diverged,

  /// One side is missing (a delete against an edit), or the content is not
  /// text so it cannot be compared.
  incomparable,
}

/// The remote bytes a dialog may show, given what the record says exists.
///
/// A record marked `remoteExists: false` still carries `remoteSnapshot` — the
/// last known content of a file that was deleted on the server. Showing those
/// bytes as "the Nextcloud version" is a lie with teeth: if the snapshot is a
/// superset of the local file, [conflictShape] reads `remoteSuperset`,
/// [defaultResolution] preselects keepRemote, and the hint promises "Keeping it
/// loses nothing" — while the resolve takes the `remoteExists == false` branch
/// and *deletes the local file*. The two halves are each correct alone and
/// destructive together.
///
/// So the record is authoritative about existence, and the snapshot is only
/// shown for a side that still exists.
List<int>? conflictRemoteBytesToShow(
  SyncConflict conflict,
  List<int>? snapshotBytes,
) => conflict.remoteExists ? snapshotBytes : null;

ConflictShape conflictShape({String? local, String? remote}) {
  if (local == null || remote == null) return ConflictShape.incomparable;
  if (local == remote) return ConflictShape.identical;
  if (local.startsWith(remote)) return ConflictShape.localSuperset;
  if (remote.startsWith(local)) return ConflictShape.remoteSuperset;
  return ConflictShape.diverged;
}

/// What to preselect in the resolve dialog, or null to force an explicit
/// choice.
///
/// The dialog used to preselect keep-local unconditionally. On the A24 at
/// 02:47, `daily/2026-08-21.typ` was local 184 bytes against remote 221 — the
/// remote being local plus the appended line "today we will play concert with
/// Flor". Accepting the default would have silently deleted that line, and only
/// reading the byte counts caught it. A default that can destroy the strictly
/// newer side is the wrong default on a data-safety screen, so a default is
/// offered only where it is provably lossless.
SyncConflictResolution? defaultResolution(ConflictShape shape) =>
    switch (shape) {
      ConflictShape.identical ||
      ConflictShape.localSuperset => SyncConflictResolution.keepLocal,
      ConflictShape.remoteSuperset => SyncConflictResolution.keepRemote,
      ConflictShape.diverged || ConflictShape.incomparable => null,
    };

/// Human description of one side, in terms of the *other* side. "adds 1 line"
/// is something a person can act on; "221 bytes" is not.
String conflictSideLabel(
  ConflictShape shape, {
  required bool isLocal,
  required String? text,
  required int? byteLength,
}) {
  if (byteLength == null) return 'File deleted';
  final isSuperset =
      (isLocal && shape == ConflictShape.localSuperset) ||
      (!isLocal && shape == ConflictShape.remoteSuperset);
  final isSubset =
      (isLocal && shape == ConflictShape.remoteSuperset) ||
      (!isLocal && shape == ConflictShape.localSuperset);
  return switch (shape) {
    ConflictShape.identical => 'Identical content · $byteLength bytes',
    _ when isSuperset => 'Has everything the other side has, plus more',
    _ when isSubset => 'Missing what the other side added',
    _ => '$byteLength bytes',
  };
}

/// Extra line the dialog shows when one side strictly extends the other, so
/// the safe choice is visible rather than inferred from two byte counts.
String? conflictShapeHint(ConflictShape shape) => switch (shape) {
  ConflictShape.identical =>
    'Both copies are the same. Either choice is safe.',
  ConflictShape.localSuperset =>
    'This device has everything Nextcloud has, plus more. Keeping it loses '
        'nothing.',
  ConflictShape.remoteSuperset =>
    'Nextcloud has everything this device has, plus more. Keeping it loses '
        'nothing.',
  ConflictShape.diverged =>
    'Both copies changed separately, so one of them will lose changes. '
        'Choose deliberately, or edit the final version below.',
  ConflictShape.incomparable => null,
};
