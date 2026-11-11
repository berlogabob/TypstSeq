import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault.dart';

void main() {
  test('failed remote conflict download removes its system temp file', () async {
    final retryDelays = NextcloudSync.busyRetryDelays;
    NextcloudSync.busyRetryDelays = const [];
    addTearDown(() => NextcloudSync.busyRetryDelays = retryDelays);
    const path = 'notes/conflict.typ';
    var etag = '"v1"';
    var rejectGet = false;
    var rejectedGets = 0;
    final remoteBytes = utf8.encode('original');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final relative = Uri.decodeComponent(request.uri.path).split('/').last;
      if (request.method == 'GET' && relative == 'conflict.typ') {
        if (rejectGet) {
          rejectedGets++;
          request.response.statusCode = HttpStatus.internalServerError;
        } else {
          request.response.headers.set(HttpHeaders.etagHeader, etag);
          request.response.add(remoteBytes);
        }
      } else if (request.method == 'MKCOL') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      } else if (request.method == 'PUT') {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(
          '<d:multistatus xmlns:d="DAV:"><d:response>'
          '<d:href>/remote.php/dav/files/alice/TyLogVault/</d:href>'
          '<d:propstat><d:prop><d:getetag>"root"</d:getetag>'
          '<d:resourcetype><d:collection/></d:resourcetype>'
          '</d:prop></d:propstat></d:response><d:response>'
          '<d:href>/remote.php/dav/files/alice/TyLogVault/$path</d:href>'
          '<d:propstat><d:prop><d:getlastmodified>Tue, 01 Jan 2030 00:00:00 GMT</d:getlastmodified>'
          '<d:getetag>$etag</d:getetag><d:getcontentlength>${remoteBytes.length}</d:getcontentlength>'
          '</d:prop></d:propstat></d:response></d:multistatus>',
        );
      } else {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      }
      await request.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('conflict_tmp_cleanup_');
    try {
      final vault = Vault(dir);
      await vault.ensureCreated();
      await vault.storage.writeBytes(path, remoteBytes);
      final config = NextcloudConfig(
        serverUrl:
            'http://${server.address.address}:${server.port}/remote.php/dav/files/alice/TyLogVault',
        username: 'alice',
        password: 'secret',
      );
      await NextcloudSync(config).sync(vault);

      await vault.storage.writeText(path, 'local edit');
      etag = '"v2"';
      rejectGet = true;
      final before = await _conflictTemps();
      try {
        await NextcloudSync(config).sync(vault);
      } catch (_) {
        // A failed conflict snapshot is reported either by the result or error.
      }
      expect(rejectedGets, greaterThan(0));
      expect(await _conflictTemps(), before);
    } finally {
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}

Future<Set<String>> _conflictTemps() async => {
  for (final entity in await Directory.systemTemp.list().toList())
    if (entity is File &&
        entity.uri.pathSegments.last.startsWith('tylog-conflict-'))
      entity.path,
};
