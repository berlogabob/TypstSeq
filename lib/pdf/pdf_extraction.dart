import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum PdfExtractionStatus { extracted, unsupported, invalid }

class PdfTextPage {
  const PdfTextPage({
    required this.page,
    required this.text,
    required this.start,
    required this.end,
  });

  final int page;
  final String text;
  final int start;
  final int end;
}

class PdfExtraction {
  const PdfExtraction({
    required this.sourceVersionId,
    required this.sha256,
    required this.status,
    required this.pages,
    this.reason,
  });

  final String sourceVersionId;
  final String sha256;
  final PdfExtractionStatus status;
  final List<PdfTextPage> pages;
  final String? reason;

  String get text => pages.map((page) => page.text).join('\n');
}

/// Builds a stable, page-addressable extraction record from platform PDF text.
/// The platform reader supplies one nullable string per page; null/empty pages
/// remain accounted for instead of being silently treated as extracted text.
PdfExtraction versionPdfText({
  required String sourceVersionId,
  required List<int> bytes,
  required Iterable<String?> pageTexts,
}) {
  final digest = sha256.convert(Uint8List.fromList(bytes)).toString();
  if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
    return PdfExtraction(
      sourceVersionId: sourceVersionId,
      sha256: digest,
      status: PdfExtractionStatus.invalid,
      pages: const [],
      reason: 'missing PDF header',
    );
  }
  var offset = 0;
  var extracted = false;
  final pages = <PdfTextPage>[];
  var page = 0;
  for (final value in pageTexts) {
    final text = value ?? '';
    final start = offset;
    offset += text.length;
    pages.add(PdfTextPage(page: page++, text: text, start: start, end: offset));
    extracted |= text.trim().isNotEmpty;
    offset++; // newline separator in the combined text projection
  }
  return PdfExtraction(
    sourceVersionId: sourceVersionId,
    sha256: digest,
    status: extracted
        ? PdfExtractionStatus.extracted
        : PdfExtractionStatus.unsupported,
    pages: pages,
    reason: extracted ? null : 'no selectable text',
  );
}
