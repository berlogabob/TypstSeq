import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/pdf/pdf_extraction.dart';

void main() {
  test('versioned extraction preserves page and character offsets', () {
    final result = versionPdfText(
      sourceVersionId: 'source-v1',
      bytes: '%PDF-1.7'.codeUnits,
      pageTexts: const ['Alpha', 'Beta'],
    );
    expect(result.status, PdfExtractionStatus.extracted);
    expect(result.sha256, hasLength(64));
    expect(result.pages[0].start, 0);
    expect(result.pages[0].end, 5);
    expect(result.pages[1].start, 6);
    expect(result.pages[1].end, 10);
    expect(result.text, 'Alpha\nBeta');
  });

  test('image-only pages are explicit unsupported input', () {
    final result = versionPdfText(
      sourceVersionId: 'source-v2',
      bytes: '%PDF-1.7'.codeUnits,
      pageTexts: const [null, ''],
    );
    expect(result.status, PdfExtractionStatus.unsupported);
    expect(result.reason, 'no selectable text');
    expect(result.pages, hasLength(2));
  });

  test('invalid bytes are rejected before page processing', () {
    final result = versionPdfText(
      sourceVersionId: 'bad',
      bytes: const [1, 2, 3],
      pageTexts: const ['ignored'],
    );
    expect(result.status, PdfExtractionStatus.invalid);
    expect(result.pages, isEmpty);
  });

  test('large page corpus keeps stable cumulative offsets', () {
    final result = versionPdfText(
      sourceVersionId: 'large',
      bytes: '%PDF-1.7'.codeUnits,
      pageTexts: List.generate(1000, (i) => 'page-$i'),
    );
    expect(result.status, PdfExtractionStatus.extracted);
    expect(result.pages, hasLength(1000));
    for (var i = 1; i < result.pages.length; i++) {
      expect(result.pages[i].start, greaterThan(result.pages[i - 1].end));
      expect(result.pages[i].end - result.pages[i].start, 'page-$i'.length);
    }
    expect(result.text, startsWith('page-0\npage-1\npage-2'));
  });

  test(
    'citation offsets map to their page and clip across page boundaries',
    () {
      final extraction = versionPdfText(
        sourceVersionId: 'v',
        bytes: '%PDF-1.7'.codeUnits,
        pageTexts: const ['Alpha', 'Beta'],
      );
      expect(pdfPageRangeForOffset(extraction, 6, 10), (
        page: 1,
        start: 0,
        end: 4,
      ));
      expect(pdfPageRangeForOffset(extraction, 3, 8), (
        page: 0,
        start: 3,
        end: 5,
      ));
      expect(pdfPageRangeForOffset(extraction, 5, 6), isNull);
    },
  );

  test('citation offsets preserve Dart UTF-16 positions', () {
    final extraction = versionPdfText(
      sourceVersionId: 'v',
      bytes: '%PDF-1.7'.codeUnits,
      pageTexts: const ['A😀B'],
    );
    expect(pdfPageRangeForOffset(extraction, 1, 3), (
      page: 0,
      start: 1,
      end: 3,
    ));
  });
}
