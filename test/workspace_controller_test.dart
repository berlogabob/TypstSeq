import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met in time');
    }
    await Future.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'controller owns open, source, save, and index with fake boundaries',
    () async {
      final storage = _MemoryStorage();
      final inspector = _FakeInspector();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: inspector,
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      const entry = VaultEntry(
        id: 'fake',
        name: 'Fake vault',
        path: '/not-used',
      );

      await controller.openVault(entry, storage: storage);

      // The fast path is already usable before the background index build
      // finishes.
      expect(controller.vault, isNotNull);
      expect(controller.note, startsWith('daily/'));
      expect(controller.source, contains('#import "/_system/tylog.typ"'));

      await _waitUntil(() => controller.index != null);
      expect(controller.index?.notes, hasLength(1));
      expect(inspector.calls, 1);

      controller.edit('${controller.source}\nController edit.\n');
      expect(controller.dirty, isTrue);
      await controller.save(syncAfter: false);
      expect(controller.dirty, isFalse);
      expect(
        await storage.readText(controller.note!),
        contains('Controller edit.'),
      );

      await controller.refreshIndex(force: true);
      expect(controller.index?.notes.single.metadataSource, 'typst-query');
      expect(inspector.calls, 2);
    },
  );

  test(
    'openVault loads user-vendored packages from _system/packages',
    () async {
      final storage = _MemoryStorage();
      final bytes = Uint8List.fromList(utf8.encode('#let hi() = "hello"\n'));
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      const entry = VaultEntry(
        id: 'vendored',
        name: 'Vendored vault',
        path: '/not-used',
      );

      // Establish the vault first (creates the settings marker + managed
      // files), then drop a user-vendored package in and reopen — this
      // mirrors a user copying a package into an existing vault.
      await controller.openVault(entry, storage: storage);
      await _waitUntil(() => controller.index != null && !controller.rebuilding);
      await storage.writeBytes('_system/packages/foo/1.0.0/lib.typ', bytes);
      await controller.openVault(entry, storage: storage);
      await _waitUntil(() => controller.index != null && !controller.rebuilding);

      expect(
        controller.typstPackageFiles['_system/packages/foo/1.0.0/lib.typ'],
        bytes,
      );
      expect(
        controller.typstPackageFiles['/_system/packages/foo/1.0.0/lib.typ'],
        bytes,
      );
    },
  );

  test(
    'openVault unblocks the UI before the background index finishes',
    () async {
      final storage = _GatedStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      const entry = VaultEntry(
        id: 'gated',
        name: 'Gated vault',
        path: '/not-used',
      );

      var notifyCount = 0;
      Object? vaultAtFirstNotify;
      Object? indexAtFirstNotify;
      controller.addListener(() {
        notifyCount++;
        if (notifyCount == 1) {
          vaultAtFirstNotify = controller.vault;
          indexAtFirstNotify = controller.index;
        }
      });

      await controller.openVault(entry, storage: storage);

      // openVault returns as soon as the fast reads are done: the
      // recursive scan the background rebuild needs is blocked on the
      // gate, so at the very first notification (and still once
      // openVault's own await completes) vault/note/source are already
      // populated but index is not.
      expect(vaultAtFirstNotify, isNotNull);
      expect(indexAtFirstNotify, isNull);
      expect(controller.vault, isNotNull);
      expect(controller.note, isNotNull);
      expect(controller.source, isNotEmpty);
      expect(controller.index, isNull);

      storage.gate.complete();
      await _waitUntil(() => controller.index != null);
      expect(controller.index?.notes, hasLength(1));
    },
  );

  test(
    'registered Android vault is never recreated when access is empty',
    () async {
      final storage = _MemoryStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.openVault(
        const VaultEntry(
          id: 'android',
          name: 'Android vault',
          path: '',
          storageKind: 'android-tree',
          treeUri: 'content://test/tree',
        ),
        storage: storage,
      );

      expect(controller.vault, isNull);
      expect(controller.status, startsWith('Open failed:'));
      expect(storage._directories, {''});
      expect(storage._files, isEmpty);
    },
  );

  test('failed initial sync does not activate draft cloud config', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
      storage: _MemoryStorage(),
    );
    final draft = NextcloudConfig(
      serverUrl:
          'http://${server.address.address}:${server.port}/remote.php/dav/files/alice/TyLogVault',
      username: 'alice',
      password: 'secret',
    );

    expect(
      await controller.syncNow(
        trigger: 'setup',
        configOverride: draft,
        initialMode: InitialSyncMode.safeMerge,
      ),
      isFalse,
    );
    expect(controller.cloud, isNull);
    expect(controller.syncing, isFalse);
  });

  test(
    'autosave landing mid-sync does not spuriously flag a conflict',
    () async {
      // TestWidgetsFlutterBinding installs a global HttpOverrides that fakes
      // every HttpClient with 400 responses (to keep other widget tests off
      // the network); this test needs a real WebDAV round-trip, so lift it
      // for the duration of this test only.
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: _MemoryStorage(),
      );
      await _waitUntil(() => controller.index != null);
      final path = controller.note!;
      final original = controller.source;
      controller.cloud = server.config;

      // Baseline sync uploads the vault's starter content and clears the
      // slate for the sync under test.
      expect(await controller.syncNow(trigger: 'setup'), isTrue);
      expect(controller.syncConflicts, isEmpty);

      // Arm the gate so the *next* sync's remote listing stalls at a known
      // point, giving a deterministic (non-wall-clock) window to land an
      // autosave mid-sync, after sourceBeforeSync has already been captured.
      server.armGate();
      final syncFuture = controller.syncNow(trigger: 'manual');
      await server.gateReached.future;

      // The user typed during the sync; the 400ms autosave timer landed the
      // new content on disk before the sync finished.
      controller.edit('$original\nEdited during sync.\n');
      await controller.save(syncAfter: false);

      server.releaseGate.complete();
      expect(await syncFuture, isTrue);

      // Disk holds exactly what the editor shows (our own autosave) --
      // nothing diverged, so no conflict should have been filed. Checking
      // syncConflicts alone would not distinguish "never created" from
      // "created, then self-healed": either way `status` must never have
      // flashed the alarming "Needs attention" a genuine conflict would
      // cause, since concurrentConflict is set at creation time regardless
      // of any later self-heal.
      expect(controller.syncConflicts, isEmpty);
      expect(controller.status, isNot(contains('attention')));
      expect(
        await controller.vault!.storage.readText(path),
        contains('Edited during sync.'),
      );
    },
  );

  test(
    'a genuine foreign disk change during sync still files a conflict',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: _MemoryStorage(),
      );
      await _waitUntil(() => controller.index != null);
      final path = controller.note!;
      final original = controller.source;
      controller.cloud = server.config;

      expect(await controller.syncNow(trigger: 'setup'), isTrue);
      expect(controller.syncConflicts, isEmpty);

      server.armGate();
      final syncFuture = controller.syncNow(trigger: 'manual');
      await server.gateReached.future;

      // The editor changes (so editorChanged becomes true) but the disk is
      // written by something other than our own autosave, with content that
      // matches neither the original nor the edited editor text.
      controller.edit('$original\nEdited during sync.\n');
      await controller.vault!.storage.writeText(path, 'foreign disk content');

      server.releaseGate.complete();
      expect(await syncFuture, isTrue);

      expect(controller.syncConflicts, hasLength(1));
      expect(controller.syncConflicts.single.path, path);
    },
  );

  test('sync errors explain resumable network and authentication failures', () {
    expect(
      friendlySyncError(const SocketException('offline')),
      contains('Progress was saved'),
    );
    expect(
      friendlySyncError(const HttpException('PROPFIND unexpected status 401')),
      'Nextcloud rejected the login. Re-enter the app password.',
    );
    // resolveConflict's etag-mismatch guard throws a StateError whose own
    // message tells the user what to do ("run sync and review the new
    // conflict"); friendlySyncError must not swallow that into a generic
    // message, since the fallback path is the only thing that surfaces it.
    expect(
      friendlySyncError(
        StateError('Nextcloud changed again; run sync and review the new conflict'),
      ),
      contains('Nextcloud changed again; run sync and review the new conflict'),
    );
  });

  test('stopCloudPolling cancels a running poll timer', () async {
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
      storage: _MemoryStorage(),
    );
    await _waitUntil(() => controller.index != null);
    controller.cloud = NextcloudConfig(
      serverUrl: 'http://127.0.0.1:1/remote.php/dav/files/alice/TyLogVault',
      username: 'alice',
      password: 'secret',
    );

    controller.startCloudPolling();
    expect(controller.hasActiveCloudPoll, isTrue);

    controller.stopCloudPolling();
    expect(controller.hasActiveCloudPoll, isFalse);
  });

  test(
    'a poll tick clears a phantom conflict instead of staying stuck forever',
    () async {
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: _MemoryStorage(),
      );
      await _waitUntil(() => controller.index != null);
      // Simulate self-heal: the in-memory list still holds a conflict, but
      // its record was already deleted from (or never written to) disk.
      controller.syncConflicts = [
        SyncConflict(
          id: 'phantom',
          path: 'notes/gone.typ',
          recordPath: '.tylog/conflicts/phantom.json',
          createdAt: DateTime.utc(2026),
          localExists: true,
          remoteExists: true,
        ),
      ];
      expect(controller.hasSyncConflicts, isTrue);

      await controller.pollTick();

      expect(controller.hasSyncConflicts, isFalse);
      expect(controller.syncConflicts, isEmpty);
    },
  );

  test('shouldRolloverToday detects a calendar day change', () {
    final openedAt = DateTime(2026, 7, 15, 23, 55);
    expect(
      shouldRolloverToday(
        openedAt: openedAt,
        now: DateTime(2026, 7, 15, 23, 59),
      ),
      isFalse,
    );
    expect(
      shouldRolloverToday(openedAt: openedAt, now: DateTime(2026, 7, 16, 0, 1)),
      isTrue,
    );
    expect(
      shouldRolloverToday(
        openedAt: DateTime(2026, 12, 31, 23, 59),
        now: DateTime(2027, 1, 1, 0, 1),
      ),
      isTrue,
    );
  });
}

