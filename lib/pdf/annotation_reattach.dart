import 'pdf_extraction.dart';

enum ReattachmentStatus { exact, ambiguous, missing }

class ReattachedAnnotation {
  const ReattachedAnnotation({
    required this.status,
    this.page,
    this.startOffset,
    this.endOffset,
  });

  final ReattachmentStatus status;
  final int? page;
  final int? startOffset;
  final int? endOffset;
}

/// Reattaches an annotation by quote and preserves its declared text offset.
/// Duplicate quotes are ambiguous because the old offset cannot prove identity.
ReattachedAnnotation reattachAnnotation({
  required String quote,
  required int oldStartOffset,
  required Iterable<PdfTextPage> pages,
}) {
  if (quote.isEmpty || oldStartOffset < 0) {
    return const ReattachedAnnotation(status: ReattachmentStatus.missing);
  }
  final pageList = pages.toList(growable: false);
  if (pageList.any(
    (page) =>
        page.page < 0 ||
        page.start < 0 ||
        page.end < page.start ||
        page.end - page.start != page.text.length,
  )) {
    return const ReattachedAnnotation(status: ReattachmentStatus.missing);
  }

  ReattachedAnnotation? match;
  for (final page in pageList) {
    var cursor = 0;
    while (true) {
      final found = page.text.indexOf(quote, cursor);
      if (found < 0) break;
      if (match != null) {
        return const ReattachedAnnotation(status: ReattachmentStatus.ambiguous);
      }
      match = ReattachedAnnotation(
        status: ReattachmentStatus.exact,
        page: page.page,
        startOffset: page.start + found,
        endOffset: page.start + found + quote.length,
      );
      cursor = found + 1;
    }
  }
  return match ??
      const ReattachedAnnotation(status: ReattachmentStatus.missing);
}
