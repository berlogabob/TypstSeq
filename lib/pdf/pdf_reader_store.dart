import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../database/tylog_database.dart';
import '../retrieval/chunking.dart';
import '../vault_storage.dart';
import 'pdf_extraction.dart';

const _extractorVersion = 'pdf-reader-v1';

Future<PdfExtraction> persistPdfReaderExtraction({
  required TyLogDatabase database,
  required String path,
  required List<int> bytes,
  required List<String?> pageTexts,
}) async {
  validateVaultPath(path);
  final sourceId = 'pdf-source-${sha256.convert(utf8.encode(path))}';
  final extracted = versionPdfText(
    sourceVersionId: '',
    bytes: bytes,
    pageTexts: pageTexts,
  );
  return database.transaction(() async {
    final source =
        await (database.select(database.sources)
              ..where(
                (row) => row.kind.equals('pdf') & row.locator.equals(path),
              )
              ..limit(1))
            .getSingleOrNull();
    if (source == null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await database
          .into(database.sources)
          .insert(
            SourcesCompanion.insert(
              id: sourceId,
              kind: 'pdf',
              locator: Value(path),
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );
    }
    final sourceKey = source?.id ?? sourceId;
    final versionId = '$sourceKey:${extracted.sha256}:$_extractorVersion';
    final extraction = PdfExtraction(
      sourceVersionId: versionId,
      sha256: extracted.sha256,
      status: extracted.status,
      pages: extracted.pages,
      reason: extracted.reason,
    );
    final existing =
        await (database.select(database.sourceVersions)
              ..where((row) => row.id.equals(versionId))
              ..limit(1))
            .getSingleOrNull();
    if (existing == null) {
      await database.savePdfExtraction(
        sourceId: sourceKey,
        extraction: extraction,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (extraction.pages.isNotEmpty) {
        await database.saveChunks(
          chunkText(sourceVersionId: versionId, text: extraction.text),
        );
      }
    } else {
      final persistedPages = jsonDecode(existing.pagesJson) as List;
      if (persistedPages.length != extraction.pages.length ||
          List.generate(
            persistedPages.length,
            (i) =>
                persistedPages[i]['text'] != extraction.pages[i].text ||
                persistedPages[i]['start'] != extraction.pages[i].start ||
                persistedPages[i]['end'] != extraction.pages[i].end,
          ).any((changed) => changed)) {
        throw StateError(
          'PDF extraction changed without a new extractor version',
        );
      }
      final pages = persistedPages
          .map(
            (value) => PdfTextPage(
              page: (value as Map)['page'] as int,
              text: value['text'] as String,
              start: value['start'] as int,
              end: value['end'] as int,
            ),
          )
          .toList(growable: false);
      return PdfExtraction(
        sourceVersionId: existing.id,
        sha256: existing.sha256,
        status: PdfExtractionStatus.values.byName(existing.status),
        pages: pages,
        reason: existing.status == PdfExtractionStatus.unsupported.name
            ? 'no selectable text'
            : null,
      );
    }
    return extraction;
  });
}

Future<void> savePdfReaderSelection({
  required TyLogDatabase database,
  required PdfExtraction extraction,
  required int page,
  required int localStart,
  required int localEnd,
}) async {
  if (extraction.status != PdfExtractionStatus.extracted ||
      page < 0 ||
      page >= extraction.pages.length) {
    throw ArgumentError('selection page is not extracted');
  }
  final selectedPage = extraction.pages[page];
  if (selectedPage.text.isEmpty ||
      localStart < 0 ||
      localEnd <= localStart ||
      localEnd > selectedPage.text.length) {
    throw ArgumentError('selection range is outside the page text');
  }
  final quote = selectedPage.text.substring(localStart, localEnd);
  final context = selectedPage.text.substring(
    localStart - 40 < 0 ? 0 : localStart - 40,
    localEnd + 40 > selectedPage.text.length
        ? selectedPage.text.length
        : localEnd + 40,
  );
  await database.transaction(() async {
    final id = '${extraction.sourceVersionId}:$page:$localStart:$localEnd';
    final existing =
        await (database.select(database.annotations)
              ..where((row) => row.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.saveAnnotation(
      id: id,
      sourceVersionId: extraction.sourceVersionId,
      page: page,
      startOffset: selectedPage.start + localStart,
      endOffset: selectedPage.start + localEnd,
      quote: quote,
      context: context,
      createdAtMs: now,
      updatedAtMs: now,
    );
  });
}