class _FakeInspector implements TypstInspector {
  int calls = 0;

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    calls++;
    final note = scanNote(input.path, input.source);
    return [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {
          'schema': 1,
          'entity': 'note',
          'id': note.id,
          'title': note.title,
          'kind': note.kind,
          'date': note.date,
          'tags': note.tags,
          'aliases': note.aliases,
          'properties': note.properties,
        },
      ),
    ];
  }
}

class _MemoryStorage extends VaultStorage {
  final Map<String, Uint8List> _files = {};
  final Set<String> _directories = {''};

  @override
  Future<void> createDirectory(String path) async {
    if (path.isEmpty) return;
    final parts = path.split('/');
    for (var i = 1; i <= parts.length; i++) {
      _directories.add(parts.take(i).join('/'));
    }
  }

  @override
  Future<void> delete(String path) async {
    _files.removeWhere((key, _) => key == path || key.startsWith('$path/'));
    _directories.removeWhere((key) => key == path || key.startsWith('$path/'));
  }

  @override
  Future<bool> exists(String path) async =>
      _files.containsKey(path) || _directories.contains(path);

  @override
  Future<String> hash(String path) async => base64.encode(_files[path]!);

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final prefix = path.isEmpty ? '' : '$path/';
    bool included(String candidate) {
      if (!candidate.startsWith(prefix) || candidate == path) return false;
      return recursive || !candidate.substring(prefix.length).contains('/');
    }

