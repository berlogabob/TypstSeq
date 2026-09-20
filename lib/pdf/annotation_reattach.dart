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

/// Reattaches an annotation by quote and preserves a deterministic offset.
/// Duplicate quotes are accepted only when the old offset selects one uniquely.
ReattachedAnnotation reattachAnnotation({
  required String quote,
  required int oldStartOffset,
  required Iterable<PdfTextPage> pages,
}) {
  if (quote.isEmpty || oldStartOffset < 0) {
    return const ReattachedAnnotation(status: ReattachmentStatus.missing);
  }
  final pageList = pages.toList(growable: false);
  final text = pageList.map((page) => page.text).join('\n');
  final starts = <int>[];
  var cursor = 0;
  while (true) {
    final found = text.indexOf(quote, cursor);
    if (found < 0) break;
    starts.add(found);
    cursor = found + quote.length;
  }
  if (starts.isEmpty) {
    return const ReattachedAnnotation(status: ReattachmentStatus.missing);
  }
  if (starts.length > 1) {
    final distances = starts
        .map((start) => (start - oldStartOffset).abs())
        .toList(growable: false);
    final best = distances.reduce((a, b) => a < b ? a : b);
    if (distances.where((value) => value == best).length != 1) {
      return const ReattachedAnnotation(status: ReattachmentStatus.ambiguous);
    }
    return _target(pageList, starts[distances.indexOf(best)], quote.length);
  }
  return _target(pageList, starts.single, quote.length);
}

ReattachedAnnotation _target(List<PdfTextPage> pages, int start, int length) {
  for (final page in pages) {
    if (start >= page.start && start + length <= page.end) {
      return ReattachedAnnotation(
        status: ReattachmentStatus.exact,
        page: page.page,
        startOffset: start,
        endOffset: start + length,
      );
    }
  }
  return const ReattachedAnnotation(status: ReattachmentStatus.missing);
}
