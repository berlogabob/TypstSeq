import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/pdf/pdf_extraction.dart';
import 'package:tylog/retrieval/chunking.dart';

void main() {
  test('chunks resume pending work and store embedding bytes', () async {
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
    final extraction = versionPdfText(
      sourceVersionId: 'version',
      bytes: '%PDF-1.7'.codeUnits,
      pageTexts: const ['text'],
    );
    await database.savePdfExtraction(
      sourceId: 'source',
      extraction: extraction,
      createdAtMs: 2,
    );
    final chunk = chunkText(sourceVersionId: 'version', text: 'text').single;
    await database.saveChunks([chunk]);
    expect((await database.pendingChunks()).single.id, chunk.id);
    await database.completeChunk(
      chunk.id,
      model: 'test-model',
      embedding: [1, 2],
    );
    expect(await database.pendingChunks(), isEmpty);
    expect((await database.select(database.chunks).get()).single.embedding, [
      1,
      2,
    ]);
  });
}
