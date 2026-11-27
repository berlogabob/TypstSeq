import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:tylog_core/storage.dart';
import 'package:tylog_core/sync_paths.dart';

import '../nextcloud_sync.dart' show isSyncInternalPath;

/// Serves one vault as a minimal WebDAV server on loopback, for a paired P2P
/// peer: the iroh tunnel forwards the peer's connections here, and the peer
/// runs the ordinary sync engine against it exactly as against a plain WebDAV
/// server (`NextcloudConfig(kind: 'peer')`). Reconciliation, conflicts and
/// deletion guards therefore stay in the engine, on the syncing side.
///
/// Only syncable vault paths are visible or writable; `.tylog/`, `_index/` and
/// everything else outside `isSyncableVaultPath` returns 404/403. Every
/// request needs Basic auth with [password] (any user name): other apps on the
/// device can reach a loopback port too.
///
/// ETags are size + mtime + [generation]. mtime alone misses a same-size edit
/// in the same second on SAF (second granularity); the generation is the
/// vault's per-path count of local writes, which closes that gap for edits
/// made in this app.
class VaultDavServer {
  VaultDavServer({
    required this.storage,
    required this.password,
    this.generation,
    this.onWritten,
    this.onNotify,
  });

  /// URL path prefix. Not `/`: the engine treats a href ending in its root
  /// path as the root collection, and every href ends in ''.
  static const rootPath = '/tylog-vault-dav/';

  final VaultStorage storage;
  final String password;
  final int Function(String path)? generation;

  /// A peer wrote or deleted [path]: refresh the index and mark it pending for
  /// the other remotes.
  final void Function(String path)? onWritten;

  /// The peer asks this device to sync with it now (`POST /tylog-notify`).
  final void Function()? onNotify;

  HttpServer? _server;

  int? get port => _server?.port;

