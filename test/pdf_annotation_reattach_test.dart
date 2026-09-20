import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/pdf/annotation_reattach.dart';
import 'package:tylog/pdf/pdf_extraction.dart';

void main() {
  test('reattaches a moved quote to its page and offsets', () {
    final result = reattachAnnotation(
      quote: 'quote',
      oldStartOffset: 7,
      pages: const [
        PdfTextPage(page: 0, text: 'Alpha', start: 0, end: 5),
        PdfTextPage(page: 1, text: 'Beta quote', start: 6, end: 16),
      ],
    );
    expect(result.status, ReattachmentStatus.exact);
    expect(result.page, 1);
    expect(result.startOffset, 11);
    expect(result.endOffset, 16);
  });

  test('duplicate quote with equal candidates is marked ambiguous', () {
    final result = reattachAnnotation(
      quote: 'aa',
      oldStartOffset: 2,
      pages: const [PdfTextPage(page: 0, text: 'aaXXaa', start: 0, end: 6)],
    );
    expect(result.status, ReattachmentStatus.ambiguous);
  });
}
