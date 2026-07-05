import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'vault.dart';

class NextcloudConfig {
  const NextcloudConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  final String serverUrl;
  final String username;
  final String password;

  bool get isReady =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  Uri get rootUri {
    final base = Uri.parse(serverUrl.trim().replaceFirst(RegExp(r'/+$'), ''));
    if (base.path.contains('/remote.php/dav/files/')) {
      return base.path.endsWith('/')
          ? base
          : base.replace(path: '${base.path}/');
    }
    return base.replace(
      path:
          '${base.path.replaceFirst(RegExp(r'/+$'), '')}/remote.php/dav/files/$username/TyLogVault/',
    );
  }

  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'password': password,
  };

  static NextcloudConfig fromJson(Map<String, Object?> json) => NextcloudConfig(
    serverUrl: json['serverUrl'] as String? ?? json['url'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
  );

  static Future<File> settingsFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/nextcloud.json');
  }

  static Future<NextcloudConfig?> load() async {
    final file = await settingsFile();
    if (!await file.exists()) return null;
    return fromJson(
      jsonDecode(await file.readAsString()) as Map<String, Object?>,
    );
  }

  Future<void> save() async {
    final file = await settingsFile();
    await file.writeAsString(jsonEncode(toJson()), flush: true);
  }
}

class NextcloudSync {
  NextcloudSync(this.config);

