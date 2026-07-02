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

  Future<String> sync(Vault vault) async {
    try {
      if (!config.isReady) throw StateError('Nextcloud settings are empty');
      await _mkcol(config.rootUri);
      final remote = await _remoteFiles();
      final downloaded = <String>{};
      var up = 0;
      var down = 0;

      for (final entry in remote.entries) {
        final local = File('${vault.root.path}/${entry.key}');
        if (!await local.exists() ||
            entry.value.isAfter(await local.lastModified())) {
          await local.parent.create(recursive: true);
          await _download(entry.key, local);
          downloaded.add(entry.key);
          down++;
        }
      }

      for (final file in await _localFiles(vault.root)) {
        final path = vault.relativePath(file);
        if (downloaded.contains(path)) continue;
        final localTime = await file.lastModified();
        final remoteTime = remote[path];
        if (remoteTime == null || localTime.isAfter(remoteTime)) {
          await _upload(path, file);
          up++;
        }
      }

      await vault.rebuildIndex();
      return 'Sync: ↑$up ↓$down, remote ${remote.length}';
    } finally {
      _client.close(force: true);
    }
  }

  Future<List<File>> _localFiles(Directory root) async {
    final out = <File>[];
    await for (final entity in root.list(recursive: true)) {
      if (entity is File && !entity.path.endsWith('.tmp')) out.add(entity);
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
      if (path != null) files[path] = HttpDate.parse(match.group(2)!);
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

  Future<void> _download(String path, File file) async {
    final response = await (await _open(
      'GET',
      _remoteUri(path),
    )).close().timeout(const Duration(seconds: 60));
    if (response.statusCode >= 400) {
      throw HttpException('GET $path ${response.statusCode}');
    }
    await response.pipe(file.openWrite());
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
}
