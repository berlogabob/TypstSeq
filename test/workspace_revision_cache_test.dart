import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/database/revision_publisher.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (desktopManaged, omitListMetadata) in [
    (false, false),
    (false, true),
    (true, false),
    (true, true),
  ]) {
    test(
      'revision sync publishes, ingests and caches files '
      '(desktop: $desktopManaged, list metadata: ${!omitListMetadata})',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'revision-cache-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final storage = _CountingStorage(directory, omitListMetadata);
        final database = TyLogDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final controller = WorkspaceController(
          taskScheduler: TaskScheduler(),
          inspector: _FakeInspector(),
          reconcileTasks: (_) async {},
          databaseForVault: (_) async => database,
          useForegroundService: false,
        );
        addTearDown(controller.dispose);
        final entry = VaultEntry(
          id: 'local',
          name: 'Local',
          path: desktopManaged
              ? '${Platform.environment['HOME']}/Nextcloud/revision-test'
              : '/unused',
        );
        expect(isNextcloudManagedVault(Directory(entry.path)), desktopManaged);
        await controller.openVault(entry, storage: storage);
        await controller.refreshIndex(always: true);
        controller.note = null;
        controller.cloud = const NextcloudConfig(
          serverUrl: 'https://example.invalid/remote.php/dav/files/alice/Vault',
          username: 'alice',
          password: 'secret',
        );
        if (desktopManaged) {
          controller.note = 'notes/local.typ';
          controller.edit(
            '#show: tylog.note.with(id: "local", title: "Local")\nEdited',
          );
          expect(await controller.save(syncAfter: false), isTrue);
          controller.note = null;
          expect(await database.pendingRevisionUploads(), isNotEmpty);
          expect(await controller.syncNow(), isTrue);
          final files = await storage.list(path: '_system/revisions');
          expect(files, hasLength(1));
          final envelope = RevisionPublisher.decodeEnvelope(
            await storage.readBytes(files.single.path),
          );
          expect(envelope.node!.content, endsWith('Edited'));
          expect(await database.pendingRevisionUploads(), isEmpty);
          expect(controller.status, 'Sync handled by Nextcloud Desktop');
        }
        final localRevisionCount =
            (await database.select(database.revisions).get()).length;
        const path = '_system/revisions/remote.json';
        final node = NodeData(
          id: 'remote',
          type: 'note',
          title: 'Remote',
          content: 'first',
          attributesJson: '{}',
          eventStartMs: null,
          eventEndMs: null,
          createdAtMs: 1,
          updatedAtMs: 1,
        );
        final revision = RevisionData(
          id: 'remote-1',
          entityKind: 'node',
          entityId: 'remote',
          parentRevisionId: null,
          payloadJson: '{}',
          createdAtMs: 1,
        );
        Future<void> writeEnvelope(NodeData node, RevisionData revision) =>
            storage.writeText(
              path,
              jsonEncode({
                'node': node.toJson(),
                'revision': revision.toJson(),
              }),
            );
        await writeEnvelope(node, revision);
        final client = _ResolveHttpClient();
        await HttpOverrides.runZoned(
          () async {
            expect(await controller.syncNow(), isTrue);
            expect(storage.revisionReads, greaterThan(0));
            expect(
              await database.select(database.revisions).get(),
              hasLength(localRevisionCount + 1),
            );
            storage.revisionReads = 0;
            storage.revisionStats = 0;
            expect(await controller.syncNow(), isTrue);
            expect(storage.revisionReads, 0);
            if (!omitListMetadata) expect(storage.revisionStats, 0);

            // Size alone must not hide a file whose modification time changed.
            final file = File('${directory.path}/$path');
            final modified = (await file.stat()).modified;
            await file.setLastModified(
              modified.add(const Duration(seconds: 2)),
            );
            expect(await controller.syncNow(), isTrue);
            expect(storage.revisionReads, greaterThan(0));
            storage.revisionReads = 0;
            expect(await controller.syncNow(), isTrue);
            expect(storage.revisionReads, 0);

            // A changed envelope must still reach the receiver.
            await writeEnvelope(
              node.copyWith(content: 'second'),
              RevisionData(
                id: 'remote-2',
                entityKind: 'node',
                entityId: 'remote',
                parentRevisionId: 'remote-1',
                payloadJson: '{}',
                createdAtMs: 2,
              ),
            );
            expect(await controller.syncNow(), isTrue);
            expect(storage.revisionReads, greaterThan(0));
            expect(
              await database.select(database.revisions).get(),
              hasLength(localRevisionCount + 2),
            );

            expect(
              (await database.select(database.nodes).get())
                  .singleWhere((node) => node.id == 'remote')
                  .content,
              'second',
            );

            // Reopening the vault reuses the stamps persisted in the same
            // database, so nothing already ingested is read again.
            await controller.openVault(entry, storage: storage);
            await controller.refreshIndex(always: true);
            controller.note = null;
            controller.cloud = const NextcloudConfig(
              serverUrl:
                  'https://example.invalid/remote.php/dav/files/alice/Vault',
              username: 'alice',
              password: 'secret',
            );
            storage.revisionReads = 0;
            expect(await controller.syncNow(), isTrue);
            expect(storage.revisionReads, 0);
            if (desktopManaged) {
              await writeEnvelope(
                node.copyWith(content: 'divergent'),
                RevisionData(
                  id: 'remote-fork',
                  entityKind: 'node',
                  entityId: 'remote',
                  parentRevisionId: 'missing-parent',
                  payloadJson: '{}',
                  createdAtMs: 3,
                ),
              );
              expect(await controller.syncNow(), isTrue);
              expect(controller.status, 'Needs attention');
              expect(controller.syncError, isNull);
              storage.revisionReads = 0;
              expect(await controller.syncNow(), isTrue);
              expect(storage.revisionReads, 0);
              expect(controller.status, 'Sync handled by Nextcloud Desktop');
            }
          },
          createHttpClient: (_) {
            expect(
              desktopManaged,
              isFalse,
              reason: 'Desktop sync must use local I/O only',
            );
            return client;
          },
        );
      },
    );
  }
  test('desktop-managed vault without an in-app account still publishes '
      'revisions from the poll timer', () async {
    final directory = await Directory.systemTemp.createTemp('desktop-rev-');
    addTearDown(() => directory.delete(recursive: true));
    final storage = _CountingStorage(directory, false);
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
      databaseForVault: (_) async => database,
      useForegroundService: false,
    );
    addTearDown(controller.dispose);
    final entry = VaultEntry(
      id: 'local',
      name: 'Local',
      path: '${Platform.environment['HOME']}/Nextcloud/revision-test',
    );
    await controller.openVault(entry, storage: storage);
    await controller.refreshIndex(always: true);
    // No controller.cloud: the Mac's Nextcloud Desktop setup has no account.
    controller.note = 'notes/local.typ';
    controller.edit('#show: tylog.note.with(id: "local", title: "Local")\nMac');
    expect(await controller.save(syncAfter: false), isTrue);
    controller.note = null;
    expect(await database.pendingRevisionUploads(), isNotEmpty);
    controller.startCloudPolling();
    for (var i = 0; i < 50; i++) {
      if ((await storage.list(path: '_system/revisions')).isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await storage.list(path: '_system/revisions'), hasLength(1));
    controller.stopCloudPolling();
  });
}

