import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'vault.dart';
import 'vault_storage.dart';

class NextcloudConfig {
  const NextcloudConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.remoteFolder = 'TyLogVault',
  });

  final String serverUrl;
  final String username;
  final String password;
  final String remoteFolder;

  bool get isReady {
    final server = Uri.tryParse(serverUrl.trim());
    final folders = _remoteFolders;
    if (server == null) return false;
    // ponytail: https required; http only to loopback (local/test dav). Basic auth
    // over cleartext http to a public host would leak the password on the wire.
    final loopback =
        server.host == 'localhost' ||
        (InternetAddress.tryParse(server.host)?.isLoopback ?? false);
    final schemeOk =
        server.scheme == 'https' || (server.scheme == 'http' && loopback);
    return schemeOk &&
        server.host.isNotEmpty &&
        username.trim().isNotEmpty &&
        password.isNotEmpty &&
        folders.isNotEmpty &&
        !folders.any((folder) => folder == '.' || folder == '..');
  }

  List<String> get _remoteFolders => remoteFolder
      .trim()
      .split('/')
      .where((folder) => folder.isNotEmpty)
      .toList();

  Uri get rootUri {
    final base = Uri.parse(serverUrl.trim().replaceFirst(RegExp(r'/+$'), ''));
    if (base.path.contains('/remote.php/dav/files/')) {
      return base.path.endsWith('/')
          ? base
          : base.replace(path: '${base.path}/');
    }
    return base.replace(
      path:
          '${base.path.replaceFirst(RegExp(r'/+$'), '')}/remote.php/dav/files/${username.trim()}/${_remoteFolders.join('/')}/',
    );
  }

  bool get usesDirectWebDavUrl =>
      Uri.parse(serverUrl.trim()).path.contains('/remote.php/dav/files/');

  Uri get filesUri {
    if (usesDirectWebDavUrl) return rootUri;
    final base = Uri.parse(serverUrl.trim().replaceFirst(RegExp(r'/+$'), ''));
    return base.replace(
      path:
          '${base.path.replaceFirst(RegExp(r'/+$'), '')}/remote.php/dav/files/${username.trim()}/',
    );
  }

  NextcloudConfig withPassword(String password) => NextcloudConfig(
    serverUrl: serverUrl,
    username: username,
    password: password,
    remoteFolder: remoteFolder,
  );

  // ponytail: password lives in the OS keystore only, never in vaults.json /
  // nextcloud.json. `password` is intentionally absent from toJson.
  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'remoteFolder': remoteFolder,
  };

  static NextcloudConfig fromJson(Map<String, Object?> json) => NextcloudConfig(
    serverUrl: json['serverUrl'] as String? ?? json['url'] as String? ?? '',
    username: json['username'] as String? ?? '',
    // Legacy inline password (pre-keystore files); migrated out on next load/save.
    password: json['password'] as String? ?? '',
    remoteFolder: json['remoteFolder'] as String? ?? 'TyLogVault',
  );

  static const _secure = FlutterSecureStorage();
  static String _secretKey(String? vaultId) =>
      'nextcloud-password-${vaultId ?? '__default__'}';

  Future<void> saveSecret({String? vaultId}) =>
      _secure.write(key: _secretKey(vaultId), value: password);

  static Future<String?> readSecret({String? vaultId}) =>
      _secure.read(key: _secretKey(vaultId));

  static Future<void> deleteSecret({String? vaultId}) =>
      _secure.delete(key: _secretKey(vaultId));

  static Future<File> settingsFile({String? vaultId}) async {
    final base = await getApplicationDocumentsDirectory();
    final suffix = vaultId == null
        ? ''
        : '-${sha256.convert(utf8.encode(vaultId))}';
    return File('${base.path}/nextcloud$suffix.json');
  }

  static Future<NextcloudConfig?> load({String? vaultId}) async {
    final file = await settingsFile(vaultId: vaultId);
    if (!await file.exists()) return null;
    final config = fromJson(
      jsonDecode(await file.readAsString()) as Map<String, Object?>,
    );
    final secret = await readSecret(vaultId: vaultId);
    if (secret != null) return config.withPassword(secret);
    // Migrate a legacy inline password into the keystore and strip it from disk.
    if (config.password.isNotEmpty) await config.save(vaultId: vaultId);
    return config;
  }

  Future<void> save({String? vaultId}) async {
    await saveSecret(vaultId: vaultId);
    final file = await settingsFile(vaultId: vaultId);
    await writeFileAtomic(file, utf8.encode(jsonEncode(toJson())));
  }
}

class NextcloudSync {
  NextcloudSync(this.config, {this.onProgress, this.canReplaceLocal});

  final NextcloudConfig config;
  final void Function(String stage, String? path)? onProgress;
  final bool Function(String path)? canReplaceLocal;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  static Duration propfindBodyTimeout = const Duration(seconds: 60);

