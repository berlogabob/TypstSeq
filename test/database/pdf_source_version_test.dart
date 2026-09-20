import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/pdf/pdf_extraction.dart';

void main() {
  test(
    'PDF extraction versions persist with stable offsets and status',
    () async {
      final database = TyLogDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database
          .into(database.sources)
          .insert(
            SourcesCompanion.insert(
              id: 'source-1',
              kind: 'pdf',
              title: const Value('Paper'),
              locator: const Value('assets/paper.pdf'),
              createdAtMs: 1,
              updatedAtMs: 1,
            ),
          );
      final extraction = versionPdfText(
        sourceVersionId: 'source-1-v1',
        bytes: '%PDF-1.7'.codeUnits,
        pageTexts: const ['one', 'two'],
      );
      await database.savePdfExtraction(
        sourceId: 'source-1',
        extraction: extraction,
        createdAtMs: 10,
      );
      final versions = await database.sourceVersionsFor('source-1');
      expect(versions.single.id, 'source-1-v1');
      expect(versions.single.status, 'extracted');
      expect(versions.single.pagesJson, contains('"start":0'));
      expect(versions.single.pagesJson, contains('"start":4'));
    },
  );
}
