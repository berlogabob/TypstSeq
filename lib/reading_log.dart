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