  final NextcloudConfig config;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  Future<SyncResult> sync(Vault vault, {String trigger = 'manual'}) async {
    try {
      if (!config.isReady) throw StateError('Nextcloud settings are empty');
      await _mkcol(config.rootUri);
      final syncState = await _loadSyncState(vault);
      final remote = await _remoteFiles();
      var up = 0;
      var down = 0;
      var skip = 0;
      var conflict = 0;
      var repaired = await _cleanResolvedConflictCopies(vault);
      final decisions = <SyncDecision>[];
      final localFiles = await _localFiles(vault.root);
      final localByPath = {
        for (final file in localFiles) vault.relativePath(file): file,
      };
      final allPaths = <String>{...localByPath.keys, ...remote.keys}.toList()
        ..sort();

      for (final path in allPaths) {
        final local = localByPath[path] ?? File('${vault.root.path}/$path');
        final localExists = await local.exists();
        final remoteFile = remote[path];
        final remoteTime = remoteFile?.modified;
        final localTime = localExists ? await local.lastModified() : null;
        final localHash = localExists ? await _sha256(local) : null;
        final prev = syncState[path];
        final localChanged = prev?.localSha256 != null
            ? localHash != prev!.localSha256
            : _isChanged(localTime, prev?.localMillis);
        final remoteChanged =
            prev?.remoteEtag != null && remoteFile?.etag != null
            ? remoteFile!.etag != prev!.remoteEtag
            : _isChanged(remoteTime, prev?.remoteMillis);
        var action = decideSyncAction(
          localExists: localExists,
          remoteExists: remoteFile != null,
          localChanged: localChanged,
          remoteChanged: remoteChanged,
          hasSyncCursor: prev != null,
          localMillis: localTime?.millisecondsSinceEpoch,
          remoteMillis: remoteTime?.millisecondsSinceEpoch,
        );
        DateTime? uploadedRemoteTime;
        String? uploadedRemoteEtag;
        String? observedRemoteEtag;
        var reason = '';
        if (action == SyncAction.download) {
          await local.parent.create(recursive: true);
          final download =
              remoteFile?.length == 0 &&
                  _protectFromEmpty(path) &&
                  localExists &&
                  await local.length() > 0
              ? _DownloadResult(protected: true, etag: remoteFile?.etag)
              : await _download(path, local, protectNonEmpty: true);
          observedRemoteEtag = download.etag;
          if (download.protected) {
            uploadedRemoteEtag = await _upload(
              path,
              local,
              localHash: localHash!,
              remote: remoteFile,
            );
            uploadedRemoteTime = DateTime.now().toUtc();
            action = SyncAction.upload;
            up++;
            repaired++;
            reason = 'remote-empty-repaired';
          } else {
            down++;
            reason = localTime == null ? 'local-missing' : 'remote-newer';
          }
        } else if (action == SyncAction.upload) {
          try {
            uploadedRemoteEtag = await _upload(
              path,
              local,
              localHash: localHash!,
              remote: remoteFile,
            );
            uploadedRemoteTime = DateTime.now().toUtc();
            up++;
            reason = remoteTime == null ? 'remote-missing' : 'local-newer';
          } on _RemoteChanged {
            final captured = await _saveRemoteConflictCopy(vault, path);
            observedRemoteEtag = captured.etag;
            if (await _sha256(captured.file) == localHash) {
              await captured.file.delete();
              action = SyncAction.skip;
              skip++;
              repaired++;
              reason = 'same-content';
            } else {
              action = SyncAction.conflict;
              conflict++;
              reason = 'remote-changed-during-upload';
            }
          }
        } else if (action == SyncAction.conflict) {
          final captured = await _saveRemoteConflictCopy(vault, path);
          final copy = captured.file;
          observedRemoteEtag = captured.etag;
          final remoteHash = await _sha256(copy);
          if (remoteHash == localHash) {
            await copy.delete();
            action = SyncAction.skip;
            skip++;
            repaired++;
            reason = 'same-content';
          } else if (_protectFromEmpty(path) &&
              await copy.length() == 0 &&
              await local.length() > 0) {
            await copy.delete();
            uploadedRemoteEtag = await _upload(
              path,
              local,
              localHash: localHash!,
              remote: remoteFile,
            );
            uploadedRemoteTime = DateTime.now().toUtc();
            action = SyncAction.upload;
            up++;
            repaired++;
            reason = 'remote-empty-repaired';
          } else {
            conflict++;
            reason = 'both-changed';
          }
        } else {
          skip++;
          reason = 'no-change';
        }
        final nextLocalExists = await local.exists();
        final nextLocal = nextLocalExists ? await local.lastModified() : null;
        final nextRemote = uploadedRemoteTime ?? remoteTime;
        syncState[path] = SyncCursor(
          localMillis: nextLocal?.millisecondsSinceEpoch,
          remoteMillis: nextRemote?.millisecondsSinceEpoch,
          localSha256: nextLocalExists ? await _sha256(local) : null,
          remoteEtag:
              uploadedRemoteEtag ?? observedRemoteEtag ?? remoteFile?.etag,
        );
        decisions.add(
          SyncDecision(
            path: path,
            action: action,
            reason: reason,
            localMillis: nextLocal?.millisecondsSinceEpoch,
            remoteMillis: nextRemote?.millisecondsSinceEpoch,
          ),
        );
      }

      await _saveSyncState(vault, syncState);
      await _appendTrace(
        vault,
        SyncTrace(
          timestamp: DateTime.now().toUtc().toIso8601String(),
          trigger: trigger,
          uploaded: up,
          downloaded: down,
          skipped: skip,
          conflicts: conflict,
          remoteCount: remote.length,
          decisions: decisions,
        ),
      );
      await vault.rebuildIndex();
      return SyncResult(
        trigger: trigger,
        uploaded: up,
        downloaded: down,
        skipped: skip,
        conflicts: conflict,
        remoteCount: remote.length,
        repaired: repaired,
      );
    } finally {
      _client.close(force: true);
    }
  }

