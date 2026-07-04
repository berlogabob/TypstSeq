import 'dart:convert';
import 'dart:io';

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
        final remoteTime = remote[path];
        final localTime = localExists ? await local.lastModified() : null;
        final prev = syncState[path];
        final localChanged = _isChanged(localTime, prev?.localMillis);
        final remoteChanged = _isChanged(remoteTime, prev?.remoteMillis);
        var action = decideSyncAction(
          localExists: localExists,
          remoteExists: remoteTime != null,
          localChanged: localChanged,
          remoteChanged: remoteChanged,
          hasSyncCursor: prev != null,
          localMillis: localTime?.millisecondsSinceEpoch,
          remoteMillis: remoteTime?.millisecondsSinceEpoch,
        );
        DateTime? uploadedRemoteTime;
        var reason = '';
        if (action == SyncAction.download) {
          await local.parent.create(recursive: true);
          final protected = await _download(path, local, protectNonEmpty: true);
          if (protected) {
            action = SyncAction.conflict;
            conflict++;
            reason = 'remote-empty';
          } else {
            down++;
            reason = localTime == null ? 'local-missing' : 'remote-newer';
          }
        } else if (action == SyncAction.upload) {
          await _upload(path, local);
          uploadedRemoteTime = DateTime.now().toUtc();
          up++;
          reason = remoteTime == null ? 'remote-missing' : 'local-newer';
        } else if (action == SyncAction.conflict) {
          await _saveRemoteConflictCopy(vault, path);
          conflict++;
          reason = 'both-changed';
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

  Future<Map<String, DateTime>> _remoteFiles() async {
    final request = await _open('PROPFIND', config.rootUri);
    request.headers.set('Depth', 'infinity');
    request.write(
      '''<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getlastmodified/></d:prop></d:propfind>''',
    );
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw HttpException('PROPFIND ${response.statusCode}');
    }

    final files = <String, DateTime>{};
    for (final match in RegExp(
      r'<[^:>]*:?response[^>]*>.*?<[^:>]*:?href[^>]*>(.*?)</[^:>]*:?href>.*?<[^:>]*:?getlastmodified[^>]*>(.*?)</[^:>]*:?getlastmodified>.*?</[^:>]*:?response>',
      dotAll: true,
    ).allMatches(body)) {
      final href = Uri.decodeComponent(match.group(1)!);
      if (href.endsWith('/')) continue;
      final path = _relativeRemotePath(href);
      if (path != null && !_isSyncInternal(path)) {
        files[path] = HttpDate.parse(match.group(2)!);
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

  Future<void> _upload(String path, File file) async {
    await _ensureParents(path);
    final request = await _open('PUT', _remoteUri(path));
    await request.addStream(file.openRead());
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode >= 400) {
      throw HttpException('PUT $path ${response.statusCode}');
    }
  }

  Future<bool> _download(
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
    try {
      await response.pipe(tmp.openWrite());
      if (protectNonEmpty &&
          await file.exists() &&
          await file.length() > 0 &&
          await tmp.length() == 0) {
        await tmp.rename(
          '${file.path}.remote-conflict-${DateTime.now().millisecondsSinceEpoch}',
        );
        return true;
      }
      await tmp.rename(file.path);
      return false;
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  Future<void> _saveRemoteConflictCopy(Vault vault, String path) async {
    final conflict = File(
      '${vault.root.path}/$path.remote-conflict-${DateTime.now().millisecondsSinceEpoch}',
    );
    await conflict.parent.create(recursive: true);
    await _download(path, conflict);
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

  bool _isSyncInternal(String path) => isSyncInternalPath(path);

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

bool isSyncInternalPath(String path) =>
    path == '.tylog/index.json' ||
    path == '.tylog/search-index.json.gz' ||
    path == '.tylog/tylog.typ' ||
    path == '.tylog/sync_state.json' ||
    path == '.tylog/sync_trace.jsonl' ||
    path.startsWith('.tylog/backups/') ||
    path.startsWith('.tylog/search-index.json.gz-') ||
    path.contains('.remote-conflict-') ||
    path.endsWith('.tmp');

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
  });

  final String trigger;
  final int uploaded;
  final int downloaded;
  final int skipped;
  final int conflicts;
  final int remoteCount;

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
  const SyncCursor({this.localMillis, this.remoteMillis});

  final int? localMillis;
  final int? remoteMillis;

  factory SyncCursor.fromJson(Map<String, Object?> json) => SyncCursor(
    localMillis: (json['localMillis'] as num?)?.toInt(),
    remoteMillis: (json['remoteMillis'] as num?)?.toInt(),
  );

  Map<String, Object?> toJson() => {
    'localMillis': localMillis,
    'remoteMillis': remoteMillis,
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