  Future<SyncResult> sync(Vault vault, {String trigger = 'manual'}) async {
    final runId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    var stage = 'start';
    String? currentPath;
    var up = 0;
    var down = 0;
    var skip = 0;
    var conflict = 0;
    var repaired = 0;
    var deletedLocal = 0;
    var deletedRemote = 0;
    var remoteCount = 0;
    final decisions = <SyncDecision>[];
    void progress(String next, [String? path]) {
      stage = next;
      currentPath = path;
      onProgress?.call(next, path);
    }

    // ponytail: trace events are buffered and written once per sync (one SAF
    // write instead of a full read+rewrite per event); a hard process kill
    // loses that run's trace, acceptable for diagnostics.
    final traceEvents = <Map<String, Object?>>[];
    progress(stage);
    traceEvents.add({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'runId': runId,
      'event': 'started',
      'trigger': trigger,
    });
    try {
      if (!config.isReady) throw StateError('Nextcloud settings are empty');
      progress('prepare-remote-folder');
      await _ensureConfiguredFolder();
      progress('load-local-state');
      final loadedState = await _loadSyncState(vault);
      final syncState = loadedState.cursors;
      if (loadedState.recovered) {
        traceEvents.add({
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'runId': runId,
          'event': 'state-recovered',
          'trigger': trigger,
        });
      }
      progress('list-remote');
      final remote = await _remoteFiles();
      remoteCount = remote.length;
      progress('scan-local');
      repaired = await _cleanResolvedConflictCopies(vault);
      final localEntries = await _localFiles(vault.storage);
      if (syncState.isNotEmpty && remote.isNotEmpty && localEntries.isEmpty) {
        throw StateError(
          'Local vault listed no syncable files; refusing to propagate deletions.',
        );
      }
      // ponytail: proportional guard against a flaky DocumentsProvider dropping
      // listing entries; threshold max(10, 25%), add a confirmation flow if it
      // ever fires on legitimate bulk deletes.
      final plannedDeletions = syncState.keys
          .where((path) => !localEntries.containsKey(path) && remote.containsKey(path))
          .length;
      final deletionLimit = math.max(10, syncState.length ~/ 4);
      if (plannedDeletions > deletionLimit) {
        throw StateError(
          'Refusing to propagate $plannedDeletions deletions '
          '(limit $deletionLimit); local listing may be incomplete.',
        );
      }
      final unresolved = (await loadSyncConflicts(
        vault,
      )).map((conflict) => conflict.path).toSet();
      final allPaths = <String>{
        ...localEntries.keys,
        ...remote.keys,
        ...syncState.keys,
      }.toList()..sort();

      for (final path in allPaths) {
        progress('sync-file', path);
        final localStat = localEntries[path];
        final localExists = localStat != null;
        final remoteFile = remote[path];
        final remoteTime = remoteFile?.modified;
        final prev = syncState[path];
        final localHash = localExists
            ? await _localHash(vault.storage, path, localStat, prev)
            : null;
        final remoteExists = remoteFile != null;
        final localChanged = prev == null
            ? localExists
            : localHash != prev.localSha256;
        final remoteChanged = prev == null
            ? remoteExists
            : !remoteExists ||
                  (prev.remoteEtag != null && remoteFile.etag != null
                      ? _normEtag(remoteFile.etag) != _normEtag(prev.remoteEtag)
                      : _isChanged(remoteTime, prev.remoteMillis));
        var action = SyncAction.skip;
        DateTime? uploadedRemoteTime;
        String? uploadedRemoteEtag;
        String? observedRemoteEtag;
        var reason = '';
        if (unresolved.contains(path)) {
          skip++;
          reason = 'unresolved-conflict';
        } else if ((prev == null && localExists && remoteExists) ||
            (loadedState.recovered && localExists && remoteExists) ||
            (prev != null &&
                localChanged &&
                remoteChanged &&
                localExists &&
                remoteExists)) {
          final captured = await _captureRemote(path);
          observedRemoteEtag = captured.etag;
          if (await _sha256(captured.file) == localHash) {
            await captured.file.delete();
            action = SyncAction.skip;
            skip++;
            repaired++;
            reason = 'same-content';
          } else if (_protectFromEmpty(path) &&
              await captured.file.length() == 0 &&
              (localStat.size ?? 0) > 0) {
            await captured.file.delete();
            action = SyncAction.upload;
            uploadedRemoteEtag = await _uploadStorage(
              path,
              vault.storage,
              localHash: localHash!,
              remote: remoteFile,
            );
            uploadedRemoteTime = DateTime.now().toUtc();
            up++;
            repaired++;
            reason = 'remote-empty-repaired';
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
            conflict++;
            reason = prev == null ? 'first-sync-different' : 'both-changed';
          }
        } else if (prev != null && !localExists && remoteExists) {
          if (remoteChanged || loadedState.recovered) {
            action = SyncAction.conflict;
            await _storeConflict(
              vault,
              path,
              localExists: false,
              remoteExists: true,
              remoteFile: remoteFile,
            );
            conflict++;
            reason = 'local-delete-remote-edit';
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
              conflict++;
              reason = 'remote-changed-during-delete';
            }
          }
        } else if (!localExists && !remoteExists) {
          syncState.remove(path);
          skip++;
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
          );
          observedRemoteEtag = download.etag;
          if (download.protected) {
            action = SyncAction.upload;
            uploadedRemoteEtag = await _uploadStorage(
              path,
              vault.storage,
              localHash: localHash!,
              remote: remoteFile,
            );
            uploadedRemoteTime = DateTime.now().toUtc();
            up++;
            repaired++;
            reason = 'remote-empty-repaired';
          } else {
            down++;
            reason = localExists ? 'remote-newer' : 'local-missing';
          }
        } else if ((localExists && !remoteExists) ||
            (localChanged && !remoteChanged)) {
          action = SyncAction.upload;
          try {
            uploadedRemoteEtag = await _uploadStorage(
              path,
              vault.storage,
              localHash: localHash!,
              remote: remoteFile,
            );
            uploadedRemoteTime = DateTime.now().toUtc();
            up++;
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
            conflict++;
            reason = 'remote-changed-during-upload';
          }
        } else {
          skip++;
          reason = 'no-change';
        }
        // Only a download changes the local file; everything else can reuse the
        // stat and hash captured above instead of re-reading over SAF.
        final downloaded = action == SyncAction.download;
        final nextLocal = downloaded
            ? await vault.storage.stat(path)
            : localStat;
        final nextLocalExists = downloaded ? nextLocal != null : localExists;
        final nextRemote = uploadedRemoteTime ?? remoteTime;
        if (action != SyncAction.conflict) {
          final nextRemoteExists =
              action != SyncAction.deleteRemote &&
              (remoteExists || action == SyncAction.upload);
          if (nextLocalExists && nextRemoteExists) {
            syncState[path] = SyncCursor(
              localMillis: nextLocal?.modified?.millisecondsSinceEpoch,
              localSize: nextLocal?.size,
              remoteMillis: nextRemote?.millisecondsSinceEpoch,
              localSha256: downloaded
                  ? await vault.storage.hash(path)
                  : localHash,
              remoteEtag: _normEtag(
                uploadedRemoteEtag ?? observedRemoteEtag ?? remoteFile?.etag,
              ),
            );
          } else if (!nextLocalExists && !nextRemoteExists) {
            syncState.remove(path);
          }
        }
        decisions.add(
          SyncDecision(
            path: path,
            action: action,
            reason: reason,
            localMillis: nextLocal?.modified?.millisecondsSinceEpoch,
            remoteMillis: nextRemote?.millisecondsSinceEpoch,
          ),
        );
      }

