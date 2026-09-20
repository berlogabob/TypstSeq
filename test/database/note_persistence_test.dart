import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  late TyLogDatabase database;

  setUp(() => database = TyLogDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test(
    'new note preserves source and scanned metadata in one durable edit',
    () async {
      const source = '''#show: tylog.note.with(
  id: "header-id",
  title: "Research note",
  tags: ("important",),
  properties: ("status": "draft",),
)
#tylog.ref-note("target")[Target]
#tylog.attachment("assets/paper.pdf")
Body''';

      final result = await persistNoteSource(
        database: database,
        path: 'notes/research.typ',
        source: source,
        updatedAtMs: 100,
      );
      final attributes =
          jsonDecode(result.node.attributesJson) as Map<String, dynamic>;

      expect(result.node.id, 'header-id');
      expect(result.node.content, source);
      expect(attributes['tags'], contains('important'));
      expect(attributes['outgoingLinks'], contains('target'));
      expect(attributes['attachments'], isNotEmpty);
      expect((attributes['properties'] as Map)['status'], 'draft');
      expect(await database.select(database.nodes).get(), hasLength(1));
      expect(await database.select(database.revisions).get(), hasLength(1));
      expect(await database.select(database.outboxEntries).get(), hasLength(1));
      expect(
        await database.select(database.derivedInvalidations).get(),
        hasLength(1),
      );
    },
  );

  test('second edit is parented and keeps node creation time', () async {
    final first = await persistNoteSource(
      database: database,
      path: 'notes/a.typ',
      source: '#show: tylog.note.with(id: "a", title: "A")\nfirst',
      updatedAtMs: 100,
    );
    final second = await persistNoteSource(
      database: database,
      path: 'notes/a.typ',
      source: '#show: tylog.note.with(id: "a", title: "A")\nsecond',
      updatedAtMs: 100,
    );

    expect(second.node.id, first.node.id);
    expect(second.node.createdAtMs, 100);
    expect(second.node.updatedAtMs, 101);
    expect(second.revision.parentRevisionId, first.revision.id);
    expect(await database.select(database.revisions).get(), hasLength(2));
    expect(await database.select(database.outboxEntries).get(), hasLength(2));
    expect(
      await database.select(database.derivedInvalidations).get(),
      hasLength(2),
    );
  });

  test('deleted note retains a tombstone revision', () async {
    const source = '#show: tylog.note.with(id: "a", title: "A")\nbody';
    final first = await persistNoteSource(
      database: database,
      path: 'notes/a.typ',
      source: source,
      updatedAtMs: 100,
    );

    final deleted = await persistDeletedVaultNote(
      database,
      path: 'notes/a.typ',
      previousSource: source,
      nowMs: 200,
    );
    final attributes =
        jsonDecode(deleted.node.attributesJson) as Map<String, dynamic>;

    expect(deleted.node.content, isEmpty);
    expect(attributes['deletedAtMs'], 200);
    expect(deleted.revision.parentRevisionId, first.revision.id);
    expect(await database.select(database.revisions).get(), hasLength(2));
  });

  test('import target path reuses its target node identity', () async {
    await database
        .into(database.importJobs)
        .insert(
          ImportJobsCompanion.insert(
            id: 'job',
            sourceKind: 'legacy',
            sourceFingerprint: 'fingerprint',
            status: 'running',
            totalCount: 1,
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        );
    await database
        .into(database.importItems)
        .insert(
          ImportItemsCompanion.insert(
            jobId: 'job',
            sourcePath: 'old/a.typ',
            state: 'written',
            targetNodeId: Value('imported-node'),
            targetPath: Value('notes/a.typ'),
            updatedAtMs: 1,
          ),
        );

    final result = await persistNoteSource(
      database: database,
      path: 'notes/a.typ',
      source: '#show: tylog.note.with(id: "header-id", title: "A")\nbody',
      updatedAtMs: 50,
    );

    expect(result.node.id, 'imported-node');
    expect(await database.select(database.nodes).get(), hasLength(1));
    expect(
      (await database.select(database.nodes).getSingle()).id,
      'imported-node',
    );
  });
}