  Future<int> start({int port = 0}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen((request) {
      unawaited(_handle(request));
    });
    return server.port;
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (!_authorized(request)) {
        response.statusCode = HttpStatus.unauthorized;
        response.headers.set('WWW-Authenticate', 'Basic realm="TyLog"');
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/tylog-notify') {
        await request.drain<void>();
        onNotify?.call();
        response.statusCode = HttpStatus.noContent;
        return;
      }
      final path = _vaultPath(request.uri.path);
      if (path == null) {
        await request.drain<void>();
        response.statusCode = HttpStatus.notFound;
        return;
      }
      switch (request.method) {
        case 'PROPFIND':
          await _propfind(request, path);
        case 'GET':
        case 'HEAD':
          await _get(request, path);
        case 'PUT':
          await _put(request, path);
        case 'DELETE':
          await _delete(request, path);
        case 'MKCOL':
          await _mkcol(request, path);
        case 'MOVE':
          await _move(request, path);
        default:
          await request.drain<void>();
          response.statusCode = HttpStatus.methodNotAllowed;
      }
    } catch (error) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.write('$error');
      } catch (_) {
        // Headers already sent; closing below still ends the response.
      }
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Basic ')) return false;
    final String decoded;
    try {
      decoded = utf8.decode(base64Decode(header.substring(6).trim()));
    } catch (_) {
      return false;
    }
    final colon = decoded.indexOf(':');
    if (colon < 0) return false;
    return _constantTimeEquals(decoded.substring(colon + 1), password);
  }

  /// The vault-relative path for a request path, '' for the root, a trailing
  /// '/' kept for collections; null outside the root or with `..` segments.
  static String? _vaultPath(String requestPath) {
    if (!requestPath.startsWith(rootPath)) {
      return requestPath == rootPath.substring(0, rootPath.length - 1)
          ? ''
          : null;
    }
    final String relative;
    try {
      relative = Uri.decodeComponent(requestPath.substring(rootPath.length));
    } catch (_) {
      return null;
    }
    final segments = relative.split('/');
    if (relative.contains('\\') ||
        segments.any((part) => part == '..' || part == '.')) {
      return null;
    }
    return relative;
  }

  static bool _visibleFile(String path) =>
      isSyncableVaultPath(path) && !isSyncInternalPath(path);

  static bool _visibleFolder(String folder) {
    final clean = folder.endsWith('/')
        ? folder.substring(0, folder.length - 1)
        : folder;
    return clean.isEmpty || _visibleFile('$clean/file.typ');
  }

  String _etag(VaultStorageEntry entry) {
    final modified = entry.modified?.microsecondsSinceEpoch ?? 0;
    return '"${entry.size ?? 0}-$modified-${generation?.call(entry.path) ?? 0}"';
  }

  static String _href(String path) =>
      rootPath + path.split('/').map(Uri.encodeComponent).join('/');

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _fileResponse(VaultStorageEntry entry) {
    final modified = HttpDate.format(
      (entry.modified ?? DateTime.fromMillisecondsSinceEpoch(0)).toUtc(),
    );
    return '<d:response><d:href>${_xml(_href(entry.path))}</d:href>'
        '<d:propstat><d:prop><d:resourcetype/>'
        '<d:getlastmodified>$modified</d:getlastmodified>'
        '<d:getetag>${_xml(_etag(entry))}</d:getetag>'
        '<d:getcontentlength>${entry.size ?? 0}</d:getcontentlength>'
        '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
        '</d:response>';
  }

  static String _folderResponse(String folder) {
    final path = folder.isEmpty || folder.endsWith('/') ? folder : '$folder/';
    return '<d:response><d:href>${_xml(_href(path))}</d:href>'
        '<d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>'
        '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
        '</d:response>';
  }

  Future<void> _propfind(HttpRequest request, String path) async {
    await request.drain<void>();
    final depth = request.headers.value('Depth') ?? 'infinity';
    final response = request.response;
    final body = StringBuffer(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:multistatus xmlns:d="DAV:">',
    );
    final folder = path.isEmpty || path.endsWith('/');
    if (!folder) {
      final entry = _visibleFile(path) ? await storage.stat(path) : null;
      if (entry == null || entry.isDirectory) {
        // A collection addressed without its trailing slash.
        if (entry != null && _visibleFolder(path)) {
          body.write(_folderResponse(path));
        } else {
          response.statusCode = HttpStatus.notFound;
          return;
        }
      } else {
        body.write(_fileResponse(entry));
      }
    } else {
      final base = path.isEmpty ? '' : path.substring(0, path.length - 1);
      if (!_visibleFolder(path) ||
          (base.isNotEmpty && !await storage.exists(base))) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      body.write(_folderResponse(path));
      if (depth != '0') {
        final entries = await storage.list(path: base, recursive: depth != '1');
        for (final entry in entries) {
          if (entry.isDirectory) {
            if (_visibleFolder(entry.path)) {
              body.write(_folderResponse(entry.path));
            }
          } else if (_visibleFile(entry.path)) {
            body.write(_fileResponse(entry));
          }
        }
      }
    }
    body.write('</d:multistatus>');
    final bytes = utf8.encode(body.toString());
    response.statusCode = 207;
    response.headers.contentType = ContentType(
      'application',
      'xml',
      charset: 'utf-8',
    );
    response.contentLength = bytes.length;
    response.add(bytes);
  }

  Future<VaultStorageEntry?> _file(String path) async {
    if (!_visibleFile(path)) return null;
    final entry = await storage.stat(path);
    return entry == null || entry.isDirectory ? null : entry;
  }

  Future<void> _get(HttpRequest request, String path) async {
    await request.drain<void>();
    final response = request.response;
    final entry = await _file(path);
    if (entry == null) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final bytes = await storage.readBytes(path);
    response.headers.set(HttpHeaders.etagHeader, _etag(entry));
    if (request.headers.value('X-Hash')?.toLowerCase() == 'sha256') {
      response.headers.set('X-Hash-SHA256', sha256.convert(bytes).toString());
    }
    response.contentLength = bytes.length;
    if (request.method != 'HEAD') response.add(bytes);
  }

  /// Null when the request's If-Match / If-None-Match allow the write.
  String? _preconditionFailure(
    HttpRequest request,
    VaultStorageEntry? current,
  ) {
    final ifMatch = request.headers.value(HttpHeaders.ifMatchHeader);
    final ifNoneMatch = request.headers.value(HttpHeaders.ifNoneMatchHeader);
    if (ifNoneMatch == '*' && current != null) return 'exists';
    if (ifMatch != null) {
      if (current == null) return 'missing';
      if (ifMatch.trim() != '*' && _norm(ifMatch) != _norm(_etag(current))) {
        return 'changed';
      }
    }
    return null;
  }

  static String _norm(String etag) =>
      etag.trim().replaceFirst(RegExp(r'^W/'), '').replaceAll('"', '');

  Future<void> _put(HttpRequest request, String path) async {
    final response = request.response;
    if (path.isEmpty || path.endsWith('/') || !_visibleFile(path)) {
      await request.drain<void>();
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final digest = sha256.convert(bytes).toString();
    final checksum = request.headers.value('OC-Checksum');
    if (checksum != null &&
        checksum.toUpperCase().startsWith('SHA256:') &&
        checksum.substring(7).toLowerCase() != digest) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    final current = await _file(path);
    if (_preconditionFailure(request, current) != null) {
      response.statusCode = HttpStatus.preconditionFailed;
      return;
    }
    final slash = path.lastIndexOf('/');
    if (slash > 0) await storage.createDirectory(path.substring(0, slash));
    await storage.writeBytes(path, bytes);
    onWritten?.call(path);
    final written = await storage.stat(path);
    response.statusCode = current == null
        ? HttpStatus.created
        : HttpStatus.noContent;
    if (written != null) {
      response.headers.set(HttpHeaders.etagHeader, _etag(written));
    }
    response.headers.set('X-Hash-SHA256', digest);
  }

  Future<void> _delete(HttpRequest request, String path) async {
    await request.drain<void>();
    final response = request.response;
    final current = await _file(path);
    if (current == null) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    if (_preconditionFailure(request, current) != null) {
      response.statusCode = HttpStatus.preconditionFailed;
      return;
    }
    await storage.delete(path);
    onWritten?.call(path);
    response.statusCode = HttpStatus.noContent;
  }

  Future<void> _mkcol(HttpRequest request, String path) async {
    await request.drain<void>();
    final response = request.response;
    final folder = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    if (folder.isEmpty || await storage.exists(folder)) {
      response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    if (!_visibleFolder(folder)) {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    await storage.createDirectory(folder);
    response.statusCode = HttpStatus.created;
  }

  Future<void> _move(HttpRequest request, String path) async {
    await request.drain<void>();
    final response = request.response;
    final destinationHeader = request.headers.value('Destination');
    final destination = destinationHeader == null
        ? null
        : _vaultPath(Uri.parse(destinationHeader).path);
    final current = await _file(path);
    if (destination == null ||
        destination.isEmpty ||
        destination.endsWith('/') ||
        !_visibleFile(destination)) {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    if (current == null) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    if (_preconditionFailure(request, current) != null) {
      response.statusCode = HttpStatus.preconditionFailed;
      return;
    }
    final overwrite = request.headers.value('Overwrite')?.toUpperCase() != 'F';
    final existing = await _file(destination);
    if (existing != null && !overwrite) {
      response.statusCode = HttpStatus.preconditionFailed;
      return;
    }
    // ponytail: copy + delete; VaultStorage has no rename, and a crash in
    // between leaves both copies, which the next sync pass reconciles.
    final bytes = await storage.readBytes(path);
    final slash = destination.lastIndexOf('/');
    if (slash > 0) {
      await storage.createDirectory(destination.substring(0, slash));
    }
    await storage.writeBytes(destination, bytes);
    await storage.delete(path);
    onWritten?.call(path);
    onWritten?.call(destination);
    final moved = await storage.stat(destination);
    response.statusCode = existing == null
        ? HttpStatus.created
        : HttpStatus.noContent;
    if (moved != null) {
      response.headers.set(HttpHeaders.etagHeader, _etag(moved));
    }
  }
}

bool _constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length && i < y.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}