      progress('save-local-state');
      await _saveSyncState(vault, syncState);
      traceEvents.add({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'runId': runId,
        'event': 'completed',
        'trigger': trigger,
        'uploaded': up,
        'downloaded': down,
        'skipped': skip,
        'conflicts': conflict,
        'repaired': repaired,
        'deletedLocal': deletedLocal,
        'deletedRemote': deletedRemote,
        'remoteCount': remoteCount,
        'decisions': decisions.map((decision) => decision.toJson()).toList(),
      });
      return SyncResult(
        trigger: trigger,
        uploaded: up,
        downloaded: down,
        skipped: skip,
        conflicts: conflict,
        remoteCount: remoteCount,
        repaired: repaired,
        deletedLocal: deletedLocal,
        deletedRemote: deletedRemote,
      );
    } catch (error) {
      traceEvents.add({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'runId': runId,
        'event': 'failed',
        'trigger': trigger,
        'stage': stage,
        'path': ?currentPath,
        'errorType': error.runtimeType.toString(),
        'errorMessage': _safeErrorMessage(error),
        'uploaded': up,
        'downloaded': down,
        'skipped': skip,
        'conflicts': conflict,
        'repaired': repaired,
        'deletedLocal': deletedLocal,
        'deletedRemote': deletedRemote,
        'remoteCount': remoteCount,
        'decisions': decisions.map((decision) => decision.toJson()).toList(),
      });
      rethrow;
    } finally {
      await _trace(vault, traceEvents);
      onProgress?.call('idle', null);
      _client.close(force: true);
    }
  }

  Future<void> resolveConflict(
    Vault vault,
    SyncConflict conflict,
    SyncConflictResolution resolution, {
    String? mergedText,
  }) async {
    try {
      final remote = await _remoteFiles();
      final currentRemote = remote[conflict.path];
      if (conflict.remoteExists != (currentRemote != null) ||
          conflict.remoteEtag != null &&
              _normEtag(currentRemote?.etag) !=
                  _normEtag(conflict.remoteEtag)) {
        throw StateError(
          'Nextcloud changed again; run sync and review the new conflict',
        );
      }

      String? remoteEtag;
      if (resolution == SyncConflictResolution.keepRemote) {
        if (conflict.remoteExists) {
          await vault.storage.writeBytes(
            conflict.path,
            await vault.storage.readBytes(conflict.remoteSnapshot!),
          );
          remoteEtag = currentRemote?.etag;
        } else {
          await vault.storage.delete(conflict.path);
        }
      } else {
        if (resolution == SyncConflictResolution.merge) {
          if (mergedText == null || mergedText.trim().isEmpty) {
            throw ArgumentError('Merged text cannot be empty');
          }
          await vault.storage.writeText(conflict.path, mergedText);
        } else if (conflict.localExists) {
          await vault.storage.writeBytes(
            conflict.path,
            await vault.storage.readBytes(conflict.localSnapshot!),
          );
        }
        if (await vault.storage.exists(conflict.path)) {
          remoteEtag = await _uploadStorage(
            conflict.path,
            vault.storage,
            localHash: await vault.storage.hash(conflict.path),
            remote: currentRemote,
          );
        } else if (currentRemote != null) {
          await _deleteRemote(conflict.path, currentRemote.etag);
        }
      }

      final state = await _loadSyncState(vault);
      final localExists = await vault.storage.exists(conflict.path);
      final remoteExists = resolution == SyncConflictResolution.keepRemote
          ? conflict.remoteExists
          : localExists;
      if (localExists && remoteExists) {
        final local = await vault.storage.stat(conflict.path);
        state.cursors[conflict.path] = SyncCursor(
          localMillis: local?.modified?.millisecondsSinceEpoch,
          remoteMillis: currentRemote?.modified.millisecondsSinceEpoch,
          localSha256: await vault.storage.hash(conflict.path),
          remoteEtag: _normEtag(remoteEtag ?? currentRemote?.etag),
        );
      } else {
        state.cursors.remove(conflict.path);
      }
      await _saveSyncState(vault, state.cursors);
      for (final snapshot in [
        conflict.localSnapshot,
        conflict.remoteSnapshot,
        conflict.recordPath,
      ]) {
        if (snapshot != null) await vault.storage.delete(snapshot);
      }
    } finally {
      _client.close(force: true);
    }
  }

  Future<Map<String, VaultStorageEntry>> _localFiles(
    VaultStorage storage,
  ) async {
    final out = <String, VaultStorageEntry>{};
    for (final entity in await storage.list(recursive: true)) {
      if (entity.isDirectory || entity.path.endsWith('.tmp')) continue;
      if (_isSyncInternal(entity.path)) continue;
      out[entity.path] = entity;
    }
    return out;
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

  Future<Map<String, _RemoteFile>> _remoteFiles() async {
    final request = await _open('PROPFIND', config.rootUri);
    request.headers.set('Depth', 'infinity');
    request.write(
      '''<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getlastmodified/><d:getetag/><d:getcontentlength/></d:prop></d:propfind>''',
    );
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(propfindBodyTimeout);
    if (response.statusCode != 207) {
      throw HttpException('PROPFIND unexpected status ${response.statusCode}');
    }
    if (!RegExp(r'<[^:>]*:?multistatus\b').hasMatch(body)) {
      throw const HttpException('PROPFIND invalid multistatus response');
    }

    final files = <String, _RemoteFile>{};
    for (final match in RegExp(
      r'<[^:>]*:?response[^>]*>(.*?)</[^:>]*:?response>',
      dotAll: true,
    ).allMatches(body)) {
      final block = match.group(1)!;
      try {
        final hrefValue = _xmlValue(block, 'href');
        if (hrefValue == null) {
          throw const FormatException('missing href');
        }
        final href = Uri.decodeComponent(hrefValue);
        if (href.endsWith('/')) continue;
        final modifiedValue = _xmlValue(block, 'getlastmodified');
        if (modifiedValue == null) {
          throw const FormatException('missing getlastmodified');
        }
        final path = _relativeRemotePath(href);
        if (path == null) {
          throw const FormatException('path is outside configured folder');
        }
        final lengthValue = _xmlValue(block, 'getcontentlength');
        final length = lengthValue == null ? null : int.tryParse(lengthValue);
        if (lengthValue != null && length == null) {
          throw const FormatException('invalid getcontentlength');
        }
        if (!_isSyncInternal(path)) {
          files[path] = _RemoteFile(
            modified: HttpDate.parse(modifiedValue),
            etag: _xmlValue(block, 'getetag'),
            length: length,
          );
        }
      } catch (error) {
        if (error is! FormatException && error is! HttpException) rethrow;
        final message = error is FormatException
            ? error.message
            : (error as HttpException).message;
        throw HttpException('PROPFIND invalid file metadata: $message');
      }
    }
    return files;
  }

  String? _relativeRemotePath(String href) {
    final root = config.rootUri.path;
    final start = href.indexOf(root);
    if (start < 0) return null;
    final path = href.substring(start + root.length);
    return path.isEmpty ? null : path;
  }

  // Nextcloud quotes the etag in PROPFIND (getetag) but not in the PUT `oc-etag`
  // header, so a stored upload etag never string-matches the next PROPFIND and
  // every upload looks like a remote change → spurious download (ping-pong).
  // Canonicalize (drop surrounding quotes and a weak `W/` prefix) for compares
  // and cursor storage; the raw etag is still sent verbatim in If-Match.
  static String? _normEtag(String? etag) {
    if (etag == null) return null;
    var value = etag.trim();
    if (value.toLowerCase().startsWith('w/')) value = value.substring(2);
    return value.replaceAll('"', '');
  }

  Future<String?> _upload(
    String path,
    File file, {
    required String localHash,
    required _RemoteFile? remote,
  }) async {
    await _ensureParents(path);
    final request = await _open('PUT', _remoteUri(path));
    request.contentLength = await file.length();
    request.headers.set('X-Hash', 'sha256');
    if (remote?.etag != null) {
      request.headers.set(HttpHeaders.ifMatchHeader, remote!.etag!);
    } else if (remote == null) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, '*');
    }
    // ponytail: flat 5-minute cap per file transfer; chunked/resumable uploads if
    // large attachments start hitting this.
    await request.addStream(file.openRead()).timeout(const Duration(minutes: 5));
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode == HttpStatus.preconditionFailed) {
      throw const _RemoteChanged();
    }
    if (response.statusCode >= 400) {
      throw HttpException('PUT $path ${response.statusCode}');
    }
    final remoteHash = response.headers.value('x-hash-sha256');
    if (remoteHash != null && remoteHash.toLowerCase() != localHash) {
      throw HttpException('PUT $path checksum mismatch');
    }
    return response.headers.value('oc-etag') ??
        response.headers.value(HttpHeaders.etagHeader);
  }

  Future<String?> _uploadStorage(
    String path,
    VaultStorage storage, {
    required String localHash,
    required _RemoteFile? remote,
  }) async {
    final file = await storage.materialize(path);
    try {
      return await _upload(path, file, localHash: localHash, remote: remote);
    } finally {
      if (storage.materializedFilesAreTemporary && await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<_DownloadResult> _download(
    String path,
    File file, {
    bool protectNonEmpty = false,
  }) async {
    final tmp = File(
      '${file.path}.download-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final request = await _open('GET', _remoteUri(path));
    request.headers.set('X-Hash', 'sha256');
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode >= 400) {
      throw HttpException('GET $path ${response.statusCode}');
    }
    final etag =
        response.headers.value(HttpHeaders.etagHeader) ??
        response.headers.value('oc-etag');
    try {
      await response.pipe(tmp.openWrite()).timeout(const Duration(minutes: 5));
      // A truncated body (dropped connection, chunked short read) must never
      // be committed as the local note.
      final declaredLength = response.headers.contentLength;
      if (declaredLength >= 0 && await tmp.length() != declaredLength) {
        throw HttpException('GET $path truncated body');
      }
      final remoteHash = response.headers.value('x-hash-sha256');
      if (remoteHash != null &&
          remoteHash.toLowerCase() != await _sha256(tmp)) {
        throw HttpException('GET $path checksum mismatch');
      }
      if (protectNonEmpty &&
          _protectFromEmpty(path) &&
          await file.exists() &&
          await file.length() > 0 &&
          await tmp.length() == 0) {
        await tmp.delete();
        return _DownloadResult(protected: true, etag: etag);
      }
      await tmp.rename(file.path);
      return _DownloadResult(protected: false, etag: etag);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  Future<_DownloadResult> _downloadStorage(
    String path,
    VaultStorage storage, {
    bool protectNonEmpty = false,
  }) async {
    final temporary = await File(
      '${Directory.systemTemp.path}/tylog-${DateTime.now().microsecondsSinceEpoch}.tmp',
    ).create();
    try {
      final result = await _download(path, temporary);
      if (protectNonEmpty &&
          _protectFromEmpty(path) &&
          await storage.exists(path) &&
          (await storage.stat(path))!.size! > 0 &&
          await temporary.length() == 0) {
        return _DownloadResult(protected: true, etag: result.etag);
      }
      _requireLocalReplacementAllowed(path);
      await storage.importFile(path, temporary);
      return result;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  void _requireLocalReplacementAllowed(String path) {
    if (canReplaceLocal?.call(path) == false) {
      throw const SyncDeferred();
    }
  }

  Future<({File file, String? etag})> _captureRemote(String path) async {
    final file = await File(
      '${Directory.systemTemp.path}/tylog-conflict-${DateTime.now().microsecondsSinceEpoch}.tmp',
    ).create();
    final result = await _download(path, file);
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
        await vault.storage.importFile('$base.remote', temporary);
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
        'remoteEtag': _normEtag(observedRemoteEtag ?? remoteFile?.etag),
        if (localExists) 'localSnapshot': '$base.local',
        if (remoteExists) 'remoteSnapshot': '$base.remote',
      }),
    );
  }

  Future<int> _cleanResolvedConflictCopies(Vault vault) async {
    var cleaned = 0;
    for (final entity in await vault.storage.list(recursive: true)) {
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
              _protectFromEmpty(vault.relativePath(original)) &&
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

  Future<void> _ensureParents(String path) async {
    final parts = path.split('/')..removeLast();
    var uri = config.rootUri;
    for (final part in parts) {
      uri = uri.resolve('$part/');
      await _mkcol(uri);
    }
  }

  Future<void> _ensureConfiguredFolder() async {
    if (config.usesDirectWebDavUrl) {
      await _mkcol(config.rootUri);
      return;
    }
    var uri = config.filesUri;
    for (final folder in config._remoteFolders) {
      uri = uri.resolve('${Uri.encodeComponent(folder)}/');
      await _mkcol(uri);
    }
  }

  Uri _remoteUri(String path) =>
      config.rootUri.resolveUri(Uri(pathSegments: path.split('/')));

  Future<void> _mkcol(Uri uri) async {
    final response = await (await _open(
      'MKCOL',
      uri,
    )).close().timeout(const Duration(seconds: 20));
    if (response.statusCode >= 400 && response.statusCode != 405) {
      throw HttpException('MKCOL ${response.statusCode}');
    }
  }

  Future<void> _deleteRemote(String path, String? etag) async {
    final request = await _open('DELETE', _remoteUri(path));
    if (etag != null) request.headers.set(HttpHeaders.ifMatchHeader, etag);
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode == HttpStatus.preconditionFailed) {
      throw const _RemoteChanged();
    }
    if (response.statusCode >= 400 &&
        response.statusCode != HttpStatus.notFound) {
      throw HttpException('DELETE $path ${response.statusCode}');
    }
  }

  Future<HttpClientRequest> _open(String method, Uri uri) async {
    final request = await _client.openUrl(method, uri);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'TyLog WebDAV sync');
    return request;
  }

  bool _isChanged(DateTime? now, int? previousMillis) {
    if (now == null) return false;
    if (previousMillis == null) return true;
    return now.millisecondsSinceEpoch > previousMillis;
  }

  bool _isSyncInternal(String path) =>
      isSyncInternalPath(path) || !isSyncableVaultPath(path);

  Future<({Map<String, SyncCursor> cursors, bool recovered})> _loadSyncState(
    Vault vault,
  ) async {
    const path = '.tylog/sync_state.json';
    if (!await vault.storage.exists(path)) {
      return (cursors: <String, SyncCursor>{}, recovered: false);
    }
    final source = await vault.storage.readText(path);
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map || decoded['cursors'] is! Map) {
        throw const FormatException('sync state requires a cursors map');
      }
      final cursors = <String, SyncCursor>{};
      for (final entry in (decoded['cursors'] as Map).entries) {
        if (entry.key is! String || entry.value is! Map) {
          throw const FormatException('sync cursor must be a map');
        }
        final cursor = (entry.value as Map).cast<String, Object?>();
        if (!_validSyncCursor(cursor)) {
          throw const FormatException('sync cursor has invalid fields');
        }
        cursors[entry.key as String] = SyncCursor.fromJson(cursor);
      }
      return (cursors: cursors, recovered: false);
    } catch (error) {
      if (error is! FormatException && error is! TypeError) rethrow;
      final modified =
          (await vault.storage.stat(path))?.modified?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;
      final archive = '.tylog/sync_state.corrupt-$modified.json';
      if (!await vault.storage.exists(archive)) {
        await vault.storage.writeText(archive, source);
      }
      return (cursors: <String, SyncCursor>{}, recovered: true);
    }
  }

  Future<void> _saveSyncState(
    Vault vault,
    Map<String, SyncCursor> state,
  ) async {
    await vault.storage.writeText(
      '.tylog/sync_state.json',
      const JsonEncoder.withIndent('  ').convert({
        'cursors': {for (final e in state.entries) e.key: e.value.toJson()},
      }),
    );
  }

  Future<void> _trace(Vault vault, List<Map<String, Object?>> events) async {
    try {
      await _appendTrace(vault, events);
    } catch (_) {
      // Diagnostics must never stop file synchronization.
    }
  }

  Future<void> _appendTrace(
    Vault vault,
    List<Map<String, Object?>> events,
  ) async {
    if (events.isEmpty) return;
    const path = '.tylog/sync_trace.jsonl';
    var bytes = await vault.storage.exists(path)
        ? await vault.storage.readBytes(path)
        : <int>[];
    if (bytes.length > 512 * 1024) {
      var start = bytes.length - 256 * 1024;
      while (start < bytes.length && bytes[start] != 10) {
        start++;
      }
      bytes = bytes.sublist(start < bytes.length ? start + 1 : bytes.length);
    }
    await vault.storage.writeBytes(path, [
      ...bytes,
      for (final event in events) ...utf8.encode('${jsonEncode(event)}\n'),
    ]);
  }
}

bool _validSyncCursor(Map<String, Object?> json) =>
    (json['localMillis'] == null || json['localMillis'] is num) &&
    (json['localSize'] == null || json['localSize'] is num) &&
    (json['remoteMillis'] == null || json['remoteMillis'] is num) &&
    (json['localSha256'] == null || json['localSha256'] is String) &&
    (json['remoteEtag'] == null || json['remoteEtag'] is String);

/// A benign abort: the user started editing the file mid-sync, so the sync
/// backs off instead of replacing local content. Callers should re-queue,
/// not surface an error.
class SyncDeferred implements Exception {
  const SyncDeferred();

  @override
  String toString() => 'Local edit started during sync; retry after autosave';
}

String _safeErrorMessage(Object error) => switch (error) {
  SyncDeferred() => error.toString(),
  HttpException() => error.message,
  FileSystemException() => error.message,
  FormatException() => error.message,
  SocketException() => error.message,
  StateError() => error.message.toString(),
  _ => error.runtimeType.toString(),
};

bool _protectFromEmpty(String path) =>
    path.endsWith('.typ') || path == '_system/bibliography.yml';

Future<String> _sha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

String? _xmlValue(String xml, String name) {
  final match = RegExp(
    '<[^:>]*:?$name[^>]*>(.*?)</[^:>]*:?$name>',
    dotAll: true,
  ).firstMatch(xml);
  return match
      ?.group(1)
      ?.replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .trim();
}

class _RemoteFile {
  const _RemoteFile({required this.modified, this.etag, this.length});

  final DateTime modified;
  final String? etag;
  final int? length;
}

class _DownloadResult {
  const _DownloadResult({required this.protected, this.etag});

  final bool protected;
  final String? etag;
}

class _RemoteChanged implements Exception {
  const _RemoteChanged();
}

bool isSyncInternalPath(String path) =>
    path.startsWith('.tylog/') ||
    path.startsWith('_index/') ||
    path.contains('.remote-conflict-') ||
    path.endsWith('.tmp') ||
    isSafBackupPath(path);

// Orphan of an interrupted SAF atomic replace: `.<name>.tylog-<nanos>.backup`.
bool isSafBackupPath(String path) {
  final name = path.split('/').last;
  return name.startsWith('.') &&
      name.endsWith('.backup') &&
      name.contains('.tylog-');
}

bool isSyncableVaultPath(String path) => const [
  'daily/',
  'notes/',
  'projects/',
  'articles/',
  'assets/',
  'outputs/',
  '_system/',
].any((prefix) => path.startsWith(prefix));

bool isNextcloudManagedVault(
  Directory vault, {
  Map<String, String>? environment,
  bool? desktop,
}) {
  if (!(desktop ?? (Platform.isMacOS || Platform.isLinux))) return false;
  final home = (environment ?? Platform.environment)['HOME'];
  if (home == null) return false;
  final path = vault.absolute.path;
  return path == '$home/Nextcloud' ||
      path.startsWith('$home/Nextcloud${Platform.pathSeparator}') ||
      (path.startsWith('$home/Library/CloudStorage${Platform.pathSeparator}') &&
          path
              .substring('$home/Library/CloudStorage/'.length)
              .split(Platform.pathSeparator)
              .first
              .toLowerCase()
              .contains('nextcloud'));
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.path,
    required this.recordPath,
    required this.createdAt,
    required this.localExists,
    required this.remoteExists,
    this.localSnapshot,
    this.remoteSnapshot,
    this.localModified,
    this.remoteModified,
    this.remoteEtag,
  });

  final String id;
  final String path;
  final String recordPath;
  final DateTime createdAt;
  final bool localExists;
  final bool remoteExists;
  final String? localSnapshot;
  final String? remoteSnapshot;
  final DateTime? localModified;
  final DateTime? remoteModified;
  final String? remoteEtag;

  bool get isText => const {
    '.typ',
    '.yml',
    '.yaml',
    '.json',
    '.txt',
    '.md',
    '.csv',
  }.any(path.toLowerCase().endsWith);
}

