import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'vault.dart';
import 'vault_storage.dart';

part 'nextcloud_sync/conflicts.dart';
part 'nextcloud_sync/path_sync.dart';
part 'nextcloud_sync/sync_state.dart';
part 'nextcloud_sync/webdav_client.dart';



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
  const RemoteVaultInspection(this.kind, {this.userFileCount = 0});

  final RemoteVaultKind kind;
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

/// A WebDAV request that completed with a definitive error status. Unlike a
/// dropped connection (a plain [HttpException]/[SocketException]), retrying
/// cannot change the outcome, so [NextcloudSync._retryTransient] rethrows these
/// at once instead of burning the retry budget at every sync stage.
class WebDavStatusException extends HttpException {
  WebDavStatusException(super.message);
}

class NextcloudSync {
  NextcloudSync(this.config, {this.onProgress, this.canReplaceLocal});

  final NextcloudConfig config;
  final void Function(String stage, String? path)? onProgress;
  final bool Function(String path)? canReplaceLocal;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final _ensuredParents = <String>{};

  /// How often a run may persist its cursor map mid-loop.
  ///
  /// Bounds checkpoint cost by wall-clock instead of by vault size — see the
  /// comment at the call site. `@visibleForTesting` so a test can drive many
  /// checkpoints without waiting real seconds.
  @visibleForTesting
  static Duration checkpointInterval = const Duration(seconds: 5);

  static Duration propfindBodyTimeout = const Duration(seconds: 60);
  static List<Duration> connectionRetryDelays = const [
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  /// Cheap, conservative preflight for a background poll: uncertain remote
  /// state falls through to a full sync.
  ///
  /// Deliberately does *not* verify the local tree against the cursors. That
  /// check costs a full recursive listing (~2.3s of the storage thread on a
  /// 1700-note SAF vault, every 25s) and this is not the path local edits
  /// travel: an edit schedules its own sync through
  /// `WorkspaceController.queueCloudSync`, and `sync()` still runs the local
  /// check on every startup, resume and manual run. What this gives up is
  /// noticing a local change made by *another app* during a poll — that now
  /// waits for the next real sync instead.

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
      return true;
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
      var lastCheckpoint = DateTime.now();
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
            // "skip / no-change" is the one decision that carries no
            // information: nothing was transferred and nothing was compared
            // beyond fingerprints, and the same trace event already reports the
            // count as `skipped`. Recording it per path is what makes a
            // steady-state run write ~400 KB of JSON inside a single trace line
            // — enough to push sync_trace.jsonl past its own 512 KB trim
            // threshold on every run — and what makes the sync dashboard build
            // one ListTile per note, eagerly, in a Column. Every other reason,
            // including the other `skip` ones like unresolved-conflict, is kept.
            if (result.decision.action != SyncAction.skip ||
                result.decision.reason != 'no-change') {
              decisions.add(result.decision);
            }
            completed++;
            progress('sync-file $completed/${allPaths.length}', path);
            // Time-based, not every-N-files. A checkpoint re-encodes *every*
            // cursor, not just the ones that changed, so triggering it per N
            // files makes a run scale with vault size squared: measured on a
            // 2061-path vault, one checkpoint is 38 ms of blocked isolate on a
            // P30 and the old `% 10` gate fired 206 times — 2.75 s of encoding,
            // and ~110 MB written through SafBridge's single write thread, whose
            // fair lock blocks every concurrent read while it runs.
            //
            // The trade is what a mid-sync process kill costs, and it is small:
            // the cursors it would lose only save the *next* run from
            // re-comparing those paths, not from re-transferring them, and the
            // post-loop save at the end of this method still persists everything
            // on a clean finish.
            if (cursorsDirty &&
                DateTime.now().difference(lastCheckpoint) >=
                    checkpointInterval) {
              final snapshot = Map<String, SyncCursor>.of(cursors);
              final write = checkpointTail.then(
                (_) => _saveSyncState(vault, snapshot, rootEtag: freshRootEtag),
              );
              checkpointTail = write.catchError((_) {});
              await write;
              cursorsDirty = false;
              lastCheckpoint = DateTime.now();
            }
          } catch (error, stack) {
            firstError ??= error;
            firstStack ??= stack;
          }
        }
      }

      // 8 in-flight requests: local I/O behind these is capped lower anyway
      // (SafBridge runs 4 read threads and 1 write thread), so this mainly
      // buys overlap on network latency. Archive bootstrap stays serial.
      await Future.wait(
        List.generate(
          math.min(archiveSnapshot == null ? 8 : 1, allPaths.length),
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
              NextcloudSync._normEtag(currentRemote?.etag) !=
                  NextcloudSync._normEtag(conflict.remoteEtag)) {
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
          remoteEtag: NextcloudSync._normEtag(remoteEtag ?? currentRemote?.etag),
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

/// Parses a Depth:infinity PROPFIND body into remote-file entries. Top-level
/// and dependent only on plain data so it can run inside compute().
({Map<String, _RemoteFile> files, String? rootEtag}) _parsePropfindBody(
  ({String body, String rootPath, bool includeNonSyncable}) args,
) {
  final files = <String, _RemoteFile>{};
  // The root collection's own entry (href ends with '/') is included in a
  // Depth:infinity response alongside every file; its etag changes
  // whenever anything beneath it changes, which is what makes the
  // no-change shortcut in sync() safe to rely on.
  String? rootEtag;
  for (final match in RegExp(
    r'<[^:>]*:?response[^>]*>(.*?)</[^:>]*:?response>',
    dotAll: true,
  ).allMatches(args.body)) {
    final block = match.group(1)!;
    try {
      final hrefValue = _xmlValue(block, 'href');
      if (hrefValue == null) {
        throw const FormatException('missing href');
      }
      final href = Uri.decodeComponent(hrefValue);
      if (href.endsWith('/')) {
        if (rootEtag == null && _isRootHrefFor(href, args.rootPath)) {
          rootEtag = _xmlValue(block, 'getetag');
        }
        continue;
      }
      final modifiedValue = _xmlValue(block, 'getlastmodified');
      if (modifiedValue == null) {
        throw const FormatException('missing getlastmodified');
      }
      final path = _relativeRemotePathFor(href, args.rootPath);
      if (path == null) {
        throw const FormatException('path is outside configured folder');
      }
      final lengthValue = _xmlValue(block, 'getcontentlength');
      final length = lengthValue == null ? null : int.tryParse(lengthValue);
      if (lengthValue != null && length == null) {
        throw const FormatException('invalid getcontentlength');
      }
      final syncInternal = isSyncInternalPath(path) || !isSyncableVaultPath(path);
      if (args.includeNonSyncable || !syncInternal) {
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

bool _isRootHrefFor(String href, String root) {
  final normalizedRoot = root.endsWith('/')
      ? root.substring(0, root.length - 1)
      : root;
  final normalizedHref = href.endsWith('/')
      ? href.substring(0, href.length - 1)
      : href;
  return normalizedHref.endsWith(normalizedRoot);
}

String? _relativeRemotePathFor(String href, String root) {
  final start = href.indexOf(root);
  if (start < 0) return null;
  final path = href.substring(start + root.length);
  return path.isEmpty ? null : path;
}

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
  const _DownloadResult({required this.protected, this.etag, this.localSha256});

  /// sha256 of the bytes just written, computed while they were already in
  /// hand — saves re-reading the whole file back to build the sync cursor.
  final String? localSha256;

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
