import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  final defaultRetryDelays = NextcloudSync.connectionRetryDelays;
  final defaultCheckpointInterval = NextcloudSync.checkpointInterval;
  // Zero-delay single retry keeps failure-path tests fast while still
  // exercising the transient-retry logic.
  setUp(() {
    NextcloudSync.connectionRetryDelays = const [Duration.zero];
    // Checkpointing is time-throttled in production, and these fixtures sync a
    // handful of files against a local server in well under one interval — so
    // without this no mid-loop checkpoint would ever fire and the resume tests
    // would be exercising only the error-path save.
    NextcloudSync.checkpointInterval = Duration.zero;
  });
  tearDown(() {
    NextcloudSync.connectionRetryDelays = defaultRetryDelays;
    NextcloudSync.checkpointInterval = defaultCheckpointInterval;
  });

  test('no-change sync skips the local index rebuild', () {
    const unchanged = SyncResult(
      trigger: 'poll',
      uploaded: 0,
      downloaded: 0,
      skipped: 21,
      conflicts: 0,
      remoteCount: 21,
    );
    const downloaded = SyncResult(
      trigger: 'poll',
      uploaded: 0,
      downloaded: 1,
      skipped: 20,
      conflicts: 0,
      remoteCount: 21,
    );

    expect(unchanged.requiresIndexRefresh, isFalse);
    expect(downloaded.requiresIndexRefresh, isTrue);
  });

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

  test('initial setup maps all local and cloud combinations', () {
    expect(
      initialSyncModeFor(localHasData: false, remoteHasData: false),
      InitialSyncMode.safeMerge,
    );
    expect(
      initialSyncModeFor(localHasData: true, remoteHasData: false),
      InitialSyncMode.uploadLocal,
    );
    expect(
      initialSyncModeFor(localHasData: false, remoteHasData: true),
      InitialSyncMode.downloadRemote,
    );
    expect(
      initialSyncModeFor(localHasData: true, remoteHasData: true),
      InitialSyncMode.safeMerge,
    );
  });

  test(
    'setup inspection distinguishes local and remote vault states',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_preflight_');
      final remote = <String, _MutableRemoteFile>{};
      final server = await _mutableWebDavServer(remote);
      final missingServer = await _missingWebDavServer();
      addTearDown(() async {
        await server.close(force: true);
        await missingServer.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      final starter = await vault.todayNote(DateTime(2026, 7, 14));

      final pristine = await inspectLocalSync(vault);
      expect(pristine.hasUserContent, isFalse);
      expect(pristine.pristineStarterPaths, [starter]);
      expect(
        (await NextcloudSync(_config(missingServer)).inspectRemoteVault()).kind,
        RemoteVaultKind.missing,
      );
      expect(
        (await NextcloudSync(_config(server)).inspectRemoteVault()).kind,
        RemoteVaultKind.empty,
      );

      remote['other.txt'] = _remoteText('unrelated');
      expect(
        (await NextcloudSync(_config(server)).inspectRemoteVault()).kind,
        RemoteVaultKind.nonVault,
      );

      remote
        ..clear()
        ..['_system/tylog.typ'] = _remoteText('helper')
        ..['notes/cloud.typ'] = _remoteText('cloud note');
      final valid = await NextcloudSync(_config(server)).inspectRemoteVault();
      expect(valid.kind, RemoteVaultKind.validVault);
      expect(valid.userFileCount, 1);

      await vault.storage.writeText(starter, 'edited starter');
      expect((await inspectLocalSync(vault)).userFileCount, 1);
    },
  );

  test(
    'initial sync modes cover the four local and cloud combinations',
    () async {
      Future<({Vault vault, Directory dir, String starter})> freshVault(
        String name,
      ) async {
        final dir = await Directory.systemTemp.createTemp(name);
        final vault = Vault(dir);
        await vault.ensureCreated();
        final starter = await vault.todayNote(DateTime(2026, 7, 14));
        return (vault: vault, dir: dir, starter: starter);
      }

      final empty = await freshVault('tylog_initial_empty_');
      final emptyRemote = <String, _MutableRemoteFile>{};
      final emptyServer = await _mutableWebDavServer(emptyRemote);
      final localOnly = await freshVault('tylog_initial_upload_');
      await localOnly.vault.storage.writeText('notes/local.typ', 'local note');
      final uploadRemote = <String, _MutableRemoteFile>{
        '_system/tylog.typ': _remoteBytes(
          await localOnly.vault.storage.readBytes('_system/tylog.typ'),
        ),
      };
      final uploadServer = await _mutableWebDavServer(uploadRemote);
      final cloudOnly = await freshVault('tylog_initial_download_');
      final helper = await cloudOnly.vault.storage.readBytes(
        '_system/tylog.typ',
      );
      final downloadRemote = <String, _MutableRemoteFile>{
        '_system/tylog.typ': _remoteBytes(helper),
        'notes/cloud.typ': _remoteText('cloud note'),
      };
      final downloadServer = await _mutableWebDavServer(downloadRemote);
      final both = await freshVault('tylog_initial_merge_');
      await both.vault.storage.writeText('notes/local.typ', 'local only');
      await both.vault.storage.writeText('notes/both.typ', 'local version');
      final mergeHelper = await both.vault.storage.readBytes(
        '_system/tylog.typ',
      );
      final mergeRemote = <String, _MutableRemoteFile>{
        '_system/tylog.typ': _remoteBytes(mergeHelper),
        'notes/cloud.typ': _remoteText('cloud only'),
        'notes/both.typ': _remoteText('cloud version'),
      };
      final mergeServer = await _mutableWebDavServer(mergeRemote);
      addTearDown(() async {
        for (final server in [
          emptyServer,
          uploadServer,
          downloadServer,
          mergeServer,
        ]) {
          await server.close(force: true);
        }
        for (final dir in [empty.dir, localOnly.dir, cloudOnly.dir, both.dir]) {
          await dir.delete(recursive: true);
        }
      });

      final created = await NextcloudSync(
        _config(emptyServer),
      ).sync(empty.vault, initialMode: InitialSyncMode.safeMerge);
      expect(created.deletedLocal + created.deletedRemote, 0);
      expect(emptyRemote, contains('_system/tylog.typ'));

      final uploaded = await NextcloudSync(
        _config(uploadServer),
      ).sync(localOnly.vault, initialMode: InitialSyncMode.uploadLocal);
      expect(uploaded.deletedLocal + uploaded.deletedRemote, 0);
      expect(utf8.decode(uploadRemote['notes/local.typ']!.bytes), 'local note');

      final downloaded = await NextcloudSync(
        _config(downloadServer),
      ).sync(cloudOnly.vault, initialMode: InitialSyncMode.downloadRemote);
      expect(downloaded.deletedRemote, 0);
      expect(
        await cloudOnly.vault.storage.readText('notes/cloud.typ'),
        'cloud note',
      );
      expect(await cloudOnly.vault.storage.exists(cloudOnly.starter), isFalse);

      final merged = await NextcloudSync(
        _config(mergeServer),
      ).sync(both.vault, initialMode: InitialSyncMode.safeMerge);
      expect(merged.conflicts, 1);
      expect(merged.deletedLocal + merged.deletedRemote, 0);
      expect(
        await both.vault.storage.readText('notes/cloud.typ'),
        'cloud only',
      );
      expect(utf8.decode(mergeRemote['notes/local.typ']!.bytes), 'local only');
      expect(
        (await loadSyncConflicts(both.vault)).single.path,
        'notes/both.typ',
      );
    },
  );

  test(
    'checkpoint cadence is time-bound, not per-file',
    () async {
      // A checkpoint re-encodes every cursor, so a per-N-files trigger scales
      // with vault size squared: on a real 2061-path vault the old `% 10` gate
      // fired 206 times at 38 ms each on a P30 — 2.75 s of blocked isolate and
      // ~110 MB written. With a wall-clock interval the count is bounded by run
      // duration instead, so a bigger vault costs no extra checkpoints.
      //
      // This run transfers 30 files against a local server in well under one
      // interval, so a correct implementation checkpoints mid-loop zero times;
      // the per-file version would have managed three.
      NextcloudSync.checkpointInterval = const Duration(minutes: 5);
      final remote = <String, _MutableRemoteFile>{
        '_system/tylog.typ': _remoteText('helper'),
        for (var index = 0; index < 30; index++)
          'notes/${index.toString().padLeft(2, '0')}.typ': _remoteText(
            'remote $index',
          ),
      };
      final server = await _mutableWebDavServer(remote);
      final dir = await Directory.systemTemp.createTemp('tylog_cadence_');
      final storage = _CheckpointCountingStorage(dir);
      final vault = Vault.withStorage(storage);
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      await vault.ensureCreated();

      await NextcloudSync(
        _config(server),
      ).sync(vault, initialMode: InitialSyncMode.downloadRemote);

      // The bootstrap marker plus the single post-loop save. Anything more means
      // the per-file gate is back.
      expect(
        storage.checkpointWrites,
        lessThanOrEqualTo(2),
        reason: 'checkpointing more than twice for 30 files means the cadence '
            'is scaling with file count again',
      );
      // Durability is unaffected: the run still persists every cursor at the end.
      final saved =
          jsonDecode(await vault.storage.readText('.tylog/sync_state.json'))
              as Map<String, Object?>;
      expect((saved['cursors'] as Map).length, greaterThanOrEqualTo(30));
    },
  );

  test(
    'interrupted initial sync checkpoints and resumes completed files',
    () async {
      final remote = <String, _MutableRemoteFile>{
        '_system/tylog.typ': _remoteText('helper'),
        for (var index = 0; index < 14; index++)
          'notes/${index.toString().padLeft(2, '0')}.typ': _remoteText(
            'remote $index',
          ),
      };
      final gets = <String, int>{};
      final server = await _mutableWebDavServer(
        remote,
        interruptGetOnce: 'notes/11.typ',
        getCounts: gets,
      );
      // Disable transient retries so the interruption aborts this run and the
      // checkpoint/resume path is what gets exercised.
      NextcloudSync.connectionRetryDelays = const [];
      final dir = await Directory.systemTemp.createTemp('tylog_checkpoint_');
      final storage = _CheckpointCountingStorage(dir);
      final vault = Vault.withStorage(storage);
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      await vault.ensureCreated();
      await vault.todayNote(DateTime(2026, 7, 14));

      await expectLater(
        NextcloudSync(
          _config(server),
        ).sync(vault, initialMode: InitialSyncMode.downloadRemote),
        throwsA(anything),
      );

      final checkpoint =
          jsonDecode(await vault.storage.readText('.tylog/sync_state.json'))
              as Map<String, Object?>;
      expect(checkpoint['schema'], 2);
      expect(
        checkpoint['remoteKey'],
        isA<String>().having((v) => v.length, 'length', 64),
      );
      expect((checkpoint['cursors'] as Map).length, greaterThanOrEqualTo(10));
      expect(storage.checkpointWrites, greaterThanOrEqualTo(3));

      await NextcloudSync(_config(server)).sync(vault, trigger: 'retry');

      expect(gets['notes/00.typ'], 1);
      expect(gets['notes/10.typ'], 1);
      expect(gets['notes/11.typ'], 2);
      expect(await vault.storage.readText('notes/13.typ'), 'remote 13');
    },
  );

  test(
    'steady-state second sync writes sync_state.json zero times',
    () async {
      // Empty remote: the first sync uploads the vault's own starter
      // content (including the real `_system/tylog.typ`, not a stand-in),
      // so nothing conflicts and the second sync is genuinely steady-state.
      final remote = <String, _MutableRemoteFile>{};
      final server = await _mutableWebDavServer(remote);
      final dir = await Directory.systemTemp.createTemp('tylog_dirty_gate_');
      final storage = _CheckpointCountingStorage(dir);
      final vault = Vault.withStorage(storage);
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      await vault.ensureCreated();
      for (var index = 0; index < 20; index++) {
        await vault.storage.writeText(
          'notes/${index.toString().padLeft(2, '0')}.typ',
          'note $index',
        );
      }

      // The root etag persisted by a full run is captured before that run's
      // own uploads, so the run right after bootstrap is still a full run
      // (self-correcting: it settles on an accurate etag since nothing else
      // changes during it). The run after *that* is the one that can shortcut.
      await NextcloudSync(_config(server)).sync(vault);
      await NextcloudSync(_config(server)).sync(vault, trigger: 'poll');
      storage.checkpointWrites = 0;

      final result = await NextcloudSync(
        _config(server),
      ).sync(vault, trigger: 'poll');

      expect(result.uploaded, 0);
      expect(result.downloaded, 0);
      expect(result.conflicts, 0);
      expect(storage.checkpointWrites, 0);
    },
  );

  test(
    'no-change shortcut probes the root etag instead of listing the tree',
    () async {
      final remote = <String, _MutableRemoteFile>{
        'notes/a.typ': _remoteText('note a'),
      };
      final metrics = _WebDavMetrics();
      final server = await _mutableWebDavServer(remote, metrics: metrics);
      final dir = await Directory.systemTemp.createTemp('tylog_shortcut_noop_');
      final storage = _CheckpointCountingStorage(dir);
      final vault = Vault.withStorage(storage);
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      await vault.ensureCreated();
      // Bootstrap, then one settling run so the persisted root etag reflects
      // the bootstrap's own uploads (see comment in the checkpoint test above).
      await NextcloudSync(_config(server)).sync(vault);
      await NextcloudSync(_config(server)).sync(vault, trigger: 'poll');

      metrics
        ..depthZeroPropfinds = 0
        ..depthInfinityPropfinds = 0;
      storage.checkpointWrites = 0;

      final result = await NextcloudSync(
        _config(server),
      ).sync(vault, trigger: 'poll');

      expect(metrics.depthZeroPropfinds, 1);
      expect(metrics.depthInfinityPropfinds, 0);
      expect(storage.checkpointWrites, 0);
      expect(result.uploaded, 0);
      expect(result.downloaded, 0);
      expect(result.skipped, 0);
      expect(result.conflicts, 0);
      final events = await _traceEvents(vault);
      expect(events.map((event) => event['event']), contains('no-change-shortcut'));
    },
  );

  test(
    'no-change shortcut falls through and downloads a remote change',
    () async {
      final remote = <String, _MutableRemoteFile>{
        'notes/a.typ': _remoteText('note a'),
      };
      final metrics = _WebDavMetrics();
      final server = await _mutableWebDavServer(remote, metrics: metrics);
      final dir = await Directory.systemTemp.createTemp(
        'tylog_shortcut_remote_change_',
      );
      final vault = Vault(dir);
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      await vault.ensureCreated();
      await NextcloudSync(_config(server)).sync(vault);

      // Simulates another client editing the file directly: the collection
      // etag (derived from current file state) changes along with it, so
      // the probe must catch this without us bumping anything by hand.
      remote['notes/a.typ'] = _remoteText('note a v2');
      metrics
        ..depthZeroPropfinds = 0
        ..depthInfinityPropfinds = 0;

      final result = await NextcloudSync(
        _config(server),
      ).sync(vault, trigger: 'poll');

      expect(metrics.depthZeroPropfinds, 1);
      expect(metrics.depthInfinityPropfinds, 1);
      expect(result.downloaded, 1);
      expect(await vault.storage.readText('notes/a.typ'), 'note a v2');
    },
  );

  test(
    'no-change shortcut never skips a local edit (data-safety guard)',
    () async {
      final remote = <String, _MutableRemoteFile>{
        'notes/a.typ': _remoteText('note a'),
      };
      final metrics = _WebDavMetrics();
      final server = await _mutableWebDavServer(remote, metrics: metrics);
      final dir = await Directory.systemTemp.createTemp(
        'tylog_shortcut_local_change_',
      );
      final vault = Vault(dir);
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      await vault.ensureCreated();
      await NextcloudSync(_config(server)).sync(vault);

      // The remote is untouched (the probe would match) but the local file
      // changed; the shortcut must still fall through to a full run rather
      // than risk skipping a real edit.
      await vault.storage.writeText('notes/a.typ', 'edited locally');
      metrics
        ..depthZeroPropfinds = 0
        ..depthInfinityPropfinds = 0;

      final result = await NextcloudSync(
        _config(server),
      ).sync(vault, trigger: 'poll');

      expect(metrics.depthZeroPropfinds, 1);
      expect(metrics.depthInfinityPropfinds, 1);
      expect(result.uploaded, 1);
      expect(
        utf8.decode(remote['notes/a.typ']!.bytes),
        'edited locally',
      );
    },
  );

  test('a transient abort during folder preparation is retried', () async {
    final remote = <String, _MutableRemoteFile>{
      '_system/tylog.typ': _remoteText('helper'),
      'notes/cloud.typ': _remoteText('cloud note'),
    };
    final server = await _mutableWebDavServer(remote, interruptMkcolOnce: true);
    final dir = await Directory.systemTemp.createTemp('tylog_mkcol_abort_');
    final vault = Vault(dir);
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    await vault.ensureCreated();

    final result = await NextcloudSync(
      _config(server),
    ).sync(vault, initialMode: InitialSyncMode.downloadRemote);

    expect(result.downloaded, remote.length);
    expect(await vault.storage.readText('notes/cloud.typ'), 'cloud note');
  });

  test('a transient mid-transfer abort is retried within the same run', () async {
    final remote = <String, _MutableRemoteFile>{
      '_system/tylog.typ': _remoteText('helper'),
      for (var index = 0; index < 5; index++)
        'notes/$index.typ': _remoteText('remote $index'),
    };
    final gets = <String, int>{};
    final server = await _mutableWebDavServer(
      remote,
      interruptGetOnce: 'notes/3.typ',
      getCounts: gets,
    );
    final dir = await Directory.systemTemp.createTemp('tylog_transient_');
    final vault = Vault(dir);
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    await vault.ensureCreated();

    final result = await NextcloudSync(
      _config(server),
    ).sync(vault, initialMode: InitialSyncMode.downloadRemote);

    expect(result.downloaded, remote.length);
    expect(gets['notes/3.typ'], 2);
    expect(await vault.storage.readText('notes/3.typ'), 'remote 3');
  });

  test('resumed bootstrap with many cursor-less files uses the ZIP archive', () async {
    final remote = <String, _MutableRemoteFile>{
      '_system/tylog.typ': _remoteText('helper'),
    };
    final metrics = _WebDavMetrics();
    final server = await _mutableWebDavServer(
      remote,
      serveArchive: true,
      metrics: metrics,
    );
    final dir = await Directory.systemTemp.createTemp('tylog_resume_zip_');
    final vault = Vault(dir);
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    await vault.ensureCreated();
    await NextcloudSync(
      _config(server),
    ).sync(vault, initialMode: InitialSyncMode.safeMerge);
    final getsAfterBootstrap = metrics.individualGets;

    // The bulk of the vault arrives later (interrupted bootstrap on another
    // run, or another device uploaded) — a plain startup sync should fetch it
    // as one archive instead of a per-file GET crawl.
    for (var index = 0; index < 40; index++) {
      remote['articles/$index.typ'] = _remoteText('article $index\n' * 50);
    }
    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(result.downloaded, 40);
    expect(metrics.archiveGets, 1);
    expect(metrics.individualGets, getsAfterBootstrap);
    expect(
      await vault.storage.readText('articles/39.typ'),
      'article 39\n' * 50,
    );
  });

  test('legacy state upgrades and a different remote resets cursors', () async {
    final server = await _webDavServer(remoteContent: 'remote note');
    final dir = await Directory.systemTemp.createTemp('tylog_state_remote_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = File('${dir.path}/daily/2026/07/note.typ');
    await note.parent.create(recursive: true);
    await note.writeAsString('local note');
    await _seedCursor(vault, 'daily/2026/07/note.typ', note, '"remote-1"');

    await NextcloudSync(_config(server)).sync(vault);
    final upgraded =
        jsonDecode(await vault.storage.readText('.tylog/sync_state.json'))
            as Map<String, Object?>;
    expect(upgraded['schema'], 2);
    expect(upgraded['remoteKey'], isA<String>());

    await vault.storage.writeText(
      '.tylog/sync_state.json',
      jsonEncode({...upgraded, 'remoteKey': 'different-remote'}),
    );
    final result = await NextcloudSync(_config(server)).sync(vault);
    expect(result.conflicts, 1);
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
    // Nextcloud Desktop's checksum types are case-sensitive; a lowercase
    // type makes it silently refuse to sync the file.
    expect(noteUpload['checksum'], startsWith('SHA256:'));
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
      await vault.storage.writeText('.tylog/sync_state.json', '{');

      final result = await NextcloudSync(_config(server)).sync(vault);

      expect(result.conflicts, 1);
      expect(await note.readAsString(), 'local note');
      final conflict = (await loadSyncConflicts(vault)).single;
      expect(
        await vault.storage.readText(conflict.remoteSnapshot!),
        'remote note',
      );
      expect(
        (await vault.storage.list(
          path: '.tylog',
        )).where((file) => file.path.contains('sync_state.corrupt-')).length,
        1,
      );
      expect(
        jsonDecode(await vault.storage.readText('.tylog/sync_state.json')),
        isA<Map>(),
      );
      expect(await vault.storage.exists('.tylog/sync_state.json.tmp'), isFalse);
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
      await vault.storage.writeText('.tylog/sync_state.json', '{');

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
      await vault.storage.writeText('.tylog/sync_state.json', state.value);

      await NextcloudSync(_config(server)).sync(vault);

      expect(
        (await vault.storage.list(
          path: '.tylog',
        )).where((file) => file.path.contains('sync_state.corrupt-')).length,
        1,
      );
      final events = await _traceEvents(vault);
      expect(
        events.map((event) => event['event']),
        contains('state-recovered'),
      );
    });
  }

  test(
    'failed recovery replaces corrupt state with a resumable checkpoint',
    () async {
      final broken = await _webDavServer(
        interrupted: true,
        remoteContent: 'remote note',
      );
      final dir = await Directory.systemTemp.createTemp(
        'tylog_retry_recovery_',
      );
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
      await vault.storage.writeText('.tylog/sync_state.json', '{');

      await expectLater(
        NextcloudSync(_config(broken)).sync(vault),
        throwsA(anything),
      );
      final checkpoint =
          jsonDecode(await vault.storage.readText('.tylog/sync_state.json'))
              as Map<String, Object?>;
      expect(checkpoint['schema'], 2);
      expect(checkpoint['cursors'], isNotEmpty);
      expect(
        (await vault.storage.list(
          path: '.tylog',
        )).where((file) => file.path.contains('sync_state.corrupt-')).length,
        1,
      );

      await broken.close(force: true);
      healthy = await _webDavServer(remoteContent: 'remote note');
      final result = await NextcloudSync(_config(healthy)).sync(vault);

      expect(result.conflicts, 1);
      expect(await note.readAsString(), 'local note');
    },
  );

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
    await vault.storage.writeText('.tylog/sync_state.json', '{');

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

  test('which sync stage blocks the root isolate', () async {
    // Phase 2.2. Everything measured so far priced sync components in isolation;
    // this runs a whole sync and attributes root-isolate stalls to the stage
    // reported by onProgress, so the decision to move sync onto the worker (which
    // costs the canReplaceLocal predicate and ~30 root-isolate vault writers) is
    // made against evidence rather than a hunch.
    //
    // A local server means no network latency, so what shows up here is purely
    // the work sync does on the calling isolate. Diagnostic: it prints, and
    // asserts only that it measured something.
    const files = 600;
    final remote = <String, _MutableRemoteFile>{
      '_system/tylog.typ': _remoteText('helper'),
      for (var index = 0; index < files; index++)
        'notes/${index.toString().padLeft(3, '0')}.typ': _remoteText(
          'remote note $index ${List.filled(200, 'body').join(' ')}',
        ),
    };
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_sync_stages_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();

    const frame = Duration(milliseconds: 16);
    var stage = 'start';
    final worst = <String, Duration>{};
    final dropped = <String, int>{};
    var last = DateTime.now();
    final ticker = Timer.periodic(frame, (_) {
      final now = DateTime.now();
      final gap = now.difference(last);
      last = now;
      // Attribute to whatever stage was running when the tick came due.
      final key = stage.startsWith('sync-file') ? 'sync-file' : stage;
      if (gap > (worst[key] ?? Duration.zero)) worst[key] = gap;
      final late = gap - frame;
      if (late > Duration.zero) {
        dropped[key] =
            (dropped[key] ?? 0) + late.inMicroseconds ~/ frame.inMicroseconds;
      }
    });

    await NextcloudSync(
      _config(server),
      onProgress: (next, _) => stage = next,
    ).sync(vault, initialMode: InitialSyncMode.downloadRemote);
    ticker.cancel();

    final ranked = worst.keys.toList()
      ..sort((a, b) => worst[b]!.compareTo(worst[a]!));
    // ignore: avoid_print
    print('SYNC-STAGES files=$files (local server, so no network in these)');
    for (final key in ranked) {
      // ignore: avoid_print
      print(
        '  ${key.padRight(22)} worst ${worst[key]!.inMilliseconds}ms  '
        'dropped ${dropped[key] ?? 0}',
      );
    }

    expect(worst, isNotEmpty, reason: 'no stage was ever observed');

    // The finding this test exists to protect. Measured at 150/300/600/1200
    // files, `sync-file` never leaves the 16 ms timer floor and drops zero
    // frames, while `list-remote` grew with entry count (25/35/51 ms) until
    // its PROPFIND parse moved into a compute() isolate. The
    // per-file loop is I/O-bound with an await at every step, so it does not
    // block the calling isolate — which is why moving NextcloudSync onto the
    // worker was dropped: it would buy nothing and cost the canReplaceLocal
    // predicate plus ~30 root-isolate vault writers.
    //
    // If this ever fails, something synchronous was added to the per-file path
    // and that conclusion needs revisiting.
    expect(
      dropped['sync-file'] ?? 0,
      lessThanOrEqualTo(2),
      reason: 'the per-file loop is dropping frames — it used not to, so '
          'blocking work has been added to it',
    );
  });

  test('a no-change run does not trace one decision per file', () async {
    // The `completed` event embeds every decision, so recording "skip /
    // no-change" per path put ~400 KB of JSON in one line on a 2000-note vault —
    // which is how sync_trace.jsonl came to sit at 799 KB on a real device,
    // above its own 512 KB trim threshold, and why the dashboard built a
    // ListTile per note. The counts in the same event carry that information.
    final remote = <String, _MutableRemoteFile>{
      '_system/tylog.typ': _remoteText('helper'),
      for (var index = 0; index < 25; index++)
        'notes/${index.toString().padLeft(2, '0')}.typ': _remoteText(
          'remote $index',
        ),
    };
    final server = await _mutableWebDavServer(remote);
    final dir = await Directory.systemTemp.createTemp('tylog_trace_volume_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();

    // First run transfers everything; those decisions are real and kept.
    await NextcloudSync(
      _config(server),
    ).sync(vault, initialMode: InitialSyncMode.downloadRemote);
    await vault.storage.delete('.tylog/sync_trace.jsonl');

    // Second run changes nothing, so it should decide "skip / no-change"
    // everywhere and record none of it.
    final second = await NextcloudSync(_config(server)).sync(vault);
    expect(second.skipped, greaterThanOrEqualTo(25));

    final completed = (await _traceEvents(
      vault,
    )).firstWhere((event) => event['event'] == 'completed');
    final recorded = (completed['decisions'] as List).cast<Map>();
    // Not "no decisions at all": local-only files (_system, the daily note) are
    // legitimately `remote-missing` under downloadRemote, and that is worth
    // tracing. The invariant is narrower — the noise entry is never recorded.
    expect(
      recorded.where(
        (d) => d['action'] == 'skip' && d['reason'] == 'no-change',
      ),
      isEmpty,
      reason: 'skip/no-change is still being traced per path',
    );
    // ...and the volume is bounded by what actually happened, not by vault size.
    expect(recorded.length, lessThan(second.skipped));
    expect(completed['skipped'], second.skipped);
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
    final oldLine = '${jsonEncode({'old': List.filled(1024, 'x').join()})}\n';
    await vault.storage.writeText(
      '.tylog/sync_trace.jsonl',
      List.filled(600, oldLine).join(),
    );

    await NextcloudSync(_config(server)).sync(vault);

    expect(
      (await vault.storage.stat('.tylog/sync_trace.jsonl'))!.size,
      lessThan(512 * 1024),
    );
    for (final line in (await vault.storage.readText(
      '.tylog/sync_trace.jsonl',
    )).split('\n')) {
      if (line.isEmpty) continue;
      expect(jsonDecode(line), isA<Map>());
    }

    await vault.storage.delete('.tylog/sync_trace.jsonl');
    await vault.storage.createDirectory('.tylog/sync_trace.jsonl');
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
    await _seedCursor(vault, 'daily/2026/07/note.typ', note, '"remote-1"');
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
      await _seedCursor(vault, 'daily/2026/07/note.typ', note, '"remote-1"');

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

  test(
    'resolveConflict prunes an orphaned record instead of throwing',
    () async {
      final remote = <String, _MutableRemoteFile>{
        'notes/live.typ': _MutableRemoteFile(
          bytes: utf8.encode('remote note'),
          etag: '"remote"',
          modified: DateTime.now().toUtc(),
        ),
      };
      final server = await _mutableWebDavServer(remote);
      final dir = await Directory.systemTemp.createTemp(
        'tylog_orphan_conflict_',
      );
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      await vault.storage.writeText('notes/live.typ', 'local text');
      await createSyncConflict(
        vault,
        'notes/live.typ',
        localBytes: utf8.encode('local text'),
        remoteBytes: utf8.encode('remote note'),
      );
      final conflict = (await loadSyncConflicts(vault)).single;
      // Self-heal (or a previous resolve) already removed the remote
      // snapshot on disk before the UI's stale in-memory copy gets acted on.
      await vault.storage.delete(conflict.remoteSnapshot!);

      await expectLater(
        NextcloudSync(
          _config(server),
        ).resolveConflict(vault, conflict, SyncConflictResolution.keepRemote),
        completes,
      );

      expect(await loadSyncConflicts(vault), isEmpty);
    },
  );

  test(
    'resolveConflict probes one file instead of listing the tree',
    () async {
      final remote = <String, _MutableRemoteFile>{
        'notes/live.typ': _MutableRemoteFile(
          bytes: utf8.encode('remote note'),
          etag: '"remote"',
          modified: DateTime.now().toUtc(),
        ),
        for (var index = 0; index < 20; index++)
          'notes/other$index.typ': _remoteText('other $index'),
      };
      final metrics = _WebDavMetrics();
      final server = await _mutableWebDavServer(remote, metrics: metrics);
      final dir = await Directory.systemTemp.createTemp(
        'tylog_resolve_probe_',
      );
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      await vault.storage.writeText('notes/live.typ', 'local text');
      await createSyncConflict(
        vault,
        'notes/live.typ',
        localBytes: utf8.encode('local text'),
        remoteBytes: utf8.encode('remote note'),
      );
      final conflict = (await loadSyncConflicts(vault)).single;
      metrics
        ..depthZeroPropfinds = 0
        ..depthInfinityPropfinds = 0;

      await NextcloudSync(
        _config(server),
      ).resolveConflict(vault, conflict, SyncConflictResolution.keepLocal);

      expect(metrics.depthInfinityPropfinds, 0);
      expect(metrics.depthZeroPropfinds, 1);
    },
  );

  test(
    'createSyncConflict replaces an existing unresolved record for the '
    'same path instead of stacking',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_dedupe_');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(dir);
      await vault.ensureCreated();

      await createSyncConflict(
        vault,
        'notes/dupe.typ',
        localBytes: utf8.encode('local v1'),
        remoteBytes: utf8.encode('remote v1'),
      );
      await createSyncConflict(
        vault,
        'notes/dupe.typ',
        localBytes: utf8.encode('local v2'),
        remoteBytes: utf8.encode('remote v2'),
      );

      final conflicts = await loadSyncConflicts(vault);
      expect(conflicts, hasLength(1));
      final conflict = conflicts.single;
      expect(
        await vault.storage.readText(conflict.localSnapshot!),
        'local v2',
      );
      expect(
        await vault.storage.readText(conflict.remoteSnapshot!),
        'remote v2',
      );
    },
  );

  test(
    'loadSyncConflicts self-heals a record whose snapshots are identical',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_selfheal_');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(dir);
      await vault.ensureCreated();

      await createSyncConflict(
        vault,
        'notes/spurious.typ',
        localBytes: utf8.encode('same content'),
        remoteBytes: utf8.encode('same content'),
      );
      await createSyncConflict(
        vault,
        'notes/real.typ',
        localBytes: utf8.encode('local content'),
        remoteBytes: utf8.encode('remote content'),
      );

      // loadSyncConflicts is the function under test, so capture the
      // spurious record's file paths by reading the raw .json before it
      // self-heals (rather than duplicating its resolution logic here).
      final rawEntries = await vault.storage.list(path: '.tylog/conflicts');
      final spuriousJson = <String>[];
      for (final entry in rawEntries) {
        if (entry.isDirectory || !entry.path.endsWith('.json')) continue;
        final json =
            (jsonDecode(await vault.storage.readText(entry.path)) as Map)
                .cast<String, Object?>();
        if (json['path'] == 'notes/spurious.typ') spuriousJson.add(entry.path);
      }
      expect(spuriousJson, hasLength(1));
      final spuriousBase = spuriousJson.single.substring(
        0,
        spuriousJson.single.length - '.json'.length,
      );

      final conflicts = await loadSyncConflicts(vault);

      expect(conflicts, hasLength(1));
      expect(conflicts.single.path, 'notes/real.typ');
      // The spurious record and both its snapshots must be gone entirely.
      expect(await vault.storage.exists('$spuriousBase.json'), isFalse);
      expect(await vault.storage.exists('$spuriousBase.local'), isFalse);
      expect(await vault.storage.exists('$spuriousBase.remote'), isFalse);
      final remaining = (await vault.storage.list(
        path: '.tylog/conflicts',
        recursive: true,
      )).where((entry) => !entry.isDirectory).toList();
      expect(remaining, hasLength(3)); // real.typ's .json + .local + .remote
    },
  );

  test(
    'unresolved conflict record refreshes its etag when the remote changes '
    'again, unblocking resolution',
    () async {
      final remote = <String, _MutableRemoteFile>{
        'notes/deadlock.typ': _MutableRemoteFile(
          bytes: utf8.encode('remote v1'),
          etag: '"remote-1"',
          modified: DateTime.now().toUtc(),
        ),
      };
      final server = await _mutableWebDavServer(remote);
      final dir = await Directory.systemTemp.createTemp('tylog_deadlock_');
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      await vault.storage.writeText('notes/deadlock.typ', 'local v1');

      // First sync: divergent content records a conflict with remoteEtag
      // "remote-1".
      await NextcloudSync(_config(server)).sync(vault);
      var conflict = (await loadSyncConflicts(
        vault,
      )).singleWhere((item) => item.path == 'notes/deadlock.typ');
      expect(conflict.remoteEtag, 'remote-1');

      // Another device edits the remote file again while the conflict sits
      // unresolved; without a refresh, resolveConflict's guard would throw
      // forever since the stored etag can never match again.
      remote['notes/deadlock.typ'] = _MutableRemoteFile(
        bytes: utf8.encode('remote v2'),
        etag: '"remote-2"',
        modified: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );

      // Without an intervening sync, the guard still throws (unchanged).
      await expectLater(
        NextcloudSync(
          _config(server),
        ).resolveConflict(vault, conflict, SyncConflictResolution.keepLocal),
        throwsA(isA<StateError>()),
      );

      // Running sync again must refresh the record in place (same path
      // skipped as unresolved, but its etag/snapshot catch up).
      await NextcloudSync(_config(server)).sync(vault);
      conflict = (await loadSyncConflicts(
        vault,
      )).singleWhere((item) => item.path == 'notes/deadlock.typ');
      expect(conflict.remoteEtag, 'remote-2');
      expect(
        await vault.storage.readText(conflict.remoteSnapshot!),
        'remote v2',
      );

      await NextcloudSync(
        _config(server),
      ).resolveConflict(vault, conflict, SyncConflictResolution.keepLocal);

      expect(await vault.storage.readText('notes/deadlock.typ'), 'local v1');
      expect(utf8.decode(remote['notes/deadlock.typ']!.bytes), 'local v1');
      expect(await loadSyncConflicts(vault), isEmpty);
    },
  );

  test(
    'local rename uses one conditional MOVE without retransferring',
    () async {
      final remote = <String, _MutableRemoteFile>{};
      final metrics = _WebDavMetrics();
      final server = await _mutableWebDavServer(
        remote,
        includeChecksums: true,
        metrics: metrics,
      );
      final dir = await Directory.systemTemp.createTemp('tylog_local_rename_');
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      await vault.storage.writeText('notes/old.typ', 'same note');
      await NextcloudSync(_config(server)).sync(vault);

      final bytes = await vault.storage.readBytes('notes/old.typ');
      await vault.storage.writeBytes('notes/new.typ', bytes);
      await vault.storage.delete('notes/old.typ');
      metrics
        ..moves = 0
        ..puts = 0
        ..individualGets = 0;

      final result = await NextcloudSync(_config(server)).sync(vault);

      expect(result.renamed, 1);
      expect(result.requiresIndexRefresh, isTrue);
      expect(metrics.moves, 1);
      expect(metrics.puts, 0);
      expect(metrics.individualGets, 0);
      expect(remote, isNot(contains('notes/old.typ')));
      expect(utf8.decode(remote['notes/new.typ']!.bytes), 'same note');
    },
  );

  test('remote rename uses checksum and migrates the local cursor', () async {
    final remote = <String, _MutableRemoteFile>{};
    final metrics = _WebDavMetrics();
    final server = await _mutableWebDavServer(
      remote,
      includeChecksums: true,
      metrics: metrics,
    );
    final dir = await Directory.systemTemp.createTemp('tylog_remote_rename_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/old.typ', 'same note');
    await NextcloudSync(_config(server)).sync(vault);

    remote['notes/new.typ'] = remote.remove('notes/old.typ')!;
    metrics.individualGets = 0;
    final result = await NextcloudSync(_config(server)).sync(vault);

    expect(result.renamed, 1);
    expect(metrics.individualGets, 0);
    expect(await vault.storage.exists('notes/old.typ'), isFalse);
    expect(await vault.storage.readText('notes/new.typ'), 'same note');
    final state =
        jsonDecode(await vault.storage.readText('.tylog/sync_state.json'))
            as Map<String, Object?>;
    final cursors = state['cursors']! as Map<String, dynamic>;
    expect(cursors, contains('notes/new.typ'));
    expect(cursors, isNot(contains('notes/old.typ')));
  });

  test('both sides already renamed is completed idempotently', () async {
    final remote = <String, _MutableRemoteFile>{};
    final server = await _mutableWebDavServer(remote, includeChecksums: true);
    final dir = await Directory.systemTemp.createTemp('tylog_both_rename_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/old.typ', 'same note');
    await NextcloudSync(_config(server)).sync(vault);

    await vault.storage.writeBytes(
      'notes/new.typ',
      await vault.storage.readBytes('notes/old.typ'),
    );
    await vault.storage.delete('notes/old.typ');
    remote['notes/new.typ'] = remote.remove('notes/old.typ')!;

    final result = await NextcloudSync(_config(server)).sync(vault);
    expect(result.renamed, 1);
    expect(await vault.storage.exists('notes/old.typ'), isFalse);
    expect(await vault.storage.readText('notes/new.typ'), 'same note');
  });

  test('ambiguous identical renames are not inferred', () async {
    final remote = <String, _MutableRemoteFile>{};
    final metrics = _WebDavMetrics();
    final server = await _mutableWebDavServer(remote, metrics: metrics);
    final dir = await Directory.systemTemp.createTemp('tylog_ambiguous_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    for (final path in const ['notes/a.typ', 'notes/b.typ']) {
      await vault.storage.writeText(path, 'duplicate');
    }
    await NextcloudSync(_config(server)).sync(vault);
    for (final pair in const [
      ('notes/a.typ', 'notes/c.typ'),
      ('notes/b.typ', 'notes/d.typ'),
    ]) {
      await vault.storage.writeBytes(
        pair.$2,
        await vault.storage.readBytes(pair.$1),
      );
      await vault.storage.delete(pair.$1);
    }
    metrics.moves = 0;

    final result = await NextcloudSync(_config(server)).sync(vault);
    expect(result.renamed, 0);
    expect(result.conflicts, 2);
    expect(metrics.moves, 0);
    for (final path in const ['notes/a.typ', 'notes/b.typ']) {
      expect(remote, contains(path));
    }
    for (final path in const ['notes/c.typ', 'notes/d.typ']) {
      expect(remote, contains(path));
    }
  });

  test('a copy is uploaded and is not treated as a rename', () async {
    final remote = <String, _MutableRemoteFile>{};
    final metrics = _WebDavMetrics();
    final server = await _mutableWebDavServer(remote, metrics: metrics);
    final dir = await Directory.systemTemp.createTemp('tylog_copy_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/original.typ', 'same note');
    await NextcloudSync(_config(server)).sync(vault);
    await vault.storage.writeBytes(
      'notes/copy.typ',
      await vault.storage.readBytes('notes/original.typ'),
    );
    metrics
      ..moves = 0
      ..puts = 0;

    final result = await NextcloudSync(_config(server)).sync(vault);
    expect(result.renamed, 0);
    expect(metrics.moves, 0);
    expect(metrics.puts, 1);
    expect(remote, contains('notes/original.typ'));
    expect(remote, contains('notes/copy.typ'));
  });

  test('rename plus edit preserves both versions without MOVE', () async {
    final remote = <String, _MutableRemoteFile>{};
    final metrics = _WebDavMetrics();
    final server = await _mutableWebDavServer(remote, metrics: metrics);
    final dir = await Directory.systemTemp.createTemp('tylog_rename_edit_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/old.typ', 'old body');
    await NextcloudSync(_config(server)).sync(vault);
    await vault.storage.delete('notes/old.typ');
    await vault.storage.writeText('notes/new.typ', 'edited body');
    metrics
      ..moves = 0
      ..puts = 0;

    final result = await NextcloudSync(_config(server)).sync(vault);
    expect(result.renamed, 0);
    expect(result.conflicts, 1);
    expect(metrics.moves, 0);
    expect(metrics.puts, 1);
    expect(utf8.decode(remote['notes/old.typ']!.bytes), 'old body');
    expect(utf8.decode(remote['notes/new.typ']!.bytes), 'edited body');
  });

  test('a conditional MOVE race preserves both sides for Retry', () async {
    final remote = <String, _MutableRemoteFile>{};
    final metrics = _WebDavMetrics();
    final server = await _mutableWebDavServer(
      remote,
      rejectMove: true,
      metrics: metrics,
    );
    final dir = await Directory.systemTemp.createTemp('tylog_move_race_');
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/old.typ', 'same note');
    await NextcloudSync(_config(server)).sync(vault);
    await vault.storage.writeBytes(
      'notes/new.typ',
      await vault.storage.readBytes('notes/old.typ'),
    );
    await vault.storage.delete('notes/old.typ');

    await expectLater(
      NextcloudSync(_config(server)).sync(vault),
      throwsA(anything),
    );
    expect(metrics.moves, 1);
    expect(remote, contains('notes/old.typ'));
    expect(remote, isNot(contains('notes/new.typ')));
    expect(await vault.storage.readText('notes/new.typ'), 'same note');
  });

  test('remote checksums avoid equality GETs', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_checksum_');
    final vault = Vault(dir);
    await vault.ensureCreated();
    await vault.storage.writeText('notes/same.typ', 'same note');
    final remote = <String, _MutableRemoteFile>{
      '_system/tylog.typ': _remoteBytes(
        await vault.storage.readBytes('_system/tylog.typ'),
      ),
      'notes/same.typ': _remoteText('same note'),
    };
    final metrics = _WebDavMetrics();
    final server = await _mutableWebDavServer(
      remote,
      includeChecksums: true,
      metrics: metrics,
    );
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    final result = await NextcloudSync(
      _config(server),
    ).sync(vault, initialMode: InitialSyncMode.safeMerge);
    expect(result.conflicts, 0);
    expect(metrics.individualGets, 0);
  });

  test(
    'lowercase server checksum is self-repaired for an in-sync file',
    () async {
      final content = utf8.encode('poisoned upload');
      final remote = <String, _MutableRemoteFile>{
        'daily/2026/07/note.typ': _MutableRemoteFile(
          bytes: content,
          etag: '"remote-1"',
          modified: DateTime.utc(2026, 7, 1),
        ),
      };
      final uploads = <Map<String, Object?>>[];
      final server = await _mutableWebDavServer(
        remote,
        lowercaseChecksums: true,
        uploads: uploads,
      );
      final dir = await Directory.systemTemp.createTemp(
        'tylog_checksum_repair_',
      );
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      await vault.storage.writeBytes('daily/2026/07/note.typ', content);

      final result = await NextcloudSync(_config(server)).sync(vault);

      final repairs = uploads
          .where((upload) => upload['path'] == 'daily/2026/07/note.typ')
          .toList();
      expect(repairs, hasLength(1));
      expect(repairs.single['checksum'], startsWith('SHA256:'));
      expect(repairs.single['body'], 'poisoned upload');
      expect(result.repaired, greaterThanOrEqualTo(1));
      expect(result.conflicts, 0);

      // Second sync: the repair PUT already replaced the stored checksum
      // with the uppercase type, so nothing re-fires.
      uploads.clear();
      final second = await NextcloudSync(_config(server)).sync(vault);
      expect(
        uploads.where((upload) => upload['path'] == 'daily/2026/07/note.typ'),
        isEmpty,
      );
      expect(second.conflicts, 0);
    },
  );

  test(
    'a genuinely changed file with a lowercase server checksum still '
    'conflicts normally',
    () async {
      final remote = <String, _MutableRemoteFile>{
        'daily/2026/07/note.typ': _MutableRemoteFile(
          bytes: utf8.encode('remote version'),
          etag: '"remote-1"',
          modified: DateTime.utc(2026, 7, 1),
        ),
      };
      final uploads = <Map<String, Object?>>[];
      final server = await _mutableWebDavServer(
        remote,
        lowercaseChecksums: true,
        uploads: uploads,
      );
      final dir = await Directory.systemTemp.createTemp(
        'tylog_checksum_guard_',
      );
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      await vault.storage.writeText(
        'daily/2026/07/note.typ',
        'local version',
      );

      final result = await NextcloudSync(_config(server)).sync(vault);

      expect(result.conflicts, greaterThanOrEqualTo(1));
      expect(
        uploads.where((upload) => upload['path'] == 'daily/2026/07/note.typ'),
        isEmpty,
      );
      expect(
        utf8.decode(remote['daily/2026/07/note.typ']!.bytes),
        'remote version',
      );
    },
  );

  test(
    'path transfers use two to eight workers and one MKCOL per parent',
    () async {
      final remote = <String, _MutableRemoteFile>{};
      final metrics = _WebDavMetrics();
      final server = await _mutableWebDavServer(
        remote,
        transferDelay: const Duration(milliseconds: 40),
        metrics: metrics,
      );
      final dir = await Directory.systemTemp.createTemp('tylog_parallel_');
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      for (var i = 0; i < 12; i++) {
        await vault.storage.writeText('notes/$i.typ', 'note $i');
      }

      await NextcloudSync(
        _config(server),
      ).sync(vault, initialMode: InitialSyncMode.uploadLocal);

      expect(metrics.maxTransfers, greaterThan(1));
      expect(metrics.maxTransfers, lessThanOrEqualTo(8));
      expect(
        metrics.mkcols['/remote.php/dav/files/alice/TyLogVault/notes/'],
        1,
      );
    },
  );

  test(
    '1602-file restore uses two PROPFINDs and one ZIP GET',
    () async {
      final remote = <String, _MutableRemoteFile>{
        '_system/tylog.typ': _remoteText('helper'),
        for (var i = 0; i < 1602; i++)
          'articles/$i.typ': _remoteText('article $i'),
      };
      final metrics = _WebDavMetrics();
      final server = await _mutableWebDavServer(
        remote,
        includeChecksums: true,
        serveArchive: true,
        metrics: metrics,
      );
      final dir = await Directory.systemTemp.createTemp('tylog_archive_');
      final vault = Vault(dir);
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      await vault.ensureCreated();

      final result = await NextcloudSync(
        _config(server),
      ).sync(vault, initialMode: InitialSyncMode.downloadRemote);

      expect(result.downloaded, remote.length);
      expect(metrics.propfinds, 2);
      expect(metrics.archiveGets, 1);
      expect(metrics.individualGets, 0);
      expect(await vault.storage.readText('articles/1601.typ'), 'article 1601');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('unsupported ZIP restore falls back to individual transfers', () async {
    final remote = <String, _MutableRemoteFile>{
      '_system/tylog.typ': _remoteText('helper'),
      'notes/cloud.typ': _remoteText('cloud note'),
    };
    final metrics = _WebDavMetrics();
    final server = await _mutableWebDavServer(remote, metrics: metrics);
    final dir = await Directory.systemTemp.createTemp(
      'tylog_archive_fallback_',
    );
    final vault = Vault(dir);
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    await vault.ensureCreated();

    await NextcloudSync(
      _config(server),
    ).sync(vault, initialMode: InitialSyncMode.downloadRemote);

    expect(metrics.archiveGets, 1);
    expect(metrics.individualGets, remote.length);
    expect(await vault.storage.readText('notes/cloud.typ'), 'cloud note');
  });

  test('changed ZIP snapshot makes no user-visible local changes', () async {
    final remote = <String, _MutableRemoteFile>{
      '_system/tylog.typ': _remoteText('helper'),
      for (var i = 0; i < 32; i++) 'notes/$i.typ': _remoteText('note $i'),
    };
    final server = await _mutableWebDavServer(
      remote,
      serveArchive: true,
      changeSnapshotAfterArchive: true,
    );
    final dir = await Directory.systemTemp.createTemp('tylog_archive_race_');
    final vault = Vault(dir);
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    await vault.ensureCreated();
    final starter = await vault.todayNote(DateTime(2026, 7, 15));

    await expectLater(
      NextcloudSync(
        _config(server),
      ).sync(vault, initialMode: InitialSyncMode.downloadRemote),
      throwsStateError,
    );

    expect(await vault.storage.exists(starter), isTrue);
    expect(await vault.storage.exists('notes/0.typ'), isFalse);
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

  group('pollIsUnchanged', () {
    Future<({Vault vault, HttpServer server, Map<String, _MutableRemoteFile> remote})>
    synced() async {
      final remote = <String, _MutableRemoteFile>{
        'notes/a.typ': _remoteText('note a'),
      };
      final server = await _mutableWebDavServer(remote);
      final dir = await Directory.systemTemp.createTemp('tylog_poll_');
      addTearDown(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
      final vault = Vault(dir);
      await vault.ensureCreated();
      // Twice: the first run uploads the vault scaffolding, and the etag it
      // saves is the pre-upload one. The second settles into steady state.
      await NextcloudSync(_config(server)).sync(vault);
      await NextcloudSync(_config(server)).sync(vault);
      return (vault: vault, server: server, remote: remote);
    }

    test('skips a poll when the remote root etag is unchanged', () async {
      final s = await synced();

      expect(
        await NextcloudSync(_config(s.server)).pollIsUnchanged(
          s.vault,
          dirty: false,
        ),
        isTrue,
      );
    });

    test('falls through when the remote root etag moved', () async {
      final s = await synced();
      s.remote['notes/b.typ'] = _remoteText('note b');

      expect(
        await NextcloudSync(_config(s.server)).pollIsUnchanged(
          s.vault,
          dirty: false,
        ),
        isFalse,
      );
    });

    test('falls through while the editor is dirty', () async {
      final s = await synced();

      expect(
        await NextcloudSync(_config(s.server)).pollIsUnchanged(
          s.vault,
          dirty: true,
        ),
        isFalse,
      );
    });

    test('falls through when a conflict is pending', () async {
      final s = await synced();
      await createSyncConflict(
        s.vault,
        'notes/a.typ',
        localBytes: utf8.encode('local'),
        remoteBytes: utf8.encode('remote'),
      );

      expect(
        await NextcloudSync(_config(s.server)).pollIsUnchanged(
          s.vault,
          dirty: false,
        ),
        isFalse,
      );
    });

    test('falls through when the server is unreachable', () async {
      final s = await synced();
      final config = _config(s.server);
      await s.server.close(force: true);

      expect(
        await NextcloudSync(config).pollIsUnchanged(s.vault, dirty: false),
        isFalse,
      );
    });

    // The deliberate trade: a local-only change is NOT detected by the poll,
    // because verifying it costs a full recursive listing every 25s. Local
    // edits reach the cloud via queueCloudSync, and sync() still runs the
    // local cursor check on every startup, resume and manual run.
    test('does not detect a local-only change (sync() still does)', () async {
      final s = await synced();
      await s.vault.storage.writeText('notes/a.typ', 'edited locally');

      expect(
        await NextcloudSync(_config(s.server)).pollIsUnchanged(
          s.vault,
          dirty: false,
        ),
        isTrue,
      );

      final result = await NextcloudSync(_config(s.server)).sync(s.vault);
      expect(result.uploaded, 1);
    });
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

class _CheckpointCountingStorage extends LocalVaultStorage {
  _CheckpointCountingStorage(super.root);

  int checkpointWrites = 0;

  @override
  Future<void> writeBytes(String path, List<int> bytes) {
    if (path == '.tylog/sync_state.json') checkpointWrites++;
    return super.writeBytes(path, bytes);
  }
}

Future<List<Map<String, Object?>>> _traceEvents(Vault vault) async =>
    (await vault.storage.readText('.tylog/sync_trace.jsonl'))
        .split('\n')
        .where((line) => line.isNotEmpty)
        .map((line) => (jsonDecode(line) as Map).cast<String, Object?>())
        .toList();

Future<void> _seedCursor(
  Vault vault,
  String notePath,
  File note,
  String remoteEtag,
) async {
  final hash = sha256.convert(await note.readAsBytes()).toString();
  await vault.storage.writeText(
    '.tylog/sync_state.json',
    jsonEncode({
      'cursors': {
        notePath: {
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
        'checksum': request.headers.value('oc-checksum'),
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

class _WebDavMetrics {
  int propfinds = 0;
  int archiveGets = 0;
  int moves = 0;
  int puts = 0;
  int individualGets = 0;
  int activeTransfers = 0;
  int maxTransfers = 0;
  // Depth:0 root-etag probes vs. Depth:infinity full-tree listings, tracked
  // separately from [propfinds] (which counts both) so the no-change
  // shortcut tests can assert exactly which kind of PROPFIND happened.
  int depthZeroPropfinds = 0;
  int depthInfinityPropfinds = 0;
  final mkcols = <String, int>{};

  void startTransfer() {
    activeTransfers++;
    if (activeTransfers > maxTransfers) maxTransfers = activeTransfers;
  }

  void finishTransfer() => activeTransfers--;
}

_MutableRemoteFile _remoteText(String text) => _remoteBytes(utf8.encode(text));

_MutableRemoteFile _remoteBytes(List<int> bytes) => _MutableRemoteFile(
  bytes: bytes,
  etag: '"fixture-${sha256.convert(bytes)}"',
  modified: DateTime.utc(2030),
);

Future<HttpServer> _missingWebDavServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  });
  return server;
}

/// A stand-in for a real Nextcloud collection etag: derived purely from the
/// current file map (path + etag of every entry), so it changes whenever the
/// map changes — whether that's a PUT/MOVE/DELETE routed through the server
/// handler below, or a test directly mutating `files` to simulate a change
/// from another client.
String _collectionEtag(Map<String, _MutableRemoteFile> files) {
  final buffer = StringBuffer();
  for (final key in files.keys.toList()..sort()) {
    buffer.write('$key:${files[key]!.etag}\n');
  }
  return '"col-${sha256.convert(utf8.encode(buffer.toString()))}"';
}

Future<HttpServer> _mutableWebDavServer(
  Map<String, _MutableRemoteFile> files, {
  bool unquotedPutEtag = false,
  bool rejectDelete = false,
  bool rejectMove = false,
  bool includeChecksums = false,
  // Simulates files this app PUT before the OC-Checksum header case fix:
  // the server still stores the lowercase `sha256:` type, which is what
  // makes Nextcloud Desktop refuse to sync the file. A path stops being
  // served lowercase once a real PUT (re-)uploads it, matching how the
  // repair actually clears the poisoned state server-side.
  bool lowercaseChecksums = false,
  bool serveArchive = false,
  bool changeSnapshotAfterArchive = false,
  String? interruptGetOnce,
  bool interruptMkcolOnce = false,
  Map<String, int>? getCounts,
  Duration transferDelay = Duration.zero,
  _WebDavMetrics? metrics,
  List<Map<String, Object?>>? uploads,
}) async {
  const root = '/remote.php/dav/files/alice/TyLogVault/';
  var version = 0;
  var interrupted = false;
  var mkcolInterrupted = false;
  var archiveChanged = false;
  final upgradedChecksums = <String>{};
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path.startsWith(root)
        ? request.uri.path.substring(root.length)
        : '';
    if (request.method == 'MKCOL') {
      metrics?.mkcols.update(
        request.uri.path,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (interruptMkcolOnce && !mkcolInterrupted) {
        mkcolInterrupted = true;
        final socket = await request.response.detachSocket(
          writeHeaders: false,
        );
        socket.destroy();
        return;
      }
      request.response.statusCode = HttpStatus.methodNotAllowed;
    } else if (request.method == 'PROPFIND') {
      metrics?.propfinds++;
      final depth = request.headers.value('Depth');
      if (depth == '0') {
        metrics?.depthZeroPropfinds++;
      } else {
        metrics?.depthInfinityPropfinds++;
      }
      if (path.isNotEmpty) {
        // Single-resource probe (resolveConflict's etag check): one
        // response for that path only, or 404 if it doesn't exist.
        final file = files[path];
        if (file == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          final checksum = sha256.convert(file.bytes);
          final serveLowercase =
              lowercaseChecksums && !upgradedChecksums.contains(path);
          final checksumType = serveLowercase ? 'sha256' : 'SHA256';
          request.response.statusCode = 207;
          request.response.write(
            '<d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">'
            '<d:response><d:href>$root$path</d:href>'
            '<d:propstat><d:prop><d:getlastmodified>'
            '${HttpDate.format(file.modified)}'
            '</d:getlastmodified><d:getetag>${file.etag}</d:getetag>'
            '<d:getcontentlength>${file.bytes.length}</d:getcontentlength>'
            '${includeChecksums || lowercaseChecksums ? '<oc:checksums><oc:checksum>$checksumType:$checksum</oc:checksum></oc:checksums>' : ''}'
            '</d:prop></d:propstat></d:response>'
            '</d:multistatus>',
          );
        }
        await request.response.close();
        return;
      }
      request.response.statusCode = 207;
      request.response.write(
        '<d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">',
      );
      // The root collection's own entry: a real Nextcloud server's etag here
      // changes whenever anything beneath it changes, which is what the
      // no-change shortcut probes for. Computed fresh from current file
      // state so it reacts to direct test mutations of `files`, not just
      // PUT/MOVE/DELETE routed through this handler.
      request.response.write(
        '<d:response><d:href>$root</d:href>'
        '<d:propstat><d:prop><d:getetag>${_collectionEtag(files)}</d:getetag>'
        '<d:resourcetype><d:collection/></d:resourcetype>'
        '</d:prop></d:propstat></d:response>',
      );
      if (depth != '0') {
        for (final entry in files.entries) {
          final checksum = sha256.convert(entry.value.bytes);
          final serveLowercase =
              lowercaseChecksums && !upgradedChecksums.contains(entry.key);
          final checksumType = serveLowercase ? 'sha256' : 'SHA256';
          request.response.write(
            '<d:response><d:href>$root${entry.key}</d:href>'
            '<d:propstat><d:prop><d:getlastmodified>'
            '${HttpDate.format(entry.value.modified)}'
            '</d:getlastmodified><d:getetag>${entry.value.etag}</d:getetag>'
            '<d:getcontentlength>${entry.value.bytes.length}</d:getcontentlength>'
            '${includeChecksums || lowercaseChecksums ? '<oc:checksums><oc:checksum>$checksumType:$checksum</oc:checksum></oc:checksums>' : ''}'
            '</d:prop></d:propstat></d:response>',
          );
        }
      }
      request.response.write('</d:multistatus>');
    } else if (request.method == 'GET') {
      if (path.isEmpty) {
        metrics?.archiveGets++;
        if (!serveArchive) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final archive = Archive();
        for (final entry in files.entries) {
          archive.addFile(
            ArchiveFile.bytes('TyLogVault/${entry.key}', entry.value.bytes),
          );
        }
        final bytes = ZipEncoder().encodeBytes(archive);
        request.response.headers.contentType = ContentType(
          'application',
          'zip',
        );
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        if (changeSnapshotAfterArchive && !archiveChanged && files.isNotEmpty) {
          archiveChanged = true;
          final first = files.entries.first;
          files[first.key] = _MutableRemoteFile(
            bytes: first.value.bytes,
            etag: '"changed-after-archive"',
            modified: first.value.modified.add(const Duration(seconds: 1)),
          );
        }
        await request.response.close();
        return;
      }
      getCounts?.update(path, (count) => count + 1, ifAbsent: () => 1);
      metrics?.individualGets++;
      metrics?.startTransfer();
      try {
        if (transferDelay != Duration.zero) await Future.delayed(transferDelay);
        final file = files[path];
        if (file == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else if (!interrupted && path == interruptGetOnce) {
          interrupted = true;
          request.response.contentLength = file.bytes.length + 10;
          final socket = await request.response.detachSocket(
            writeHeaders: true,
          );
          socket.add(file.bytes.take(1).toList());
          await socket.flush();
          socket.destroy();
          return;
        } else {
          request.response.headers.set(HttpHeaders.etagHeader, file.etag);
          request.response.add(file.bytes);
        }
      } finally {
        metrics?.finishTransfer();
      }
    } else if (request.method == 'PUT') {
      metrics?.puts++;
      metrics?.startTransfer();
      try {
        if (transferDelay != Duration.zero) await Future.delayed(transferDelay);
        final bytes = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        uploads?.add({
          'path': path,
          'body': utf8.decode(bytes),
          'checksum': request.headers.value('oc-checksum'),
          'ifMatch': request.headers.value(HttpHeaders.ifMatchHeader),
        });
        upgradedChecksums.add(path);
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
      } finally {
        metrics?.finishTransfer();
      }
    } else if (request.method == 'MOVE') {
      metrics?.moves++;
      final source = files[path];
      final destinationValue = request.headers.value('destination');
      final destination = destinationValue == null
          ? null
          : Uri.parse(destinationValue).path;
      final target = destination != null && destination.startsWith(root)
          ? destination.substring(root.length)
          : null;
      final ifMatch = request.headers.value(HttpHeaders.ifMatchHeader);
      if (rejectMove || source == null || ifMatch != source.etag) {
        request.response.statusCode = HttpStatus.preconditionFailed;
      } else if (target == null ||
          files.containsKey(target) ||
          request.headers.value('overwrite')?.toUpperCase() != 'F') {
        request.response.statusCode = HttpStatus.preconditionFailed;
      } else {
        files.remove(path);
        files[target] = source;
        request.response.statusCode = HttpStatus.created;
        request.response.headers.set('OC-Etag', source.etag);
      }
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