    return [
      for (final directory in _directories)
        if (included(directory))
          VaultStorageEntry(path: directory, isDirectory: true),
      for (final entry in _files.entries)
        if (included(entry.key))
          VaultStorageEntry(
            path: entry.key,
            isDirectory: false,
            size: entry.value.length,
            modified: DateTime.utc(2026, 7, 14),
          ),
    ];
  }

  @override
  Future<Uint8List> readBytes(String path) async => _files[path]!;

  @override
  Future<VaultStorageEntry?> stat(String path) async {
    final bytes = _files[path];
    if (bytes != null) {
      return VaultStorageEntry(
        path: path,
        isDirectory: false,
        size: bytes.length,
        modified: DateTime.utc(2026, 7, 14),
      );
    }
    return _directories.contains(path)
        ? VaultStorageEntry(path: path, isDirectory: true)
        : null;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final slash = path.lastIndexOf('/');
    if (slash > 0) await createDirectory(path.substring(0, slash));
    _files[path] = Uint8List.fromList(bytes);
  }
}

/// A storage double whose recursive listing blocks until [gate] completes,
/// simulating a slow full-vault scan (e.g. Android SAF) so tests can observe
/// state while the background index rebuild is still in flight. Non-recursive
/// listing (used by the fast open path, e.g. sync-conflict lookup) is left
/// unblocked so `openVault` itself does not hang.
class _GatedStorage extends _MemoryStorage {
  final gate = Completer<void>();

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    if (recursive) await gate.future;
    return super.list(path: path, recursive: recursive);
  }
}

