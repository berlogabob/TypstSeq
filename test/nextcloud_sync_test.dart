import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';

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

  test('Nextcloud remote folder is persisted and used', () {
    const config = NextcloudConfig(
      serverUrl: 'https://cloud.example/',
      username: 'alice',
      password: 'secret',
      remoteFolder: 'Research/TyLog',
    );

    final restored = NextcloudConfig.fromJson(config.toJson());
    expect(restored.remoteFolder, 'Research/TyLog');
    expect(
      restored.rootUri.toString(),
      'https://cloud.example/remote.php/dav/files/alice/Research/TyLog/',
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

  test('sync excludes operational state and keeps durable v5 roots', () {
    expect(isSyncInternalPath('_index/index.json'), isTrue);
    expect(isSyncInternalPath('_index/search-index.json.gz'), isTrue);
    expect(isSyncInternalPath('.tylog/settings.json'), isTrue);
    expect(isSyncInternalPath('.tylog/backups/123/notes/a.typ'), isTrue);
    expect(isSyncableVaultPath('_system/tylog.typ'), isTrue);
    expect(isSyncableVaultPath('daily/2026/07/a.typ'), isTrue);
    expect(isSyncableVaultPath('notes/a.typ'), isTrue);
    expect(isSyncableVaultPath('journal/a.typ'), isFalse);
    expect(isSyncInternalPath('notes/a.typ.remote-conflict-1'), isTrue);
    expect(isSyncInternalPath('notes/.a.typ.tylog-12345.backup'), isTrue);
    expect(isSyncInternalPath('daily/2026/07/.x.typ.tylog-9.backup'), isTrue);
    expect(isSyncInternalPath('notes/backup-notes.typ'), isFalse);
    expect(
      isSyncInternalPath(
        '_index/index.json.remote-conflict-1.remote-conflict-2',
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
    final note = File('${dir.path}/daily/2026/07/note.typ');
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
    final note = File('${dir.path}/daily/2026/07/note.typ');
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
    final note = File('${dir.path}/daily/2026/07/note.typ');
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
    final note = File('${dir.path}/daily/2026/07/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('local note');
    await note.setLastModified(DateTime.utc(2030));

    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(await note.readAsString(), 'local note');
    expect(result.conflicts, 1);
    final conflict = (await loadSyncConflicts(vault)).single;
    expect(
      await vault.storage.readText(conflict.remoteSnapshot!),
      'remote note',
    );

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

  test(
    'corrupt sync state preserves differing local and remote copies',
    () async {
      final server = await _webDavServer(remoteContent: 'remote note');
      final dir = await Directory.systemTemp.createTemp('tylog_corrupt_state_');
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      final note = File('${dir.path}/daily/2026/07/note.typ');
      await note.parent.create(recursive: true);
      await note.writeAsString('local note');
      await File('${vault.meta.path}/sync_state.json').writeAsString('{');

      final result = await NextcloudSync(_config(server)).sync(vault);

      expect(result.conflicts, 1);
      expect(await note.readAsString(), 'local note');
      final conflict = (await loadSyncConflicts(vault)).single;
      expect(
        await vault.storage.readText(conflict.remoteSnapshot!),
        'remote note',
      );
      expect(
        await vault.meta
            .list()
            .where((file) => file.path.contains('sync_state.corrupt-'))
            .length,
        1,
      );
      expect(
        jsonDecode(
          await File('${vault.meta.path}/sync_state.json').readAsString(),
        ),
        isA<Map>(),
      );
      expect(
        await File('${vault.meta.path}/sync_state.json.tmp').exists(),
        isFalse,
      );
    },
  );

  test(
    'corrupt sync state repairs identical copies without conflict',
    () async {
      final server = await _webDavServer(remoteContent: 'same note');
      final dir = await Directory.systemTemp.createTemp('tylog_corrupt_same_');
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      final note = File('${dir.path}/daily/2026/07/note.typ');
      await note.parent.create(recursive: true);
      await note.writeAsString('same note');
      await File('${vault.meta.path}/sync_state.json').writeAsString('{');

      final result = await NextcloudSync(_config(server)).sync(vault);

      expect(result.conflicts, 0);
      expect(result.repaired, greaterThanOrEqualTo(1));
      expect(
        await note.parent
            .list()
            .where((file) => file.path.contains('.remote-conflict-'))
            .isEmpty,
        isTrue,
      );
    },
  );

  for (final state in {
    'missing schema': '{}',
    'wrong cursors type': '{"cursors":[]}',
    'malformed cursor':
        '{"cursors":{"daily/2026/07/note.typ":{"localMillis":"bad"}}}',
  }.entries) {
    test('invalid sync state (${state.key}) enters recovery', () async {
      final server = await _webDavServer();
      final dir = await Directory.systemTemp.createTemp('tylog_bad_schema_');
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      await File(
        '${vault.meta.path}/sync_state.json',
      ).writeAsString(state.value);

      await NextcloudSync(_config(server)).sync(vault);

      expect(
        await vault.meta
            .list()
            .where((file) => file.path.contains('sync_state.corrupt-'))
            .length,
        1,
      );
      final events = await _traceEvents(vault);
      expect(
        events.map((event) => event['event']),
        contains('state-recovered'),
      );
    });
  }

  test('failed recovery keeps corrupt state for the next retry', () async {
    final broken = await _webDavServer(
      interrupted: true,
      remoteContent: 'remote note',
    );
    final dir = await Directory.systemTemp.createTemp('tylog_retry_recovery_');
    HttpServer? healthy;
    addTearDown(() async {
      await broken.close(force: true);
      await healthy?.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = File('${dir.path}/daily/2026/07/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('local note');
    final state = File('${vault.meta.path}/sync_state.json');
    await state.writeAsString('{');

    await expectLater(
      NextcloudSync(_config(broken)).sync(vault),
      throwsA(anything),
    );
    expect(await state.readAsString(), '{');
    expect(
      await vault.meta
          .list()
          .where((file) => file.path.contains('sync_state.corrupt-'))
          .length,
      1,
    );

    await broken.close(force: true);
    healthy = await _webDavServer(remoteContent: 'remote note');
    final result = await NextcloudSync(_config(healthy)).sync(vault);

    expect(result.conflicts, 1);
    expect(await note.readAsString(), 'local note');
  });

  test('recovery still transfers files that exist on only one side', () async {
    final remote = <String, _MutableRemoteFile>{
      'daily/2026/07/remote.typ': _MutableRemoteFile(
        bytes: utf8.encode('remote only'),
        etag: '"remote"',
        modified: DateTime.utc(2030),
      ),
    };
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_recovery_sides_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final local = File('${dir.path}/notes/local.typ');
    await local.parent.create(recursive: true);
    await local.writeAsString('local only');
    await File('${vault.meta.path}/sync_state.json').writeAsString('{');

    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(result.uploaded, greaterThan(0));
    expect(result.downloaded, greaterThan(0));
    expect(result.conflicts, 0);
    expect(utf8.decode(remote['notes/local.typ']!.bytes), 'local only');
  });

  test('invalid remote metadata reports a WebDAV protocol error', () async {
    final server = await _webDavServer(remoteModifiedValue: 'not-a-date');
    final dir = await Directory.systemTemp.createTemp('tylog_bad_propfind_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    await expectLater(
      NextcloudSync(_config(server)).sync(Vault(dir)),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          contains('PROPFIND invalid file metadata'),
        ),
      ),
    );
    final events = await _traceEvents(Vault(dir));
    expect(events.last['event'], 'failed');
    expect(events.last['stage'], 'list-remote');
    expect(jsonEncode(events), isNot(contains('secret')));
  });

  test('a stalled PROPFIND body times out instead of hanging', () async {
    final originalTimeout = NextcloudSync.propfindBodyTimeout;
    NextcloudSync.propfindBodyTimeout = const Duration(milliseconds: 100);
    addTearDown(() => NextcloudSync.propfindBodyTimeout = originalTimeout);
    final server = await _webDavServer(propfindStalled: true);
    final dir = await Directory.systemTemp.createTemp('tylog_propfind_stall_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    await expectLater(
      NextcloudSync(_config(server)).sync(Vault(dir)),
      throwsA(isA<TimeoutException>()),
    ).timeout(const Duration(seconds: 10));
  });

  test('HTTP 200 HTML is not accepted as an empty WebDAV folder', () async {
    final server = await _webDavServer(
      propfindStatus: HttpStatus.ok,
      propfindBody: '<html>login</html>',
    );
    final dir = await Directory.systemTemp.createTemp('tylog_html_propfind_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    await expectLater(
      NextcloudSync(_config(server)).sync(Vault(dir)),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          contains('PROPFIND unexpected status 200'),
        ),
      ),
    );
  });

  test('sync trace is bounded and never blocks synchronization', () async {
    final server = await _webDavServer(remoteContent: 'remote note');
    final dir = await Directory.systemTemp.createTemp('tylog_trace_limit_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final trace = File('${vault.meta.path}/sync_trace.jsonl');
    final oldLine = '${jsonEncode({'old': List.filled(1024, 'x').join()})}\n';
    await trace.writeAsString(List.filled(600, oldLine).join());

    await NextcloudSync(_config(server)).sync(vault);

    expect(await trace.length(), lessThan(512 * 1024));
    for (final line in await trace.readAsLines()) {
      expect(jsonDecode(line), isA<Map>());
    }

    await trace.delete();
    await Directory(trace.path).create();
    final retry = await NextcloudSync(_config(server)).sync(vault);
    expect(retry.remoteCount, 1);
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
    final note = File('${dir.path}/daily/2026/07/note.typ');
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
      final note = File('${dir.path}/daily/2026/07/note.typ');
      await note.parent.create(recursive: true);
      await note.writeAsString('local old');
      await _seedCursor(vault, note, '"remote-1"');

      final result = await NextcloudSync(_config(server)).sync(vault);

      expect(result.downloaded, 1);
      expect(await note.readAsString(), 'remote changed');
    },
  );

  test('fresh upload is followed by a remote edit download', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_two_way_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = File('${dir.path}/daily/2026/07/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('android edit');

    final first = await NextcloudSync(_config(server)).sync(vault);
    expect(first.uploaded, greaterThan(0));
    expect(
      utf8.decode(remote['daily/2026/07/note.typ']!.bytes),
      'android edit',
    );

    remote['daily/2026/07/note.typ'] = _MutableRemoteFile(
      bytes: utf8.encode('android edit\nmac edit'),
      etag: '"mac-edit"',
      modified: DateTime.now().toUtc().add(const Duration(seconds: 1)),
    );
    final second = await NextcloudSync(_config(server)).sync(vault);

    expect(second.downloaded, 1);
    expect(await note.readAsString(), 'android edit\nmac edit');
  });

  test('unquoted PUT etag does not cause a ping-pong download', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote, unquotedPutEtag: true);
    final dir = await Directory.systemTemp.createTemp('tylog_pingpong_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = File('${dir.path}/daily/2026/07/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('android edit');

    final first = await NextcloudSync(_config(server)).sync(vault);
    expect(first.uploaded, greaterThan(0));

    // Nothing changed remotely. The second sync must settle — not re-download the
    // file we just uploaded merely because the PUT etag was returned unquoted.
    final second = await NextcloudSync(_config(server)).sync(vault);
    expect(second.downloaded, 0);
    expect(second.uploaded, 0);
  });

  test('sync does not depend on a local index cache', () async {
    final server = await _webDavServer(remoteContent: 'remote note');
    final dir = await Directory.systemTemp.createTemp('tylog_no_index_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    final vault = Vault(dir);
    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(result.downloaded, 1);
    expect(
      await File('${dir.path}/daily/2026/07/note.typ').readAsString(),
      'remote note',
    );
  });

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
    final note = File('${dir.path}/daily/2026/07/note.typ');
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

  test('truncated chunked download is never committed', () async {
    final server = await _webDavServer(
      truncatedChunked: true,
      remoteContent: 'full remote note content',
    );
    final dir = await Directory.systemTemp.createTemp('tylog_truncated_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = File('${dir.path}/daily/2026/07/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('keep local');
    await note.setLastModified(DateTime.utc(2020));

    await expectLater(
      NextcloudSync(_config(server)).sync(vault, trigger: 'test'),
      throwsA(anything),
    );

    expect(await note.readAsString(), 'keep local');
  });

  test('local deletion removes an unchanged remote file', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_delete_remote_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/delete.typ', 'delete me');
    await NextcloudSync(_config(server)).sync(vault);

    await vault.storage.delete('notes/delete.typ');
    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(result.deletedRemote, 1);
    expect(remote.containsKey('notes/delete.typ'), isFalse);
  });

  test('empty local vault listing cannot wipe remote files', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_empty_local_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/keep.typ', 'keep remote');
    await NextcloudSync(_config(server)).sync(vault);

    for (final path in const [
      'daily',
      'notes',
      'projects',
      'articles',
      'assets',
      'outputs',
      '_system',
    ]) {
      final root = Directory('${dir.path}/$path');
      if (await root.exists()) await root.delete(recursive: true);
    }

    await expectLater(
      NextcloudSync(_config(server)).sync(vault),
      throwsStateError,
    );
    expect(utf8.decode(remote['notes/keep.typ']!.bytes), 'keep remote');
  });

  test('unchanged files are not re-hashed on the next sync', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_fastpath_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final storage = _HashCountingStorage(dir);
    final vault = Vault.withStorage(storage);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/a.typ', 'note a');
    await vault.storage.writeText('notes/b.typ', 'note b');
    await NextcloudSync(_config(server)).sync(vault);

    storage.hashCalls = 0;
    final second = await NextcloudSync(_config(server)).sync(vault);

    expect(second.uploaded, 0);
    expect(second.downloaded, 0);
    expect(second.conflicts, 0);
    expect(storage.hashCalls, 0);
  });

  test('mass local disappearance does not wipe remote files', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_mass_delete_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    for (var i = 0; i < 20; i++) {
      await vault.storage.writeText('notes/note$i.typ', 'note $i');
    }
    await NextcloudSync(_config(server)).sync(vault);

    // Simulates a flaky listing (or accidental bulk removal): most files gone
    // locally while the remote is unchanged.
    for (var i = 0; i < 15; i++) {
      await vault.storage.delete('notes/note$i.typ');
    }

    await expectLater(
      NextcloudSync(_config(server)).sync(vault),
      throwsStateError,
    );
    for (var i = 0; i < 20; i++) {
      expect(remote.containsKey('notes/note$i.typ'), isTrue);
    }
  });

  test('remote absence restores the authoritative local file', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_delete_local_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/delete.typ', 'delete me');
    await NextcloudSync(_config(server)).sync(vault);

    remote.remove('notes/delete.typ');
    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(result.uploaded, 1);
    expect(await vault.storage.readText('notes/delete.typ'), 'delete me');
    expect(utf8.decode(remote['notes/delete.typ']!.bytes), 'delete me');
  });

  test('remote edit cannot replace a note edited during sync', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_edit_guard_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/editing.typ', 'saved text');
    await NextcloudSync(_config(server)).sync(vault);
    remote['notes/editing.typ'] = _MutableRemoteFile(
      bytes: utf8.encode('remote edit'),
      etag: '"remote-edit"',
      modified: DateTime.now().toUtc().add(const Duration(seconds: 1)),
    );

    await expectLater(
      NextcloudSync(_config(server), canReplaceLocal: (_) => false).sync(vault),
      throwsA(isA<SyncDeferred>()),
    );

    expect(await vault.storage.readText('notes/editing.typ'), 'saved text');
  });

  test('delete versus edit creates a structured conflict', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_delete_conflict_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/delete.typ', 'original');
    await NextcloudSync(_config(server)).sync(vault);

    await vault.storage.delete('notes/delete.typ');
    remote['notes/delete.typ'] = _MutableRemoteFile(
      bytes: utf8.encode('remote edit'),
      etag: '"remote-edit"',
      modified: DateTime.now().toUtc(),
    );
    final result = await NextcloudSync(_config(server)).sync(vault);
    final conflict = (await loadSyncConflicts(
      vault,
    )).singleWhere((item) => item.path == 'notes/delete.typ');

    expect(result.conflicts, 1);
    expect(conflict.localExists, isFalse);
    expect(conflict.remoteExists, isTrue);
    expect(
      await vault.storage.readText(conflict.remoteSnapshot!),
      'remote edit',
    );
  });

  test('HTTP 412 during remote deletion becomes a conflict', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote, rejectDelete: true);
    final dir = await Directory.systemTemp.createTemp('tylog_delete_412_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/delete.typ', 'original');
    await NextcloudSync(_config(server)).sync(vault);

    await vault.storage.delete('notes/delete.typ');
    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(result.conflicts, 1);
    expect(
      (await loadSyncConflicts(
        vault,
      )).any((item) => item.path == 'notes/delete.typ'),
      isTrue,
    );
  });

  test('binary conflicts remain binary and preserve both snapshots', () async {
    final remote = <String, _MutableRemoteFile>{
      'assets/data.bin': _MutableRemoteFile(
        bytes: const [4, 5, 6],
        etag: '"remote"',
        modified: DateTime.now().toUtc(),
      ),
    };
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_binary_conflict_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeBytes('assets/data.bin', [1, 2, 3]);

    await NextcloudSync(_config(server)).sync(vault);
    final conflict = (await loadSyncConflicts(
      vault,
    )).singleWhere((item) => item.path == 'assets/data.bin');

    expect(conflict.isText, isFalse);
    expect(await vault.storage.readBytes(conflict.localSnapshot!), [1, 2, 3]);
    expect(await vault.storage.readBytes(conflict.remoteSnapshot!), [4, 5, 6]);

    await NextcloudSync(
      _config(server),
    ).resolveConflict(vault, conflict, SyncConflictResolution.keepRemote);
    expect(await vault.storage.readBytes('assets/data.bin'), [4, 5, 6]);
    expect(await loadSyncConflicts(vault), isEmpty);
  });

  test('keep local resolves with edits made after the conflict', () async {
    final remote = <String, _MutableRemoteFile>{
      'notes/live.typ': _MutableRemoteFile(
        bytes: utf8.encode('remote note'),
        etag: '"remote"',
        modified: DateTime.now().toUtc(),
      ),
    };
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_live_conflict_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/live.typ', 'original local');
    await createSyncConflict(
      vault,
      'notes/live.typ',
      localBytes: utf8.encode('original local'),
      remoteBytes: utf8.encode('remote note'),
    );
    final conflict = (await loadSyncConflicts(vault)).single;
    await vault.storage.writeText('notes/live.typ', 'updated local');

    await NextcloudSync(
      _config(server),
    ).resolveConflict(vault, conflict, SyncConflictResolution.keepLocal);

    expect(await vault.storage.readText('notes/live.typ'), 'updated local');
    expect(utf8.decode(remote['notes/live.typ']!.bytes), 'updated local');
    expect(await loadSyncConflicts(vault), isEmpty);
  });

  test('nested configured folders are created one segment at a time', () async {
    final created = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.method == 'MKCOL') created.add(request.uri.path);
      request.response.statusCode = request.method == 'PROPFIND' ? 207 : 201;
      if (request.method == 'PROPFIND') {
        request.response.write('<d:multistatus xmlns:d="DAV:"/>');
      }
      await request.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('tylog_nested_remote_');
    addTearDown(() => dir.delete(recursive: true));
    final config = NextcloudConfig(
      serverUrl: 'http://${server.address.address}:${server.port}',
      username: 'alice',
      password: 'secret',
      remoteFolder: 'Research/TyLog',
    );

    await NextcloudSync(config).sync(Vault(dir));

    expect(created.take(2), [
      '/remote.php/dav/files/alice/Research/',
      '/remote.php/dav/files/alice/Research/TyLog/',
    ]);
  });
}

