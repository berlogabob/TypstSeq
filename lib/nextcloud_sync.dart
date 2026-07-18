import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
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

enum RemoteVaultKind { missing, empty, validVault, nonVault }

enum InitialSyncMode { uploadLocal, downloadRemote, safeMerge }

InitialSyncMode initialSyncModeFor({
  required bool localHasData,
  required bool remoteHasData,
}) => localHasData && !remoteHasData
    ? InitialSyncMode.uploadLocal
    : !localHasData && remoteHasData
    ? InitialSyncMode.downloadRemote
    : InitialSyncMode.safeMerge;

class RemoteVaultInspection {
  const RemoteVaultInspection(
    this.kind, {
    this.fileCount = 0,
    this.userFileCount = 0,
  });

  final RemoteVaultKind kind;
  final int fileCount;
  final int userFileCount;
}

class LocalSyncInspection {
  const LocalSyncInspection({
    required this.userFileCount,
    required this.pristineStarterPaths,
  });

  final int userFileCount;
  final List<String> pristineStarterPaths;

  bool get hasUserContent => userFileCount > 0;
}

Future<LocalSyncInspection> inspectLocalSync(Vault vault) async {
  var userFiles = 0;
  final pristine = <String>[];
  for (final entry in await vault.storage.list(recursive: true)) {
    if (entry.isDirectory || !isSyncableVaultPath(entry.path)) continue;
    if (entry.path.startsWith('_system/')) continue;
    if (entry.path.startsWith('daily/') && entry.path.endsWith('.typ')) {
      final source = await vault.storage.readText(entry.path);
      if (isPristineStarterNote(entry.path, source)) {
        pristine.add(entry.path);
        continue;
      }
    }
    userFiles++;
  }
  pristine.sort();
  return LocalSyncInspection(
    userFileCount: userFiles,
    pristineStarterPaths: pristine,
  );
}

/// A poll is skippable only when both collection etags are known and match,
/// and the caller knows there are no unsaved local edits.
bool canSkipPoll({
  required bool dirty,
  required String? lastEtag,
  required String? currentEtag,
}) {
  if (dirty) return false;
  final previous = NextcloudSync._normEtag(lastEtag);
  final current = NextcloudSync._normEtag(currentEtag);
  return previous != null &&
      previous.isNotEmpty &&
      current != null &&
      current.isNotEmpty &&
      previous == current;
}

class NextcloudSync {
  NextcloudSync(this.config, {this.onProgress, this.canReplaceLocal});

  final NextcloudConfig config;
  final void Function(String stage, String? path)? onProgress;
  final bool Function(String path)? canReplaceLocal;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final _ensuredParents = <String>{};

