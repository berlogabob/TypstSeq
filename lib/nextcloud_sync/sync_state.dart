part of '../nextcloud_sync.dart';

extension _SyncStatePersistence on NextcloudSync {
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
      bool legacy,
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
        legacy: false,
      );
    }
    final source = await vault.storage.readText(path);
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map || decoded['cursors'] is! Map) {
        throw const FormatException('sync state requires a cursors map');
      }
      // `schema` and `remoteKey` absent means the file predates those fields,
      // and both are deliberately tolerated rather than treated as unknown.
      // An audit flagged this as "absent read as current", the same shape as a
      // real bug elsewhere — but here the safe-looking alternatives are worse.
      // Rejecting the file discards a deliberate, tested migration; accepting
      // it as *recovered* turns every path into a comparison and hands the
      // user a conflict per file on their first sync after upgrading. And the
      // risk it guards against is not real: an unbound cursor carries a
      // server-generated etag, so against a different server it simply fails
      // to match and the pass re-decides the path correctly. Each cursor entry
      // is validated on its own by _validSyncCursor regardless.
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
          legacy: false,
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
        // Written before `schema`/`remoteKey` existed. Accepted rather than
        // discarded — that migration is deliberate — but reported, so the pass
        // rewrites the file and the ambiguity lasts exactly one pass instead
        // of until something else happens to change.
        legacy: decoded['schema'] == null || decoded['remoteKey'] == null,
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
        legacy: false,
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
  ) => appendVaultTrace(vault, events);
}
