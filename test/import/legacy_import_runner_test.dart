import 'dart:convert';
import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/import/legacy_import_plan.dart';
import 'package:tylog/import/legacy_import_runner.dart';
import 'package:tylog_core/storage.dart';
import 'dart:io';

class S extends VaultStorage {
  final Map<String, List<int>> files;
  final Set<String> reads = {};
  final Set<String> failures = {};
  S(this.files);
  @override
  Future<bool> exists(String p) async => files.containsKey(p);
  @override
  Future<void> createDirectory(String p) async {}
  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async => files.keys
      .map(
        (p) => VaultStorageEntry(
          path: p,
          isDirectory: false,
          size: files[p]!.length,
        ),
      )
      .toList();
  @override
  Future<VaultStorageEntry?> stat(String p) async => null;
  @override
  Future<Uint8List> readBytes(String p) async {
    reads.add(p);
    if (failures.contains(p)) throw StateError('private failure: $p');
    return Uint8List.fromList(files[p]!);
  }

  @override
  Future<void> writeBytes(String p, List<int> b) async {}
  @override
  Future<void> delete(String p) async {}
  @override
  Future<String> hash(String p) async => '';
}

class WritableS extends S {
  WritableS(super.files);

  @override
  Future<void> writeBytes(String p, List<int> b) async {
    files[p] = List<int>.from(b);
  }
}

