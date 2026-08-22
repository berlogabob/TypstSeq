part of '../nextcloud_sync.dart';

extension _PathSync on NextcloudSync {
  bool _shouldUseArchive({
    required InitialSyncMode? initialMode,
    required bool stateRecovered,
    required Map<String, VaultStorageEntry> local,
    required Map<String, _RemoteFile> remote,
    required Map<String, SyncCursor> state,
  }) {
    if (initialMode == InitialSyncMode.downloadRemote) return remote.isNotEmpty;
    // Any run with many cursor-less remote files (interrupted bootstrap being
    // resumed, bulk upload from another device) benefits from one ZIP GET.
    final candidates = remote.entries.where(
      (entry) =>
          !local.containsKey(entry.key) ||
          stateRecovered ||
          !state.containsKey(entry.key),
    );
    final list = candidates.toList();
    if (list.length < 32) return false;
    final candidateBytes = list.fold<int>(
      0,
      (total, entry) => total + (entry.value.length ?? 0),
    );
    final totalBytes = remote.values.fold<int>(
      0,
      (total, file) => total + (file.length ?? 0),
    );
    // ponytail: a fixed crossover avoids downloading a huge archive for a few
    // changes; tune this only if device measurements show a worse boundary.
    return totalBytes == 0 || candidateBytes * 2 >= totalBytes;
  }

