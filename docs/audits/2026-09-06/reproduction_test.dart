// Explicit audit tests live outside test/ so known failures do not enter CI.
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
// Audit probes: expected to fail on release 0.4.4+99.
// Run explicitly with flutter test; uses temporary/in-memory vaults only.
import 'package:tylog/models.dart';
import 'package:tylog/vault_worker.dart';
import 'package:flutter/material.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/work_surface.dart';
import 'package:tylog/knowledge_screen.dart';
import 'package:tylog/saved_searches.dart';
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

  test('AUDIT disposing worker terminates its active command', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_audit_worker_');
    addTearDown(() => dir.delete(recursive: true));
    await Vault(dir).ensureCreated();
    final worker = await VaultWorkerClient.spawn(
      entry: VaultEntry(id: 'audit', name: 'Audit', path: dir.path),
    );
    final finished = worker.run(const RebuildIndexCommand(stale: {})).toList();
    await worker.dispose();
    await finished.timeout(const Duration(seconds: 1));
  });

  testWidgets('AUDIT navigation retains edits when save fails', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final WorkspaceController controller = home.workspace;
    final storage = _MemoryStorage();
    await storage.writeText(
      'notes/a.typ',
      '#show: tylog.note.with(id: "a", title: "A")\nOriginal',
    );
    await storage.writeText('notes/b.typ', 'Other note');
    controller.vault = Vault.withStorage(storage);
    controller.replaceNote(
      'notes/a.typ',
      await storage.readText('notes/a.typ'),
    );
    // Emptying a real managed note is a real save rejection (Vault.saveNote).
    home.sourceController.text = '';
    controller.edit('');
    await tester.pump();
    home.mode = 'library';
    controller.notifyListeners();
    await tester.pump();
    final page = tester.widget<LibraryView>(find.byType(LibraryView));
    page.onOpenPath('notes/b.typ');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    print(
      'AUDIT after rejected save + navigation: note=${controller.note}, dirty=${controller.dirty}',
    );
    expect(controller.note, 'notes/a.typ');
    expect(controller.dirty, isTrue);
  });
  testWidgets('AUDIT saved search additions preserve earlier additions', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final WorkspaceController controller = home.workspace;
    final storage = _MemoryStorage();
    controller.vault = Vault.withStorage(storage);
    controller.index = const VaultIndex(
      notesByPath: {},
      backlinksByTarget: {},
      tasks: [],
    );
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    final screen = tester.widget<KnowledgeScreen>(find.byType(KnowledgeScreen));
    await screen.onSaveSearch!(const SavedSearch(name: 'First', query: 'one'));
    await screen.onSaveSearch!(const SavedSearch(name: 'Second', query: 'two'));
    final saved = await SavedSearchStore(storage).load();
    print(
      'AUDIT saved searches after two saves: ${saved.map((s) => s.name).toList()}',
    );
    expect(saved.map((s) => s.name), containsAll(['First', 'Second']));
  });

  test('AUDIT cold startup publishes index only once', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await _GatedWebDavServer.start();
    addTearDown(() => server.server.close(force: true));
    var reconciles = 0;
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {
        reconciles++;
      },
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      VaultEntry(
        id: 'audit',
        name: 'Audit',
        path: '/not-used',
        cloud: server.config,
      ),
      storage: _MemoryStorage(),
      trigger: 'startup',
    );
    await _waitUntil(
      () =>
          controller.index != null &&
          !controller.syncing &&
          !controller.rebuilding,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    print('AUDIT cold startup index publications: $reconciles');
    expect(reconciles, 1);
  });
  test('AUDIT failed polls without downloads do not reindex', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      r.response.statusCode = 401;
      await r.response.close();
    });
    addTearDown(() => server.close(force: true));
    var reconciles = 0;
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {
        reconciles++;
      },
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'audit', name: 'Audit', path: '/not-used'),
      storage: _MemoryStorage(),
    );
    await _waitUntil(() => controller.index != null && !controller.rebuilding);
    final before = reconciles;
    controller.cloud = NextcloudConfig(
      serverUrl: 'http://127.0.0.1:${server.port}/vault',
      username: 'audit',
      password: 'test-only',
    );
    await controller.pollTick();
    await controller.pollTick();
    print(
      'AUDIT index publications after two rejected polls: ${reconciles - before}',
    );
    expect(reconciles, before);
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

  /// Paths written, so a test can assert a write did *not* happen.
  final writes = <String>[];
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
    writes.add(path);
    final slash = path.lastIndexOf('/');
    if (slash > 0) await createDirectory(path.substring(0, slash));
    _files[path] = Uint8List.fromList(bytes);
  }
}

class _GatedWebDavServer {
  _GatedWebDavServer._(this.server);

  static const _root = '/remote.php/dav/files/alice/TyLogVault/';

  final HttpServer server;
  final Map<String, List<int>> _files = {};

  /// Paths the client PUT, so a test can assert what actually synced.
  final uploaded = <String>[];

  /// Fail every PUT past this many, so a batch can half-succeed.
  int? failUploadsAfter;
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
            request.response.headers.set(HttpHeaders.etagHeader, _etags[path]!);
            request.response.add(bytes);
          }
        case 'PUT':
          final bytes = await request.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          if (failUploadsAfter != null &&
              uploaded.length >= failUploadsAfter!) {
            request.response.statusCode = HttpStatus.internalServerError;
            break;
          }
          _files[path] = bytes;
          uploaded.add(path);
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
