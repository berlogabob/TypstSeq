/// Bare web links in a note, and turning one into a link to the article the
/// article pipeline made from it.
library;

import 'models.dart';
import 'scanner.dart' show unescapeMarkup;
import 'values.dart';

/// A bare URL as written in the source (`\_` escapes and all) and as the
/// web knows it (the job's `url`).
class BareLink {
  const BareLink(this.start, this.end, this.source, this.url);
  final int start;
  final int end;
  final String source;
  final String url;
}

final _url = RegExp(r'https?://[^\s<>\]\)"]+');

/// URLs typed as plain text: not inside a call (`#link("…")`, a ref-note
/// label) and not on a comment line.
List<BareLink> bareLinks(String source) {
  final links = <BareLink>[];
  for (final match in _url.allMatches(source)) {
    final lineStart = source.lastIndexOf('\n', match.start) + 1;
    final before = source.substring(lineStart, match.start);
    if (before.trimLeft().startsWith('//')) continue;
    // Inside `#call(` or its `[label]` on the same line: not ours to touch.
    final call = before.lastIndexOf('#');
    if (call >= 0 &&
        RegExp(r'^#[\w.-]+[(\[]').hasMatch(before.substring(call)) &&
        !before.substring(call).contains(']')) {
      continue;
    }
    var raw = match.group(0)!;
    // Sentence punctuation after a link is not part of it.
    raw = raw.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
    links.add(
      BareLink(match.start, match.start + raw.length, raw, unescapeMarkup(raw)),
    );
  }
  return links;
}

/// Replaces every bare spelling of [url] with a link to [article], titled.
/// The URL itself lives on in the article note. Returns [source] unchanged
/// when the link is gone or already replaced.
String linkArticle(String source, String url, NoteRef article) {
  final hits = bareLinks(source).where((link) => link.url == url).toList();
  if (hits.isEmpty) return source;
  final replacement =
      '#tylog.ref-note(${typstString(article.id)})'
      '[${escapeMarkup(article.title)}]';
  var out = source;
  for (final link in hits.reversed) {
    out = out.replaceRange(link.start, link.end, replacement);
  }
  return out;
}
