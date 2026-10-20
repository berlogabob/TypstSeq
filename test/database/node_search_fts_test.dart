import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  late TyLogDatabase database;

  setUp(() => database = TyLogDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test(
    'incrementally indexes Unicode node text and excludes tombstones',
    () async {
      await persistNoteSource(
        database: database,
        path: 'notes/pt.typ',
        source:
            '#show: tylog.note.with(id: "pt", title: "Ação")\nárvore rápida',
        updatedAtMs: 1,
      );
      await persistNoteSource(
        database: database,
        path: 'notes/deleted.typ',
        source: '#show: tylog.note.with(id: "deleted", title: "Gone")\nsecret',
        updatedAtMs: 1,
      );
      await persistNoteSource(
        database: database,
        deleted: true,
        path: 'notes/deleted.typ',
        source: '#show: tylog.note.with(id: "deleted", title: "Gone")\nsecret',
        updatedAtMs: 2,
      );

      expect(await database.searchNodeIds('acao'), ['pt']);
      expect(await database.searchNodeIds('arvore'), ['pt']);
      expect(await database.searchNodeIds('secret'), isEmpty);
      expect(database.searchNodeIds('acao', limit: 101), throwsArgumentError);
    },
  );

  test('rebuild repopulates the derived index', () async {
    await persistNoteSource(
      database: database,
      path: 'notes/a.typ',
      source: '#show: tylog.note.with(id: "a", title: "Alpha")\nbody',
      updatedAtMs: 1,
    );
    await database.customStatement('DELETE FROM node_search_fts');
    expect(await database.searchNodeIds('alpha'), isEmpty);
    await database.rebuildNodeSearch();
    expect(await database.searchNodeIds('alpha'), ['a']);
  });

  test('refreshNodeSearch reindexes only requested records', () async {
    await persistNoteSource(
      database: database,
      path: 'notes/a.typ',
      source: '#show: tylog.note.with(id: "a", title: "Alpha")\nbody',
      updatedAtMs: 1,
    );
    await persistNoteSource(
      database: database,
      path: 'notes/b.typ',
      source: '#show: tylog.note.with(id: "b", title: "Beta")\nbody',
      updatedAtMs: 1,
    );
    expect(await database.refreshNodeSearch(['a', 'a']), 1);
    expect(await database.searchNodeIds('alpha'), ['a']);
    expect(await database.searchNodeIds('beta'), ['b']);
  });

  test('finds Cyrillic entity titles and ref-note labels', () async {
    await persistNoteSource(
      database: database,
      path: 'notes/run.typ',
      source:
          '#show: tylog.note.with(id: "run", title: "Пробежка")\n',
      updatedAtMs: 1,
    );
    await persistNoteSource(
      database: database,
      path: 'daily/2023/04/2023-04-01.typ',
      source:
          '#show: tylog.note.with(id: "2023-04-01", title: "2023-04-01", kind: "daily")\n'
          '- #tylog.ref-note("Пробежка")[Пробежка]\n',
      updatedAtMs: 1,
    );

    expect(await database.searchNodeIds('пробежка'), ['run', '2023-04-01']);
  });

  test('resolves imported durable node IDs to note paths', () async {
    await persistNoteSource(
      database: database,
      path: 'daily/2023/04/2023-04-01.typ',
      source:
          '#show: tylog.note.with(id: "2023-04-01", title: "2023-04-01", kind: "daily")\n'
          '- #tylog.ref-note("Пробежка")[Пробежка]\n',
    );
    await database.customStatement(
      'UPDATE nodes SET id = ? WHERE id = ?',
      ['imported-daily-id', '2023-04-01'],
    );
    await database.customStatement(
      'UPDATE node_search_fts SET node_id = ? WHERE node_id = ?',
      ['imported-daily-id', '2023-04-01'],
    );

    expect(
      await database.nodePathsForIds(['imported-daily-id']),
      {'imported-daily-id': 'daily/2023/04/2023-04-01.typ'},
    );
  });
}