  static Duration propfindBodyTimeout = const Duration(seconds: 60);
  static List<Duration> connectionRetryDelays = const [
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  /// Cheap, conservative preflight for a background poll. Uncertain remote
  /// state or any local cursor mismatch falls through to a full sync.
  Future<bool> pollIsUnchanged(Vault vault, {required bool dirty}) async {
    try {
      if (dirty) return false;
      final state = await _loadSyncState(vault);
      if (state.recovered ||
          state.remoteMismatch ||
          state.rootEtag == null ||
          (await loadSyncConflicts(vault)).isNotEmpty) {
        return false;
      }
      final currentEtag = await _retryTransient(_rootEtag);
      if (!canSkipPoll(
        dirty: dirty,
        lastEtag: state.rootEtag,
        currentEtag: currentEtag,
      )) {
        return false;
      }
      final local = await _localFiles(vault.storage);
      return _matchesLocalCursorSnapshot(local.syncable, state.cursors);
    } catch (_) {
      return false;
    } finally {
      _client.close(force: true);
    }
  }

  Future<RemoteVaultInspection> inspectRemoteVault() async {
    try {
      final result = await _remoteFiles(
        allowMissing: true,
        includeNonSyncable: true,
      );
      if (result == null) {
        return const RemoteVaultInspection(RemoteVaultKind.missing);
      }
      final remote = result.files;
      if (remote.isEmpty) {
        return const RemoteVaultInspection(RemoteVaultKind.empty);
      }
      final userFiles = remote.keys
          .where(
            (path) => isSyncableVaultPath(path) && !path.startsWith('_system/'),
          )
          .length;
      return RemoteVaultInspection(
        remote.containsKey('_system/tylog.typ')
            ? RemoteVaultKind.validVault
            : RemoteVaultKind.nonVault,
        fileCount: remote.length,
        userFileCount: userFiles,
      );
    } finally {
      _client.close(force: true);
    }
  }

  Future<SyncResult> sync(
    Vault vault, {
    String trigger = 'manual',
    InitialSyncMode? initialMode,
  }) async {
    final runId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    var stage = 'start';
    String? currentPath;
    var up = 0;
    var down = 0;
    var skip = 0;
    var conflict = 0;
    var repaired = 0;
    var renamed = 0;
    var deletedLocal = 0;
    var deletedRemote = 0;
    var remoteCount = 0;
    var cursorsDirty = false;
    String? freshRootEtag;
    Map<String, SyncCursor>? syncState;
    _RemoteArchiveSnapshot? archiveSnapshot;
    var pristineStarterPaths = const <String>[];
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
      // The pre-loop stages need the same transient-error protection as the
      // per-file loop: a socket abort here otherwise kills every run at start.
      await _retryTransient(_ensureConfiguredFolder);
      progress('load-local-state');
      final loadedState = await _loadSyncState(vault);
      syncState = initialMode == null
          ? loadedState.cursors
          : <String, SyncCursor>{};
      final stateRecovered = initialMode == null && loadedState.recovered;
      if (loadedState.remoteMismatch) {
        traceEvents.add({
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'runId': runId,
          'event': 'state-reset-remote',
          'trigger': trigger,
        });
      }
      if (stateRecovered) {
        traceEvents.add({
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'runId': runId,
          'event': 'state-recovered',
          'trigger': trigger,
        });
      }
      // Fast path for a steady-state poll: the root collection's own etag
      // changes whenever anything beneath it changes (the mechanism real
      // Nextcloud clients rely on). If it still matches what the last full
      // run observed, and every local file is exactly where its cursor left
      // it, nothing at all changed and the Depth:infinity crawl, rename
      // detection, conflict-copy scan and per-path loop can all be skipped.
      // Any mismatch falls straight through to the full run below — this
      // must never be the thing that decides a local edit is safe to skip.
      if (initialMode == null &&
          !stateRecovered &&
          !loadedState.remoteMismatch &&
          loadedState.rootEtag != null) {
        progress('probe-root');
        final unresolvedForShortcut = await loadSyncConflicts(vault);
        if (unresolvedForShortcut.isEmpty) {
          final probedEtag = await _retryTransient(_rootEtag);
          if (canSkipPoll(
            dirty: false,
            lastEtag: loadedState.rootEtag,
            currentEtag: probedEtag,
          )) {
            progress('scan-local-shortcut');
            final localListing = await _localFiles(vault.storage);
            if (_matchesLocalCursorSnapshot(localListing.syncable, syncState)) {
              remoteCount = syncState.length;
              traceEvents.add({
                'timestamp': DateTime.now().toUtc().toIso8601String(),
                'runId': runId,
                'event': 'no-change-shortcut',
                'trigger': trigger,
                'uploaded': 0,
                'downloaded': 0,
                'skipped': 0,
                'conflicts': 0,
                'repaired': 0,
                'renamed': 0,
                'deletedLocal': 0,
                'deletedRemote': 0,
                'remoteCount': remoteCount,
              });
              return SyncResult(
                trigger: trigger,
                uploaded: 0,
                downloaded: 0,
                skipped: 0,
                conflicts: 0,
                remoteCount: remoteCount,
              );
            }
          }
        }
      }
      progress('list-remote');
      final remoteResult = (await _retryTransient(_remoteFiles))!;
      final remote = remoteResult.files;
      freshRootEtag = remoteResult.rootEtag;
      remoteCount = remote.length;
      final remoteUserCount = remote.keys
          .where((path) => !path.startsWith('_system/'))
          .length;
      if (initialMode == InitialSyncMode.uploadLocal &&
          (remoteUserCount > 0 ||
              remote.isNotEmpty && !remote.containsKey('_system/tylog.typ'))) {
        throw StateError(
          'The cloud folder changed and is no longer an empty TyLog vault.',
        );
      }
      if (initialMode == InitialSyncMode.downloadRemote &&
          (!remote.containsKey('_system/tylog.typ') || remoteUserCount == 0)) {
        throw StateError(
          'The cloud folder changed and is not a populated TyLog vault.',
        );
      }
      if (initialMode == InitialSyncMode.safeMerge &&
          remote.isNotEmpty &&
          !remote.containsKey('_system/tylog.typ')) {
        throw StateError('The cloud folder is not a TyLog vault.');
      }
      if (initialMode == InitialSyncMode.downloadRemote) {
        final local = await inspectLocalSync(vault);
        if (local.hasUserContent) {
          throw StateError('The local vault changed and is no longer empty.');
        }
        pristineStarterPaths = local.pristineStarterPaths;
      }
      progress('scan-local');
      final localListing = await _localFiles(vault.storage);
      final localEntries = localListing.syncable;
      repaired = await _cleanResolvedConflictCopies(vault, localListing.raw);
      if (syncState.isNotEmpty && remote.isNotEmpty && localEntries.isEmpty) {
        throw StateError(
          'Local vault listed no syncable files; refusing to propagate deletions.',
        );
      }
      progress('detect-renames');
      final renameDetection = await _detectRenames(
        vault,
        localEntries,
        remote,
        syncState,
        progress,
        rootEtag: freshRootEtag,
      );
      renamed = renameDetection.decisions.length;
      decisions.addAll(renameDetection.decisions);
      // ponytail: proportional guard against a flaky DocumentsProvider dropping
      // listing entries; threshold max(10, 25%), add a confirmation flow if it
      // ever fires on legitimate bulk deletes.
      final plannedDeletions = syncState.keys
          .where(
            (path) =>
                !localEntries.containsKey(path) && remote.containsKey(path),
          )
          .length;
      final deletionLimit = math.max(10, syncState.length ~/ 4);
      if (plannedDeletions > deletionLimit) {
        throw StateError(
          'Refusing to propagate $plannedDeletions deletions '
          '(limit $deletionLimit); local listing may be incomplete.',
        );
      }
      // Save the bootstrap/reset marker before the first transfer. A retry can
      // then resume even if Android kills the process before the first batch.
      // Only a genuine reset/bootstrap needs this write — a plain steady-state
      // run hasn't changed anything relative to what's already on disk.
      if (stateRecovered || loadedState.remoteMismatch || initialMode != null) {
        await _saveSyncState(vault, syncState, rootEtag: freshRootEtag);
      }
      if (_shouldUseArchive(
        initialMode: initialMode,
        stateRecovered: stateRecovered,
        local: localEntries,
        remote: remote,
        state: syncState,
      )) {
        try {
          archiveSnapshot = await _downloadArchive(remote, progress);
        } on IOException {
          archiveSnapshot = null; // fall back to per-file transfers
        } on TimeoutException {
          archiveSnapshot = null;
        }
      }
      if (archiveSnapshot != null) progress('extract-archive');
      for (final path in pristineStarterPaths) {
        await vault.storage.delete(path);
        localEntries.remove(path);
      }
      final unresolved = {
        for (final conflict in await loadSyncConflicts(vault))
          conflict.path: conflict,
      };
      final allPaths = <String>{
        ...localEntries.keys,
        ...remote.keys,
        ...syncState.keys,
      }.toList()..sort();
      final cursors = syncState;
      var completed = 0;
      var nextPath = 0;
      Object? firstError;
      StackTrace? firstStack;
      Future<void> checkpointTail = Future.value();
      Future<void> worker() async {
        while (firstError == null) {
          final index = nextPath++;
          if (index >= allPaths.length) return;
          final path = allPaths[index];
          progress('sync-file $completed/${allPaths.length}', path);
          try {
            // Android drops sockets mid-request (power save, network switch);
            // one blip must not abort a multi-minute run.
            final result = await _retryTransient(
              () => _syncPath(
                vault: vault,
                path: path,
                localStat: localEntries[path],
                remoteFile: remote[path],
                previous: cursors[path],
                stateRecovered: stateRecovered,
                initialMode: initialMode,
                unresolvedConflict: unresolved[path],
                possibleRename: renameDetection.protectedLocalDeletions
                    .contains(path),
                archive: archiveSnapshot,
              ),
            );
            if (result.updateCursor) {
              if (result.cursor == null) {
                if (cursors.remove(path) != null) cursorsDirty = true;
              } else {
                final previousCursor = cursors[path];
                cursors[path] = result.cursor!;
                if (_cursorNeedsPersist(previousCursor, result.cursor!)) {
                  cursorsDirty = true;
                }
              }
            }
            up += result.uploaded;
            down += result.downloaded;
            skip += result.skipped;
            conflict += result.conflicts;
            repaired += result.repaired;
            deletedRemote += result.deletedRemote;
            decisions.add(result.decision);
            completed++;
            progress('sync-file $completed/${allPaths.length}', path);
            if (completed % 10 == 0 && cursorsDirty) {
              final snapshot = Map<String, SyncCursor>.of(cursors);
              final write = checkpointTail.then(
                (_) => _saveSyncState(vault, snapshot, rootEtag: freshRootEtag),
              );
              checkpointTail = write.catchError((_) {});
              await write;
              cursorsDirty = false;
            }
          } catch (error, stack) {
            firstError ??= error;
            firstStack ??= stack;
          }
        }
      }

      await Future.wait(
        List.generate(
          math.min(archiveSnapshot == null ? 4 : 1, allPaths.length),
          (_) => worker(),
        ),
      );
      await checkpointTail;
      if (firstError != null) {
        Error.throwWithStackTrace(firstError!, firstStack!);
      }

      // Note: freshRootEtag reflects the remote as it was *before* this
      // run's own uploads/deletes/renames (it was captured by the same
      // Depth:infinity listing the per-path loop just used, before the
      // loop ran). A run that itself changes the remote is therefore one
      // run behind on enabling the shortcut — self-correcting, since the
      // *next* full run's own pre-loop listing will already reflect those
      // changes and persist an accurate etag if nothing further happens.
      progress('save-local-state');
      if (cursorsDirty || freshRootEtag != loadedState.rootEtag) {
        await _saveSyncState(vault, syncState, rootEtag: freshRootEtag);
      }
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
        'renamed': renamed,
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
        renamed: renamed,
        deletedLocal: deletedLocal,
        deletedRemote: deletedRemote,
      );
    } catch (error) {
      final checkpoint = syncState;
      if (checkpoint != null) {
        try {
          await _saveSyncState(vault, checkpoint, rootEtag: freshRootEtag);
        } catch (checkpointError) {
          traceEvents.add({
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'runId': runId,
            'event': 'checkpoint-failed',
            'errorType': checkpointError.runtimeType.toString(),
            'errorMessage': _safeErrorMessage(checkpointError),
          });
        }
      }
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
        'renamed': renamed,
        'deletedLocal': deletedLocal,
        'deletedRemote': deletedRemote,
        'remoteCount': remoteCount,
        'decisions': decisions.map((decision) => decision.toJson()).toList(),
      });
      rethrow;
    } finally {
      if (archiveSnapshot != null) await archiveSnapshot.close();
      await _trace(vault, traceEvents);
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
      // Self-heal (loadSyncConflicts) may have already deleted this record's
      // snapshot(s) on disk between when the UI loaded it and now — e.g. the
      // dashboard held a stale in-memory copy. There's nothing left to apply
      // in that case; treat it as already resolved instead of crashing on
      // the missing file.
      if (resolution == SyncConflictResolution.keepRemote &&
          conflict.remoteExists &&
          (conflict.remoteSnapshot == null ||
              !await vault.storage.exists(conflict.remoteSnapshot!))) {
        for (final snapshot in [
          conflict.localSnapshot,
          conflict.remoteSnapshot,
          conflict.recordPath,
        ]) {
          if (snapshot != null) await vault.storage.delete(snapshot);
        }
        return;
      }
      // A single-resource Depth:0 probe instead of a whole-tree PROPFIND —
      // resolving one conflict shouldn't cost a full remote crawl.
      final currentRemote = await _probeRemoteFile(conflict.path);
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
      await _saveSyncState(vault, state.cursors, rootEtag: state.rootEtag);
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
        throw HttpException('GET archive $status');
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
        if (_normEtag(entry.value.etag) != _normEtag(current.etag)) {
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
    required SyncConflict? unresolvedConflict,
    required bool possibleRename,
    required _RemoteArchiveSnapshot? archive,
  }) async {
    final localExists = localStat != null;
    final remoteExists = remoteFile != null;
    final remoteTime = remoteFile?.modified;
    Uint8List? localBytes;
    String? localHash;
    if (localExists) {
      final millis = localStat.modified?.millisecondsSinceEpoch;
      if (previous?.localSha256 != null &&
          millis != null &&
          millis == previous!.localMillis &&
          localStat.size != null &&
          localStat.size == previous.localSize) {
        localHash = previous.localSha256;
      } else {
        localBytes = await vault.storage.readBytes(path);
        localHash = sha256.convert(localBytes).toString();
      }
    }
    final localChanged = previous == null
        ? localExists
        : localHash != previous.localSha256;
    final remoteChanged = previous == null
        ? remoteExists
        : !remoteExists ||
              (previous.remoteEtag != null && remoteFile.etag != null
                  ? _normEtag(remoteFile.etag) != _normEtag(previous.remoteEtag)
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

    if (unresolvedConflict != null) {
      skipped++;
      reason = 'unresolved-conflict';
      // The stored etag is frozen at record time; the sync loop skips this
      // path forever otherwise, and resolveConflict's own guard throws
      // whenever the remote moves again — permanently, since nothing here
      // ever refreshed it. Catch up the record so the guard can pass once
      // the user reviews the current remote content.
      if (remoteFile != null &&
          _normEtag(remoteFile.etag) != _normEtag(unresolvedConflict.remoteEtag)) {
        await _refreshConflictRemote(vault, unresolvedConflict, remoteFile, archive);
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
            bytes: localBytes,
          );
          uploadedRemoteTime = DateTime.now().toUtc();
          uploaded++;
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
          conflicts++;
          reason = previous == null ? 'first-sync-different' : 'both-changed';
        }
      }
    } else if (previous != null && !localExists && remoteExists) {
      if (remoteChanged || stateRecovered || possibleRename) {
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
      if (download.protected) {
        action = SyncAction.upload;
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
    } else if ((localExists && !remoteExists) ||
        (localChanged && !remoteChanged)) {
      action = SyncAction.upload;
      try {
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
        final repairBytes = localBytes ?? await vault.storage.readBytes(path);
        final repairedEtag = await _uploadStorage(
          path,
          vault.storage,
          localHash: localHash,
          remote: remoteFile,
          bytes: repairBytes,
        );
        observedRemoteEtag = repairedEtag ?? observedRemoteEtag;
        repaired++;
        reason = 'checksum-repaired';
      } on _RemoteChanged {
        // Remote moved since PROPFIND; leave state as-is and let the next
        // sync pass re-evaluate whether a repair is still needed.
      }
    }

    final wasDownloaded = action == SyncAction.download;
    final nextLocal = wasDownloaded
        ? await vault.storage.stat(path)
        : localStat;
    final nextLocalExists = wasDownloaded ? nextLocal != null : localExists;
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
              ? await vault.storage.hash(path)
              : localHash,
          remoteEtag: _normEtag(
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
          _normEtag(entry.value.remoteEtag) == _normEtag(oldRemote.etag);
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
        remoteEtag: _normEtag(moved.etag),
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
          remoteEtag: _normEtag(remoteFile.etag),
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

  Future<({Map<String, _RemoteFile> files, String? rootEtag})?> _remoteFiles({
    bool allowMissing = false,
    bool includeNonSyncable = false,
  }) async {
    final request = await _open('PROPFIND', config.rootUri);
    request.headers.set('Depth', 'infinity');
    request.write(
      '''<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns"><d:prop><d:getlastmodified/><d:getetag/><d:getcontentlength/><oc:checksums/></d:prop></d:propfind>''',
    );
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(propfindBodyTimeout);
    if (allowMissing && response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != 207) {
      throw HttpException('PROPFIND unexpected status ${response.statusCode}');
    }
    if (!RegExp(r'<[^:>]*:?multistatus\b').hasMatch(body)) {
      throw const HttpException('PROPFIND invalid multistatus response');
    }

    final files = <String, _RemoteFile>{};
    // The root collection's own entry (href ends with '/') is included in a
    // Depth:infinity response alongside every file; its etag changes
    // whenever anything beneath it changes, which is what makes the
    // no-change shortcut in sync() safe to rely on.
    String? rootEtag;
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
        if (href.endsWith('/')) {
          if (rootEtag == null && _isRootHref(href)) {
            rootEtag = _xmlValue(block, 'getetag');
          }
          continue;
        }
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
        if (includeNonSyncable || !_isSyncInternal(path)) {
          final checksum = _xmlSha256Info(block);
          files[path] = _RemoteFile(
            modified: HttpDate.parse(modifiedValue),
            etag: _xmlValue(block, 'getetag'),
            length: length,
            sha256: checksum?.hash,
            sha256Lowercase: checksum?.lowercase ?? false,
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
    return (files: files, rootEtag: rootEtag);
  }

  bool _isRootHref(String href) {
    final root = config.rootUri.path;
    final normalizedRoot = root.endsWith('/')
        ? root.substring(0, root.length - 1)
        : root;
    final normalizedHref = href.endsWith('/')
        ? href.substring(0, href.length - 1)
        : href;
    return normalizedHref.endsWith(normalizedRoot);
  }

  /// Depth:0 probe of just the root collection's etag — the cheap
  /// "has anything at all changed" check used by the no-change shortcut in
  /// sync(), instead of a full Depth:infinity crawl. Only trusts a response
  /// whose href actually resolves to the root — a server that ignores Depth
  /// and always answers with some other resource must not produce a
  /// misleading match.
  Future<String?> _rootEtag() async {
    final request = await _open('PROPFIND', config.rootUri);
    request.headers.set('Depth', '0');
    request.write(
      '''<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getetag/></d:prop></d:propfind>''',
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
    for (final match in RegExp(
      r'<[^:>]*:?response[^>]*>(.*?)</[^:>]*:?response>',
      dotAll: true,
    ).allMatches(body)) {
      final block = match.group(1)!;
      final hrefValue = _xmlValue(block, 'href');
      if (hrefValue == null) continue;
      if (_isRootHref(Uri.decodeComponent(hrefValue))) {
        return _xmlValue(block, 'getetag');
      }
    }
    return null;
  }

  /// Single-resource Depth:0 probe used by resolveConflict — one request
  /// instead of a whole-tree PROPFIND to check one file's current etag.
  Future<_RemoteFile?> _probeRemoteFile(String path) async {
    final request = await _open('PROPFIND', _remoteUri(path));
    request.headers.set('Depth', '0');
    request.write(
      '''<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getlastmodified/><d:getetag/></d:prop></d:propfind>''',
    );
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(propfindBodyTimeout);
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != 207) {
      throw HttpException('PROPFIND unexpected status ${response.statusCode}');
    }
    if (!RegExp(r'<[^:>]*:?multistatus\b').hasMatch(body)) {
      throw const HttpException('PROPFIND invalid multistatus response');
    }
    String? block;
    for (final match in RegExp(
      r'<[^:>]*:?response[^>]*>(.*?)</[^:>]*:?response>',
      dotAll: true,
    ).allMatches(body)) {
      final candidate = match.group(1)!;
      final hrefValue = _xmlValue(candidate, 'href');
      if (hrefValue == null) continue;
      if (_relativeRemotePath(Uri.decodeComponent(hrefValue)) == path) {
        block = candidate;
        break;
      }
    }
    if (block == null) return null;
    final modifiedValue = _xmlValue(block, 'getlastmodified');
    if (modifiedValue == null) {
      throw const HttpException(
        'PROPFIND invalid file metadata: missing getlastmodified',
      );
    }
    return _RemoteFile(
      modified: HttpDate.parse(modifiedValue),
      etag: _xmlValue(block, 'getetag'),
    );
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
    List<int> bytes, {
    required String localHash,
    required _RemoteFile? remote,
  }) async {
    await _ensureParents(path);
    final request = await _open('PUT', _remoteUri(path));
    request.contentLength = bytes.length;
    request.headers.set('X-Hash', 'sha256');
    // Nextcloud Desktop's checksum types are case-sensitive (SHA256, not
    // sha256); a lowercase type makes it reject the file with "unknown
    // checksum type" and refuse to sync it at all.
    request.headers.set('OC-Checksum', 'SHA256:$localHash');
    if (remote?.etag != null) {
      request.headers.set(HttpHeaders.ifMatchHeader, remote!.etag!);
    } else if (remote == null) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, '*');
    }
    // ponytail: flat 5-minute cap per file transfer; chunked/resumable uploads if
    // large attachments start hitting this.
    request.add(bytes);
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
    List<int>? bytes,
  }) async {
    return _upload(
      path,
      bytes ?? await storage.readBytes(path),
      localHash: localHash,
      remote: remote,
    );
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
    _RemoteArchiveSnapshot? archive,
    _RemoteFile? remoteFile,
  }) async {
    if (archive != null && archive.contains(path)) {
      final bytes = archive.read(path);
      if (remoteFile?.length != null && bytes.length != remoteFile!.length) {
        throw HttpException('Archive $path size mismatch');
      }
      if (remoteFile?.sha256 != null &&
          sha256.convert(bytes).toString() != remoteFile!.sha256) {
        throw HttpException('Archive $path checksum mismatch');
      }
      if (protectNonEmpty &&
          _protectFromEmpty(path) &&
          await storage.exists(path) &&
          ((await storage.stat(path))?.size ?? 0) > 0 &&
          bytes.isEmpty) {
        return _DownloadResult(protected: true, etag: remoteFile?.etag);
      }
      _requireLocalReplacementAllowed(path);
      await storage.writeBytes(path, bytes);
      return _DownloadResult(protected: false, etag: remoteFile?.etag);
    }
    final temporary = await File(
      '${Directory.systemTemp.path}/tylog-${DateTime.now().microsecondsSinceEpoch}.tmp',
    ).create();
    try {
      final result = await _download(path, temporary);
      if (remoteFile?.sha256 != null &&
          await _sha256(temporary) != remoteFile!.sha256) {
        throw HttpException('GET $path checksum mismatch');
      }
      if (protectNonEmpty &&
          _protectFromEmpty(path) &&
          await storage.exists(path) &&
          (await storage.stat(path))!.size! > 0 &&
          await temporary.length() == 0) {
        return _DownloadResult(protected: true, etag: result.etag);
      }
      _requireLocalReplacementAllowed(path);
      await storage.writeBytes(path, await temporary.readAsBytes());
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
        'remoteEtag': _normEtag(observedRemoteEtag ?? remoteFile?.etag),
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
        'remoteEtag': _normEtag(captured.etag ?? remoteFile.etag),
        if (conflict.localSnapshot != null)
          'localSnapshot': conflict.localSnapshot,
        'remoteSnapshot': '$base.remote',
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

  Future<void> _ensureParents(String path) async {
    final parts = path.split('/')..removeLast();
    var uri = config.rootUri;
    for (final part in parts) {
      uri = uri.resolve('$part/');
      if (!_ensuredParents.add(uri.toString())) continue;
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
    await response.drain<void>();
    if (response.statusCode >= 400 && response.statusCode != 405) {
      throw HttpException('MKCOL ${response.statusCode}');
    }
  }

  Future<_RemoteFile> _moveRemote(
    String from,
    String to,
    _RemoteFile source,
  ) async {
    await _ensureParents(to);
    final request = await _open('MOVE', _remoteUri(from));
    request.headers.set('Destination', _remoteUri(to).toString());
    request.headers.set('Overwrite', 'F');
    if (source.etag != null) {
      request.headers.set(HttpHeaders.ifMatchHeader, source.etag!);
    }
    final response = await request.close().timeout(const Duration(seconds: 60));
    final etag =
        response.headers.value('oc-etag') ??
        response.headers.value(HttpHeaders.etagHeader) ??
        source.etag;
    final status = response.statusCode;
    await response.drain<void>();
    if (status == HttpStatus.preconditionFailed ||
        status == HttpStatus.conflict) {
      throw const _RemoteChanged();
    }
    if (status >= 400) throw HttpException('MOVE $from ${response.statusCode}');
    return _RemoteFile(
      modified: DateTime.now().toUtc(),
      etag: etag,
      length: source.length,
      sha256: source.sha256,
    );
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

  // ponytail: retries a whole path sync on any I/O error; a PUT whose success
  // response was lost re-runs into If-Match 412 and surfaces as a resolvable
  // conflict — per-request idempotency keys if that ever bites.
  Future<T> _retryTransient<T>(Future<T> Function() run) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await run();
      } on IOException {
        if (attempt >= connectionRetryDelays.length) rethrow;
      } on TimeoutException {
        if (attempt >= connectionRetryDelays.length) rethrow;
      }
      await Future<void>.delayed(connectionRetryDelays[attempt]);
    }
  }

  Future<HttpClientRequest> _open(String method, Uri uri) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final request = await _client.openUrl(method, uri);
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
        );
        request.headers.set(HttpHeaders.userAgentHeader, 'TyLog WebDAV sync');
        return request;
      } on SocketException {
        if (attempt >= connectionRetryDelays.length) rethrow;
      } on TimeoutException {
        if (attempt >= connectionRetryDelays.length) rethrow;
      }
      await Future<void>.delayed(connectionRetryDelays[attempt]);
    }
  }

  bool _isChanged(DateTime? now, int? previousMillis) {
    if (now == null) return false;
    if (previousMillis == null) return true;
    return now.millisecondsSinceEpoch > previousMillis;
  }

  bool _isSyncInternal(String path) =>
      isSyncInternalPath(path) || !isSyncableVaultPath(path);

  String get _remoteKey {
    final root = config.rootUri;
    final normalized = Uri(
      scheme: root.scheme.toLowerCase(),
      host: root.host.toLowerCase(),
      port: root.hasPort ? root.port : null,
      path: root.path,
    );
    return sha256
        .convert(utf8.encode('$normalized\n${config.username.trim()}'))
        .toString();
  }

  Future<
    ({
      Map<String, SyncCursor> cursors,
      bool recovered,
      bool remoteMismatch,
      String? rootEtag,
    })
  >
  _loadSyncState(Vault vault) async {
    const path = '.tylog/sync_state.json';
    if (!await vault.storage.exists(path)) {
      return (
        cursors: <String, SyncCursor>{},
        recovered: false,
        remoteMismatch: false,
        rootEtag: null,
      );
    }
    final source = await vault.storage.readText(path);
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map || decoded['cursors'] is! Map) {
        throw const FormatException('sync state requires a cursors map');
      }
      if (decoded['schema'] != null && decoded['schema'] != 2) {
        throw const FormatException('unsupported sync state schema');
      }
      if (decoded['remoteKey'] != null && decoded['remoteKey'] is! String) {
        throw const FormatException('sync state remoteKey must be a string');
      }
      if (decoded['rootEtag'] != null && decoded['rootEtag'] is! String) {
        throw const FormatException('sync state rootEtag must be a string');
      }
      final storedRemoteKey = decoded['remoteKey'] as String?;
      if (storedRemoteKey != null && storedRemoteKey != _remoteKey) {
        return (
          cursors: <String, SyncCursor>{},
          recovered: false,
          remoteMismatch: true,
          rootEtag: null,
        );
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
      return (
        cursors: cursors,
        recovered: false,
        remoteMismatch: false,
        rootEtag: decoded['rootEtag'] as String?,
      );
    } catch (error) {
      if (error is! FormatException && error is! TypeError) rethrow;
      final modified =
          (await vault.storage.stat(path))?.modified?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;
      final archive = '.tylog/sync_state.corrupt-$modified.json';
      if (!await vault.storage.exists(archive)) {
        await vault.storage.writeText(archive, source);
      }
      return (
        cursors: <String, SyncCursor>{},
        recovered: true,
        remoteMismatch: false,
        rootEtag: null,
      );
    }
  }

  Future<void> _saveSyncState(
    Vault vault,
    Map<String, SyncCursor> state, {
    String? rootEtag,
  }) async {
    await vault.storage.writeText(
      '.tylog/sync_state.json',
      jsonEncode({
        'schema': 2,
        'remoteKey': _remoteKey,
        'rootEtag': ?rootEtag,
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

/// Whether a rebuilt cursor differs from the previous one in a way that
/// actually matters for a future sync decision — i.e. worth a checkpoint
/// write. Deliberately excludes `remoteMillis`: it's derived from the
/// server's `getlastmodified` header, which round-trips through the
/// second-precision HTTP-date format and so drifts by sub-second amounts on
/// every real listing even when nothing changed. `remoteEtag` is the
/// authoritative "did the remote change" signal whenever the server
/// provides one (the common case); comparing raw millis here would mark
/// nearly every steady-state file dirty on every run, defeating the point.
bool _cursorNeedsPersist(SyncCursor? previous, SyncCursor next) =>
    previous == null ||
    previous.localMillis != next.localMillis ||
    previous.localSize != next.localSize ||
    previous.localSha256 != next.localSha256 ||
    previous.remoteEtag != next.remoteEtag;

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

/// Parses the `oc:checksums` PROPFIND block, returning both the hash and
/// whether its `sha256:` type prefix was stored in lowercase — Nextcloud
/// Desktop only recognizes the uppercase `SHA256:` type and otherwise refuses
/// to sync the file, which is what files this app PUT before the header case
/// fix look like server-side.
({String hash, bool lowercase})? _xmlSha256Info(String xml) {
  for (final match in RegExp(
    r'<[^:>]*:?checksum[^>]*>\s*([^<]+)\s*</[^:>]*:?checksum>',
    caseSensitive: false,
  ).allMatches(xml)) {
    final value = match.group(1)!.trim();
    if (value.toLowerCase().startsWith('sha256:')) {
      final colon = value.indexOf(':');
      return (
        hash: value.substring(colon + 1).toLowerCase(),
        lowercase: value.substring(0, colon) == 'sha256',
      );
    }
  }
  return null;
}

class _RemoteFile {
  const _RemoteFile({
    required this.modified,
    this.etag,
    this.length,
    this.sha256,
    this.sha256Lowercase = false,
  });

  final DateTime modified;
  final String? etag;
  final int? length;
  final String? sha256;
  final bool sha256Lowercase;
}

class _RemoteArchiveSnapshot {
  const _RemoteArchiveSnapshot({
    required this.source,
    required this.input,
    required this.files,
  });

  final File source;
  final InputFileStream input;
  final Map<String, ArchiveFile> files;

  bool contains(String path) => files.containsKey(path);

  Uint8List read(String path) {
    final bytes = files[path]?.readBytes();
    if (bytes == null) {
      throw FormatException('Archive file is unreadable: $path');
    }
    return bytes;
  }

  Future<void> close() async {
    for (final file in files.values) {
      await file.close();
    }
    await input.close();
    if (await source.exists()) await source.delete();
  }
}

class _RenameDetection {
  const _RenameDetection({
    required this.decisions,
    required this.protectedLocalDeletions,
  });

  final List<SyncDecision> decisions;
  final Set<String> protectedLocalDeletions;
}

class _PathResult {
  const _PathResult({
    required this.decision,
    required this.updateCursor,
    required this.cursor,
    this.uploaded = 0,
    this.downloaded = 0,
    this.skipped = 0,
    this.conflicts = 0,
    this.repaired = 0,
    this.deletedRemote = 0,
  });

  final SyncDecision decision;
  final bool updateCursor;
  final SyncCursor? cursor;
  final int uploaded;
  final int downloaded;
  final int skipped;
  final int conflicts;
  final int repaired;
  final int deletedRemote;
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
      final localSnapshot = json['localSnapshot'] as String?;
      final remoteSnapshot = json['remoteSnapshot'] as String?;
      if (localSnapshot != null &&
          remoteSnapshot != null &&
          await vault.storage.exists(localSnapshot) &&
          await vault.storage.exists(remoteSnapshot) &&
          sha256.convert(await vault.storage.readBytes(localSnapshot)) ==
              sha256.convert(await vault.storage.readBytes(remoteSnapshot))) {
        // Both snapshots agree byte-for-byte: there is nothing to review.
        // This self-heals spurious conflicts (e.g. our own autosave racing
        // sync before the fix below existed) with no manual steps.
        await vault.storage.delete(localSnapshot);
        await vault.storage.delete(remoteSnapshot);
        await vault.storage.delete(entry.path);
        continue;
      }
      conflicts.add(
        SyncConflict(
          id: json['id']! as String,
          path: json['path']! as String,
          recordPath: entry.path,
          createdAt: DateTime.parse(json['createdAt']! as String),
          localExists: json['localExists']! as bool,
          remoteExists: json['remoteExists']! as bool,
          localSnapshot: localSnapshot,
          remoteSnapshot: remoteSnapshot,
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

/// Deletes any existing unresolved conflict record (and its snapshots) for
/// [path] so a fresh record replaces it instead of stacking. Conflicts are
/// per-path: only the newest divergence is ever worth the user's review.
Future<void> _discardConflictsForPath(Vault vault, String path) async {
  for (final entry in await vault.storage.list(path: '.tylog/conflicts')) {
    if (entry.isDirectory || !entry.path.endsWith('.json')) continue;
    Map<String, Object?> json;
    try {
      json = (jsonDecode(await vault.storage.readText(entry.path)) as Map)
          .cast<String, Object?>();
    } catch (_) {
      continue;
    }
    if (json['path'] != path) continue;
    for (final key in const ['localSnapshot', 'remoteSnapshot']) {
      final snapshot = json[key] as String?;
      if (snapshot != null && await vault.storage.exists(snapshot)) {
        await vault.storage.delete(snapshot);
      }
    }
    await vault.storage.delete(entry.path);
  }
}

Future<void> createSyncConflict(
  Vault vault,
  String path, {
  required List<int> localBytes,
  required List<int>? remoteBytes,
}) async {
  await _discardConflictsForPath(vault, path);
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

enum SyncAction {
  upload,
  download,
  rename,
  deleteLocal,
  deleteRemote,
  skip,
  conflict,
}

class SyncResult {
  const SyncResult({
    required this.trigger,
    required this.uploaded,
    required this.downloaded,
    required this.skipped,
    required this.conflicts,
    required this.remoteCount,
    this.repaired = 0,
    this.renamed = 0,
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
  final int renamed;
  final int deletedLocal;
  final int deletedRemote;

  bool get requiresIndexRefresh =>
      uploaded > 0 || downloaded > 0 || renamed > 0 || deletedLocal > 0;

  @override
  String toString() =>
      'Sync($trigger): ↑$uploaded ↓$downloaded ↪$renamed =$skipped !$conflicts, remote $remoteCount';
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
