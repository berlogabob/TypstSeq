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

  test('retrieved chunk resolves to a stable source range', () async {
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
    expect(await database.navigationForChunk(chunk.id), (
      chunkId: chunk.id,
      sourceId: 'source',
      sourceVersionId: 'version',
      startOffset: 0,
      endOffset: 4,
    ));
    expect(await database.navigationForChunk('missing'), equals(null));
  });

  test('retrieved chunk batch resolves in caller order', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.sources)
        .insert(
          SourcesCompanion.insert(
            id: 'source',
            kind: 'pdf',
            title: const Value('Example paper'),
            locator: const Value('papers/example.pdf'),
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        );
    await database.savePdfExtraction(
      sourceId: 'source',
      extraction: versionPdfText(
        sourceVersionId: 'version',
        bytes: '%PDF-1.7'.codeUnits,
        pageTexts: const ['one two'],
      ),
      createdAtMs: 2,
    );
    final chunks = chunkText(
      sourceVersionId: 'version',
      text: 'one two',
      targetLength: 3,
      overlap: 0,
    );
    await database.saveChunks(chunks);
    await database
        .into(database.sources)
        .insert(
          SourcesCompanion.insert(
            id: 'web-source',
            kind: 'web',
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        );
    await database.savePdfExtraction(
      sourceId: 'web-source',
      extraction: versionPdfText(
        sourceVersionId: 'web-version',
        bytes: '%PDF-1.7'.codeUnits,
        pageTexts: const ['web'],
      ),
      createdAtMs: 2,
    );
    final webChunk = chunkText(
      sourceVersionId: 'web-version',
      text: 'web',
    ).single;
    await database.saveChunks([webChunk]);

    final hits = await database.navigationForChunks([
      webChunk.id,
      chunks.last.id,
      'missing',
      chunks.first.id,
    ]);
    expect(hits.map((hit) => hit.chunkId), [
      webChunk.id,
      chunks.last.id,
      chunks.first.id,
    ]);
    expect(hits.map((hit) => hit.sourceId), ['web-source', 'source', 'source']);
    final pdfCitations = await database.pdfCitationsForChunks([
      webChunk.id,
      chunks.last.id,
    ]);
    expect(pdfCitations.map((hit) => hit.chunkId), [chunks.last.id]);
    expect(pdfCitations.single.sourceKind, 'pdf');
    expect(pdfCitations.single.sourceLocator, 'papers/example.pdf');
    expect(pdfCitations.single.sourceTitle, 'Example paper');
    expect(pdfCitations.single.sourceVersionId, 'version');
    expect(pdfCitations.single.content, 'o');
  });
}
