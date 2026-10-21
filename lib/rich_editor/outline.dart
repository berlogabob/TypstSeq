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
// Task depth lives in originalSource, so the key carries it too: equal text
// with different task indentation must not share an outline.
String? _outlineKey;
List<OutlineLine> _outlineLines = const [];

List<OutlineLine> outlineOf(TyLogDocument document) {
  final visible = document.visibleText;
  final key = StringBuffer(visible);
  for (final block in document.blocks) {
    if (block.style == TyLogBlockStyle.taskLine) {
      key.write('\u0000${_leadingWhitespace(block.originalSource)}');
    }
  }
  final cacheKey = key.toString();
  if (cacheKey == _outlineKey) return _outlineLines;
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
  _outlineKey = cacheKey;
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

/// Each foldable line's subtree as a range: from the end of the parent line
/// (its newline hidden too) to the end of its last descendant. One pass.
Map<int, TextRange> subtreeRanges(List<OutlineLine> lines) {
  final ranges = <int, TextRange>{};
  final open = <OutlineLine>[];
  void close(OutlineLine parent, OutlineLine last) {
    if (parent.end < last.end) {
      ranges[parent.start] = TextRange(start: parent.end, end: last.end);
    }
  }

  OutlineLine? previous;
  for (final line in lines) {
    while (open.isNotEmpty && line.depth <= open.last.depth) {
      close(open.removeLast(), previous!);
    }
    if (line.isFoldable) open.add(line);
    previous = line;
  }
  while (open.isNotEmpty) {
    close(open.removeLast(), previous!);
  }
  return ranges;
}

List<TextRange> hiddenRanges(
  TyLogDocument document,
  Set<int> foldedParentLineStarts,
) {
  final subtrees = subtreeRanges(outlineOf(document));
  final ranges = [for (final start in foldedParentLineStarts) ?subtrees[start]];
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
