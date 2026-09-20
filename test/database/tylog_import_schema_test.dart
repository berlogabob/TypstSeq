import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  late Directory dir;
  late TyLogDatabase db;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('tylog_import_schema_');
    db = await openDatabaseWithFile(File('${dir.path}/db.sqlite'));
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('creates v5 import tables', () async {
    expect(db.schemaVersion, 5);
    expect(await db.select(db.importJobs).get(), isEmpty);
    expect(await db.select(db.importItems).get(), isEmpty);
  });

  test('upgrades a v4 database and preserves existing rows', () async {
    await db
        .into(db.databaseMetadata)
        .insert(
          const DatabaseMetadataData(
            key: 'existing',
            value: 'preserved',
            updatedAtMs: 7,
          ),
        );
    await db.close();
    final sqlite = sqlite3.open('${dir.path}/db.sqlite');
    sqlite.execute('DROP TABLE import_items');
    sqlite.execute('DROP TABLE import_jobs');
    sqlite.execute('PRAGMA user_version = 4');
    sqlite.close();
    db = await openDatabaseWithFile(File('${dir.path}/db.sqlite'));
    expect(db.schemaVersion, 5);
    expect(
      (await db.select(db.databaseMetadata).getSingle()).value,
      'preserved',
    );
    expect(await db.select(db.importJobs).get(), isEmpty);
  });

  test('item upsert is idempotent and pending query is bounded', () async {
    await db
        .into(db.importJobs)
        .insert(
          const ImportJobData(
            id: 'job',
            sourceKind: 'logseq',
            sourceFingerprint: 'sha',
            status: 'running',
            totalCount: 1,
            completedCount: 0,
            createdAtMs: 1,
            updatedAtMs: 1,
            errorJson: '{}',
          ),
        );
    final item = const ImportItemData(
      jobId: 'job',
      sourcePath: 'pages/a.md',
      sourceSha256: 'x',
      state: 'pending',
      targetNodeId: null,
      targetPath: null,
      errorJson: '{}',
      updatedAtMs: 2,
    );
    await db.into(db.importItems).insert(item);
    await db
        .into(db.importItems)
        .insertOnConflictUpdate(item.copyWith(sourceSha256: const Value('y')));
    expect(await db.pendingImportItems('job', limit: 1), hasLength(1));
    expect((await db.select(db.importItems).getSingle()).sourceSha256, 'y');
  });

  test('mark item and progress commit atomically', () async {
    await db
        .into(db.importJobs)
        .insert(
          const ImportJobData(
            id: 'job',
            sourceKind: 'logseq',
            sourceFingerprint: 'sha',
            status: 'running',
            totalCount: 1,
            completedCount: 0,
            createdAtMs: 1,
            updatedAtMs: 1,
            errorJson: '{}',
          ),
        );
    await db.markImportItem(
      item: const ImportItemData(
        jobId: 'job',
        sourcePath: 'pages/a.md',
        sourceSha256: 'x',
        state: 'written',
        targetNodeId: 'node',
        targetPath: 'a.typ',
        errorJson: '{}',
        updatedAtMs: 2,
      ),
      completedCount: 1,
      status: 'completed',
    );
    expect((await db.select(db.importItems).getSingle()).state, 'written');
    final job = await db.select(db.importJobs).getSingle();
    expect(job.completedCount, 1);
    expect(job.status, 'completed');

    await db
        .into(db.importJobs)
        .insert(
          const ImportJobData(
            id: 'job2',
            sourceKind: 'logseq',
            sourceFingerprint: 'sha',
            status: 'running',
            totalCount: 1,
            completedCount: 0,
            createdAtMs: 1,
            updatedAtMs: 1,
            errorJson: '{}',
          ),
        );
    await expectLater(
      db.markImportItem(
        item: const ImportItemData(
          jobId: 'job2',
          sourcePath: 'pages/b.md',
          sourceSha256: 'x',
          state: 'written',
          targetNodeId: 'node',
          targetPath: 'b.typ',
          errorJson: '{}',
          updatedAtMs: 3,
        ),
        completedCount: 2,
        status: 'completed',
      ),
      throwsException,
    );
    expect(await db.select(db.importItems).get(), hasLength(1));
    final unchanged = await (db.select(
      db.importJobs,
    )..where((t) => t.id.equals('job2'))).getSingle();
    expect(unchanged.completedCount, 0);
    expect(unchanged.status, 'running');
  });

  test('rejects invalid progress and item state', () async {
    expect(
      () => db
          .into(db.importJobs)
          .insert(
            const ImportJobData(
              id: 'bad',
              sourceKind: 'logseq',
              sourceFingerprint: 'sha',
              status: 'running',
              totalCount: 1,
              completedCount: 2,
              createdAtMs: 1,
              updatedAtMs: 1,
              errorJson: '{}',
            ),
          ),
      throwsException,
    );
    await db
        .into(db.importJobs)
        .insert(
          const ImportJobData(
            id: 'job',
            sourceKind: 'logseq',
            sourceFingerprint: 'sha',
            status: 'running',
            totalCount: 1,
            completedCount: 0,
            createdAtMs: 1,
            updatedAtMs: 1,
            errorJson: '{}',
          ),
        );
    expect(
      () => db
          .into(db.importItems)
          .insert(
            const ImportItemData(
              jobId: 'job',
              sourcePath: 'bad',
              sourceSha256: null,
              state: 'oops',
              targetNodeId: null,
              targetPath: null,
              errorJson: '{}',
              updatedAtMs: 1,
            ),
          ),
      throwsException,
    );
  });

  test(
    'imported node commit rolls back all rows on invalid progress',
    () async {
      await db
          .into(db.importJobs)
          .insert(
            const ImportJobData(
              id: 'job',
              sourceKind: 'logseq',
              sourceFingerprint: 'sha',
              status: 'running',
              totalCount: 1,
              completedCount: 0,
              createdAtMs: 1,
              updatedAtMs: 1,
              errorJson: '{}',
            ),
          );
      final node = NodeData(
        id: 'node',
        type: 'note',
        title: 'N',
        content: 'C',
        attributesJson: '{}',
        createdAtMs: 1,
        updatedAtMs: 1,
      );
      final revision = RevisionData(
        id: 'rev',
        entityKind: 'node',
        entityId: 'node',
        payloadJson: '{}',
        createdAtMs: 1,
      );
      final item = const ImportItemData(
        jobId: 'job',
        sourcePath: 'pages/a.md',
        sourceSha256: 'x',
        state: 'written',
        targetNodeId: 'node',
        targetPath: 'a.typ',
        errorJson: '{}',
        updatedAtMs: 2,
      );
      await expectLater(
        db.commitImportedNode(
          node: node,
          revision: revision,
          item: item,
          completedCount: 2,
          status: 'completed',
        ),
        throwsException,
      );
      expect(await db.select(db.nodes).get(), isEmpty);
      expect(await db.select(db.revisions).get(), isEmpty);
      expect(await db.select(db.outboxEntries).get(), isEmpty);
      expect(await db.select(db.importItems).get(), isEmpty);
      final job = await db.select(db.importJobs).getSingle();
      expect(job.completedCount, 0);
      expect(job.status, 'running');
    },
  );

  test('imported node commit writes every related row', () async {
    await db
        .into(db.importJobs)
        .insert(
          const ImportJobData(
            id: 'job',
            sourceKind: 'logseq',
            sourceFingerprint: 'sha',
            status: 'running',
            totalCount: 1,
            completedCount: 0,
            createdAtMs: 1,
            updatedAtMs: 1,
            errorJson: '{}',
          ),
        );
    final node = NodeData(
      id: 'node',
      type: 'note',
      title: 'N',
      content: 'C',
      attributesJson: '{}',
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    final revision = RevisionData(
      id: 'rev',
      entityKind: 'node',
      entityId: 'node',
      payloadJson: '{}',
      createdAtMs: 1,
    );
    await db.commitImportedNode(
      node: node,
      revision: revision,
      item: const ImportItemData(
        jobId: 'job',
        sourcePath: 'pages/a.md',
        sourceSha256: 'x',
        state: 'written',
        targetNodeId: 'node',
        targetPath: 'a.typ',
        errorJson: '{}',
        updatedAtMs: 2,
      ),
      completedCount: 1,
      status: 'completed',
    );
    expect(await db.select(db.nodes).get(), hasLength(1));
    expect(await db.select(db.revisions).get(), hasLength(1));
    expect(await db.select(db.outboxEntries).get(), hasLength(1));
    expect(await db.select(db.derivedInvalidations).get(), hasLength(1));
    expect((await db.select(db.importItems).getSingle()).state, 'written');
    final job = await db.select(db.importJobs).getSingle();
    expect(job.completedCount, 1);
    expect(job.status, 'completed');
  });

  test('creates and resumes an import job idempotently', () async {
    const job = ImportJobData(
      id: 'job',
      sourceKind: 'logseq',
      sourceFingerprint: 'sha',
      status: 'running',
      totalCount: 2,
      completedCount: 0,
      createdAtMs: 1,
      updatedAtMs: 1,
      errorJson: '{}',
    );
    const first = ImportItemData(
      jobId: 'job',
      sourcePath: 'pages/a.md',
      sourceSha256: 'a',
      state: 'pending',
      targetNodeId: null,
      targetPath: null,
      errorJson: '{}',
      updatedAtMs: 1,
    );
    const second = ImportItemData(
      jobId: 'job',
      sourcePath: 'pages/b.md',
      sourceSha256: 'b',
      state: 'pending',
      targetNodeId: null,
      targetPath: null,
      errorJson: '{}',
      updatedAtMs: 1,
    );
    await db.createOrResumeImportJob(job, [first, second]);
    await db.markImportItem(
      item: first.copyWith(state: 'written'),
      completedCount: 1,
      status: 'running',
    );
    await db.createOrResumeImportJob(job, [first, second]);
    expect((await db.select(db.importItems).get()).first.state, 'written');
    expect((await db.select(db.importJobs).getSingle()).completedCount, 1);
  });

  test('rejects resume identity mismatch without writes', () async {
    const job = ImportJobData(
      id: 'job',
      sourceKind: 'logseq',
      sourceFingerprint: 'sha',
      status: 'running',
      totalCount: 0,
      completedCount: 0,
      createdAtMs: 1,
      updatedAtMs: 1,
      errorJson: '{}',
    );
    await db.createOrResumeImportJob(job, const []);
    await expectLater(
      db.createOrResumeImportJob(
        job.copyWith(sourceFingerprint: 'other'),
        const [],
      ),
      throwsArgumentError,
    );
    expect(
      (await db.select(db.importJobs).getSingle()).sourceFingerprint,
      'sha',
    );
    expect(await db.select(db.importItems).get(), isEmpty);
  });

  test('rejects invalid initialization before creating a job', () async {
    const item = ImportItemData(
      jobId: 'bad',
      sourcePath: 'pages/a.md',
      sourceSha256: 'x',
      state: 'written',
      targetNodeId: null,
      targetPath: null,
      errorJson: '{}',
      updatedAtMs: 1,
    );
    const job = ImportJobData(
      id: 'bad',
      sourceKind: 'logseq',
      sourceFingerprint: 'sha',
      status: 'completed',
      totalCount: 2,
      completedCount: 1,
      createdAtMs: 1,
      updatedAtMs: 1,
      errorJson: '{}',
    );
    await expectLater(
      db.createOrResumeImportJob(job, [item]),
      throwsArgumentError,
    );
    expect(await db.select(db.importJobs).get(), isEmpty);
  });

  test(
    'resume reopens cancelled jobs and stale workers cannot commit',
    () async {
      const job = ImportJobData(
        id: 'cancelled',
        sourceKind: 'logseq',
        sourceFingerprint: 'sha',
        status: 'running',
        totalCount: 1,
        completedCount: 0,
        createdAtMs: 1,
        updatedAtMs: 1,
        errorJson: '{}',
      );
      const item = ImportItemData(
        jobId: 'cancelled',
        sourcePath: 'pages/a.md',
        sourceSha256: 'a',
        state: 'pending',
        targetNodeId: null,
        targetPath: null,
        errorJson: '{}',
        updatedAtMs: 1,
      );
      await db.createOrResumeImportJob(job, [item]);
      await db.cancelImportJob('cancelled', nowMs: 2);
      await expectLater(
        db.markImportItem(
          item: item.copyWith(state: 'written'),
          completedCount: 1,
          status: 'completed',
        ),
        throwsStateError,
      );
      expect(await db.resumeImportJob('cancelled'), [item]);
      expect((await db.select(db.importJobs).getSingle()).status, 'running');
    },
  );
}