Future<List<SyncConflict>> loadSyncConflicts(Vault vault) async {
  final conflicts = <SyncConflict>[];
  for (final entry in await vault.storage.list(path: '.tylog/conflicts')) {
    if (entry.isDirectory || !entry.path.endsWith('.json')) continue;
    try {
      final json = (jsonDecode(await vault.storage.readText(entry.path)) as Map)
          .cast<String, Object?>();
      conflicts.add(
        SyncConflict(
          id: json['id']! as String,
          path: json['path']! as String,
          recordPath: entry.path,
          createdAt: DateTime.parse(json['createdAt']! as String),
          localExists: json['localExists']! as bool,
          remoteExists: json['remoteExists']! as bool,
          localSnapshot: json['localSnapshot'] as String?,
          remoteSnapshot: json['remoteSnapshot'] as String?,
          localModified: json['localModified'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (json['localModified'] as num).toInt(),
                ),
          remoteModified: json['remoteModified'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (json['remoteModified'] as num).toInt(),
                ),
          remoteEtag: json['remoteEtag'] as String?,
        ),
      );
    } catch (_) {
      // A damaged record remains in diagnostics but cannot block every sync.
    }
  }
  conflicts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return conflicts;
}

Future<void> createSyncConflict(
  Vault vault,
  String path, {
  required List<int> localBytes,
  required List<int>? remoteBytes,
}) async {
  final id = sha256
      .convert(utf8.encode('$path:${DateTime.now().microsecondsSinceEpoch}'))
      .toString()
      .substring(0, 20);
  final base = '.tylog/conflicts/$id';
  await vault.storage.writeBytes('$base.local', localBytes);
  if (remoteBytes != null) {
    await vault.storage.writeBytes('$base.remote', remoteBytes);
  }
  await vault.storage.writeText(
    '$base.json',
    jsonEncode({
      'id': id,
      'path': path,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'localExists': true,
      'remoteExists': remoteBytes != null,
      'localSnapshot': '$base.local',
      if (remoteBytes != null) 'remoteSnapshot': '$base.remote',
    }),
  );
}

