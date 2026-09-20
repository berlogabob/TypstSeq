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
}