NextcloudConfig _config(HttpServer server) => NextcloudConfig(
  serverUrl:
      'http://${server.address.address}:${server.port}/remote.php/dav/files/alice/TyLogVault',
  username: 'alice',
  password: 'secret',
);

class _HashCountingStorage extends LocalVaultStorage {
  _HashCountingStorage(super.root);

  int hashCalls = 0;

  @override
  Future<String> hash(String path) {
    hashCalls++;
    return super.hash(path);
  }
}

Future<List<Map<String, Object?>>> _traceEvents(Vault vault) async =>
    (await File('${vault.meta.path}/sync_trace.jsonl').readAsLines())
        .map((line) => (jsonDecode(line) as Map).cast<String, Object?>())
        .toList();

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
  bool truncatedChunked = false,
  bool propfindStalled = false,
  String remoteContent = '',
  DateTime? remoteModified,
  String? remoteModifiedValue,
  String etag = '"remote-1"',
  int putStatus = HttpStatus.created,
  List<Map<String, Object?>>? uploads,
  int propfindStatus = 207,
  String? propfindBody,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.method == 'MKCOL') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
    } else if (request.method == 'PROPFIND') {
      if (propfindStalled) {
        // Accept the request and commit the headers, then never write (or
        // close) the body: simulates a provider that stalls mid-response.
        request.response.statusCode = propfindStatus;
        request.response.headers.contentLength = 1 << 20;
        await request.response.detachSocket(writeHeaders: true);
        return;
      }
      request.response.statusCode = propfindStatus;
      request.response.write(
        propfindBody ??
            '<d:multistatus xmlns:d="DAV:"><d:response>'
                '<d:href>/remote.php/dav/files/alice/TyLogVault/daily/2026/07/note.typ</d:href>'
                '<d:propstat><d:prop><d:getlastmodified>'
                '${remoteModifiedValue ?? HttpDate.format(remoteModified ?? DateTime.utc(2030))}'
                '</d:getlastmodified><d:getetag>$etag</d:getetag>'
                '<d:getcontentlength>${utf8.encode(remoteContent).length}</d:getcontentlength>'
                '</d:prop></d:propstat>'
                '</d:response></d:multistatus>',
      );
    } else if (request.method == 'GET') {
      request.response.headers.set(HttpHeaders.etagHeader, etag);
      if (truncatedChunked) {
        // Chunked body that terminates cleanly but is shorter than the real
        // content; only the checksum header exposes the truncation.
        request.response.headers.set(
          'X-Hash-SHA256',
          sha256.convert(utf8.encode(remoteContent)).toString(),
        );
        request.response.write(
          remoteContent.substring(0, remoteContent.length ~/ 2),
        );
        await request.response.close();
        return;
      }
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
      final status = request.uri.path.endsWith('/daily/2026/07/note.typ')
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

class _MutableRemoteFile {
  const _MutableRemoteFile({
    required this.bytes,
    required this.etag,
    required this.modified,
  });

  final List<int> bytes;
  final String etag;
  final DateTime modified;
}

Future<HttpServer> _mutableWebDavServer(
  Map<String, _MutableRemoteFile> files, {
  bool unquotedPutEtag = false,
  bool rejectDelete = false,
}) async {
  const root = '/remote.php/dav/files/alice/TyLogVault/';
  var version = 0;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path.startsWith(root)
        ? request.uri.path.substring(root.length)
        : '';
    if (request.method == 'MKCOL') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
    } else if (request.method == 'PROPFIND') {
      request.response.statusCode = 207;
      request.response.write('<d:multistatus xmlns:d="DAV:">');
      for (final entry in files.entries) {
        request.response.write(
          '<d:response><d:href>$root${entry.key}</d:href>'
          '<d:propstat><d:prop><d:getlastmodified>'
          '${HttpDate.format(entry.value.modified)}'
          '</d:getlastmodified><d:getetag>${entry.value.etag}</d:getetag>'
          '<d:getcontentlength>${entry.value.bytes.length}</d:getcontentlength>'
          '</d:prop></d:propstat></d:response>',
        );
      }
      request.response.write('</d:multistatus>');
    } else if (request.method == 'GET') {
      final file = files[path];
      if (file == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.headers.set(HttpHeaders.etagHeader, file.etag);
        request.response.add(file.bytes);
      }
    } else if (request.method == 'PUT') {
      final bytes = await request.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      final etag = '"upload-${version++}"';
      files[path] = _MutableRemoteFile(
        bytes: bytes,
        etag: etag,
        modified: DateTime.now().toUtc(),
      );
      request.response.statusCode = HttpStatus.created;
      // Real Nextcloud sends OC-Etag unquoted while PROPFIND getetag is quoted.
      request.response.headers.set(
        'OC-Etag',
        unquotedPutEtag ? etag.replaceAll('"', '') : etag,
      );
      request.response.headers.set('X-Hash-SHA256', sha256.convert(bytes));
    } else if (request.method == 'DELETE') {
      if (rejectDelete) {
        request.response.statusCode = HttpStatus.preconditionFailed;
      } else {
        files.remove(path);
        request.response.statusCode = HttpStatus.noContent;
      }
    }
    await request.response.close();
  });
  return server;
}
