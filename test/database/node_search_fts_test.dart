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
      await persistDeletedVaultNote(
        database,
        path: 'notes/deleted.typ',
        previousSource:
            '#show: tylog.note.with(id: "deleted", title: "Gone")\nsecret',
        nowMs: 2,
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
}
