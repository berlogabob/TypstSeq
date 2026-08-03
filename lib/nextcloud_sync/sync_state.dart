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