void main() {
  test('runs bounded batches and accounts outcomes', () async {
    final storage = S({
      'pages/a.md': [97],
      'journals/j.md': [98],
      'assets/x.png': [1],
      'misc/x': [2],
    });
    final manifest = await buildLegacyImportManifest(
      storage,
      LegacyImportDialect.logseq,
    );
    final dir = Directory.systemTemp.createTempSync('runner_');
    final db = await openDatabaseWithFile(File('${dir.path}/db'));
    addTearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });
    final job = ImportJobData(
      id: 'j',
      sourceKind: 'logseq',
      sourceFingerprint: manifest.fingerprint,
      status: 'running',
      totalCount: manifest.entries.length,
      completedCount: 0,
      createdAtMs: 1,
      updatedAtMs: 1,
      errorJson: '{}',
    );
    await db.createOrResumeImportJob(job, [
      for (final e in manifest.entries)
        ImportItemData(
          jobId: 'j',
          sourcePath: e.path,
          sourceSha256: null,
          state: 'pending',
          targetNodeId: null,
          targetPath: null,
          errorJson: '{}',
          updatedAtMs: 1,
        ),
    ]);
    final runner = LegacyImportRunner(
      database: db,
      storage: storage,
      manifest: manifest,
      converter: (e, s, h) async =>
          (e.kind == LegacyImportEntryKind.page ||
              e.kind == LegacyImportEntryKind.journal)
          ? (
              node: NodeData(
                id: e.path,
                type: 'note',
                title: e.path,
                content: s,
                attributesJson: '{}',
                createdAtMs: 1,
                updatedAtMs: 1,
              ),
              revision: RevisionData(
                id: 'r-${e.path}',
                entityKind: 'node',
                entityId: e.path,
                payloadJson: '{}',
                createdAtMs: 1,
              ),
              targetPath: '${e.path}.typ',
            )
          : null,
    );
    expect(await runner.runBatch('j', batchSize: 2), isTrue);
    expect(await runner.runBatch('j', batchSize: 2), isFalse);
    expect(await db.select(db.importItems).get(), hasLength(4));
    expect(await db.select(db.nodes).get(), hasLength(2));
  });

  test(
    'recreated runner processes exact bounded batches without duplicates',
    () async {
      final storage = S({
        for (var i = 0; i < 5; i++) 'pages/$i.md': [i],
      });
      final db = await _database(storage, addTearDown);
      final manifest = await buildLegacyImportManifest(
        storage,
        LegacyImportDialect.logseq,
      );
      await _initialize(db, manifest);
      var calls = 0;
      Future<({NodeData node, RevisionData revision, String targetPath})?>
      convert(LegacyImportEntry e, String source, String hash) async {
        calls++;
        return (
          node: NodeData(
            id: e.path,
            type: 'note',
            title: e.path,
            content: source,
            attributesJson: '{}',
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
          revision: RevisionData(
            id: 'r-${e.path}',
            entityKind: 'node',
            entityId: e.path,
            payloadJson: '{}',
            createdAtMs: 1,
          ),
          targetPath: '${e.path}.typ',
        );
      }

      for (var i = 0; i < 3; i++) {
        final before = calls;
        final more = await LegacyImportRunner(
          database: db,
          storage: storage,
          manifest: manifest,
          converter: convert,
        ).runBatch('job', batchSize: 2);
        expect(calls - before, lessThanOrEqualTo(2));
        if (!more) break;
      }
      expect(calls, 5);
      expect(await db.select(db.nodes).get(), hasLength(5));
      expect(await db.select(db.revisions).get(), hasLength(5));
      expect((await db.select(db.importJobs).getSingle()).completedCount, 5);
      expect((await db.select(db.importJobs).getSingle()).status, 'completed');
    },
  );

  test(
    'materializing an existing journal leaves the importer as revision owner',
    () async {
      final storage = WritableS({
        'journals/day.md': utf8.encode('legacy journal'),
        'daily/2026/01/2026-01-01.typ': utf8.encode('existing journal'),
      });
      final db = await _database(storage, addTearDown);
      final manifest = await buildLegacyImportManifest(
        storage,
        LegacyImportDialect.logseq,
      );
      await _initialize(db, manifest);
      const targetPath = 'daily/2026/01/2026-01-01.typ';
      const content = 'existing journal\n\n== From Logseq\n\nImported';
      await db.commitNodeEdit(
        node: const NodeData(
          id: 'existing-journal',
          type: 'daily',
          title: '2026-01-01',
          content: 'existing journal',
          attributesJson: '{"path":"daily/2026/01/2026-01-01.typ"}',
          createdAtMs: 10,
          updatedAtMs: 10,
        ),
        revision: const RevisionData(
          id: 'existing-journal-revision',
          entityKind: 'node',
          entityId: 'existing-journal',
          payloadJson: '{"source":"existing"}',
          createdAtMs: 10,
        ),
      );
      await db
          .into(db.importJobs)
          .insert(
            ImportJobsCompanion.insert(
              id: 'previous-job',
              sourceKind: 'logseq',
              sourceFingerprint: manifest.fingerprint,
              status: 'completed',
              totalCount: 1,
              completedCount: const Value(1),
              createdAtMs: 1,
              updatedAtMs: 20,
            ),
          );
      await db
          .into(db.importItems)
          .insert(
            ImportItemsCompanion.insert(
              jobId: 'previous-job',
              sourcePath: 'journals/old-day.md',
              state: 'written',
              targetNodeId: const Value('existing-journal'),
              targetPath: const Value(targetPath),
              updatedAtMs: 20,
            ),
          );
      final runner = LegacyImportRunner(
        database: db,
        storage: storage,
        manifest: manifest,
        converter: (entry, source, hash) async =>
            entry.path == 'journals/day.md'
            ? (() async {
                final identity = await legacyImportTargetIdentity(
                  database: db,
                  path: targetPath,
                  current: 'existing journal',
                  now: 30,
                );
                return (
                  node: NodeData(
                    id: identity.id,
                    type: 'daily',
                    title: '2026-01-01',
                    content: content,
                    attributesJson: '{"import_appended":true}',
                    createdAtMs: identity.createdAtMs,
                    updatedAtMs: 30,
                  ),
                  revision: RevisionData(
                    id: 'imported-journal-revision',
                    entityKind: 'node',
                    entityId: identity.id,
                    parentRevisionId: identity.parentRevisionId,
                    payloadJson: '{"source":"journals/day.md"}',
                    createdAtMs: 30,
                  ),
                  targetPath: targetPath,
                );
              })()
            : null,
        materializer: (_, node, path) async {
          await storage.writeText(path, node.content);
        },
      );

      expect(await runner.runBatch('job'), isFalse);
      expect(await storage.readText(targetPath), content);
      expect(await db.select(db.nodes).get(), hasLength(1));
      expect((await db.select(db.nodes).getSingle()).id, 'existing-journal');
      final revisions = await db.select(db.revisions).get();
      expect(revisions, hasLength(2));
      final imported = revisions.singleWhere(
        (revision) => revision.id == 'imported-journal-revision',
      );
      expect(imported.entityId, 'existing-journal');
      expect(imported.parentRevisionId, 'existing-journal-revision');
    },
  );

  test(
    'skips asset, unsupported, and empty without reading non-content files',
    () async {
      final storage = S({
        'pages/a.md': [97],
        'pages/empty.md': [],
        'assets/a.bin': [1],
        'other.bin': [2],
      });
      final db = await _database(storage, addTearDown);
      final manifest = await buildLegacyImportManifest(
        storage,
        LegacyImportDialect.logseq,
      );
      await _initialize(db, manifest);
      final runner = LegacyImportRunner(
        database: db,
        storage: storage,
        manifest: manifest,
        converter: (e, source, hash) async => e.path == 'pages/empty.md'
            ? null
            : (
                node: NodeData(
                  id: e.path,
                  type: 'note',
                  title: e.path,
                  content: source,
                  attributesJson: '{}',
                  createdAtMs: 1,
                  updatedAtMs: 1,
                ),
                revision: RevisionData(
                  id: 'r-${e.path}',
                  entityKind: 'node',
                  entityId: e.path,
                  payloadJson: '{}',
                  createdAtMs: 1,
                ),
                targetPath: '${e.path}.typ',
              ),
      );
      await runner.runBatch('job', batchSize: 10);
      expect(
        storage.reads,
        containsAll(<String>{'pages/a.md', 'pages/empty.md'}),
      );
      expect(storage.reads, isNot(contains('assets/a.bin')));
      expect(storage.reads, isNot(contains('other.bin')));
      final items = await db.select(db.importItems).get();
      expect(items.where((i) => i.state == 'skipped'), hasLength(3));
      expect(
        items.map((i) => jsonDecode(i.errorJson)['code']),
        containsAll(<String>[
          'legacy-import-asset',
          'legacy-import-unsupported',
          'legacy-import-empty',
        ]),
      );
    },
  );

  test(
    'read and converter failures are failed with fixed private-safe code',
    () async {
      final storage = S({
        'pages/read.md': [1],
        'pages/convert.md': [2],
        'pages/bad-utf8.md': [255],
      });
      storage.failures.add('pages/read.md');
      final db = await _database(storage, addTearDown);
      final manifest = await buildLegacyImportManifest(
        storage,
        LegacyImportDialect.logseq,
      );
      await _initialize(db, manifest);
      await LegacyImportRunner(
        database: db,
        storage: storage,
        manifest: manifest,
        converter: (e, source, hash) async =>
            throw StateError('secret ${e.path}'),
      ).runBatch('job', batchSize: 10);
      final items = await db.select(db.importItems).get();
      expect(items.every((i) => i.state == 'failed'), isTrue);
      expect(
        items.map((i) => i.errorJson),
        everyElement('{"code":"legacy-import-read-or-convert"}'),
      );
      expect(
        items.map((i) => i.errorJson),
        everyElement(isNot(contains('pages/'))),
      );
    },
  );

  test(
    'manifest mismatch and unknown checkpoint reject before reads',
    () async {
      final storage = S({
        'pages/a.md': [1],
      });
      final db = await _database(storage, addTearDown);
      final manifest = await buildLegacyImportManifest(
        storage,
        LegacyImportDialect.logseq,
      );
      await _initialize(db, manifest);
      final runner = LegacyImportRunner(
        database: db,
        storage: storage,
        manifest: manifest,
        converter: (e, s, h) async => null,
      );
      expect(() => runner.runBatch('missing'), throwsA(isA<StateError>()));
      final other = await buildLegacyImportManifest(
        storage,
        LegacyImportDialect.obsidian,
      );
      expect(
        () => LegacyImportRunner(
          database: db,
          storage: storage,
          manifest: other,
          converter: (e, s, h) async => null,
        ).runBatch('job'),
        throwsA(isA<StateError>()),
      );
      expect(storage.reads, isEmpty);
    },
  );

  test(
    'closed database propagates persistence failure and leaves item pending',
    () async {
      final storage = S({
        'pages/a.md': [1],
      });
      final db = await _database(storage, addTearDown);
      final manifest = await buildLegacyImportManifest(
        storage,
        LegacyImportDialect.logseq,
      );
      await _initialize(db, manifest);
      await db.close();
      expect(
        () => LegacyImportRunner(
          database: db,
          storage: storage,
          manifest: manifest,
          converter: (e, s, h) async => null,
        ).runBatch('job'),
        throwsA(anything),
      );
    },
  );

  test('resume reuses checkpointed materialization path', () async {
    final storage = S({'pages/a.md': utf8.encode('source')});
    final db = await _database(storage, addTearDown);
    final manifest = await buildLegacyImportManifest(
      storage,
      LegacyImportDialect.logseq,
    );
    await _initialize(db, manifest);
    var conversions = 0;
    var materializations = 0;
    final paths = <String>[];
    final materialized = <String, String>{};

    LegacyImportRunner runner() => LegacyImportRunner(
      database: db,
      storage: storage,
      manifest: manifest,
      converter: (entry, source, hash) async {
        conversions++;
        return (
          node: NodeData(
            id: 'node-$hash',
            type: 'note',
            title: entry.path,
            content: 'converted:$source',
            attributesJson: '{}',
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
          revision: RevisionData(
            id: 'revision-$hash',
            entityKind: 'node',
            entityId: 'node-$hash',
            payloadJson: '{}',
            createdAtMs: 1,
          ),
          targetPath: conversions == 1 ? 'pages/a.typ' : 'pages/a (2).typ',
        );
      },
      materializer: (item, node, targetPath) async {
        paths.add(targetPath);
        expect(node.content, 'converted:source');
        materialized[targetPath] = node.content;
        if (materializations++ == 0) throw StateError('interrupted');
      },
    );

    await expectLater(runner().runBatch('job'), throwsStateError);
    final checkpoint = await db.select(db.importItems).getSingle();
    expect(checkpoint.state, 'pending');
    expect(checkpoint.targetPath, 'pages/a.typ');
    expect(checkpoint.sourceSha256, isA<String>());
    expect(await db.select(db.revisions).get(), isEmpty);
    expect(materialized, {'pages/a.typ': 'converted:source'});

    expect(await runner().runBatch('job'), isFalse);
    expect(paths, ['pages/a.typ', 'pages/a.typ']);
    expect(materialized, {'pages/a.typ': 'converted:source'});
    expect(await db.select(db.nodes).get(), hasLength(1));
    expect(await db.select(db.revisions).get(), hasLength(1));
    final completed = await db.select(db.importItems).getSingle();
    expect(completed.state, 'written');
    expect(completed.targetPath, 'pages/a.typ');
  });

  test('terminal rows are unchanged on rerun', () async {
    final storage = S({
      'pages/a.md': [1],
    });
    final db = await _database(storage, addTearDown);
    final manifest = await buildLegacyImportManifest(
      storage,
      LegacyImportDialect.logseq,
    );
    await _initialize(db, manifest);
    await LegacyImportRunner(
      database: db,
      storage: storage,
      manifest: manifest,
      converter: (e, s, h) async => null,
    ).runBatch('job');
    final before = await db.select(db.importItems).getSingle();
    expect(
      await LegacyImportRunner(
        database: db,
        storage: storage,
        manifest: manifest,
        converter: (e, s, h) async => throw StateError('must not run'),
      ).runBatch('job'),
      isFalse,
    );
    expect(await db.select(db.importItems).getSingle(), before);
  });

  test('cancellation leaves unprocessed items pending for resume', () async {
    final storage = S({
      for (var i = 0; i < 3; i++) 'pages/$i.md': [i],
    });
    final db = await _database(storage, addTearDown);
    final manifest = await buildLegacyImportManifest(
      storage,
      LegacyImportDialect.logseq,
    );
    await _initialize(db, manifest);
    var cancelled = false;
    var cancelAfterFirst = true;
    Future<({NodeData node, RevisionData revision, String targetPath})?>
    convert(LegacyImportEntry entry, String source, String hash) async => (
      node: NodeData(
        id: entry.path,
        type: 'note',
        title: entry.path,
        content: source,
        attributesJson: '{}',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
      revision: RevisionData(
        id: 'r-${entry.path}',
        entityKind: 'node',
        entityId: entry.path,
        payloadJson: '{}',
        createdAtMs: 1,
      ),
      targetPath: '${entry.path}.typ',
    );
    final runner = LegacyImportRunner(
      database: db,
      storage: storage,
      manifest: manifest,
      shouldCancel: () => cancelled,
      converter: convert,
      materializer: (_, _, _) async {
        if (cancelAfterFirst) {
          cancelled = true;
          cancelAfterFirst = false;
        }
      },
    );

    expect(await runner.runBatch('job', batchSize: 3), isTrue);
    final paused = await db.select(db.importItems).get();
    expect(paused.where((item) => item.state == 'written'), hasLength(1));
    expect(paused.where((item) => item.state == 'pending'), hasLength(2));

    cancelled = false;
    expect(await runner.runBatch('job', batchSize: 3), isFalse);
    expect(
      (await db.select(db.importItems).get()).where(
        (item) => item.state == 'written',
      ),
      hasLength(3),
    );
  });
}

Future<TyLogDatabase> _database(
  S storage,
  void Function(FutureOr<void> Function()) registerTearDown,
) async {
  final dir = Directory.systemTemp.createTempSync('runner_more_');
  final db = await openDatabaseWithFile(File('${dir.path}/db'));
  Future<void> cleanup() async {
    await db.close();
    dir.deleteSync(recursive: true);
  }

  registerTearDown(cleanup);
  return db;
}

Future<void> _initialize(
  TyLogDatabase db,
  LegacyImportManifest manifest,
) async {
  await db.createOrResumeImportJob(
    ImportJobData(
      id: 'job',
      sourceKind: manifest.dialect.name,
      sourceFingerprint: manifest.fingerprint,
      status: 'running',
      totalCount: manifest.entries.length,
      completedCount: 0,
      createdAtMs: 1,
      updatedAtMs: 1,
      errorJson: '{}',
    ),
    [
      for (final e in manifest.entries)
        ImportItemData(
          jobId: 'job',
          sourcePath: e.path,
          sourceSha256: null,
          state: 'pending',
          targetNodeId: null,
          targetPath: null,
          errorJson: '{}',
          updatedAtMs: 1,
        ),
    ],
  );
}
