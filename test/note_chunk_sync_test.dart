import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/retrieval/note_chunk_sync.dart';

void main() {
  test(
    'sync is incremental, replaces edits, deletes notes, and keeps PDFs',
    () async {
      final db = TyLogDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              id: 'pdf',
              kind: 'pdf',
              locator: const Value('paper.pdf'),
              createdAtMs: 1,
              updatedAtMs: 1,
            ),
          );
      await db
          .into(db.sourceVersions)
          .insert(
            SourceVersionsCompanion.insert(
              id: 'pdf-version',
              sourceId: 'pdf',
              sha256: 'pdf-hash',
              status: 'extracted',
              pagesJson: '[]',
              createdAtMs: 1,
            ),
          );

      final first = await syncNoteChunks(db, {
        'a.md': (title: 'A', text: 'first note'),
        'b.md': (title: 'B', text: 'second note'),
      });
      expect(first.added, 2);
      expect((await db.pendingChunks()).isNotEmpty, isTrue);
      final second = await syncNoteChunks(db, {
        'a.md': (title: 'A', text: 'first note'),
        'b.md': (title: 'B', text: 'second note'),
      });
      expect(second.unchanged, 2);
      expect(second.added, 0);
      final before = await db.select(db.sources).get();
      await syncNoteChunks(db, {
        'a.md': (title: 'A', text: 'first note'),
        'b.md': (title: 'B', text: 'second note'),
      });
      // An unchanged resync must not write (idle gate).
      expect(
        (await db.select(db.sources).get()).map((s) => s.updatedAtMs),
        before.map((s) => s.updatedAtMs),
      );
      final oldA = (await db.select(db.sourceVersions).get()).firstWhere(
        (version) => version.sourceId == 'note:a.md',
      );
      final edited = await syncNoteChunks(db, {
        'a.md': (title: 'A2', text: 'edited note'),
        'b.md': (title: 'B', text: 'second note'),
      });
      expect((edited.added, edited.unchanged, edited.removed), (1, 1, 0));
      expect(
        (await db.select(db.sourceVersions).get())
            .where((version) => version.sourceId == 'note:a.md')
            .single
            .id,
        isNot(oldA.id),
      );
      expect(
        (await db.select(db.chunks).get()).every(
          (chunk) => chunk.sourceVersionId != oldA.id,
        ),
        isTrue,
      );
      final result = await syncNoteChunks(db, {
        'a.md': (title: 'A2', text: 'edited note'),
      });
      expect(result.removed, 1);
      expect(
        (await db.select(db.sources).get()).map((source) => source.id),
        contains('pdf'),
      );
      expect(
        (await db.select(db.sources).get()).any(
          (source) => source.id == 'note:b.md',
        ),
        isFalse,
      );
    },
  );
}
