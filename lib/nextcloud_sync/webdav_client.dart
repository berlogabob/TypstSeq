part of '../nextcloud_sync.dart';

extension _WebDavClient on NextcloudSync {
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
        .timeout(NextcloudSync.propfindBodyTimeout);
    if (allowMissing && response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != 207) {
      throw WebDavStatusException(
        'PROPFIND unexpected status ${response.statusCode}',
      );
    }
    if (!RegExp(r'<[^:>]*:?multistatus\b').hasMatch(body)) {
      throw const HttpException('PROPFIND invalid multistatus response');
    }
    // Parsing a Depth:infinity response for ~2000 entries blocks the calling
    // isolate for ~250-300 ms on a phone — the last blocking sync stage — so
    // the parse runs in a compute() isolate. Everything crossing the boundary
    // is plain data.
    return compute(_parsePropfindBody, (
      body: body,
      rootPath: config.rootUri.path,
      includeNonSyncable: includeNonSyncable,
    ));
  }

  bool _isRootHref(String href) => _isRootHrefFor(href, config.rootUri.path);

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
        .timeout(NextcloudSync.propfindBodyTimeout);
    if (response.statusCode != 207) {
      throw WebDavStatusException(
        'PROPFIND unexpected status ${response.statusCode}',
      );
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
        .timeout(NextcloudSync.propfindBodyTimeout);
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != 207) {
      throw WebDavStatusException(
        'PROPFIND unexpected status ${response.statusCode}',
      );
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

  String? _relativeRemotePath(String href) =>
      _relativeRemotePathFor(href, config.rootUri.path);

  // Nextcloud quotes the etag in PROPFIND (getetag) but not in the PUT `oc-etag`
  // header, so a stored upload etag never string-matches the next PROPFIND and
  // every upload looks like a remote change → spurious download (ping-pong).
  // Canonicalize (drop surrounding quotes and a weak `W/` prefix) for compares
  // and cursor storage; the raw etag is still sent verbatim in If-Match.

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
      throw WebDavStatusException('PUT $path ${response.statusCode}');
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
      throw WebDavStatusException('GET $path ${response.statusCode}');
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
      // Hashed once: the same digest serves the integrity check and the
      // cursor's localSha256 (it was computed twice per file before).
      final digest = sha256.convert(bytes).toString();
      if (remoteFile?.sha256 != null && digest != remoteFile!.sha256) {
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
      return _DownloadResult(
        protected: false,
        etag: remoteFile?.etag,
        localSha256: digest,
      );
    }
    final temporary = await File(
      '${Directory.systemTemp.path}/tylog-${DateTime.now().microsecondsSinceEpoch}.tmp',
    ).create();
    try {
      final result = await _download(path, temporary);
      String? verifiedSha256;
      if (remoteFile?.sha256 != null) {
        verifiedSha256 = await _sha256(temporary);
        if (verifiedSha256 != remoteFile!.sha256) {
          throw HttpException('GET $path checksum mismatch');
        }
      }
      if (protectNonEmpty &&
          _protectFromEmpty(path) &&
          await storage.exists(path) &&
          (await storage.stat(path))!.size! > 0 &&
          await temporary.length() == 0) {
        return _DownloadResult(protected: true, etag: result.etag);
      }
      _requireLocalReplacementAllowed(path);
      final bytes = await temporary.readAsBytes();
      await storage.writeBytes(path, bytes);
      return _DownloadResult(
        protected: result.protected,
        etag: result.etag,
        // The streamed digest already verified these exact bytes.
        localSha256: verifiedSha256 ?? sha256.convert(bytes).toString(),
      );
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
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
      throw WebDavStatusException('MKCOL ${response.statusCode}');
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
    if (status >= 400) {
      throw WebDavStatusException('MOVE $from ${response.statusCode}');
    }
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
      throw WebDavStatusException('DELETE $path ${response.statusCode}');
    }
  }

  // ponytail: retries a whole path sync on any I/O error; a PUT whose success
  // response was lost re-runs into If-Match 412 and surfaces as a resolvable
  // conflict — per-request idempotency keys if that ever bites.
  Future<T> _retryTransient<T>(Future<T> Function() run) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await run();
      } on WebDavStatusException {
        // A completed HTTP error response means the server was reached and
        // answered definitively; retrying just burns the retry budget at
        // every sync stage. A dropped connection instead surfaces as a plain
        // IOException below and is still retried.
        // NB: WebDavStatusException extends HttpException/IOException, so this
        // clause must precede the IOException catch.
        rethrow;
      } on IOException {
        if (attempt >= NextcloudSync.connectionRetryDelays.length) rethrow;
      } on TimeoutException {
        if (attempt >= NextcloudSync.connectionRetryDelays.length) rethrow;
      }
      await Future<void>.delayed(NextcloudSync.connectionRetryDelays[attempt]);
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
        if (attempt >= NextcloudSync.connectionRetryDelays.length) rethrow;
      } on TimeoutException {
        if (attempt >= NextcloudSync.connectionRetryDelays.length) rethrow;
      }
      await Future<void>.delayed(NextcloudSync.connectionRetryDelays[attempt]);
    }
  }
}
