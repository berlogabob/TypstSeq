import 'package:yaml/yaml.dart';

class HayagrivaEntry {
  const HayagrivaEntry({
    required this.key,
    required this.type,
    required this.title,
    this.author,
    this.year,
    this.source = 'yml',
  });

  final String key;
  final String type;
  final String title;

  /// First author's surname, when known (Zotero snapshot entries).
  final String? author;
  final String? year;

  /// 'yml' for `_system/bibliography.yml`, 'zotero' for `_system/zotero.bib`.
  final String source;
}

List<HayagrivaEntry> parseHayagrivaBibliography(String source) {
  final document = loadYaml(source);
  if (document == null) return const [];
  if (document is! YamlMap) {
    throw const FormatException('Hayagriva bibliography must be a YAML map.');
  }
  final entries = <HayagrivaEntry>[];
  for (final item in document.entries) {
    final key = item.key.toString();
    final value = item.value;
    if (value is! YamlMap) {
      throw FormatException('Bibliography entry $key must be a YAML map.');
    }
    final type = value['type']?.toString().trim() ?? '';
    final title = value['title']?.toString().trim() ?? '';
    if (type.isEmpty || title.isEmpty) {
      throw FormatException('Bibliography entry $key requires type and title.');
    }
    entries.add(HayagrivaEntry(key: key, type: type, title: title));
  }
  entries.sort((a, b) => a.key.compareTo(b.key));
  return entries;
}

/// Parses a BibLaTeX/BibTeX file (the Better BibTeX auto-export snapshot at
/// `_system/zotero.bib`). Hand-rolled on purpose — only key, type, title,
/// first-author surname, and year are needed for the citation picker; Typst
/// itself compiles the file natively. Malformed entries are skipped rather
/// than thrown: a machine-generated snapshot must never brick the picker.
List<HayagrivaEntry> parseBibtexBibliography(String source) {
  final entries = <HayagrivaEntry>[];
  var i = 0;
  while (true) {
    i = source.indexOf('@', i);
    if (i < 0) break;
    i++;
    final typeMatch = RegExp(r'[A-Za-z]+').matchAsPrefix(source, i);
    if (typeMatch == null) continue;
    final type = typeMatch.group(0)!.toLowerCase();
    i = typeMatch.end;
    final open = source.indexOf(RegExp(r'[{(]'), i);
    if (open < 0) break;
    // Only whitespace may sit between the entry type and its delimiter;
    // anything else (`@garbage` prose, emails) is not a BibTeX entry.
    if (source.substring(i, open).trim().isNotEmpty) continue;
    final close = _matchBrace(source, open);
    if (close < 0) break;
    final body = source.substring(open + 1, close);
    i = close + 1;
    if (type == 'comment' || type == 'preamble' || type == 'string') continue;
    final comma = body.indexOf(',');
    if (comma < 0) continue;
    final key = body.substring(0, comma).trim();
    if (key.isEmpty) continue;
    final fields = _bibFields(body.substring(comma + 1));
    final title = _stripBraces(fields['title'] ?? '').trim();
    if (title.isEmpty) continue;
    final year =
        fields['year']?.trim() ??
        (fields['date'] != null && fields['date']!.trim().length >= 4
            ? fields['date']!.trim().substring(0, 4)
            : null);
    entries.add(
      HayagrivaEntry(
        key: key,
        type: type,
        title: title,
        author: _firstAuthorSurname(fields['author']),
        year: year == null || year.isEmpty ? null : year,
        source: 'zotero',
      ),
    );
  }
  entries.sort((a, b) => a.key.compareTo(b.key));
  return entries;
}

/// Index of the delimiter closing the `{`/`(` at [open], honoring nested
/// `{…}` inside; -1 when unbalanced.
int _matchBrace(String source, int open) {
  final parenEntry = source[open] == '(';
  var braceDepth = 0;
  for (var i = open + 1; i < source.length; i++) {
    final c = source[i];
    if (c == '{') {
      braceDepth++;
    } else if (c == '}') {
      if (!parenEntry && braceDepth == 0) return i;
      braceDepth--;
    } else if (parenEntry && c == ')' && braceDepth == 0) {
      return i;
    }
  }
  return -1;
}

/// Splits `name = value, name = value, …` into a lowercase-keyed map. Values
/// may be `{…}` (nested braces ok), `"…"`, or a bare token; `#` concatenation
/// keeps only the first piece.
Map<String, String> _bibFields(String body) {
  final fields = <String, String>{};
  var i = 0;
  while (i < body.length) {
    final nameMatch = RegExp(
      r'\s*([A-Za-z][A-Za-z0-9_-]*)\s*=\s*',
    ).matchAsPrefix(body, i);
    if (nameMatch == null) {
      i++;
      continue;
    }
    final name = nameMatch.group(1)!.toLowerCase();
    i = nameMatch.end;
    if (i >= body.length) break;
    String value;
    final c = body[i];
    if (c == '{') {
      final close = _matchBrace(body, i);
      if (close < 0) break;
      value = body.substring(i + 1, close);
      i = close + 1;
    } else if (c == '"') {
      final close = body.indexOf('"', i + 1);
      if (close < 0) break;
      value = body.substring(i + 1, close);
      i = close + 1;
    } else {
      var end = i;
      while (end < body.length && body[end] != ',' && body[end] != '#') {
        end++;
      }
      value = body.substring(i, end).trim();
      i = end;
    }
    fields.putIfAbsent(name, () => value);
    final nextComma = body.indexOf(',', i);
    if (nextComma < 0) break;
    i = nextComma + 1;
  }
  return fields;
}

String _stripBraces(String value) => value
    .replaceAll('{', '')
    .replaceAll('}', '')
    .replaceAll(RegExp(r'\s+'), ' ');

String? _firstAuthorSurname(String? author) {
  if (author == null) return null;
  final first = _stripBraces(author).split(RegExp(r'\s+and\s+')).first.trim();
  if (first.isEmpty) return null;
  final comma = first.indexOf(',');
  if (comma >= 0) return first.substring(0, comma).trim();
  return first.split(' ').last;
}