/// A minimal WebDAV double whose remote listing (PROPFIND) can be paused
/// mid-request via [armGate], then resumed via [releaseGate]. This gives a
/// deterministic window to observe/mutate state while a real `syncNow()` is
/// in flight, without relying on wall-clock timing races.
class _GatedWebDavServer {
  _GatedWebDavServer._(this.server);

  static const _root = '/remote.php/dav/files/alice/TyLogVault/';

  final HttpServer server;
  final Map<String, List<int>> _files = {};
  final Map<String, String> _etags = {};
  var _gateArmed = false;
  var gateReached = Completer<void>();
  var releaseGate = Completer<void>();

  static Future<_GatedWebDavServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _GatedWebDavServer._(server);
    instance._listen();
    return instance;
  }

  NextcloudConfig get config => NextcloudConfig(
    serverUrl:
        'http://${server.address.address}:${server.port}'
        '/remote.php/dav/files/alice/TyLogVault',
    username: 'alice',
    password: 'secret',
  );

  /// Arms the gate for the next PROPFIND only.
  void armGate() {
    _gateArmed = true;
    gateReached = Completer<void>();
    releaseGate = Completer<void>();
  }

  void _listen() {
    server.listen((request) async {
      final path = request.uri.path.startsWith(_root)
          ? request.uri.path.substring(_root.length)
          : '';
      switch (request.method) {
        case 'MKCOL':
          request.response.statusCode = HttpStatus.methodNotAllowed;
        case 'PROPFIND':
          if (_gateArmed) {
            _gateArmed = false;
            gateReached.complete();
            await releaseGate.future;
          }
          request.response.statusCode = 207;
          request.response.write('<d:multistatus xmlns:d="DAV:">');
          for (final entry in _files.entries) {
            request.response.write(
              '<d:response><d:href>$_root${entry.key}</d:href>'
              '<d:propstat><d:prop>'
              '<d:getlastmodified>'
              '${HttpDate.format(DateTime.now().toUtc())}'
              '</d:getlastmodified>'
              '<d:getetag>${_etags[entry.key]}</d:getetag>'
              '<d:getcontentlength>${entry.value.length}</d:getcontentlength>'
              '</d:prop></d:propstat></d:response>',
            );
          }
          request.response.write('</d:multistatus>');
        case 'GET':
          final bytes = _files[path];
          if (bytes == null) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.headers.set(
              HttpHeaders.etagHeader,
              _etags[path]!,
            );
            request.response.add(bytes);
          }
        case 'PUT':
          final bytes = await request.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          _files[path] = bytes;
          _etags[path] = '"etag-${DateTime.now().microsecondsSinceEpoch}"';
          request.response.statusCode = HttpStatus.created;
          request.response.headers.set('OC-Etag', _etags[path]!);
        default:
          request.response.statusCode = HttpStatus.methodNotAllowed;
      }
      await request.response.close();
    });
  }
}
