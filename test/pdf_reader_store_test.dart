import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/pdf/pdf_extraction.dart';
import 'package:tylog/pdf/pdf_reader_store.dart';

void main() {
  test('persists stable source/version and chunks only once', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final first = await persistPdfReaderExtraction(
      database: database,
      path: 'assets/paper.pdf',
      bytes: const [37, 80, 68, 70, 45, 49],
      pageTexts: const ['Alpha'],
    );
    final second = await persistPdfReaderExtraction(
      database: database,
      path: 'assets/paper.pdf',
      bytes: const [37, 80, 68, 70, 45, 49],
      pageTexts: const ['Alpha'],
    );
    expect(second.sourceVersionId, first.sourceVersionId);
    expect(await database.select(database.sources).get(), hasLength(1));
    expect(await database.select(database.sourceVersions).get(), hasLength(1));
    expect(await database.select(database.chunks).get(), hasLength(1));
  });

  test('rejects a changed projection under the same source version', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final first = await persistPdfReaderExtraction(
      database: database,
      path: 'assets/paper.pdf',
      bytes: const [37, 80, 68, 70, 45, 49],
      pageTexts: const ['persisted'],
    );
    expect(
      () => persistPdfReaderExtraction(
        database: database,
        path: 'assets/paper.pdf',
        bytes: const [37, 80, 68, 70, 45, 49],
        pageTexts: const ['different reader projection'],
      ),
      throwsStateError,
    );
    expect(
      (await database.sourceVersionsFor(
        (await database.select(database.sources).get()).single.id,
      )).single.id,
      first.sourceVersionId,
    );
  });

  test('changed bytes retain old version and selection offsets', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final old = await persistPdfReaderExtraction(
      database: database,
      path: 'assets/paper.pdf',
      bytes: const [37, 80, 68, 70, 45, 49],
      pageTexts: const ['zero Alpha omega'],
    );
    await savePdfReaderSelection(
      database: database,
      extraction: old,
      page: 0,
      localStart: 5,
      localEnd: 10,
    );
    final next = await persistPdfReaderExtraction(
      database: database,
      path: 'assets/paper.pdf',
      bytes: const [37, 80, 68, 70, 45, 50],
      pageTexts: const ['new Alpha'],
    );
    expect(next.sourceVersionId, isNot(old.sourceVersionId));
    expect(await database.select(database.sourceVersions).get(), hasLength(2));
    final annotations = await database.annotationsFor(old.sourceVersionId);
    expect(annotations.single.startOffset, 5);
    expect(annotations.single.endOffset, 10);
  });

  test('rejects unsafe and invalid selections', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    expect(
      () => persistPdfReaderExtraction(
        database: database,
        path: '../paper.pdf',
        bytes: const [37, 80, 68, 70, 45, 49],
        pageTexts: const ['Alpha'],
      ),
      throwsArgumentError,
    );
    const extraction = PdfExtraction(
      sourceVersionId: 'v',
      sha256: 'a',
      status: PdfExtractionStatus.extracted,
      pages: [PdfTextPage(page: 0, text: 'Alpha', start: 0, end: 5)],
    );
    expect(
      () => savePdfReaderSelection(
        database: database,
        extraction: extraction,
        page: 0,
        localStart: 1,
        localEnd: 6,
      ),
      throwsArgumentError,
    );
    expect(
      () => savePdfReaderSelection(
        database: database,
        extraction: extraction,
        page: 0,
        localStart: 1,
        localEnd: 1,
      ),
      throwsArgumentError,
    );
  });

  test(
    'reassigns an existing highlight without changing its identity',
    () async {
      final database = TyLogDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final extraction = await persistPdfReaderExtraction(
        database: database,
        path: 'assets/paper.pdf',
        bytes: const [37, 80, 68, 70, 45, 49],
        pageTexts: const ['Alpha beta'],
      );
      await savePdfReaderSelection(
        database: database,
        extraction: extraction,
        page: 0,
        localStart: 0,
        localEnd: 5,
      );
      final id = '${extraction.sourceVersionId}:0:0:5';
      await reassignPdfReaderSelection(
        database: database,
        annotationId: id,
        extraction: extraction,
        page: 0,
        localStart: 6,
        localEnd: 10,
      );
      final saved = (await database.annotationsFor(
        extraction.sourceVersionId,
      )).single;
      expect(saved.id, id);
      expect(saved.quote, 'beta');
      expect(saved.startOffset, 6);
      expect(saved.endOffset, 10);
    },
  );
}
