import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

  test('empty remote note is repaired from the local note', () async {
    final uploads = <Map<String, Object?>>[];
    final server = await _webDavServer(uploads: uploads);
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
    expect(result.conflicts, 0);
    expect(result.uploaded, greaterThanOrEqualTo(1));
    expect(result.repaired, 1);
    expect(
      await note.parent
          .list()
          .where((file) => file.path.contains('.remote-conflict-'))
          .length,
      0,
    );
    final noteUpload = uploads.singleWhere(
      (upload) => upload['body'] == 'keep local',
    );
    expect(noteUpload['contentLength'], 10);
    expect(noteUpload['ifMatch'], '"remote-1"');
    expect(noteUpload['xHash'], 'sha256');
  });

  test('identical local and remote changes do not create a conflict', () async {
    final server = await _webDavServer(
      remoteContent: 'same note',
      remoteModified: DateTime.utc(2025),
    );
    final dir = await Directory.systemTemp.createTemp('tylog_same_content_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = File('${dir.path}/journal/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('same note');
    await note.setLastModified(DateTime.utc(2025));

    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(result.conflicts, 0);
    expect(result.repaired, 1);
    expect(
      await note.parent
          .list()
          .where((file) => file.path.contains('.remote-conflict-'))
          .isEmpty,
      isTrue,
    );
  });

  test('legacy identical and empty conflict copies are cleaned', () async {
    final server = await _webDavServer(remoteContent: 'keep note');
    final dir = await Directory.systemTemp.createTemp('tylog_old_conflicts_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = File('${dir.path}/journal/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('keep note');
    await File('${note.path}.remote-conflict-1').writeAsString('keep note');
    await File('${note.path}.remote-conflict-2').writeAsString('');

    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(result.repaired, greaterThanOrEqualTo(2));
    expect(
      await note.parent
          .list()
          .where((file) => file.path.contains('.remote-conflict-'))
          .isEmpty,
      isTrue,
    );
  });

  test('HTTP 412 preserves local and remote versions', () async {
    final server = await _webDavServer(
      remoteContent: 'remote note',
      remoteModified: DateTime.utc(2020),
      putStatus: HttpStatus.preconditionFailed,
    );
    final dir = await Directory.systemTemp.createTemp('tylog_precondition_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = File('${dir.path}/journal/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('local note');
    await note.setLastModified(DateTime.utc(2030));

    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(await note.readAsString(), 'local note');
    expect(result.conflicts, 1);
    final conflict =
        await note.parent
                .list()
                .where((file) => file.path.contains('.remote-conflict-'))
                .single
            as File;
    expect(await conflict.readAsString(), 'remote note');

    final retry = await NextcloudSync(_config(server)).sync(vault);
    expect(retry.downloaded, 0);
    expect(await note.readAsString(), 'local note');
  });

  test('sync cursor reads old state and persists content identity', () {
    final old = SyncCursor.fromJson({'localMillis': 1, 'remoteMillis': 2});
    expect(old.localSha256, isNull);
    expect(old.remoteEtag, isNull);

    const current = SyncCursor(
      localMillis: 1,
      remoteMillis: 2,
      localSha256: 'abc',
      remoteEtag: '"etag"',
    );
    expect(current.toJson()['localSha256'], 'abc');
    expect(current.toJson()['remoteEtag'], '"etag"');
  });

  test('touching unchanged content does not create a conflict', () async {
    final server = await _webDavServer(remoteContent: 'same note');
    final dir = await Directory.systemTemp.createTemp('tylog_touch_only_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = File('${dir.path}/journal/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('same note');
    await _seedCursor(vault, note, '"remote-1"');
    await note.setLastModified(DateTime.utc(2040));

    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(result.conflicts, 0);
    expect(await note.readAsString(), 'same note');
  });

  test(
    'changed ETag with unchanged local hash downloads remote content',
    () async {
      final server = await _webDavServer(
        remoteContent: 'remote changed',
        etag: '"remote-2"',
      );
      final dir = await Directory.systemTemp.createTemp('tylog_etag_');
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      final note = File('${dir.path}/journal/note.typ');
      await note.parent.create(recursive: true);
      await note.writeAsString('local old');
      await _seedCursor(vault, note, '"remote-1"');

      final result = await NextcloudSync(_config(server)).sync(vault);

      expect(result.downloaded, 1);
      expect(await note.readAsString(), 'remote changed');
    },
  );

  test('interrupted download leaves the original note untouched', () async {
    final server = await _webDavServer(
      interrupted: true,
      remoteContent: 'remote note',
    );
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

Future<void> _seedCursor(Vault vault, File note, String remoteEtag) async {
  final hash = sha256.convert(await note.readAsBytes()).toString();
  await File('${vault.meta.path}/sync_state.json').writeAsString(
    jsonEncode({
      'cursors': {
        vault.relativePath(note): {
          'localMillis': (await note.lastModified()).millisecondsSinceEpoch,
          'remoteMillis': DateTime.utc(2030).millisecondsSinceEpoch,
          'localSha256': hash,
          'remoteEtag': remoteEtag,
        },
      },
    }),
  );
}

Future<HttpServer> _webDavServer({
  bool interrupted = false,
  String remoteContent = '',
  DateTime? remoteModified,
  String etag = '"remote-1"',
  int putStatus = HttpStatus.created,
  List<Map<String, Object?>>? uploads,
}) async {
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
        '${HttpDate.format(remoteModified ?? DateTime.utc(2030))}'
        '</d:getlastmodified><d:getetag>$etag</d:getetag>'
        '<d:getcontentlength>${utf8.encode(remoteContent).length}</d:getcontentlength>'
        '</d:prop></d:propstat>'
        '</d:response></d:multistatus>',
      );
    } else if (request.method == 'GET') {
      request.response.headers.set(HttpHeaders.etagHeader, etag);
      if (interrupted) {
        request.response.contentLength = 100;
        final socket = await request.response.detachSocket(writeHeaders: true);
        socket.add([1, 2, 3]);
        await socket.flush();
        socket.destroy();
        return;
      }
      request.response.write(remoteContent);
    } else if (request.method == 'PUT') {
      final body = await request.fold<List<int>>(
        [],
        (all, bytes) => all..addAll(bytes),
      );
      uploads?.add({
        'body': utf8.decode(body),
        'contentLength': request.contentLength,
        'ifMatch': request.headers.value(HttpHeaders.ifMatchHeader),
        'ifNoneMatch': request.headers.value(HttpHeaders.ifNoneMatchHeader),
        'xHash': request.headers.value('x-hash'),
      });
      final status = request.uri.path.endsWith('/journal/note.typ')
          ? putStatus
          : HttpStatus.created;
      request.response.statusCode = status;
      if (status < 400) {
        request.response.headers.set('OC-Etag', '"uploaded-1"');
        request.response.headers.set('X-Hash-SHA256', sha256.convert(body));
      }
    }
    await request.response.close();
  });
  return server;
}
