part of '../nextcloud_sync.dart';

extension _SyncConflicts on NextcloudSync {
  void _requireLocalReplacementAllowed(String path) {
    if (canReplaceLocal?.call(path) == false) {
      throw const SyncDeferred();
    }
  }

  Future<({File file, String? etag})> _captureRemote(
    String path, {
    _RemoteArchiveSnapshot? archive,
    _RemoteFile? remoteFile,
  }) async {
    final file = await File(
      '${Directory.systemTemp.path}/tylog-conflict-${DateTime.now().microsecondsSinceEpoch}.tmp',
    ).create();
    if (archive != null && archive.contains(path)) {
      final bytes = archive.read(path);
      await file.writeAsBytes(bytes, flush: true);
      return (file: file, etag: remoteFile?.etag);
    }
    final result = await _download(path, file);
    if (remoteFile?.sha256 != null &&
        await _sha256(file) != remoteFile!.sha256) {
      await file.delete();
      throw HttpException('GET $path checksum mismatch');
    }
    return (file: file, etag: result.etag);
  }

  Future<void> _storeConflict(
    Vault vault,
    String path, {
    required bool localExists,
    required bool remoteExists,
    _RemoteFile? remoteFile,
    File? capturedRemote,
    String? observedRemoteEtag,
  }) async {
    await _discardConflictsForPath(vault, path);
    final id = sha256
        .convert(utf8.encode('$path:${DateTime.now().microsecondsSinceEpoch}'))
        .toString()
        .substring(0, 20);
    final base = '.tylog/conflicts/$id';
    if (localExists) {
      await vault.storage.writeBytes(
        '$base.local',
        await vault.storage.readBytes(path),
      );
    }
    File? temporary = capturedRemote;
    if (remoteExists && temporary == null) {
      final captured = await _captureRemote(path);
      temporary = captured.file;
      observedRemoteEtag ??= captured.etag;
    }
    try {
      if (temporary != null) {
        await vault.storage.writeBytes(
          '$base.remote',
          await temporary.readAsBytes(),
        );
      }
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
    final localStat = localExists ? await vault.storage.stat(path) : null;
    await vault.storage.writeText(
      '$base.json',
      jsonEncode({
        'id': id,
        'path': path,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'localExists': localExists,
        'remoteExists': remoteExists,
        'localModified': localStat?.modified?.millisecondsSinceEpoch,
        'remoteModified': remoteFile?.modified.millisecondsSinceEpoch,
        'remoteEtag': NextcloudSync._normEtag(observedRemoteEtag ?? remoteFile?.etag),
        if (localExists) 'localSnapshot': '$base.local',
        if (remoteExists) 'remoteSnapshot': '$base.remote',
      }),
    );
  }

  /// Re-captures the current remote content into an existing unresolved
  /// conflict's snapshot and rewrites its JSON with the fresh etag/modified
  /// time. Keeps the guard in [resolveConflict] honest — that guard still
  /// protects the tiny window between this refresh and the user's decision,
  /// it just no longer freezes on an etag that can never be seen again.
  Future<void> _refreshConflictRemote(
    Vault vault,
    SyncConflict conflict,
    _RemoteFile remoteFile,
    _RemoteArchiveSnapshot? archive,
  ) async {
    final captured = await _captureRemote(
      conflict.path,
      archive: archive,
      remoteFile: remoteFile,
    );
    final base = conflict.recordPath.substring(
      0,
      conflict.recordPath.length - '.json'.length,
    );
    try {
      await vault.storage.writeBytes(
        '$base.remote',
        await captured.file.readAsBytes(),
      );
    } finally {
      if (await captured.file.exists()) await captured.file.delete();
    }
    await vault.storage.writeText(
      conflict.recordPath,
      jsonEncode({
        'id': conflict.id,
        'path': conflict.path,
        'createdAt': conflict.createdAt.toUtc().toIso8601String(),
        'localExists': conflict.localExists,
        'remoteExists': true,
        'localModified': conflict.localModified?.millisecondsSinceEpoch,
        'remoteModified': remoteFile.modified.millisecondsSinceEpoch,
        'remoteEtag': NextcloudSync._normEtag(captured.etag ?? remoteFile.etag),
        if (conflict.localSnapshot != null)
          'localSnapshot': conflict.localSnapshot,
        'remoteSnapshot': '$base.remote',
      }),
    );
  }

  /// Whether a divergence about to be recorded is not really a disagreement.
  ///
  /// The both-sides-changed branch has grown six of these rules; the branches
  /// that record an ETag race had none, and those are the ones *most* likely to
  /// be spurious — the remote moved between our read and our write, which very
  /// often means a peer uploaded the same bytes or appended to them. They went
  /// straight to a record the user had to arbitrate.
  ///
  /// Returns the trace reason when the conflict can be resolved without asking,
  /// or null when it is a genuine two-sided edit. Costs one GET on the race
  /// path, which is rare and cheaper than a record nobody can act on.
  Future<String?> _spuriousConflictReason(
    Vault vault,
    String path,
    List<int> localBytes,
    _RemoteFile? remoteFile,
  ) async {
    if (remoteFile == null) return null;
    File? captured;
    try {
      captured = (await _captureRemote(path, remoteFile: remoteFile)).file;
      final remoteBytes = await captured.readAsBytes();
      if (_sameBytes(localBytes, remoteBytes)) return 'same-content';
      final winner = fastForwardWinner(
        local: localBytes,
        remote: remoteBytes,
        path: path,
      );
      if (winner == SyncConflictResolution.keepLocal) {
        return 'auto-resolved-local-extends-remote';
      }
      if (winner == SyncConflictResolution.keepRemote) {
        return 'auto-resolved-remote-extends-local';
      }
      return null;
    } catch (_) {
      // Could not read the remote to compare: fall through to recording a
      // conflict, which is the conservative answer.
      return null;
    } finally {
      if (captured != null && await captured.exists()) await captured.delete();
    }
  }

  /// The remote snapshot bytes a conflict record currently points at — what
  /// the user was shown in the dialog. Null when there is no snapshot.
  ///
  /// Must be read *before* [_refreshConflictRemote], which overwrites the
  /// snapshot in place.
  Future<List<int>?> _conflictRemoteBytes(
    Vault vault,
    SyncConflict conflict,
  ) async {
    final path = conflict.remoteSnapshot;
    if (path == null) return null;
    try {
      if (!await vault.storage.exists(path)) return null;
      return await vault.storage.readBytes(path);
    } catch (_) {
      return null;
    }
  }

  /// Re-reads one conflict record from disk after it has been rewritten, so the
  /// in-memory copy stops carrying the etag the refresh just replaced.
  ///
  /// Reads the record file directly rather than going through
  /// [loadSyncConflicts], which self-heals: it deletes any record whose two
  /// snapshots match byte-for-byte. Mid-resolve that was a live hazard, because
  /// the refresh above has just overwritten the remote snapshot — so a remote
  /// that converged on the *frozen* local snapshot deleted the record under us.
  /// The local snapshot is frozen at record time and is not the live file, so
  /// the user could be left with neither side applied, no cursor written, and
  /// "Conflict resolved" on screen.
  Future<SyncConflict?> _readConflictRecord(
    Vault vault,
    SyncConflict conflict,
  ) async {
    try {
      if (!await vault.storage.exists(conflict.recordPath)) return null;
      final json =
          (jsonDecode(await vault.storage.readText(conflict.recordPath)) as Map)
              .cast<String, Object?>();
      return conflictFromRecordJson(json, conflict.recordPath);
    } catch (_) {
      return null;
    }
  }

  /// Whether the live remote disagrees with what the record was written from.
  bool _conflictRemoteMoved(SyncConflict conflict, _RemoteFile? current) =>
      conflict.remoteExists != (current != null) ||
      conflict.remoteEtag != null &&
          NextcloudSync._normEtag(current?.etag) !=
              NextcloudSync._normEtag(conflict.remoteEtag);

  /// Rewrites an unresolved conflict to the "Nextcloud deleted it" shape after
  /// the remote really did disappear.
  ///
  /// Without this such a record can never be resolved. `resolveConflict`
  /// compares the record's `remoteExists: true` against a remote that is now
  /// absent and throws `Nextcloud changed again` on every attempt, while
  /// [_refreshConflictRemote] — the only thing that could correct the record —
  /// is reached only when the remote file exists. Proven on the A24 with
  /// `articles/coqui.ai - Site not found GitHub Pages.typ`, recorded at 17:00
  /// and deleted server-side afterwards: it gated auto-sync indefinitely and
  /// the only escape was deleting the record by hand over adb.
  ///
  /// The remote snapshot is kept as evidence — it is the last known content of
  /// a file that no longer exists on the server — but it is deliberately NOT
  /// shown as a choice. "Keep Nextcloud's version" of a deleted file means
  /// accepting the deletion, which is what the resolve does; presenting the
  /// snapshot as a restorable side made the dialog offer "loses nothing" for an
  /// action that deletes the local file. See [conflictRemoteBytesToShow].
  Future<void> _markConflictRemoteDeleted(
    Vault vault,
    SyncConflict conflict,
  ) async {
    await vault.storage.writeText(
      conflict.recordPath,
      jsonEncode({
        'id': conflict.id,
        'path': conflict.path,
        'createdAt': conflict.createdAt.toUtc().toIso8601String(),
        'localExists': conflict.localExists,
        'remoteExists': false,
        'localModified': conflict.localModified?.millisecondsSinceEpoch,
        if (conflict.localSnapshot != null)
          'localSnapshot': conflict.localSnapshot,
        if (conflict.remoteSnapshot != null)
          'remoteSnapshot': conflict.remoteSnapshot,
      }),
    );
  }

  Future<int> _cleanResolvedConflictCopies(
    Vault vault,
    List<VaultStorageEntry> entries,
  ) async {
    var cleaned = 0;
    for (final entity in entries) {
      if (entity.isDirectory || !entity.path.contains('.remote-conflict-')) {
        continue;
      }
      final relative = entity.path;
      final original = relative.substring(
        0,
        relative.indexOf('.remote-conflict-'),
      );
      if (!await vault.storage.exists(original)) continue;
      final duplicate =
          (entity.size ?? 0) == 0 &&
              _protectFromEmpty(original) &&
              ((await vault.storage.stat(original))?.size ?? 0) > 0 ||
          await vault.storage.hash(relative) ==
              await vault.storage.hash(original);
      if (duplicate) {
        await vault.storage.delete(relative);
        cleaned++;
      }
    }
    return cleaned;
  }
}