enum SyncConflictResolution { keepLocal, keepRemote, merge }

enum SyncAction { upload, download, deleteLocal, deleteRemote, skip, conflict }

class SyncResult {
  const SyncResult({
    required this.trigger,
    required this.uploaded,
    required this.downloaded,
    required this.skipped,
    required this.conflicts,
    required this.remoteCount,
    this.repaired = 0,
    this.deletedLocal = 0,
    this.deletedRemote = 0,
  });

  final String trigger;
  final int uploaded;
  final int downloaded;
  final int skipped;
  final int conflicts;
  final int remoteCount;
  final int repaired;
  final int deletedLocal;
  final int deletedRemote;

  @override
  String toString() =>
      'Sync($trigger): ↑$uploaded ↓$downloaded =$skipped !$conflicts, remote $remoteCount';
}

SyncAction decideSyncAction({
  required bool localExists,
  required bool remoteExists,
  required bool localChanged,
  required bool remoteChanged,
  bool hasSyncCursor = true,
  int? localMillis,
  int? remoteMillis,
}) {
  if (localExists && !remoteExists) return SyncAction.upload;
  if (!localExists && remoteExists) return SyncAction.download;
  if (!localExists && !remoteExists) return SyncAction.skip;
  if (localChanged && remoteChanged) {
    if (!hasSyncCursor && localMillis != null && remoteMillis != null) {
      if (localMillis > remoteMillis) return SyncAction.upload;
      if (remoteMillis > localMillis) return SyncAction.download;
    }
    return SyncAction.conflict;
  }
  if (remoteChanged) return SyncAction.download;
  if (localChanged) return SyncAction.upload;
  return SyncAction.skip;
}