  Future<_RemoteArchiveSnapshot?> _downloadArchive(
    Map<String, _RemoteFile> remote,
    void Function(String stage, String? path) progress,
  ) async {
    progress('download-archive', null);
    final temporary = await File(
      '${Directory.systemTemp.path}/tylog-${DateTime.now().microsecondsSinceEpoch}.zip',
    ).create();
    InputFileStream? input;
    var keep = false;
    try {
      final request = await _open('GET', config.rootUri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/zip');
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final status = response.statusCode;
      if (const {
        HttpStatus.badRequest,
        HttpStatus.notFound,
        HttpStatus.methodNotAllowed,
        HttpStatus.notAcceptable,
        HttpStatus.unsupportedMediaType,
        HttpStatus.notImplemented,
      }.contains(status)) {
        await response.drain<void>();
        return null;
      }
      if (status >= 400) {
        await response.drain<void>();
        throw WebDavStatusException('GET archive $status');
      }
      await response
          .pipe(temporary.openWrite())
          .timeout(const Duration(minutes: 5));
      if (response.headers.contentLength >= 0 &&
          await temporary.length() != response.headers.contentLength) {
        throw const HttpException('GET archive truncated body');
      }
      progress('validate-archive', null);
      input = InputFileStream(temporary.path);
      final archive = ZipDecoder().decodeStream(input);
      final files = _validatedArchiveFiles(archive, remote);
      if (files == null) return null;
      final after = (await _remoteFiles())!.files;
      if (!_sameRemoteSnapshot(remote, after)) {
        throw StateError('Cloud changed during archive download; Retry.');
      }
      keep = true;
      return _RemoteArchiveSnapshot(
        source: temporary,
        input: input,
        files: files,
      );
    } on ArchiveException catch (_) {
      return null;
    } on FormatException catch (_) {
      return null;
    } on RangeError catch (_) {
      return null;
    } finally {
      if (!keep) {
        if (input != null) await input.close();
        if (await temporary.exists()) await temporary.delete();
      }
    }
  }

  Map<String, ArchiveFile>? _validatedArchiveFiles(
    Archive archive,
    Map<String, _RemoteFile> remote,
  ) {
    Map<String, ArchiveFile>? map({required bool stripRoot}) {
      final out = <String, ArchiveFile>{};
      final root = config.rootUri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      for (final file in archive.files) {
        if (file.isSymbolicLink || file.name.contains('\\')) return null;
        if (file.isDirectory) continue;
        var path = file.name;
        if (stripRoot) {
          if (!path.startsWith('$root/')) return null;
          path = path.substring(root.length + 1);
        }
        try {
          validateVaultPath(path);
        } on ArgumentError {
          return null;
        }
        if (_isSyncInternal(path)) continue;
        final expected = remote[path];
        if (expected == null || out.containsKey(path)) return null;
        if (expected.length != null && expected.length != file.size) {
          return null;
        }
        out[path] = file;
      }
      return out.length == remote.length && remote.keys.every(out.containsKey)
          ? out
          : null;
    }

    return map(stripRoot: false) ?? map(stripRoot: true);
  }

  bool _sameRemoteSnapshot(
    Map<String, _RemoteFile> before,
    Map<String, _RemoteFile> after,
  ) {
    if (before.length != after.length ||
        !before.keys.every(after.containsKey)) {
      return false;
    }
    for (final entry in before.entries) {
      final current = after[entry.key]!;
      if (entry.value.length != current.length) return false;
      if (entry.value.etag != null && current.etag != null) {
        if (NextcloudSync._normEtag(entry.value.etag) != NextcloudSync._normEtag(current.etag)) {
          return false;
        }
      } else if (entry.value.modified != current.modified) {
        return false;
      }
    }
    return true;
  }

  /// One recursive listing feeds both the syncable path map used by the main
  /// loop and the raw entries (which include `.remote-conflict-*` copies)
  /// needed by [_cleanResolvedConflictCopies], instead of two tree walks.
  Future<
    ({List<VaultStorageEntry> raw, Map<String, VaultStorageEntry> syncable})
  >
  _localFiles(VaultStorage storage) async {
    final raw = await storage.list(recursive: true);
    final syncable = <String, VaultStorageEntry>{};
    for (final entity in raw) {
      if (entity.isDirectory || entity.path.endsWith('.tmp')) continue;
      if (_isSyncInternal(entity.path)) continue;
      syncable[entity.path] = entity;
    }
    return (raw: raw, syncable: syncable);
  }

  /// Cheap in-memory check for the no-change shortcut: every local file must
  /// still match its cursor's recorded mtime+size exactly, and no path may be
  /// missing or extra. Any mismatch must fall through to the full run — this
  /// is the only thing standing between a local edit and data loss.
  bool _matchesLocalCursorSnapshot(
    Map<String, VaultStorageEntry> local,
    Map<String, SyncCursor> cursors,
  ) {
    if (local.length != cursors.length) return false;
    for (final entry in local.entries) {
      final cursor = cursors[entry.key];
      if (cursor == null) return false;
      final millis = entry.value.modified?.millisecondsSinceEpoch;
      if (millis == null || millis != cursor.localMillis) return false;
      if (entry.value.size == null || entry.value.size != cursor.localSize) {
        return false;
      }
    }
    return true;
  }

  Future<_PathResult> _syncPath({
    required Vault vault,
    required String path,
    required VaultStorageEntry? localStat,
    required _RemoteFile? remoteFile,
    required SyncCursor? previous,
    required bool stateRecovered,
    required InitialSyncMode? initialMode,
    // Reassigned when a cache conflict is discarded below.
    // ignore: parameter_assignments
    SyncConflict? unresolvedConflict,
    required bool possibleRename,
    required bool allowLocalDeletes,
    required _RemoteArchiveSnapshot? archive,
  }) async {
    final localExists = localStat != null;
    final remoteExists = remoteFile != null;
    final remoteTime = remoteFile?.modified;
    Uint8List? localBytes;
    String? localHash;
    String? downloadedHash;
    if (localExists) {
      final millis = localStat.modified?.millisecondsSinceEpoch;
      // The same mtime+size gate as the shortcut, and the same blind spot: at
      // SAF's second granularity a same-size edit inside one second reuses the
      // *previous* hash and the path is then judged unchanged. Skipping the
      // shortcut is not enough on its own — the full pass reaches this and
      // makes the identical mistake — so a path with a pending local write is
      // always re-hashed. That costs one digest for a file we know just moved.
      if (previous?.localSha256 != null &&
          !vault.isPendingSyncWrite(path) &&
          millis != null &&
          millis == previous!.localMillis &&
          localStat.size != null &&
          localStat.size == previous.localSize) {
        localHash = previous.localSha256;
      } else {
        // Native streaming digest: hashing here used to pull the whole file
        // across the platform channel for every changed path, even the ones
        // that turn out to be downloads or skips. _uploadStorage reads the
        // bytes itself on the paths that actually upload.
        localHash = await vault.storage.hash(path);
      }
    }
    // The editor's 400ms autosave can land between the scan-time hash above
    // and the upload's own read of the file. Snapshotting bytes and hashing
    // exactly those bytes keeps the PUT body, its OC-Checksum, and the
    // recorded cursor describing one version — otherwise the next run sees
    // its own upload as a remote change and manufactures a conflict.
    Future<void> snapshotForUpload() async {
      localBytes = await vault.storage.readBytes(path);
      final snapshotHash = sha256.convert(localBytes!).toString();
      if (snapshotHash != localHash) {
        localHash = snapshotHash;
        localStat = await vault.storage.stat(path) ?? localStat;
      }
    }

    final localChanged = previous == null
        ? localExists
        : localHash != previous.localSha256;
    final remoteChanged = previous == null
        ? remoteExists
        : !remoteExists ||
              (previous.remoteEtag != null && remoteFile.etag != null
                  ? NextcloudSync._normEtag(remoteFile.etag) != NextcloudSync._normEtag(previous.remoteEtag)
                  : _isChanged(remoteTime, previous.remoteMillis));
    var action = SyncAction.skip;
    DateTime? uploadedRemoteTime;
    String? uploadedRemoteEtag;
    String? observedRemoteEtag;
    var reason = '';
    var uploaded = 0;
    var downloaded = 0;
    var skipped = 0;
    var conflicts = 0;
    var repaired = 0;
    var deletedRemote = 0;
    var deletedLocal = 0;

    if (unresolvedConflict != null && isRegenerableCachePath(path)) {
      // A conflict already recorded against a cache file would otherwise sit
      // there forever: the loop skips a conflicted path before reaching the
      // branches that know a donor is regenerable, so the record is the only
      // thing keeping it alive. Drop it and let this pass handle the path
      // normally.
      await _discardConflictsForPath(vault, path);
      unresolvedConflict = null;
      repaired++;
    }

    if (unresolvedConflict != null) {
      skipped++;
      reason = 'unresolved-conflict';
      // The stored etag is frozen at record time; the sync loop skips this
      // path forever otherwise, and resolveConflict's own guard throws
      // whenever the remote moves again — permanently, since nothing here
      // ever refreshed it. Catch up the record so the guard can pass once
      // the user reviews the current remote content.
      if (remoteFile != null) {
        if (NextcloudSync._normEtag(remoteFile.etag) !=
            NextcloudSync._normEtag(unresolvedConflict.remoteEtag)) {
          await _refreshConflictRemote(
            vault,
            unresolvedConflict,
            remoteFile,
            archive,
          );
        }
      } else if (unresolvedConflict.remoteExists) {
        // The remote is gone. Left as-is the record is unresolvable forever:
        // resolveConflict's guard compares remoteExists (true) against a
        // missing remote and throws on every attempt, and the refresh above
        // can never run. Rewrite it to the delete-vs-changed shape the
        // existing UI already knows how to resolve.
        await _markConflictRemoteDeleted(vault, unresolvedConflict);
      }
    } else if (initialMode == InitialSyncMode.downloadRemote) {
      if (remoteExists) {
        action = SyncAction.download;
        final download = await _downloadStorage(
          path,
          vault.storage,
          protectNonEmpty: true,
          archive: archive,
          remoteFile: remoteFile,
        );
        if (download.protected) {
          throw StateError('Cloud file $path is empty; local copy kept.');
        }
        observedRemoteEtag = download.etag;
        downloadedHash = download.localSha256;
        downloaded++;
        reason = localExists ? 'initial-cloud-copy' : 'initial-download';
      } else {
        skipped++;
        reason = 'initial-local-only';
      }
    } else if ((previous == null && localExists && remoteExists) ||
        (stateRecovered && localExists && remoteExists) ||
        (previous != null &&
            localChanged &&
            remoteChanged &&
            localExists &&
            remoteExists)) {
      if (remoteFile.sha256 != null && remoteFile.sha256 == localHash) {
        observedRemoteEtag = remoteFile.etag;
        skipped++;
        repaired++;
        reason = 'same-content';
      } else {
        final captured = await _captureRemote(
          path,
          archive: archive,
          remoteFile: remoteFile,
        );
        observedRemoteEtag = captured.etag;
        if (await _sha256(captured.file) == localHash) {
          await captured.file.delete();
          skipped++;
          repaired++;
          reason = 'same-content';
        } else if (await _sameImageDifferentMetadata(
          vault,
          path,
          captured.file,
          localBytes: localBytes,
        )) {
          // Same picture, different metadata — Android hands us a GPS-redacted
          // read of a file whose bytes on disk are intact, so a geotagged photo
          // looks changed on this device forever. Treating it as a conflict is
          // wrong twice over: it can never be resolved (the next read is
          // redacted again), and "keep this device version" would upload the
          // redacted copy and destroy the coordinates on the server.
          await captured.file.delete();
          skipped++;
          reason = 'same-image-metadata-differs';
        } else if (_protectFromEmpty(path) &&
            await captured.file.length() == 0 &&
            (localStat?.size ?? 0) > 0) {
          await captured.file.delete();
          action = SyncAction.upload;
          await snapshotForUpload();
          uploadedRemoteEtag = await _uploadStorage(
            path,
            vault.storage,
            localHash: localHash!,
            remote: remoteFile,
            bytes: localBytes,
          );
          uploadedRemoteTime = DateTime.now().toUtc();
          uploaded++;
          repaired++;
          reason = 'remote-empty-repaired';
        } else if (isRegenerableCachePath(path)) {
          // Two devices' views of a shared cache file. Nothing here is
          // user-authored, so the remote copy wins rather than the user being
          // asked to arbitrate between two derived indexes.
          await captured.file.delete();
          action = SyncAction.download;
          final download = await _downloadStorage(
            path,
            vault.storage,
            protectNonEmpty: true,
            archive: archive,
            remoteFile: remoteFile,
          );
          observedRemoteEtag = download.etag;
          downloadedHash = download.localSha256;
          downloaded++;
          repaired++;
          reason = 'cache-refetched';
        } else if (fastForwardWinner(
              local: localBytes ?? await vault.storage.readBytes(path),
              remote: await captured.file.readAsBytes(),
              path: path,
            )
            case final winner?) {
          // One copy is the other plus an appended block. Keeping the longer
          // side is lossless by definition, so stopping the user for a
          // decision with one safe answer only invites the wrong one — and
          // until Phase 1 it also froze the whole vault's sync.
          await captured.file.delete();
          if (winner == SyncConflictResolution.keepRemote) {
            action = SyncAction.download;
            final download = await _downloadStorage(
              path,
              vault.storage,
              protectNonEmpty: true,
              archive: archive,
              remoteFile: remoteFile,
            );
            observedRemoteEtag = download.etag;
            downloadedHash = download.localSha256;
            downloaded++;
            reason = 'auto-resolved-remote-extends-local';
          } else {
            action = SyncAction.upload;
            await snapshotForUpload();
            uploadedRemoteEtag = await _uploadStorage(
              path,
              vault.storage,
              localHash: localHash!,
              remote: remoteFile,
              bytes: localBytes,
            );
            uploadedRemoteTime = DateTime.now().toUtc();
            uploaded++;
            reason = 'auto-resolved-local-extends-remote';
          }
          repaired++;
        } else {
          action = SyncAction.conflict;
          await _storeConflict(
            vault,
            path,
            localExists: true,
            remoteExists: true,
            remoteFile: remoteFile,
            capturedRemote: captured.file,
            observedRemoteEtag: observedRemoteEtag,
          );
          conflicts++;
          reason = previous == null ? 'first-sync-different' : 'both-changed';
        }
      }
    } else if (previous != null && !localExists && remoteExists) {
      if ((remoteChanged || stateRecovered || possibleRename) &&
          isRegenerableCachePath(path)) {
        // A pruned donor racing its own republication. Take the remote copy
        // rather than asking about a cache file.
        action = SyncAction.download;
        final download = await _downloadStorage(
          path,
          vault.storage,
          protectNonEmpty: true,
          archive: archive,
          remoteFile: remoteFile,
        );
        observedRemoteEtag = download.etag;
        downloadedHash = download.localSha256;
        downloaded++;
        repaired++;
        reason = 'cache-refetched';
      } else if (remoteChanged || stateRecovered || possibleRename) {
        action = SyncAction.conflict;
        await _storeConflict(
          vault,
          path,
          localExists: false,
          remoteExists: true,
          remoteFile: remoteFile,
        );
        conflicts++;
        reason = possibleRename
            ? 'possible-rename-kept'
            : 'local-delete-remote-edit';
      } else if (isRegenerableCachePath(path)) {
        // Never propagate. This device's copy is absent because its own prune
        // dropped a donor it could not read - not because anyone deleted
        // anything - and propagating that removed the desktop's freshly
        // published donor from the server, which is the one file the whole
        // fleet was waiting on.
        action = SyncAction.download;
        final download = await _downloadStorage(
          path,
          vault.storage,
          protectNonEmpty: true,
          archive: archive,
          remoteFile: remoteFile,
        );
        observedRemoteEtag = download.etag;
        downloadedHash = download.localSha256;
        downloaded++;
        repaired++;
        reason = 'cache-refetched';
      } else {
        try {
          action = SyncAction.deleteRemote;
          await _deleteRemote(path, remoteFile.etag);
          deletedRemote++;
          reason = 'local-deleted';
        } on _RemoteChanged {
          action = SyncAction.conflict;
          await _storeConflict(
            vault,
            path,
            localExists: false,
            remoteExists: true,
            remoteFile: remoteFile,
          );
          conflicts++;
          reason = 'remote-changed-during-delete';
        }
      }
    } else if (!localExists && !remoteExists) {
      skipped++;
      reason = 'both-missing';
      // ponytail: PROPFIND absence is not a deletion tombstone. The selected
      // Android folder is authoritative, so a missing remote is restored.
    } else if (remoteExists &&
        (!localExists || (remoteChanged && !localChanged))) {
      action = SyncAction.download;
      final download = await _downloadStorage(
        path,
        vault.storage,
        protectNonEmpty: true,
        archive: archive,
        remoteFile: remoteFile,
      );
      observedRemoteEtag = download.etag;
      downloadedHash = download.localSha256;
      if (download.protected) {
        action = SyncAction.upload;
        await snapshotForUpload();
        uploadedRemoteEtag = await _uploadStorage(
          path,
          vault.storage,
          localHash: localHash!,
          remote: remoteFile,
          bytes: localBytes,
        );
        uploadedRemoteTime = DateTime.now().toUtc();
        uploaded++;
        repaired++;
        reason = 'remote-empty-repaired';
      } else {
        downloaded++;
        reason = localExists ? 'remote-newer' : 'local-missing';
      }
    } else if (allowLocalDeletes &&
        localExists &&
        !remoteExists &&
        !localChanged &&
        !stateRecovered &&
        !possibleRename &&
        previous?.remoteEtag != null) {
      // Mirror of 'local-deleted' above: the cursor proves this exact content
      // was synced with the server before (etag recorded, bytes unchanged
      // since), so a missing remote is another device's deletion. Re-uploading
      // here resurrected every vault deletion — and the PUT into the deleted
      // parent collection 404-failed the whole run (2026-08-19). Local edits
      // since the last sync still win: localChanged falls through to upload.
      action = SyncAction.deleteLocal;
      await vault.storage.delete(path);
      deletedLocal++;
      reason = 'remote-deleted';
    } else if ((localExists && !remoteExists) ||
        (localChanged && !remoteChanged)) {
      action = SyncAction.upload;
      try {
        await snapshotForUpload();
        uploadedRemoteEtag = await _uploadStorage(
          path,
          vault.storage,
          localHash: localHash!,
          remote: remoteFile,
          bytes: localBytes,
        );
        uploadedRemoteTime = DateTime.now().toUtc();
        uploaded++;
        reason = remoteExists ? 'local-newer' : 'remote-missing';
      } on _RemoteChanged {
        action = SyncAction.conflict;
        await _storeConflict(
          vault,
          path,
          localExists: true,
          remoteExists: true,
          remoteFile: remoteFile,
        );
        conflicts++;
        reason = 'remote-changed-during-upload';
      }
    } else {
      skipped++;
      reason = 'no-change';
    }

    // Self-heal files this app uploaded before the `OC-Checksum` header case
    // fix: the server still stores the lowercase `sha256:` type, which makes
    // Nextcloud Desktop refuse to sync the file at all ("unknown checksum
    // type"). Only re-PUT paths that are otherwise fully in sync — never a
    // path that's about to conflict, download, or genuinely upload new
    // content — and send byte-identical content guarded by If-Match so a
    // concurrent remote change (412) is simply skipped; the next sync
    // retries.
    if ((reason == 'no-change' || reason == 'same-content') &&
        remoteFile != null &&
        remoteFile.sha256Lowercase &&
        localHash != null) {
      try {
        await snapshotForUpload();
        uploadedRemoteEtag = await _uploadStorage(
          path,
          vault.storage,
          localHash: localHash!,
          remote: remoteFile,
          bytes: localBytes,
        );
        uploadedRemoteTime = DateTime.now().toUtc();
        repaired++;
        reason = 'checksum-repaired';
      } on _RemoteChanged {
        // Remote moved since PROPFIND; leave state as-is and let the next
        // sync pass re-evaluate whether a repair is still needed.
      }
    }

    if (uploadedRemoteTime != null && uploadedRemoteEtag == null) {
      // The PUT response carried no etag. Falling back to the pre-upload
      // etag in the cursor would make the next run flag this device's own
      // upload as a remote change — probe the fresh one instead.
      uploadedRemoteEtag = (await _probeRemoteFile(path))?.etag;
    }
    final wasDownloaded = action == SyncAction.download;
    final nextLocal = wasDownloaded
        ? await vault.storage.stat(path)
        : localStat;
    final nextLocalExists = action == SyncAction.deleteLocal
        ? false
        : (wasDownloaded ? nextLocal != null : localExists);
    final nextRemote = uploadedRemoteTime ?? remoteTime;
    var updateCursor = false;
    SyncCursor? cursor;
    if (action != SyncAction.conflict) {
      final nextRemoteExists =
          action != SyncAction.deleteRemote &&
          (remoteExists || action == SyncAction.upload);
      if (nextLocalExists && nextRemoteExists) {
        updateCursor = true;
        cursor = SyncCursor(
          localMillis: nextLocal?.modified?.millisecondsSinceEpoch,
          localSize: nextLocal?.size,
          remoteMillis: nextRemote?.millisecondsSinceEpoch,
          localSha256: wasDownloaded
              ? (downloadedHash ?? await vault.storage.hash(path))
              : localHash,
          remoteEtag: NextcloudSync._normEtag(
            uploadedRemoteEtag ?? observedRemoteEtag ?? remoteFile?.etag,
          ),
        );
      } else if (!nextLocalExists && !nextRemoteExists) {
        updateCursor = true;
      }
    }
    return _PathResult(
      decision: SyncDecision(
        path: path,
        action: action,
        reason: reason,
        localMillis: nextLocal?.modified?.millisecondsSinceEpoch,
        remoteMillis: nextRemote?.millisecondsSinceEpoch,
      ),
      updateCursor: updateCursor,
      cursor: cursor,
      uploaded: uploaded,
      downloaded: downloaded,
      skipped: skipped,
      conflicts: conflicts,
      repaired: repaired,
      deletedRemote: deletedRemote,
      deletedLocal: deletedLocal,
    );
  }

  Future<_RenameDetection> _detectRenames(
    Vault vault,
    Map<String, VaultStorageEntry> local,
    Map<String, _RemoteFile> remote,
    Map<String, SyncCursor> state,
    void Function(String stage, String? path) progress, {
    required String? rootEtag,
  }) async {
    if (state.isEmpty) {
      return const _RenameDetection(
        decisions: [],
        protectedLocalDeletions: <String>{},
      );
    }
    final decisions = <SyncDecision>[];
    final protectedLocalDeletions = <String>{};

    final missingLocal = state.entries.where((entry) {
      final oldRemote = remote[entry.key];
      return entry.value.localSha256 != null &&
          !local.containsKey(entry.key) &&
          oldRemote != null &&
          entry.value.remoteEtag != null &&
          oldRemote.etag != null &&
          NextcloudSync._normEtag(entry.value.remoteEtag) == NextcloudSync._normEtag(oldRemote.etag);
    }).toList();
    final localOnly = local.entries
        .where(
          (entry) =>
              !state.containsKey(entry.key) && !remote.containsKey(entry.key),
        )
        .toList();
    final oldLocalByHash = <String, List<MapEntry<String, SyncCursor>>>{};
    for (final entry in missingLocal) {
      oldLocalByHash.putIfAbsent(entry.value.localSha256!, () => []).add(entry);
    }
    final newLocalByHash =
        <String, List<MapEntry<String, VaultStorageEntry>>>{};
    for (final entry in localOnly) {
      final possible = missingLocal.any(
        (old) =>
            old.value.localSize == null ||
            entry.value.size == null ||
            old.value.localSize == entry.value.size,
      );
      if (!possible) continue;
      final hash = await vault.storage.hash(entry.key);
      newLocalByHash.putIfAbsent(hash, () => []).add(entry);
    }
    for (final group in oldLocalByHash.entries) {
      final oldMatches = group.value;
      final newMatches = newLocalByHash[group.key] ?? const [];
      if (oldMatches.length != 1 || newMatches.length != 1) {
        if (localOnly.isNotEmpty) {
          protectedLocalDeletions.addAll(oldMatches.map((entry) => entry.key));
        }
        continue;
      }
      final old = oldMatches.single;
      final replacement = newMatches.single;
      progress('detect-renames', '${old.key} → ${replacement.key}');
      final moved = await _moveRemote(
        old.key,
        replacement.key,
        remote[old.key]!,
      );
      final stat = replacement.value;
      state.remove(old.key);
      state[replacement.key] = SyncCursor(
        localMillis: stat.modified?.millisecondsSinceEpoch,
        localSize: stat.size,
        remoteMillis: moved.modified.millisecondsSinceEpoch,
        localSha256: group.key,
        remoteEtag: NextcloudSync._normEtag(moved.etag),
      );
      remote.remove(old.key);
      remote[replacement.key] = moved;
      await _saveSyncState(vault, state, rootEtag: rootEtag);
      decisions.add(
        SyncDecision(
          path: replacement.key,
          action: SyncAction.rename,
          reason: 'local-rename',
          localMillis: stat.modified?.millisecondsSinceEpoch,
          remoteMillis: moved.modified.millisecondsSinceEpoch,
        ),
      );
    }

    final missingRemote = state.entries
        .where(
          (entry) =>
              entry.value.localSha256 != null && !remote.containsKey(entry.key),
        )
        .toList();
    final remoteNew = remote.entries
        .where((entry) => !state.containsKey(entry.key))
        .toList();
    final oldRemoteByHash = <String, List<MapEntry<String, SyncCursor>>>{};
    for (final entry in missingRemote) {
      oldRemoteByHash
          .putIfAbsent(entry.value.localSha256!, () => [])
          .add(entry);
    }
    final captured = <String, ({String hash, File? file})>{};
    try {
      for (final entry in remoteNew) {
        final possible = missingRemote.any(
          (old) =>
              old.value.localSize == null ||
              entry.value.length == null ||
              old.value.localSize == entry.value.length,
        );
        if (!possible) continue;
        if (entry.value.sha256 != null) {
          captured[entry.key] = (hash: entry.value.sha256!, file: null);
        } else {
          progress('detect-renames', entry.key);
          final download = await _captureRemote(entry.key);
          captured[entry.key] = (
            hash: await _sha256(download.file),
            file: download.file,
          );
        }
      }
      final newRemoteByHash = <String, List<String>>{};
      for (final entry in captured.entries) {
        newRemoteByHash.putIfAbsent(entry.value.hash, () => []).add(entry.key);
      }
      for (final group in oldRemoteByHash.entries) {
        final oldMatches = group.value;
        final newMatches = newRemoteByHash[group.key] ?? const [];
        if (oldMatches.length != 1 || newMatches.length != 1) continue;
        final old = oldMatches.single;
        final replacement = newMatches.single;
        final oldStat = local[old.key];
        final replacementStat = local[replacement];
        if (oldStat == null && replacementStat == null) continue;
        if (oldStat != null &&
            await _localHash(vault.storage, old.key, oldStat, old.value) !=
                group.key) {
          continue;
        }
        if (replacementStat != null &&
            await vault.storage.hash(replacement) != group.key) {
          continue;
        }
        progress('detect-renames', '${old.key} → $replacement');
        _requireLocalReplacementAllowed(old.key);
        _requireLocalReplacementAllowed(replacement);
        if (replacementStat == null) {
          final source = captured[replacement]!.file;
          final bytes = source == null
              ? await vault.storage.readBytes(old.key)
              : await source.readAsBytes();
          await vault.storage.writeBytes(replacement, bytes);
          if (await vault.storage.hash(replacement) != group.key) {
            await vault.storage.delete(replacement);
            throw StateError('Local rename verification failed: $replacement');
          }
        }
        if (oldStat != null) await vault.storage.delete(old.key);
        final nextStat = await vault.storage.stat(replacement);
        if (nextStat == null) {
          throw StateError('Local rename did not create $replacement');
        }
        final remoteFile = remote[replacement]!;
        local.remove(old.key);
        local[replacement] = nextStat;
        state.remove(old.key);
        state[replacement] = SyncCursor(
          localMillis: nextStat.modified?.millisecondsSinceEpoch,
          localSize: nextStat.size,
          remoteMillis: remoteFile.modified.millisecondsSinceEpoch,
          localSha256: group.key,
          remoteEtag: NextcloudSync._normEtag(remoteFile.etag),
        );
        await _saveSyncState(vault, state, rootEtag: rootEtag);
        decisions.add(
          SyncDecision(
            path: replacement,
            action: SyncAction.rename,
            reason: 'remote-rename',
            localMillis: nextStat.modified?.millisecondsSinceEpoch,
            remoteMillis: remoteFile.modified.millisecondsSinceEpoch,
          ),
        );
      }
    } finally {
      for (final value in captured.values) {
        final file = value.file;
        if (file != null && await file.exists()) await file.delete();
      }
    }
    return _RenameDetection(
      decisions: decisions,
      protectedLocalDeletions: protectedLocalDeletions,
    );
  }

  /// Reuses the cursor's hash when mtime+size are unchanged, so steady-state
  /// syncs stop re-reading every file (a full SAF round-trip per file on
  /// Android). Missing mtime/size falls back to hashing.
  Future<String> _localHash(
    VaultStorage storage,
    String path,
    VaultStorageEntry stat,
    SyncCursor? prev,
  ) async {
    final millis = stat.modified?.millisecondsSinceEpoch;
    if (prev?.localSha256 != null &&
        millis != null &&
        millis == prev!.localMillis &&
        stat.size != null &&
        stat.size == prev.localSize) {
      return prev.localSha256!;
    }
    return storage.hash(path);
  }

  /// Whether local and remote are the same photo differing only in metadata.
  ///
  /// Android redacts GPS EXIF from images read out of shared storage, and the
  /// app cannot opt out: the redaction is decided from the identity of the
  /// DocumentsProvider serving the read, not ours, so `ACCESS_MEDIA_LOCATION`
  /// never reaches it. The file on disk keeps its coordinates; every read we do
  /// has them zeroed.
  ///
  /// Confirmed on a real device — the on-disk bytes and the server's bytes had
  /// the same SHA-256, and only the app's read differed. Without this check
  /// those photos conflict on every sync forever.
  ///
  /// Bounded on size: this reads both sides into memory, and it is only ever
  /// reached for a file whose length already matches on both sides.
  Future<bool> _sameImageDifferentMetadata(
    Vault vault,
    String path,
    File capturedRemote, {
    List<int>? localBytes,
  }) async {
    const jpeg = {'.jpg', '.jpeg'};
    final dot = path.lastIndexOf('.');
    if (dot < 0 || !jpeg.contains(path.substring(dot).toLowerCase())) {
      return false;
    }
    const limit = 32 * 1024 * 1024;
    try {
      if (await capturedRemote.length() > limit) return false;
      final local = localBytes ?? await vault.storage.readBytes(path);
      if (local.length != await capturedRemote.length()) return false;
      return sameJpegIgnoringMetadata(
        local,
        await capturedRemote.readAsBytes(),
      );
    } catch (_) {
      // Unreadable either side: no opinion, fall through to the normal
      // comparison rather than guessing the files match.
      return false;
    }
  }
}
