import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/retrieval/note_chunk_sync.dart';
import 'package:tylog/retrieval/semantic_indexer.dart';

void main() {
  test(
    'embeds pending chunks, cancels between batches, and is single-flight',
    () async {
      final db = TyLogDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await syncNoteChunks(db, {
        'a.md': (title: 'A', text: List.filled(1600, 'a').join()),
      });
      var calls = 0;
      var cancel = false;
      final indexer = SemanticIndexer(
        db: db,
        batch: 1,
        embed: (_) async {
          calls++;
          cancel = true;
          return [1, 2];
        },
      );
      final first = indexer.runUntilIdle(cancelled: () => cancel);
      expect(identical(first, indexer.runUntilIdle()), isTrue);
      await first;
      expect(calls, 1);
      expect((await db.pendingChunks()).length, greaterThan(0));
      cancel = false;
      await indexer.runUntilIdle();
      expect(await db.pendingChunks(), isEmpty);
      expect(indexer.progress.value.running, isFalse);
    },
  );

  test('a chunk that always fails ends the run instead of spinning', () async {
    final db = TyLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await syncNoteChunks(db, {'a.md': (title: 'A', text: 'short note')});
    var calls = 0;
    final indexer = SemanticIndexer(
      db: db,
      embed: (_) async {
        calls++;
        throw StateError('model unavailable');
      },
    );
    await indexer.runUntilIdle().timeout(const Duration(seconds: 5));
    expect(calls, 1);
    expect(indexer.progress.value, (done: 0, pending: 1, running: false));
  });
}
