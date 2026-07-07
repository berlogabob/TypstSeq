import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'vault.dart';

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
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}

class NextcloudSync {
  NextcloudSync(this.config);

  final NextcloudConfig config;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  Future<SyncResult> sync(Vault vault, {String trigger = 'manual'}) async {
    final runId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    var stage = 'start';
    String? currentPath;
    var up = 0;
    var down = 0;
    var skip = 0;
    var conflict = 0;
    var repaired = 0;
    var remoteCount = 0;
    final decisions = <SyncDecision>[];
    await _trace(vault, {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'runId': runId,
      'event': 'started',
      'trigger': trigger,
    });
    try {
      if (!config.isReady) throw StateError('Nextcloud settings are empty');
      stage = 'prepare-remote-folder';
      await _mkcol(config.rootUri);
      stage = 'load-local-state';
      final loadedState = await _loadSyncState(vault);
      final syncState = loadedState.cursors;
      if (loadedState.recovered) {
        await _trace(vault, {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'runId': runId,
          'event': 'state-recovered',
          'trigger': trigger,
        });
      }
      stage = 'list-remote';
      final remote = await _remoteFiles();
      remoteCount = remote.length;
      stage = 'scan-local';
      repaired = await _cleanResolvedConflictCopies(vault);
      final localFiles = await _localFiles(vault.root);
      final localByPath = {
        for (final file in localFiles) vault.relativePath(file): file,
      };
      final allPaths = <String>{...localByPath.keys, ...remote.keys}.toList()
        ..sort();

      for (final path in allPaths) {
        stage = 'sync-file';
        currentPath = path;
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
            ? _normEtag(remoteFile!.etag) != _normEtag(prev!.remoteEtag)
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
        if (loadedState.recovered && localExists && remoteFile != null) {
          action = SyncAction.conflict;
        }
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
          remoteEtag: _normEtag(
            uploadedRemoteEtag ?? observedRemoteEtag ?? remoteFile?.etag,
          ),
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

      stage = 'save-local-state';
      currentPath = null;
      await _saveSyncState(vault, syncState);
      await _trace(vault, {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'runId': runId,
        'event': 'completed',
        'trigger': trigger,
        'uploaded': up,
        'downloaded': down,
        'skipped': skip,
        'conflicts': conflict,
        'repaired': repaired,
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
      );
    } catch (error) {
      await _trace(vault, {
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
        'remoteCount': remoteCount,
        'decisions': decisions.map((decision) => decision.toJson()).toList(),
      });
      rethrow;
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

  Future<({Map<String, SyncCursor> cursors, bool recovered})> _loadSyncState(
    Vault vault,
  ) async {
    final file = File('${vault.meta.path}/sync_state.json');
    if (!await file.exists()) {
      return (cursors: <String, SyncCursor>{}, recovered: false);
    }
    final source = await file.readAsString();
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
      final modified = (await file.lastModified()).millisecondsSinceEpoch;
      final archive = File(
        '${vault.meta.path}/sync_state.corrupt-$modified.json',
      );
      if (!await archive.exists()) {
        await archive.writeAsString(source, flush: true);
      }
      return (cursors: <String, SyncCursor>{}, recovered: true);
    }
  }

  Future<void> _saveSyncState(
    Vault vault,
    Map<String, SyncCursor> state,
  ) async {
    final file = File('${vault.meta.path}/sync_state.json');
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'cursors': {for (final e in state.entries) e.key: e.value.toJson()},
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<void> _trace(Vault vault, Map<String, Object?> event) async {
    try {
      await _appendTrace(vault, event);
    } catch (_) {
      // Diagnostics must never stop file synchronization.
    }
  }

  Future<void> _appendTrace(Vault vault, Map<String, Object?> event) async {
    final file = File('${vault.meta.path}/sync_trace.jsonl');
    await file.parent.create(recursive: true);
    if (await file.exists() && await file.length() > 512 * 1024) {
      final bytes = await file.readAsBytes();
      var start = bytes.length - 256 * 1024;
      while (start < bytes.length && bytes[start] != 10) {
        start++;
      }
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(
        bytes.sublist(start < bytes.length ? start + 1 : bytes.length),
        flush: true,
      );
      await temporary.rename(file.path);
    }
    await file.writeAsString(
      '${jsonEncode(event)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

bool _validSyncCursor(Map<String, Object?> json) =>
    (json['localMillis'] == null || json['localMillis'] is num) &&
    (json['remoteMillis'] == null || json['remoteMillis'] is num) &&
    (json['localSha256'] == null || json['localSha256'] is String) &&
    (json['remoteEtag'] == null || json['remoteEtag'] is String);

String _safeErrorMessage(Object error) => switch (error) {
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