  Future<List<File>> _localFiles(Directory root) async {
    final out = <File>[];
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File || entity.path.endsWith('.tmp')) continue;
      final path = _relativePath(root, entity);
      if (_isSyncInternal(path)) continue;
      out.add(entity);
    }
    return out;
  }

  Future<Map<String, _RemoteFile>> _remoteFiles() async {
    final request = await _open('PROPFIND', config.rootUri);
    request.headers.set('Depth', 'infinity');
    request.write(
      '''<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getlastmodified/><d:getetag/><d:getcontentlength/></d:prop></d:propfind>''',
    );
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw HttpException('PROPFIND ${response.statusCode}');
    }

    final files = <String, _RemoteFile>{};
    for (final match in RegExp(
      r'<[^:>]*:?response[^>]*>(.*?)</[^:>]*:?response>',
      dotAll: true,
    ).allMatches(body)) {
      final block = match.group(1)!;
      final hrefValue = _xmlValue(block, 'href');
      final modifiedValue = _xmlValue(block, 'getlastmodified');
      if (hrefValue == null || modifiedValue == null) continue;
      final href = Uri.decodeComponent(hrefValue);
      if (href.endsWith('/')) continue;
      final path = _relativeRemotePath(href);
      if (path != null && !_isSyncInternal(path)) {
        files[path] = _RemoteFile(
          modified: HttpDate.parse(modifiedValue),
          etag: _xmlValue(block, 'getetag'),
          length: int.tryParse(_xmlValue(block, 'getcontentlength') ?? ''),
        );
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
    await request.addStream(file.openRead());
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

  Future<_DownloadResult> _download(
    String path,
    File file, {
    bool protectNonEmpty = false,
  }) async {
    final tmp = File(
      '${file.path}.download-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final response = await (await _open(
      'GET',
      _remoteUri(path),
    )).close().timeout(const Duration(seconds: 60));
    if (response.statusCode >= 400) {
      throw HttpException('GET $path ${response.statusCode}');
    }
    final etag =
        response.headers.value(HttpHeaders.etagHeader) ??
        response.headers.value('oc-etag');
    try {
      await response.pipe(tmp.openWrite());
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

  Future<({File file, String? etag})> _saveRemoteConflictCopy(
    Vault vault,
    String path,
  ) async {
    final conflict = File(
      '${vault.root.path}/$path.remote-conflict-${DateTime.now().millisecondsSinceEpoch}',
    );
    await conflict.parent.create(recursive: true);
    final result = await _download(path, conflict);
    return (file: conflict, etag: result.etag);
  }

  Future<int> _cleanResolvedConflictCopies(Vault vault) async {
    var cleaned = 0;
    await for (final entity in vault.root.list(recursive: true)) {
      if (entity is! File || !entity.path.contains('.remote-conflict-')) {
        continue;
      }
      final relative = vault.relativePath(entity);
      final original = File(
        '${vault.root.path}/${relative.substring(0, relative.indexOf('.remote-conflict-'))}',
      );
      if (!await original.exists()) continue;
      final duplicate =
          await entity.length() == 0 &&
              _protectFromEmpty(vault.relativePath(original)) &&
              await original.length() > 0 ||
          await _sha256(entity) == await _sha256(original);
      if (duplicate) {
        await entity.delete();
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

  String _relativePath(Directory root, File file) {
    final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
        ? root.absolute.path
        : '${root.absolute.path}${Platform.pathSeparator}';
    return file.absolute.path
        .substring(rootPath.length)
        .replaceAll(Platform.pathSeparator, '/');
  }

  Future<Map<String, SyncCursor>> _loadSyncState(Vault vault) async {
    final file = File('${vault.meta.path}/sync_state.json');
    if (!await file.exists()) return {};
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    return (json['cursors'] as Map? ?? const {}).map<String, SyncCursor>(
      (key, value) => MapEntry(
        key.toString(),
        SyncCursor.fromJson((value as Map).cast<String, Object?>()),
      ),
    );
  }

  Future<void> _saveSyncState(
    Vault vault,
    Map<String, SyncCursor> state,
  ) async {
    final file = File('${vault.meta.path}/sync_state.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'cursors': {for (final e in state.entries) e.key: e.value.toJson()},
      }),
      flush: true,
    );
  }

  Future<void> _appendTrace(Vault vault, SyncTrace trace) async {
    final file = File('${vault.meta.path}/sync_trace.jsonl');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(trace.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

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
    path.endsWith('.tmp');

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

enum SyncAction { upload, download, skip, conflict }

class SyncResult {
  const SyncResult({
    required this.trigger,
    required this.uploaded,
    required this.downloaded,
    required this.skipped,
    required this.conflicts,
    required this.remoteCount,
    this.repaired = 0,
  });

  final String trigger;
  final int uploaded;
  final int downloaded;
  final int skipped;
  final int conflicts;
  final int remoteCount;
  final int repaired;

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
    this.remoteMillis,
    this.localSha256,
    this.remoteEtag,
  });

  final int? localMillis;
  final int? remoteMillis;
  final String? localSha256;
  final String? remoteEtag;

  factory SyncCursor.fromJson(Map<String, Object?> json) => SyncCursor(
    localMillis: (json['localMillis'] as num?)?.toInt(),
    remoteMillis: (json['remoteMillis'] as num?)?.toInt(),
    localSha256: json['localSha256'] as String?,
    remoteEtag: json['remoteEtag'] as String?,
  );

  Map<String, Object?> toJson() => {
    'localMillis': localMillis,
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
