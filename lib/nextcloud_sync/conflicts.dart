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
