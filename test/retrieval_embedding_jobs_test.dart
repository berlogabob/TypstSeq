import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/pdf/pdf_extraction.dart';
import 'package:tylog/retrieval/chunking.dart';
import 'package:tylog/retrieval/embedding_jobs.dart';

void main() {
  test('bounded embedding batches resume after a failed item', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.sources)
        .insert(
          SourcesCompanion.insert(
            id: 'source',
            kind: 'pdf',
            title: const Value('Paper'),
            locator: const Value('paper.pdf'),
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        );
    await database.savePdfExtraction(
      sourceId: 'source',
      extraction: versionPdfText(
        sourceVersionId: 'version',
        bytes: '%PDF-1.7'.codeUnits,
        pageTexts: const ['one two three'],
      ),
      createdAtMs: 2,
    );
    await database.saveChunks([
      ...chunkText(
        sourceVersionId: 'version',
        text: 'one two',
        targetLength: 3,
        overlap: 0,
      ),
    ]);
    var attempts = 0;
    final first = await runEmbeddingBatch(
      database: database,
      model: 'fake-v1',
      limit: 1,
      embed: (_) async {
        attempts++;
        throw StateError('offline');
      },
    );
    expect(first.claimed, 1);
    expect(first.completed, 0);
    expect(first.failed, 1);
    expect((await database.pendingChunks()).length, 3);
    final second = await runEmbeddingBatch(
      database: database,
      model: 'fake-v1',
      embed: (text) async => [text.length],
    );
    expect(second.claimed, 3);
    expect(second.completed, 3);
    expect(second.failed, 0);
    expect(attempts, 1);
    expect(await database.pendingChunks(), isEmpty);
    expect(
      (await database.select(database.chunks).get()).every(
        (chunk) => chunk.embeddingModel == 'fake-v1' && chunk.embedding != null,
      ),
      isTrue,
    );
  });
}
