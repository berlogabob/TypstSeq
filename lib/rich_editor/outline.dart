part of '../rich_editor.dart';

/// One logical line in the document's visible text.
class OutlineLine {
  const OutlineLine({
    required this.start,
    required this.end,
    required this.depth,
    required this.text,
    required this.isFoldable,
    required this.blockIndex,
  });

  /// Offset of the line start in [TyLogDocument.visibleText].
  final int start;

  /// Offset just after the line text, excluding its newline.
  final int end;
  final int depth;
  final String text;
  final bool isFoldable;
  final int? blockIndex;

  TextRange get range => TextRange(start: start, end: end);
  int get lineStart => start;
}

// ponytail: one-entry cache keyed by the visible text; the editor rebuilds
// its span per keystroke and asks several times per build.
String? _outlineText;
List<OutlineLine> _outlineLines = const [];

List<OutlineLine> outlineOf(TyLogDocument document) {
  final visible = document.visibleText;
  if (visible == _outlineText) return _outlineLines;
  final ranges = document.blockRanges;
  final lines = <OutlineLine>[];
  var start = 0;
  var block = 0; // lines and blocks are both in text order: one linear pass
  while (true) {
    final newline = visible.indexOf('\n', start);
    final end = newline < 0 ? visible.length : newline;
    while (block < ranges.length &&
        !(start < ranges[block].end && end > ranges[block].start) &&
        ranges[block].end <= start) {
      block++;
    }
    final blockIndex =
        block < ranges.length &&
            start < ranges[block].end &&
            end > ranges[block].start
        ? block
        : null;
    final style = blockIndex == null ? null : document.blocks[blockIndex].style;
    final text = visible.substring(start, end);
    final depth = style == TyLogBlockStyle.bulletList
        ? _leadingWhitespace(text) ~/ 2
        : style == TyLogBlockStyle.taskLine
        ? _leadingWhitespace(document.blocks[blockIndex!].originalSource) ~/ 2
        : 0;
    lines.add(
      OutlineLine(
        start: start,
        end: end,
        depth: depth,
        text: text,
        isFoldable: false,
        blockIndex: blockIndex,
      ),
    );
    if (newline < 0) break;
    start = newline + 1;
  }
  for (var i = 0; i + 1 < lines.length; i++) {
    if (lines[i + 1].depth > lines[i].depth) {
      final line = lines[i];
      lines[i] = OutlineLine(
        start: line.start,
        end: line.end,
        depth: line.depth,
        text: line.text,
        isFoldable: true,
        blockIndex: line.blockIndex,
      );
    }
  }
  _outlineText = visible;
  return _outlineLines = lines;
}

/// Fold keys of every foldable line, in one pass (start offset -> key).
Map<int, String> foldKeysOf(String scope, List<OutlineLine> lines) {
  final seen = <String, int>{};
  return {
    for (final line in lines)
      if (line.isFoldable)
        line.start:
            'outline:$scope|${line.text}|${seen[line.text] = (seen[line.text] ?? -1) + 1}',
  };
}

List<TextRange> hiddenRanges(
  TyLogDocument document,
  Set<int> foldedParentLineStarts,
) {
  final lines = outlineOf(document);
  final ranges = <TextRange>[];
  for (var i = 0; i < lines.length; i++) {
    final parent = lines[i];
    if (!parent.isFoldable || !foldedParentLineStarts.contains(parent.start)) {
      continue;
    }
    var last = i + 1;
    while (last < lines.length && lines[last].depth > parent.depth) {
      last++;
    }
    // Start at the parent's end so its trailing newline is hidden too.
    final start = parent.end;
    final end = lines[last - 1].end;
    if (start < end) ranges.add(TextRange(start: start, end: end));
  }
  ranges.sort((a, b) => a.start.compareTo(b.start));
  final merged = <TextRange>[];
  for (final range in ranges) {
    if (merged.isEmpty || range.start > merged.last.end) {
      merged.add(range);
    } else if (range.end > merged.last.end) {
      final previous = merged.removeLast();
      merged.add(TextRange(start: previous.start, end: range.end));
    }
  }
  return merged;
}

String foldKeyFor(String scope, OutlineLine line, List<OutlineLine> lines) =>
    foldKeysOf(scope, lines)[line.start]!;

int _leadingWhitespace(String text) {
  var count = 0;
  while (count < text.length && (text[count] == ' ' || text[count] == '\t')) {
    count++;
  }
  return count;
}