class SyncCursor {
  const SyncCursor({
    this.localMillis,
    this.localSize,
    this.remoteMillis,
    this.localSha256,
    this.remoteEtag,
  });

  final int? localMillis;
  final int? localSize;
  final int? remoteMillis;
  final String? localSha256;
  final String? remoteEtag;

  factory SyncCursor.fromJson(Map<String, Object?> json) => SyncCursor(
    localMillis: (json['localMillis'] as num?)?.toInt(),
    localSize: (json['localSize'] as num?)?.toInt(),
    remoteMillis: (json['remoteMillis'] as num?)?.toInt(),
    localSha256: json['localSha256'] as String?,
    remoteEtag: json['remoteEtag'] as String?,
  );

  Map<String, Object?> toJson() => {
    'localMillis': localMillis,
    if (localSize != null) 'localSize': localSize,
    'remoteMillis': remoteMillis,
    if (localSha256 != null) 'localSha256': localSha256,
    if (remoteEtag != null) 'remoteEtag': remoteEtag,
  };
}

class SyncDecision {
  const SyncDecision({
    required this.path,
    required this.action,
    required this.reason,
    this.localMillis,
    this.remoteMillis,
  });

  final String path;
  final SyncAction action;
  final String reason;
  final int? localMillis;
  final int? remoteMillis;

  Map<String, Object?> toJson() => {
    'path': path,
    'action': action.name,
    'reason': reason,
    'localMillis': localMillis,
    'remoteMillis': remoteMillis,
  };
}

class SyncTrace {
  const SyncTrace({
    required this.timestamp,
    required this.trigger,
    required this.uploaded,
    required this.downloaded,
    required this.skipped,
    required this.conflicts,
    required this.remoteCount,
    required this.decisions,
  });

  final String timestamp;
  final String trigger;
  final int uploaded;
  final int downloaded;
  final int skipped;
  final int conflicts;
  final int remoteCount;
  final List<SyncDecision> decisions;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp,
    'trigger': trigger,
    'uploaded': uploaded,
    'downloaded': downloaded,
    'skipped': skipped,
    'conflicts': conflicts,
    'remoteCount': remoteCount,
    'decisions': decisions.map((d) => d.toJson()).toList(),
  };
}
