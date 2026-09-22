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
  final values = _selectionValues(extraction, page, localStart, localEnd);
  final id = '${extraction.sourceVersionId}:$page:$localStart:$localEnd';
  final existing =
      await (database.select(database.annotations)
            ..where((row) => row.id.equals(id))
            ..limit(1))
          .getSingleOrNull();
  if (existing != null) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  await _commitAnnotation(
    database,
    AnnotationData(
      id: id,
      sourceVersionId: extraction.sourceVersionId,
      page: page,
      startOffset: values.startOffset,
      endOffset: values.endOffset,
      quote: values.quote,
      context: values.context,
      createdAtMs: now,
      updatedAtMs: now,
    ),
  );
}

Future<void> reassignPdfReaderSelection({
  required TyLogDatabase database,
  required String annotationId,
  required PdfExtraction extraction,
  required int page,
  required int localStart,
  required int localEnd,
}) async {
  final values = _selectionValues(extraction, page, localStart, localEnd);
  final existing = await (database.select(
    database.annotations,
  )..where((row) => row.id.equals(annotationId))).getSingleOrNull();
  if (existing == null) throw StateError('annotation does not exist');
  await _commitAnnotation(
    database,
    existing.copyWith(
      sourceVersionId: extraction.sourceVersionId,
      page: page,
      startOffset: values.startOffset,
      endOffset: values.endOffset,
      quote: values.quote,
      context: values.context,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  );
}

Future<void> _commitAnnotation(
  TyLogDatabase database,
  AnnotationData annotation,
) async {
  final parent =
      await (database.select(database.revisions)
            ..where(
              (row) =>
                  row.entityKind.equals('annotation') &
                  row.entityId.equals(annotation.id),
            )
            ..orderBy([
              (row) => OrderingTerm.desc(row.createdAtMs),
              (row) => OrderingTerm.desc(row.id),
            ])
            ..limit(1))
          .getSingleOrNull();
  final payload = jsonEncode(annotation.toJson());
  final seed = '${annotation.id}|${parent?.id ?? ''}|$payload';
  final revision = RevisionData(
    id: 'annotation-${sha256.convert(utf8.encode(seed))}',
    entityKind: 'annotation',
    entityId: annotation.id,
    parentRevisionId: parent?.id,
    payloadJson: payload,
    createdAtMs: annotation.updatedAtMs,
  );
  await database.commitAnnotationEdit(
    annotation: annotation,
    revision: revision,
  );
}

({String quote, String context, int startOffset, int endOffset})
_selectionValues(
  PdfExtraction extraction,
  int page,
  int localStart,
  int localEnd,
) {
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
  return (
    quote: selectedPage.text.substring(localStart, localEnd),
    context: selectedPage.text.substring(
      localStart - 40 < 0 ? 0 : localStart - 40,
      localEnd + 40 > selectedPage.text.length
          ? selectedPage.text.length
          : localEnd + 40,
    ),
    startOffset: selectedPage.start + localStart,
    endOffset: selectedPage.start + localEnd,
  );
}