class _CountingStorage extends LocalVaultStorage {
  _CountingStorage(super.root, this.omitListMetadata);
  final bool omitListMetadata;
  int revisionReads = 0;
  int revisionStats = 0;

  @override
  Future<Uint8List> readBytes(String path) {
    if (path.startsWith('_system/revisions/')) revisionReads++;
    return super.readBytes(path);
  }

  @override
  Future<VaultStorageEntry?> stat(String path) {
    if (path.startsWith('_system/revisions/')) revisionStats++;
    return super.stat(path);
  }

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final entries = await super.list(path: path, recursive: recursive);
    if (!omitListMetadata || path != '_system/revisions') return entries;
    return [
      for (final entry in entries)
        VaultStorageEntry(path: entry.path, isDirectory: entry.isDirectory),
    ];
  }
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

class _ResolveHttpClient implements HttpClient {
  final files = <String, List<int>>{};
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _ResolveRequest(url, method, files);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ResolveHeaders implements HttpHeaders {
  @override
  String? value(String name) =>
      ['etag', 'oc-etag'].contains(name.toLowerCase()) ? '"etag"' : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ResolveRequest implements HttpClientRequest {
  _ResolveRequest(this.url, this.method, this.files);
  final Uri url;
  final Map<String, List<int>> files;
  final bytes = <int>[];
  @override
  final String method;
  @override
  final headers = _ResolveHeaders();
  @override
  void add(List<int> data) => bytes.addAll(data);
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    if (method == 'PUT') files[url.path] = bytes;
    return _ResolveResponse(url, method, files);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ResolveResponse extends Stream<List<int>> implements HttpClientResponse {
  _ResolveResponse(this.url, this.method, this.files);
  final Uri url;
  final String method;
  final Map<String, List<int>> files;
  @override
  final headers = _ResolveHeaders();
  @override
  int get statusCode => method == 'MKCOL'
      ? 405
      : method == 'PUT'
      ? 201
      : method == 'GET'
      ? 200
      : 207;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  int get contentLength => method == 'GET' ? files[url.path]!.length : 0;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(
    method == 'GET'
        ? files[url.path]!
        : utf8.encode(
            '<d:multistatus xmlns:d="DAV:">${files.entries.map((file) => '<d:response><d:href>${file.key}</d:href><d:propstat><d:prop>'
                '<d:getetag>"etag"</d:getetag>'
                '<d:getlastmodified>Thu, 08 Oct 2026 12:00:00 GMT</d:getlastmodified>'
                '<d:getcontentlength>${file.value.length}</d:getcontentlength>'
                '</d:prop></d:propstat></d:response>').join()}</d:multistatus>',
          ),
  ).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
