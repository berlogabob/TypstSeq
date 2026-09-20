import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  test(
    'annotations remain attached to a source version and sort by offset',
    () async {
      final database = TyLogDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database
          .into(database.sources)
          .insert(
            SourcesCompanion.insert(
              id: 'source',
              kind: 'pdf',
              title: const Value('Paper'),
              locator: const Value('assets/paper.pdf'),
              createdAtMs: 1,
              updatedAtMs: 1,
            ),
          );
      await database
          .into(database.sourceVersions)
          .insert(
            SourceVersionsCompanion.insert(
              id: 'version',
              sourceId: 'source',
              sha256: 'a' * 64,
              status: 'extracted',
              pagesJson: '[]',
              createdAtMs: 2,
            ),
          );
      await database.saveAnnotation(
        id: 'late',
        sourceVersionId: 'version',
        page: 0,
        startOffset: 10,
        endOffset: 14,
        quote: 'late',
        context: 'before late after',
        createdAtMs: 3,
        updatedAtMs: 3,
      );
      await database.saveAnnotation(
        id: 'early',
        sourceVersionId: 'version',
        page: 0,
        startOffset: 1,
        endOffset: 4,
        quote: 'ear',
        context: 'early',
        createdAtMs: 4,
        updatedAtMs: 4,
      );
      expect((await database.annotationsFor('version')).map((row) => row.id), [
        'early',
        'late',
      ]);
    },
  );
}
