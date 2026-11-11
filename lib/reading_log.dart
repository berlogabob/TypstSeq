/// The daily-note reading-log line for [safeTitle] (already Typst-escaped).
/// [rating] null = finished, a number string '1'..'5' = stars, anything else
/// = trashed (deleted) — then [url], when non-empty, is appended as
/// #link("...") so a deleted article can still be found again.
String readingLogLine(String safeTitle, {String? rating, String? url}) {
  final base = '- Read: $safeTitle';
  if (rating == null) return base;

  final n = int.tryParse(rating);
  if (n != null) {
    final clamped = n.clamp(0, 5);
    return '$base — ${'★' * clamped}${'☆' * (5 - clamped)}';
  }

  // Trashed.
  var line = '$base — 🗑';
  final rawUrl = url?.trim() ?? '';
  if (rawUrl.isNotEmpty) {
    final escaped = rawUrl.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    line += ' #link("$escaped")';
  }
  return line;
}

/// Applies today's reading-log [line] for [safeTitle] to the day note [source].
/// Pure, so callers can run it on the note's current text inside a serialized
/// mutation instead of on an earlier read.
String applyReadingLog(
  String source,
  String safeTitle,
  String line, {
  required bool rated,
}) {
  if (rated && source.contains('- Read: $safeTitle\n')) {
    // Finish-then-rate upgrades the existing line instead of duplicating.
    return source.replaceFirst('- Read: $safeTitle\n', '$line\n');
  }
  if (source.contains(': $safeTitle')) return source; // already logged today
  final header = source.contains('== Reading') ? '' : '\n\n== Reading';
  return '${source.trimRight()}$header\n$line\n';
}
