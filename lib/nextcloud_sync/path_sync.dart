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
        throw WebDavStatusException('GET archive $status', status);
      }
      final total = response.contentLength;
      var received = 0;
      final reportWatch = Stopwatch()..start();
      var lastReport = 0;
      void report() => progress(
        total > 0
            ? 'download-archive ${(received * 100 / total).floor()}%'
            : 'download-archive ${(received / (1024 * 1024)).toStringAsFixed(1)} MiB',
        null,
      );
      await response
          .map((chunk) {
            received += chunk.length;
            if (reportWatch.elapsedMilliseconds - lastReport >= 500) {
              lastReport = reportWatch.elapsedMilliseconds;
              report();
            }
            return chunk;
          })
          .pipe(temporary.openWrite())
          .timeout(const Duration(minutes: 5));
      report();
      // Skipped for a decompressed body; see _download in webdav_client.dart.
      if (response.compressionState !=
              HttpClientResponseCompressionState.decompressed &&
          response.contentLength >= 0 &&
          await temporary.length() != response.contentLength) {
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
        path = unorm.nfc(path);
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
        if (NextcloudSync._normEtag(entry.value.etag) !=
            NextcloudSync._normEtag(current.etag)) {
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
      // Compare canonical names, but retain the filesystem spelling in the entry.
      final key = unorm.nfc(entity.path);
      if (syncable.containsKey(key)) {
        throw StateError('Local paths have the same NFC name: $key');
      }
      syncable[key] = entity;
    }
    return (raw: raw, syncable: syncable);
  }

  /// Unconflicted local paths must match their cursor's mtime+size exactly.
  /// Pending conflicts stay outside this check until the user resolves them.
  bool _matchesLocalCursorSnapshot(
    Map<String, VaultStorageEntry> local,
    Map<String, SyncCursor> cursors, {
    Set<String> pendingPaths = const {},
  }) {
    final paths = {...local.keys, ...cursors.keys}..removeAll(pendingPaths);
    for (final path in paths) {
      final entry = local[path];
      final cursor = cursors[path];
      if (entry == null || cursor == null) return false;
      final millis = entry.modified?.millisecondsSinceEpoch;
      if (millis == null || millis != cursor.localMillis) return false;
      if (entry.size == null || entry.size != cursor.localSize) return false;
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
    int? recordedAt;
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
          !(unresolvedConflict != null && isMachineRevisionPath(path)) &&
          millis != null &&
          millis == previous!.localMillis &&
          previous.recordedAt != null &&
          previous.recordedAt! - millis >= 2000 &&
          localStat.size != null &&
          localStat.size == previous.localSize) {
        localHash = previous.localSha256;
        recordedAt = previous.recordedAt;
      } else {
        // Native streaming digest: hashing here used to pull the whole file
        // across the platform channel for every changed path, even the ones
        // that turn out to be downloads or skips. _uploadStorage reads the
        // bytes itself on the paths that actually upload.
        recordedAt = DateTime.now().millisecondsSinceEpoch;
        localHash = await vault.storage.hash(path);
      }
    }
    // The editor's 400ms autosave can land between the scan-time hash above
    // and the upload's own read of the file. Snapshotting bytes and hashing
    // exactly those bytes keeps the PUT body, its OC-Checksum, and the
    // recorded cursor describing one version — otherwise the next run sees
    // its own upload as a remote change and manufactures a conflict.
    Future<void> snapshotForUpload() async {
      if ((localStat?.size ?? 0) > 10 * 1024 * 1024 &&
          vault.storage.openRead(path, 0, 0) != null) {
        return;
      }
      recordedAt = DateTime.now().millisecondsSinceEpoch;
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
                  ? NextcloudSync._normEtag(remoteFile.etag) !=
                        NextcloudSync._normEtag(previous.remoteEtag)
                  : _isChanged(remoteTime, previous.remoteMillis));
    final listingConfirmsUpload =
        previous?.remoteEtag != null &&
        remoteFile?.etag != null &&
        NextcloudSync._normEtag(remoteFile!.etag) ==
            NextcloudSync._normEtag(previous!.remoteEtag);
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

    var verifiedRevision = false;
    if (unresolvedConflict != null &&
        isMachineRevisionPath(path) &&
        localExists &&
        remoteExists &&
        remoteFile.sha256 != null &&
        localHash == remoteFile.sha256) {
      await _discardConflictsForPath(vault, path);
      unresolvedConflict = null;
      verifiedRevision = true;
    }

    // Both sides accepted the deletion while a conflict was pending. There
    // is no live version left to arbitrate; do not leave a permanent blocker.
    if (unresolvedConflict != null &&
        !localExists &&
        !remoteExists &&
        allowLocalDeletes &&
        // A cached poll only knows paths with a cursor; a conflicted new file
        // has none. Ask the disk before discarding the only evidence.
        !await vault.storage.exists(path)) {
      await _discardConflictsForPath(vault, path);
      unresolvedConflict = null;
    }

    SyncConflictResolution? revisionWinner;
    Uint8List? revisionRemoteBytes;
    String? revisionRemoteEtag;
    var adoptRemoteConflict = false;
    if (unresolvedConflict != null && localExists && remoteExists) {
      final captured = await _captureRemote(
        path,
        archive: archive,
        remoteFile: remoteFile,
      );
      try {
        if (isMachineRevisionPath(path)) {
          recordedAt = DateTime.now().millisecondsSinceEpoch;
        }
        final bytes = localBytes ?? await vault.storage.readBytes(path);
        if (isMachineRevisionPath(path)) {
          localBytes = bytes;
          localHash = sha256.convert(bytes).toString();
          localStat = await vault.storage.stat(path) ?? localStat;
          revisionRemoteBytes = await captured.file.readAsBytes();
          // A compressed GET answers ETag "…-gzip", which If-Match on the
          // PUT never matches (412 on every run on the real server).
          final getEtag = NextcloudSync._normEtag(captured.etag);
          revisionRemoteEtag = getEtag == null ? null : '"$getEtag"';
          revisionWinner = revisionEnvelopeWinner(
            local: bytes,
            remote: revisionRemoteBytes,
          );
          // Without a GET etag we cannot guard a descendant upload.
          if (revisionWinner == SyncConflictResolution.keepLocal &&
              captured.etag == null) {
            revisionWinner = null;
          }
        }
        if (isMachineRevisionPath(path) &&
            sha256.convert(bytes).toString() == await _sha256(captured.file)) {
          await _discardConflictsForPath(vault, path);
          unresolvedConflict = null;
          verifiedRevision = true;
        }
        if (!isMachineRevisionPath(path)) {
          final remoteHash = await _sha256(captured.file);
          final latest = (await _loadSyncState(vault)).cursors[unorm.nfc(path)];
          if (remoteHash == previous?.uploadedSha256 ||
              remoteHash == latest?.uploadedSha256 ||
              (previous?.remoteConfirmed == false &&
                  remoteHash == previous?.localSha256) ||
              (latest?.remoteConfirmed == false &&
                  remoteHash == latest?.localSha256) ||
              (latest?.remoteConfirmed == false &&
                  latest?.remoteEtag != null &&
                  NextcloudSync._normEtag(captured.etag) ==
                      NextcloudSync._normEtag(latest!.remoteEtag)) ||
              await vault.hasLocalRevision(path, remoteHash)) {
            await _discardConflictsForPath(vault, path);
            unresolvedConflict = null;
            adoptRemoteConflict = true;
          }
        }
        final winner = fastForwardWinner(
          local: bytes,
          remote: await captured.file.readAsBytes(),
          path: path,
        );
        if (!verifiedRevision &&
            winner == SyncConflictResolution.keepRemote &&
            (isPristineStarterNote(
                  path,
                  utf8.decode(bytes, allowMalformed: true),
                ) ||
                (bytes.isEmpty && emptyDailyTemplate(path) != null))) {
          if (!isMachineRevisionPath(path)) {
            await _discardConflictsForPath(vault, path);
          }
          unresolvedConflict = null;
          adoptRemoteConflict = true;
        }
      } finally {
        await captured.file.delete();
      }
    }

    final machineJob =
        path.startsWith('_system/jobs/') && path.endsWith('.json');
    final resolveJobConflict =
        machineJob &&
        localExists &&
        remoteExists &&
        (unresolvedConflict != null || (localChanged && remoteChanged));

    final restoreRevision =
        isMachineRevisionPath(path) && !localExists && remoteExists;
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

    if (!verifiedRevision && revisionWinner != null) {
      try {
        if (revisionWinner == SyncConflictResolution.keepLocal) {
          // Upload exactly the live bytes whose ancestry was checked, guarded
          // by the etag of the remote bytes we compared.
          uploadedRemoteEtag = await _uploadStorage(
            path,
            vault.storage,
            localHash: localHash!,
            bytes: localBytes,
            remote: _RemoteFile(
              modified: remoteTime!,
              etag: revisionRemoteEtag,
            ),
          );
          action = SyncAction.upload;
          uploadedRemoteTime = DateTime.now().toUtc();
          uploaded++;
          reason = 'auto-resolved-local-extends-remote';
        } else {
          // Do not fetch again: a peer could have replaced the proven descendant.
          _requireLocalReplacementAllowed(path);
          if (await vault.storage.hash(path) != localHash) {
            throw const SyncDeferred();
          }
          await _snapshotBeforeReplacement(
            vault.storage,
            path,
            previous: previous,
          );
          await vault.storage.writeBytes(path, revisionRemoteBytes!);
          _recordLocalContentChange(path);
          action = SyncAction.download;
          observedRemoteEtag = revisionRemoteEtag;
          downloadedHash = sha256.convert(revisionRemoteBytes).toString();
          downloaded++;
          reason = 'auto-resolved-remote-extends-local';
        }
        await _discardConflictsForPath(vault, path);
        repaired++;
      } on _RemoteChanged {
        // Keep the evidence; the next pass must check the new remote ancestry.
        skipped++;
        reason = 'unresolved-conflict';
      }
    } else if (unresolvedConflict != null &&
        !resolveJobConflict &&
        !restoreRevision) {
      skipped++;
      reason = 'unresolved-conflict';
      // Why a revision envelope did not resolve itself, for the trace.
      if (isMachineRevisionPath(path)) {
        reason += !localExists
            ? ':no-local'
            : !remoteExists
            ? ':no-remote'
            : revisionRemoteEtag == null
            ? ':no-etag'
            : ':diverged';
      }
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
    } else if (verifiedRevision) {
      skipped++;
      repaired++;
      reason = 'same-content';
    } else if (initialMode == InitialSyncMode.downloadRemote) {
      if (remoteExists) {
        action = SyncAction.download;
        final download = await _downloadStorage(
          path,
          vault.storage,
          previous: previous,
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
    } else if (resolveJobConflict) {
      if (localHash == remoteFile.sha256) {
        skipped++;
        reason = 'same-content';
      } else if ((localStat?.modified?.millisecondsSinceEpoch ?? 0) ~/ 1000 >
          remoteTime!.millisecondsSinceEpoch ~/ 1000) {
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
        reason = 'auto-resolved-job-local-newer';
      } else {
        action = SyncAction.download;
        final download = await _downloadStorage(
          path,
          vault.storage,
          previous: previous,
          remoteFile: remoteFile,
          archive: archive,
        );
        observedRemoteEtag = download.etag;
        downloadedHash = download.localSha256;
        downloaded++;
        reason = 'auto-resolved-job-remote-newer';
      }
      if (unresolvedConflict != null) {
        await _discardConflictsForPath(vault, path);
      }
    } else if (localExists &&
        remoteExists &&
        (adoptRemoteConflict ||
            previous == null ||
            (!previous.remoteConfirmed && !listingConfirmsUpload) ||
            stateRecovered ||
            (localChanged && remoteChanged))) {
      // A producer can rewrite a coalesced envelope after the scan-time hash.
      // Compare and upload the same live snapshot, or equal bytes can conflict.
      if (isMachineRevisionPath(path)) await snapshotForUpload();
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
        final remoteHash = await _sha256(captured.file);
        final latest = (await _loadSyncState(vault)).cursors[unorm.nfc(path)];
        if (remoteHash == localHash) {
          await captured.file.delete();
          skipped++;
          repaired++;
          reason = 'same-content';
        } else if ((emptyDailyTemplate(path) == null ||
                ((localStat?.size ?? 0) > 0 &&
                    !isPristineStarterNote(
                      path,
                      utf8.decode(
                        localBytes ?? await vault.storage.readBytes(path),
                        allowMalformed: true,
                      ),
                    ))) &&
            (remoteHash == previous?.uploadedSha256 ||
                remoteHash == latest?.uploadedSha256 ||
                (previous?.remoteConfirmed == false &&
                    remoteHash == previous?.localSha256) ||
                (latest?.remoteConfirmed == false &&
                    remoteHash == latest?.localSha256) ||
                (latest?.remoteConfirmed == false &&
                    latest?.remoteEtag != null &&
                    NextcloudSync._normEtag(captured.etag) ==
                        NextcloudSync._normEtag(latest!.remoteEtag)) ||
                await vault.hasLocalRevision(path, remoteHash))) {
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
          reason = 'local-newer';
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
            (localStat?.size ?? 0) > 0 &&
            !isPristineStarterNote(
              path,
              utf8.decode(
                localBytes ?? await vault.storage.readBytes(path),
                allowMalformed: true,
              ),
            )) {
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
            previous: previous,
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
              previous: previous,
              protectNonEmpty:
                  emptyDailyTemplate(path) == null ||
                  !isPristineStarterNote(
                    path,
                    utf8.decode(
                      localBytes ?? await vault.storage.readBytes(path),
                      allowMalformed: true,
                    ),
                  ),
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
    } else if (isMachineRevisionPath(path) && !localExists && remoteExists) {
      action = SyncAction.download;
      final download = await _downloadStorage(
        path,
        vault.storage,
        archive: archive,
        remoteFile: remoteFile,
      );
      observedRemoteEtag = download.etag;
      downloadedHash = download.localSha256;
      downloaded++;
      reason = 'missing-machine-revision';
    } else if (previous != null && !localExists && remoteExists) {
      if ((remoteChanged || stateRecovered || possibleRename) &&
          isRegenerableCachePath(path)) {
        // A pruned donor racing its own republication. Take the remote copy
        // rather than asking about a cache file.
        action = SyncAction.download;
        final download = await _downloadStorage(
          path,
          vault.storage,
          previous: previous,
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
          previous: previous,
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
          // No spuriousness rules here, deliberately, unlike the upload race
          // below. An audit flagged this branch as the sibling that never got
          // them, but the two applicable ones cannot apply: the regenerable
          // cache rule already ran above, and every content rule needs a local
          // side to compare against — this path is reached precisely because
          // the local file is gone.
          //
          // A peer edited a file while this device deleted it. That is a real
          // delete-versus-edit disagreement and the one thing a person should
          // decide.
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
      // A cached local listing can miss writes made by other apps (same size
      // and mtime seen), so before downloading verify the real file hasn't
      // changed locally. See the accompanying test 'a download never
      // overwrites a local file changed outside the app'.
      if (localExists &&
          previous?.localSha256 != null &&
          await vault.storage.hash(path) != previous!.localSha256) {
        final spurious = await _spuriousConflictReason(
          vault,
          path,
          await vault.storage.readBytes(path),
          remoteFile,
        );
        if (spurious != null) {
          skipped++;
          repaired++;
          reason = spurious;
        } else {
          action = SyncAction.conflict;
          await _storeConflict(
            vault,
            path,
            localExists: true,
            remoteExists: true,
            remoteFile: remoteFile,
          );
          conflicts++;
          reason = 'local-changed-outside-app';
        }
      } else {
        action = SyncAction.download;
        final download = await _downloadStorage(
          path,
          vault.storage,
          previous: previous,
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
      }
    } else if (allowLocalDeletes &&
        localExists &&
        !remoteExists &&
        !localChanged &&
        !stateRecovered &&
        !possibleRename &&
        previous?.remoteEtag != null &&
        previous!.remoteConfirmed) {
      // Mirror of 'local-deleted' above: the cursor proves this exact content
      // was synced with the server before (etag recorded, bytes unchanged
      // since), so a missing remote is another device's deletion. Re-uploading
      // here resurrected every vault deletion — and the PUT into the deleted
      // parent collection 404-failed the whole run (2026-08-19). Local edits
      // since the last sync still win: localChanged falls through to upload.
      _requireLocalReplacementAllowed(path);
      if (await vault.storage.hash(path) != localHash) {
        throw const SyncDeferred();
      }
      action = SyncAction.deleteLocal;
      await _snapshotBeforeReplacement(vault.storage, path, previous: previous);
      await vault.storage.delete(path);
      _recordLocalContentChange(path);
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
        // The remote moved between our read and our PUT. Ask the same question
        // the both-sides-changed branch asks before assuming a disagreement:
        // very often a peer uploaded these exact bytes, or appended to them.
        final spurious = await _spuriousConflictReason(
          vault,
          path,
          localBytes ?? await vault.storage.readBytes(path),
          remoteFile,
        );
        if (spurious != null) {
          skipped++;
          repaired++;
          reason = spurious;
        } else {
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

    final wasDownloaded = action == SyncAction.download;
    // Tell the scan cache these bytes are new. Without this a downloaded note
    // whose mtime lands in the same second as the scan's listing, at the same
    // size, is indexed as unchanged — and stays that way until something else
    // moves it.
    if (wasDownloaded) {
      vault.markLocallyWritten(path);
      if (isMachineRevisionPath(path)) {
        await _discardConflictsForPath(vault, path);
      }
    }
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
          remoteConfirmed: action != SyncAction.upload,
          uploadedSha256: action == SyncAction.upload
              ? localHash
              : previous?.uploadedSha256,
          // Downloads have no receipt: their hash predates the local write.
          recordedAt: wasDownloaded ? null : recordedAt,
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
          NextcloudSync._normEtag(entry.value.remoteEtag) ==
              NextcloudSync._normEtag(oldRemote.etag);
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
      final hash = await vault.storage.hash(entry.value.path);
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
      if (unorm.nfc(old.key) == unorm.nfc(replacement.key)) {
        state.remove(old.key);
        state[unorm.nfc(replacement.key)] = old.value;
        continue;
      }
      progress('detect-renames', '${old.key} → ${replacement.key}');
      final moved = await _moveRemote(
        old.key,
        replacement.key,
        remote[old.key]!,
      );
      final stat = replacement.value;
      state.remove(old.key);
      state[replacement.key] = SyncCursor(
        // No recordedAt: the stat is from the scan, so the next index pass re-reads once.
        localMillis: stat.modified?.millisecondsSinceEpoch,
        localSize: stat.size,
        remoteMillis: moved.modified.millisecondsSinceEpoch,
        localSha256: group.key,
        uploadedSha256: old.value.uploadedSha256,
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
        // APFS aliases these spellings: never write then delete the same file.
        if (unorm.nfc(old.key) == unorm.nfc(replacement)) {
          state.remove(old.key);
          state[unorm.nfc(replacement)] = old.value;
          continue;
        }
        final oldStat = local[old.key];
        final replacementStat = local[replacement];
        if (oldStat == null && replacementStat == null) continue;
        if (oldStat != null &&
            await _localHash(vault.storage, oldStat.path, oldStat, old.value) !=
                group.key) {
          continue;
        }
        if (replacementStat != null &&
            await vault.storage.hash(replacementStat.path) != group.key) {
          continue;
        }
        progress('detect-renames', '${old.key} → $replacement');
        _requireLocalReplacementAllowed(old.key);
        _requireLocalReplacementAllowed(replacement);
        if (replacementStat == null) {
          final source = captured[replacement]!.file;
          final bytes = source == null
              ? await vault.storage.readBytes(oldStat!.path)
              : await source.readAsBytes();
          await _snapshotBeforeReplacement(vault.storage, replacement);
          await vault.storage.writeBytes(replacement, bytes);
          _recordLocalContentChange(replacement);
          if (await vault.storage.hash(replacement) != group.key) {
            await _snapshotBeforeReplacement(vault.storage, replacement);
            await vault.storage.delete(replacement);
            throw StateError('Local rename verification failed: $replacement');
          }
        }
        if (oldStat != null) {
          await _snapshotBeforeReplacement(
            vault.storage,
            oldStat.path,
            previous: old.value,
          );
          await vault.storage.delete(oldStat.path);
          _recordLocalContentChange(oldStat.path);
        }
        final nextStat = await vault.storage.stat(
          replacementStat?.path ?? replacement,
        );
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
          uploadedSha256: old.value.uploadedSha256,
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
        prev.recordedAt != null &&
        prev.recordedAt! - millis >= 2000 &&
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
