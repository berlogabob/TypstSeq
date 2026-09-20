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

  test('duplicate quote remains ambiguous when one candidate is nearer', () {
    final result = reattachAnnotation(
      quote: 'aa',
      oldStartOffset: 1,
      pages: const [
        PdfTextPage(page: 0, text: 'aa', start: 0, end: 2),
        PdfTextPage(page: 1, text: 'xaa', start: 3, end: 6),
      ],
    );
    expect(result.status, ReattachmentStatus.ambiguous);
  });

  test('overlapping quote candidates are ambiguous', () {
    final result = reattachAnnotation(
      quote: 'aaa',
      oldStartOffset: 0,
      pages: const [PdfTextPage(page: 0, text: 'aaaa', start: 0, end: 4)],
    );
    expect(result.status, ReattachmentStatus.ambiguous);
  });

  test('uses declared nonzero page offsets', () {
    final result = reattachAnnotation(
      quote: 'quote',
      oldStartOffset: 2,
      pages: const [
        PdfTextPage(page: 4, text: 'prefix', start: 100, end: 106),
        PdfTextPage(page: 5, text: 'the quote', start: 107, end: 116),
      ],
    );
    expect(result.status, ReattachmentStatus.exact);
    expect(result.page, 5);
    expect(result.startOffset, 111);
    expect(result.endOffset, 116);
  });

  test('missing quote is reported as missing', () {
    final result = reattachAnnotation(
      quote: 'missing',
      oldStartOffset: 0,
      pages: const [PdfTextPage(page: 0, text: 'present', start: 0, end: 7)],
    );
    expect(result.status, ReattachmentStatus.missing);
  });

  test('invalid page offsets are reported as missing', () {
    final result = reattachAnnotation(
      quote: 'quote',
      oldStartOffset: 0,
      pages: const [PdfTextPage(page: 0, text: 'quote', start: 10, end: 14)],
    );
    expect(result.status, ReattachmentStatus.missing);
  });
}
