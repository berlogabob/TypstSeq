import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault.dart';

void main() {
  test('Nextcloud config accepts local debug secret schema', () {
    final config = NextcloudConfig.fromJson({
      'url': 'https://cloud.example/',
      'username': 'alice',
      'password': 'secret',
    });

    expect(config.serverUrl, 'https://cloud.example/');
    expect(config.rootUri.toString(), contains('/remote.php/dav/files/alice/'));
  });

  test('Nextcloud root URL uses embedded WebDAV endpoint', () {
    const config = NextcloudConfig(
      serverUrl: 'https://cloud.example/',
      username: 'alice',
      password: 'secret',
    );

    expect(
      config.rootUri.toString(),
      'https://cloud.example/remote.php/dav/files/alice/TyLogVault/',
    );
  });

  test('Nextcloud direct WebDAV URL is accepted', () {
    const config = NextcloudConfig(
      serverUrl: 'https://cloud.example/remote.php/dav/files/alice/TyLogVault',
      username: 'alice',
      password: 'secret',
    );

    expect(
      config.rootUri.toString(),
      'https://cloud.example/remote.php/dav/files/alice/TyLogVault/',
    );
  });

  test('sync action prefers conflict when both changed', () {
    expect(
      decideSyncAction(
        localExists: true,
        remoteExists: true,
        localChanged: true,
        remoteChanged: true,
      ),
      SyncAction.conflict,
    );
  });

  test('sync action covers one-sided updates and missing files', () {
    expect(
      decideSyncAction(
        localExists: false,
        remoteExists: true,
        localChanged: false,
        remoteChanged: true,
      ),
      SyncAction.download,
    );
    expect(
      decideSyncAction(
        localExists: true,
        remoteExists: false,
        localChanged: true,
        remoteChanged: false,
      ),
      SyncAction.upload,
    );
    expect(
      decideSyncAction(
        localExists: true,
        remoteExists: true,
        localChanged: false,
        remoteChanged: false,
      ),
      SyncAction.skip,
    );
  });

  test('sync excludes derived caches but keeps durable PKMS registries', () {
    expect(isSyncInternalPath('.tylog/index.json'), isTrue);
    expect(isSyncInternalPath('.tylog/search-index.json.gz'), isTrue);
    expect(isSyncInternalPath('.tylog/tylog.typ'), isTrue);
    expect(isSyncInternalPath('.tylog/backups/123/pages/a.typ'), isTrue);
    expect(isSyncInternalPath('.tylog/tags.json'), isFalse);
    expect(isSyncInternalPath('.tylog/files.json'), isFalse);
    expect(isSyncInternalPath('.tylog/collections.json'), isFalse);
    expect(isSyncInternalPath('.tylog/templates/article.typ'), isFalse);
    expect(isSyncInternalPath('pages/a.typ.remote-conflict-1'), isTrue);
    expect(
      isSyncInternalPath(
        '.tylog/index.json.remote-conflict-1.remote-conflict-2',
      ),
      isTrue,
    );
  });

  test('embedded sync yields to a desktop-managed Nextcloud folder', () {
    expect(
      isNextcloudManagedVault(
        Directory('/home/alice/Nextcloud/TyLogVault'),
        environment: {'HOME': '/home/alice'},
        desktop: true,
      ),
      isTrue,
    );
    expect(
      isNextcloudManagedVault(
        Directory('/data/TyLogVault'),
        environment: {'HOME': '/home/alice'},
        desktop: true,
      ),
      isFalse,
    );
    expect(
      isNextcloudManagedVault(
        Directory('/home/alice/Nextcloud/TyLogVault'),
        environment: {'HOME': '/home/alice'},
        desktop: false,
      ),
      isFalse,
    );
  });

  test(
    'empty remote note is preserved as a conflict, not an overwrite',
    () async {
      final server = await _webDavServer();
      final dir = await Directory.systemTemp.createTemp('tylog_empty_remote_');
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      final note = File('${dir.path}/journal/note.typ');
      await note.parent.create(recursive: true);
      await note.writeAsString('keep local');
      await note.setLastModified(DateTime.utc(2020));

      final result = await NextcloudSync(
        _config(server),
      ).sync(vault, trigger: 'test');

      expect(await note.readAsString(), 'keep local');
      expect(result, contains('!1'));
      expect(
        await note.parent
            .list()
            .where((file) => file.path.contains('.remote-conflict-'))
            .length,
        1,
      );
    },
  );

  test('interrupted download leaves the original note untouched', () async {
    final server = await _webDavServer(interrupted: true);
    final dir = await Directory.systemTemp.createTemp('tylog_broken_remote_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = File('${dir.path}/journal/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('keep local');
    await note.setLastModified(DateTime.utc(2020));

    await expectLater(
      NextcloudSync(_config(server)).sync(vault, trigger: 'test'),
      throwsA(anything),
    );

    expect(await note.readAsString(), 'keep local');
    expect(
      await note.parent
          .list()
          .where((file) => file.path.contains('.download-'))
          .isEmpty,
      isTrue,
    );
  });
}

NextcloudConfig _config(HttpServer server) => NextcloudConfig(
  serverUrl:
      'http://${server.address.address}:${server.port}/remote.php/dav/files/alice/TyLogVault',
  username: 'alice',
  password: 'secret',
);

Future<HttpServer> _webDavServer({bool interrupted = false}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.method == 'MKCOL') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
    } else if (request.method == 'PROPFIND') {
      request.response.statusCode = 207;
      request.response.write(
        '<d:multistatus xmlns:d="DAV:"><d:response>'
        '<d:href>/remote.php/dav/files/alice/TyLogVault/journal/note.typ</d:href>'
        '<d:propstat><d:prop><d:getlastmodified>'
        '${HttpDate.format(DateTime.utc(2030))}'
        '</d:getlastmodified></d:prop></d:propstat>'
        '</d:response></d:multistatus>',
      );
    } else if (request.method == 'GET') {
      if (interrupted) {
        request.response.contentLength = 100;
        final socket = await request.response.detachSocket(writeHeaders: true);
        socket.add([1, 2, 3]);
        await socket.flush();
        socket.destroy();
        return;
      }
    } else if (request.method == 'PUT') {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.created;
    }
    await request.response.close();
  });
  return server;
}
