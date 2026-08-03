part of '../rich_editor.dart';

const _object = '\uFFFC';

/// Kill-switch for the inline "@"/"/" autocomplete popup. Flip to false to
/// instantly disable it without touching call sites, if it ever
/// destabilizes editing.
const bool kEnableInlineAutocomplete = true;

/// Icon and label shown for each [MagicAction] \u2014 the single source of truth
/// reused by both the Magic bottom-sheet menu (`app_mobile.dart`) and the
/// inline "/" command palette.
const Map<MagicAction, (IconData, String)> kMagicActionDisplay = {
  MagicAction.noteLink: (Icons.link, 'Note link'),
  MagicAction.mention: (Icons.alternate_email, 'Mention'),
  MagicAction.tag: (Icons.tag, 'Tag'),
  MagicAction.task: (Icons.task_alt, 'Task'),
  MagicAction.date: (Icons.event, 'Date'),
  MagicAction.project: (Icons.work_outline, 'Project'),
  MagicAction.citation: (Icons.format_quote, 'Citation'),
  MagicAction.attachment: (Icons.attach_file, 'Attachment'),
  MagicAction.heading: (Icons.title, 'Heading'),
  MagicAction.bold: (Icons.format_bold, 'Bold'),
  MagicAction.italic: (Icons.format_italic, 'Italic'),
  MagicAction.strike: (Icons.format_strikethrough, 'Strikethrough'),
  MagicAction.underline: (Icons.format_underline, 'Underline'),
  MagicAction.mono: (Icons.code, 'Monospace'),
  MagicAction.highlight: (Icons.border_color, 'Highlight'),
  MagicAction.table: (Icons.table_chart, 'Table'),
  MagicAction.equation: (Icons.functions, 'Equation'),
  MagicAction.report: (Icons.picture_as_pdf, 'Report'),
};

const Map<String, List<MagicAction>> kMagicActionGroups = {
  'Insert': [
    MagicAction.noteLink,
    MagicAction.mention,
    MagicAction.tag,
    MagicAction.date,
    MagicAction.citation,
    MagicAction.attachment,
    MagicAction.equation,
  ],
  'Text style': [
    MagicAction.bold,
    MagicAction.italic,
    MagicAction.underline,
    MagicAction.strike,
    MagicAction.highlight,
    MagicAction.mono,
  ],
  'Structure': [
    MagicAction.task,
    MagicAction.project,
    MagicAction.heading,
    MagicAction.table,
    MagicAction.report,
  ],
};

enum TyLogBlockStyle {
  paragraph,
  heading,
  bulletList,
  numberedList,
  protected,
  taskLine,
}

/// Sentinel distinguishing "leave [TyLogInlineStyle.highlight] unchanged"
/// from "set it to null" in [TyLogInlineStyle.copyWith] and the plumbing
/// that forwards through [TyLogDocument.toggle] / `_styleBlock`.
const Object _unsetHighlight = Object();

/// Verbatim Typst fill expressions for the four toolbar palette swatches.
/// `#highlight[...]` with no `fill:` argument (stored as `''`) renders with
/// Typst's own default fill, which is close to but not identical to
/// [kHighlightYellow] below.
const kHighlightYellow = 'rgb("#FFF59D")';
const kHighlightGreen = 'rgb("#C8E6C9")';
const kHighlightPink = 'rgb("#F8BBD0")';
const kHighlightBlue = 'rgb("#B3E5FC")';

const Map<String, Color> _highlightPalette = {
  '': Color(0xFFFFF59D),
  kHighlightYellow: Color(0xFFFFF59D),
  kHighlightGreen: Color(0xFFC8E6C9),
  kHighlightPink: Color(0xFFF8BBD0),
  kHighlightBlue: Color(0xFFB3E5FC),
};

/// Unknown/custom fill expressions (round-tripped verbatim but not in the
/// palette) render with a neutral tint rather than no highlight at all.
Color _highlightColor(String fill, Brightness brightness) {
  final color = _highlightPalette[fill] ?? const Color(0x339E9E9E);
  return brightness == Brightness.dark
      ? Color.lerp(Colors.black.withValues(alpha: color.a), color, 0.4)!
      : color;
}

class TyLogInlineStyle {
  const TyLogInlineStyle({
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.underline = false,
    this.mono = false,
    this.highlight,
  });

  final bool bold;
  final bool italic;
  final bool strike;
  final bool underline;
  final bool mono;

  /// `null` = no highlight; `''` = default-fill `#highlight[...]`; otherwise
  /// the verbatim Typst fill expression passed to `#highlight(fill: ...)`.
  final String? highlight;

  TyLogInlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? strike,
    bool? underline,
    bool? mono,
    Object? highlight = _unsetHighlight,
  }) => TyLogInlineStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    strike: strike ?? this.strike,
    underline: underline ?? this.underline,
    mono: mono ?? this.mono,
    highlight: identical(highlight, _unsetHighlight)
        ? this.highlight
        : highlight as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is TyLogInlineStyle &&
      bold == other.bold &&
      italic == other.italic &&
      strike == other.strike &&
      underline == other.underline &&
      mono == other.mono &&
      highlight == other.highlight;

  @override
  int get hashCode =>
      Object.hash(bold, italic, strike, underline, mono, highlight);
}

class TyLogInline {
  TyLogInline.text(this.text, {this.style = const TyLogInlineStyle()})
    : source = null,
      label = null,
      id = null;

  TyLogInline.atom({
    required this.source,
    required this.label,
    required this.id,
  }) : text = _object,
       style = const TyLogInlineStyle();

  String text;
  TyLogInlineStyle style;
  final String? source;
  final String? label;
  final String? id;

  bool get isAtom => source != null;

  TyLogInline copy() => isAtom
      ? TyLogInline.atom(source: source!, label: label!, id: id!)
      : TyLogInline.text(text, style: style);
}

class TyLogBlock {
  TyLogBlock({
    required this.id,
    required this.style,
    required this.parts,
    required this.originalSource,
    required this.separator,
    this.dirty = false,
    this.protectedLabel,
    this.headingLevel = 1,
  });

  final String id;
  TyLogBlockStyle style;
  List<TyLogInline> parts;
  final String originalSource;
  String separator;
  bool dirty;
  final String? protectedLabel;

  /// Number of leading `=` for a heading block (1-6); meaningless otherwise.
  int headingLevel;

  bool get isProtected => style == TyLogBlockStyle.protected;
  String get visibleText =>
      isProtected ? _object : parts.map((part) => part.text).join();

  TyLogBlock copy() => TyLogBlock(
    id: id,
    style: style,
    parts: parts.map((part) => part.copy()).toList(),
    originalSource: originalSource,
    separator: separator,
    dirty: dirty,
    protectedLabel: protectedLabel,
    headingLevel: headingLevel,
  );
}

class TyLogDocument {
  TyLogDocument._({required this.prefix, required this.blocks});

  String prefix;
  List<TyLogBlock> blocks;

  static TyLogDocument parse(String source) {
    final parsed = parseControlledTypst(source);
    if (parsed.blocks.isEmpty) {
      return TyLogDocument._(prefix: source, blocks: []);
    }

    var first = 0;
    var prefixEnd = parsed.blocks.first.start;
    final hasGeneratedHeader = RegExp(
      r'#show\s*:\s*tylog\.note\.with\s*\(',
    ).hasMatch(source);
    if (hasGeneratedHeader &&
        parsed.blocks.first.kind == ControlledBlockKind.heading) {
      first = 1;
      prefixEnd = first < parsed.blocks.length
          ? parsed.blocks[first].start
          : source.length;
    }

    final blocks = <TyLogBlock>[];
    for (var i = first; i < parsed.blocks.length; i++) {
      var block = parsed.blocks[i];
      final nextStart = i + 1 < parsed.blocks.length
          ? parsed.blocks[i + 1].start
          : source.length;
      var separator = source.substring(block.end, nextStart);
      if (i == parsed.blocks.length - 1 &&
          separator.isNotEmpty &&
          separator.trim().isEmpty &&
          block.kind == ControlledBlockKind.paragraph) {
        block = ControlledBlock(
          start: block.start,
          end: nextStart,
          source: '${block.source}$separator',
          kind: block.kind,
          supported: block.supported,
        );
        separator = '';
      }
      blocks.add(_parseBlock(block, separator, i));
    }
    return TyLogDocument._(
      prefix: source.substring(0, prefixEnd),
      blocks: blocks,
    );
  }

  TyLogDocument copy() => TyLogDocument._(
    prefix: prefix,
    blocks: blocks.map((block) => block.copy()).toList(),
  );

  String get visibleText =>
      blocks.map((block) => block.visibleText).join('\n\n');

  List<_BlockRange> get _ranges {
    final result = <_BlockRange>[];
    var cursor = 0;
    for (var i = 0; i < blocks.length; i++) {
      final end = cursor + blocks[i].visibleText.length;
      result.add(_BlockRange(i, cursor, end));
      cursor = end + 2;
    }
    return result;
  }

  String sourceFor(String id) {
    for (final block in blocks) {
      if (block.id == id) return block.originalSource;
      for (final part in block.parts) {
        if (part.id == id) return part.source!;
      }
    }
    throw StateError('Protected Typst node no longer exists.');
  }

  String labelForOffset(int offset) {
    for (final range in _ranges) {
      final block = blocks[range.index];
      if (block.isProtected && offset == range.start) {
        return block.protectedLabel ?? 'Custom Typst';
      }
      if (offset < range.start || offset >= range.end) continue;
      var cursor = range.start;
      for (final part in block.parts) {
        if (part.isAtom && offset == cursor) return part.label!;
        cursor += part.text.length;
      }
    }
    return '';
  }

  String plainText(TextRange range) {
    final start = math.max(0, math.min(range.start, visibleText.length));
    final end = math.max(start, math.min(range.end, visibleText.length));
    final buffer = StringBuffer();
    for (var i = start; i < end; i++) {
      if (visibleText.codeUnitAt(i) == 0xFFFC) {
        buffer.write(labelForOffset(i));
      } else {
        buffer.writeCharCode(visibleText.codeUnitAt(i));
      }
    }
    return buffer.toString();
  }

  void replace(
    int start,
    int end,
    String replacement, {
    TyLogInlineStyle? insertionStyle,
  }) {
    if (start < 0 || end < start || end > visibleText.length) {
      throw RangeError.range(end, start, visibleText.length);
    }
    replacement = replacement.replaceAll(_object, '');
    if (blocks.isEmpty) {
      if (replacement.isEmpty) return;
      blocks = [_newParagraph(replacement, 0, separator: '')];
      return;
    }

    final startHit = _blockAt(start, preferPrevious: true);
    final endHit = _blockAt(end, preferPrevious: true);
    if (startHit != null &&
        endHit != null &&
        startHit.index == endHit.index &&
        !blocks[startHit.index].isProtected &&
        !replacement.contains('\n\n')) {
      final block = blocks[startHit.index];
      final localStart = (start - startHit.start).clamp(
        0,
        block.visibleText.length,
      );
      final localEnd = (end - startHit.start).clamp(
        0,
        block.visibleText.length,
      );
      if (block.style == TyLogBlockStyle.taskLine) {
        if (replacement.contains('\n')) {
          throw const FormatException('Task text is a single line.');
        }
        if (localStart < 2 && localEnd > 0) {
          throw const FormatException(
            'The task checkbox is not editable text.',
          );
        }
      }
      _replaceInBlock(
        block,
        localStart,
        localEnd,
        replacement,
        insertionStyle: insertionStyle,
      );
      return;
    }

    _guardTaskLineIntegrity(start, end, replacement, startHit, endHit);
    _replaceAcrossBlocks(start, end, replacement, startHit, endHit);
  }

  /// `_replaceAcrossBlocks` rebuilds every block it touches as plain
  /// paragraphs, which would silently drop a taskLine's `#tylog.task(...)`
  /// call (recurrence, properties, id, ...) even though the visible text
  /// still matches. Refuse any multi-block/`\n\n`-containing edit that
  /// touches a task line unless it is a pure deletion that removes the
  /// whole task (the user deliberately deleted the line).
  ///
  /// The guard must inspect the same inclusive block-index span
  /// `_replaceAcrossBlocks` will rebuild — `_blockAt(..., preferPrevious:
  /// true)` resolves an offset sitting exactly on a task's trailing
  /// boundary TO the task, so a plain character-interval overlap check
  /// would miss a zero-width insertion at `range.end` that still dissolves
  /// the task.
  void _guardTaskLineIntegrity(
    int start,
    int end,
    String replacement,
    _BlockRange? startHit,
    _BlockRange? endHit,
  ) {
    final isPureDeletion = replacement.isEmpty;
    final first = startHit?.index ?? 0;
    final last = endHit?.index ?? blocks.length - 1;
    final ranges = _ranges;
    for (var i = first; i <= last && i < blocks.length; i++) {
      if (blocks[i].style != TyLogBlockStyle.taskLine) continue;
      final range = ranges[i];
      final fullyCovered = range.start >= start && range.end <= end;
      if (!isPureDeletion || !fullyCovered) {
        throw const FormatException(
          'Edit would destroy a task; delete the whole task line instead.',
        );
      }
    }
  }

  void _replaceAcrossBlocks(
    int start,
    int end,
    String replacement,
    _BlockRange? startHit,
    _BlockRange? endHit,
  ) {
    final oldVisible = visibleText;
    final nextVisible = oldVisible.replaceRange(start, end, replacement);
    final first = startHit?.index ?? 0;
    final last = endHit?.index ?? blocks.length - 1;
    final oldRanges = _ranges;
    final affectedStart = oldRanges[first].start;
    final affectedEnd = oldRanges[last].end;
    final delta = replacement.length - (end - start);
    final nextAffectedEnd = (affectedEnd + delta).clamp(
      affectedStart,
      nextVisible.length,
    );
    final value = nextVisible.substring(affectedStart, nextAffectedEnd);
    final replacements = <TyLogBlock>[];
    final segments = value.isEmpty ? const <String>[] : value.split('\n\n');
    for (var i = 0; i < segments.length; i++) {
      replacements.add(
        _newParagraph(
          segments[i],
          DateTime.now().microsecondsSinceEpoch + i,
          separator: i == segments.length - 1 ? blocks[last].separator : '\n\n',
        ),
      );
    }
    final removedThroughEnd = replacements.isEmpty && last == blocks.length - 1;
    blocks.replaceRange(first, last + 1, replacements);
    if (removedThroughEnd && blocks.isNotEmpty) blocks.last.separator = '';
  }

  void toggle(
    TextRange selection, {
    bool? bold,
    bool? italic,
    bool? strike,
    bool? underline,
    bool? mono,
    Object? highlight = _unsetHighlight,
    bool reset = false,
  }) {
    if (!selection.isValid || selection.isCollapsed) return;
    for (final range in _ranges) {
      final start = math.max(selection.start, range.start);
      final end = math.min(selection.end, range.end);
      if (start >= end || blocks[range.index].isProtected) continue;
      _styleBlock(
        blocks[range.index],
        start - range.start,
        end - range.start,
        bold: bold,
        italic: italic,
        strike: strike,
        underline: underline,
        mono: mono,
        highlight: highlight,
        reset: reset,
      );
    }
  }

  int setBlockStyle(int offset, TyLogBlockStyle style, {int headingLevel = 1}) {
    if (blocks.isEmpty) blocks = [_newParagraph('', 0, separator: '')];
    final hit = _blockAt(offset, preferPrevious: true);
    if (hit == null || blocks[hit.index].isProtected) return offset;
    final block = blocks[hit.index];
    final units = _units(block.parts);
    final local = (offset - hit.start).clamp(0, units.length);
    var lineStart = local;
    while (lineStart > 0 && units[lineStart - 1].code != 10) {
      lineStart--;
    }
    var lineEnd = local;
    while (lineEnd < units.length && units[lineEnd].code != 10) {
      lineEnd++;
    }
    final before = units.sublist(0, lineStart);
    final line = units.sublist(lineStart, lineEnd);
    final after = units.sublist(lineEnd);
    if (before.isNotEmpty && before.last.code == 10) before.removeLast();
    if (after.isNotEmpty && after.first.code == 10) after.removeAt(0);

    final togglingList =
        (style == TyLogBlockStyle.bulletList ||
            style == TyLogBlockStyle.numberedList) &&
        block.style == style;
    final togglingHeading =
        style == TyLogBlockStyle.heading &&
        block.style == TyLogBlockStyle.heading &&
        block.headingLevel == headingLevel;
    final targetStyle = togglingList || togglingHeading
        ? TyLogBlockStyle.paragraph
        : style;
    var removedPrefix = 0;
    if (block.style == TyLogBlockStyle.bulletList &&
        line.length >= 2 &&
        line[0].code == 0x2022 &&
        line[1].code == 32) {
      line.removeRange(0, 2);
      removedPrefix = 2;
    }
    if (block.style == TyLogBlockStyle.numberedList) {
      final match = RegExp(
        r'^\d+\.\s',
      ).matchAsPrefix(String.fromCharCodes(line.map((unit) => unit.code)));
      if (match != null) {
        line.removeRange(0, match.end);
        removedPrefix = match.end;
      }
    }
    if (block.style == TyLogBlockStyle.taskLine &&
        line.length >= 2 &&
        (line[0].code == 0x2610 || line[0].code == 0x2611) &&
        line[1].code == 32) {
      line.removeRange(0, 2);
      removedPrefix = 2;
    }
    var insertedPrefix = 0;
    if (targetStyle == TyLogBlockStyle.bulletList) {
      final inherited = line.isEmpty
          ? const TyLogInlineStyle()
          : line.first.style;
      line.insertAll(0, [
        _Unit(0x2022, inherited, null),
        _Unit(32, inherited, null),
      ]);
      insertedPrefix = 2;
    } else if (targetStyle == TyLogBlockStyle.numberedList) {
      final inherited = line.isEmpty
          ? const TyLogInlineStyle()
          : line.first.style;
      const prefix = '1. ';
      line.insertAll(0, [
        for (final code in prefix.codeUnits) _Unit(code, inherited, null),
      ]);
      insertedPrefix = prefix.length;
    }

    final replacements = <TyLogBlock>[];
    if (before.isNotEmpty) replacements.add(_blockFrom(block, before));
    final target = _blockFrom(
      block,
      line,
      style: targetStyle,
      headingLevel: headingLevel,
    );
    replacements.add(target);
    if (after.isNotEmpty) replacements.add(_blockFrom(block, after));
    for (final replacement in replacements) {
      replacement.separator = '\n\n';
    }
    replacements.last.separator = block.separator;
    blocks.replaceRange(hit.index, hit.index + 1, replacements);
    final targetIndex = hit.index + (before.isEmpty ? 0 : 1);
    final caretInLine = (local - lineStart - removedPrefix + insertedPrefix)
        .clamp(0, line.length);
    return _ranges[targetIndex].start + caretInLine;
  }

  /// Restyles every line a [start]..[end] selection touches — the multiline
  /// counterpart of [setBlockStyle] (which stays single-line for collapsed
  /// carets and is pinned by existing tests). One list block per source
  /// block: `\n\n` separators survive as block boundaries. Only list styles.
  int setBlockStyleRange(int start, int end, TyLogBlockStyle style) {
    assert(
      style == TyLogBlockStyle.bulletList ||
          style == TyLogBlockStyle.numberedList,
    );
    if (blocks.isEmpty) blocks = [_newParagraph('', 0, separator: '')];
    final startHit = _blockAt(start, preferPrevious: true);
    final endHit = _blockAt(end, preferPrevious: true);
    if (startHit == null || endHit == null) return end;
    var caretIndex = -1;
    var addedBeforeCaret = 0;
    // Backward so replacements never shift the offsets of unprocessed blocks.
    for (var i = endHit.index; i >= startHit.index; i--) {
      final block = blocks[i];
      if (block.isProtected) continue;
      final range = _ranges[i];
      final units = _units(block.parts);
      var localStart = i == startHit.index
          ? (start - range.start).clamp(0, units.length)
          : 0;
      var localEnd = i == endHit.index
          ? (end - range.start).clamp(0, units.length)
          : units.length;
      // A selection ending at column 0 of a line touches none of its text —
      // step back so that line is left alone.
      if (localEnd > localStart &&
          localEnd > 0 &&
          units[localEnd - 1].code == 10) {
        localEnd--;
      }
      while (localStart > 0 && units[localStart - 1].code != 10) {
        localStart--;
      }
      while (localEnd < units.length && units[localEnd].code != 10) {
        localEnd++;
      }
      final before = units.sublist(0, localStart);
      final segment = units.sublist(localStart, localEnd);
      final after = units.sublist(localEnd);
      if (before.isNotEmpty && before.last.code == 10) before.removeLast();
      if (after.isNotEmpty && after.first.code == 10) after.removeAt(0);
      final targetStyle = block.style == style
          ? TyLogBlockStyle.paragraph
          : style;
      final restyled = _restyleSegmentLines(
        segment,
        from: block.style,
        to: targetStyle,
      );
      final replacements = <TyLogBlock>[];
      if (before.isNotEmpty) replacements.add(_blockFrom(block, before));
      replacements.add(_blockFrom(block, restyled, style: targetStyle));
      if (after.isNotEmpty) replacements.add(_blockFrom(block, after));
      for (final replacement in replacements) {
        replacement.separator = '\n\n';
      }
      replacements.last.separator = block.separator;
      blocks.replaceRange(i, i + 1, replacements);
      final targetIndex = i + (before.isEmpty ? 0 : 1);
      // Splits of a numbered block keep stale visible numbers, which would
      // fail toSource round-trip validation and silently revert the edit.
      _renumberBlock(targetIndex);
      if (before.isNotEmpty) _renumberBlock(i);
      if (after.isNotEmpty) _renumberBlock(targetIndex + 1);
      if (i == endHit.index) {
        caretIndex = targetIndex;
      } else {
        addedBeforeCaret += replacements.length - 1;
      }
    }
    if (caretIndex < 0) return end;
    return _ranges[caretIndex + addedBeforeCaret].end;
  }

  /// Strips [from]-style line prefixes and applies [to]-style prefixes on
  /// every line of [segment] (same per-line rules as [setBlockStyle]).
  List<_Unit> _restyleSegmentLines(
    List<_Unit> segment, {
    required TyLogBlockStyle from,
    required TyLogBlockStyle to,
  }) {
    final lines = <List<_Unit>>[[]];
    for (final unit in segment) {
      if (unit.code == 10) {
        lines.add(<_Unit>[]);
      } else {
        lines.last.add(unit);
      }
    }
    final result = <_Unit>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (from == TyLogBlockStyle.bulletList &&
          line.length >= 2 &&
          line[0].code == 0x2022 &&
          line[1].code == 32) {
        line.removeRange(0, 2);
      } else if (from == TyLogBlockStyle.numberedList) {
        final match = RegExp(r'^\d+\.\s').matchAsPrefix(
          String.fromCharCodes(line.map((unit) => unit.code)),
        );
        if (match != null) line.removeRange(0, match.end);
      } else if (from == TyLogBlockStyle.taskLine &&
          line.length >= 2 &&
          (line[0].code == 0x2610 || line[0].code == 0x2611) &&
          line[1].code == 32) {
        line.removeRange(0, 2);
      }
      final inherited = line.isEmpty
          ? const TyLogInlineStyle()
          : line.first.style;
      if (to == TyLogBlockStyle.bulletList) {
        line.insertAll(0, [
          _Unit(0x2022, inherited, null),
          _Unit(32, inherited, null),
        ]);
      } else if (to == TyLogBlockStyle.numberedList) {
        line.insertAll(0, [
          for (final code in '${i + 1}. '.codeUnits)
            _Unit(code, inherited, null),
        ]);
      }
      if (i > 0) result.add(_Unit(10, inherited, null));
      result.addAll(line);
    }
    return result;
  }

  void replaceProtected(String id, String source) {
    final index = blocks.indexWhere((block) => block.id == id);
    if (index >= 0) {
      final parsed = parseControlledTypst(source);
      final replacement = parsed.blocks.length == 1
          ? _parseBlock(parsed.blocks.single, blocks[index].separator, index)
          : TyLogBlock(
              id: blocks[index].id,
              style: TyLogBlockStyle.protected,
              parts: const [],
              originalSource: source,
              separator: blocks[index].separator,
              dirty: false,
              protectedLabel: 'Custom Typst',
            );
      blocks[index] = replacement;
      return;
    }
    for (final block in blocks) {
      final part = block.parts.indexWhere((part) => part.id == id);
      if (part < 0) continue;
      block.parts[part] = TyLogInline.atom(
        source: source,
        label: _atomLabel(source),
        id: id,
      );
      block.dirty = true;
      return;
    }
  }

  int insertSource(
    TextRange selection,
    String source, {
    required String label,
  }) {
    if (blocks.isEmpty) blocks = [_newParagraph('', 0, separator: '')];
    _replaceWithParts(selection, [
      TyLogInline.atom(
        source: source,
        label: label,
        id: 'atom-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ]);
    return selection.start + 1;
  }

  int insertBlock(TextRange selection, String source) {
    final parsed = parseControlledTypst(source);
    final replacements = [
      for (var i = 0; i < parsed.blocks.length; i++)
        _parseBlock(parsed.blocks[i], '\n\n', blocks.length + i),
    ];
    // Multi-block sources are only allowed when every block is a task line
    // (the multiline convert-to-tasks flow); tables/equations stay one block.
    if (replacements.length != 1 &&
        !replacements.every(
          (block) => block.style == TyLogBlockStyle.taskLine,
        )) {
      throw const FormatException('Magic block must contain one Typst block.');
    }
    final count = replacements.length;
    final isTask = replacements.last.style == TyLogBlockStyle.taskLine;
    if (blocks.isEmpty) {
      blocks = [
        ...replacements,
        _newParagraph('', count, separator: ''),
      ];
      return isTask ? _ranges[count - 1].end : 3;
    }
    replace(selection.start, selection.end, '');
    final hit = _blockAt(selection.start, preferPrevious: true);
    if (hit == null) {
      final firstIndex = blocks.length;
      blocks.addAll([
        ...replacements,
        _newParagraph('', blocks.length + count, separator: ''),
      ]);
      return isTask ? _ranges[firstIndex + count - 1].end : _ranges.last.start;
    }
    final current = blocks[hit.index];
    if (!current.isProtected && current.visibleText.isEmpty) {
      blocks.insertAll(hit.index, replacements);
      return isTask
          ? _ranges[hit.index + count - 1].end
          : _ranges[hit.index + count].start;
    }
    final tailSeparator = current.separator;
    if (!current.isProtected) {
      final units = _units(current.parts);
      while (units.isNotEmpty && units.last.code == 10) {
        units.removeLast();
      }
      current.parts = _parts(units);
    }
    current
      ..separator = '\n\n'
      ..dirty = true;
    blocks.insertAll(hit.index + 1, replacements);
    final next = hit.index + 1 + count;
    if (next >= blocks.length ||
        blocks[next].isProtected ||
        blocks[next].visibleText.isNotEmpty) {
      blocks.insert(
        next,
        _newParagraph(
          '',
          DateTime.now().microsecondsSinceEpoch,
          separator: tailSeparator,
        ),
      );
    }
    return isTask ? _ranges[hit.index + count].end : _ranges[next].start;
  }

  int insertNewline(int offset) {
    final hit = _blockAt(offset, preferPrevious: true);
    if (hit == null) return offset;
    if (blocks[hit.index].isProtected) {
      // At the chip's edges, Enter opens a writable paragraph next to the
      // protected node; anywhere on the chip itself it is still refused.
      if (offset == hit.end) {
        final protected = blocks[hit.index];
        blocks.insert(
          hit.index + 1,
          _newParagraph(
            '',
            DateTime.now().microsecondsSinceEpoch,
            separator: protected.separator,
          ),
        );
        protected.separator = '\n\n';
        return _ranges[hit.index + 1].start;
      }
      if (offset == hit.start) {
        blocks.insert(
          hit.index,
          _newParagraph(
            '',
            DateTime.now().microsecondsSinceEpoch,
            separator: '\n\n',
          ),
        );
        // Caret stays with the chip; the blank line sits above it.
        return _ranges[hit.index + 1].start;
      }
      return offset;
    }
    final block = blocks[hit.index];
    if (block.style == TyLogBlockStyle.taskLine) {
      final content = block.visibleText.length > 2
          ? block.visibleText.substring(2)
          : '';
      if (content.isEmpty) {
        return setBlockStyle(offset, TyLogBlockStyle.paragraph);
      }
      // Same body as the protected trailing-edge branch above: a task line
      // never splits, Enter anywhere in it opens a fresh paragraph after it.
      blocks.insert(
        hit.index + 1,
        _newParagraph(
          '',
          DateTime.now().microsecondsSinceEpoch,
          separator: block.separator,
        ),
      );
      block.separator = '\n\n';
      return _ranges[hit.index + 1].start;
    }
    if (block.style == TyLogBlockStyle.bulletList) {
      final units = _units(block.parts);
      final local = (offset - hit.start).clamp(0, units.length);
      var start = local;
      while (start > 0 && units[start - 1].code != 10) {
        start--;
      }
      var end = local;
      while (end < units.length && units[end].code != 10) {
        end++;
      }
      final contentStart =
          start +
          (end - start >= 2 &&
                  units[start].code == 0x2022 &&
                  units[start + 1].code == 32
              ? 2
              : 0);
      if (units.sublist(contentStart, end).every((unit) => unit.code == 32)) {
        return setBlockStyle(offset, TyLogBlockStyle.bulletList);
      }
      replace(offset, offset, '\n• ');
      return offset + 3;
    }
    if (block.style == TyLogBlockStyle.numberedList) {
      final units = _units(block.parts);
      final local = (offset - hit.start).clamp(0, units.length);
      var start = local;
      while (start > 0 && units[start - 1].code != 10) {
        start--;
      }
      var end = local;
      while (end < units.length && units[end].code != 10) {
        end++;
      }
      final lineText = String.fromCharCodes(
        units.sublist(start, end).map((unit) => unit.code),
      );
      final match = RegExp(r'^(\d+)\.\s').matchAsPrefix(lineText);
      final contentStart = start + (match?.end ?? 0);
      if (units.sublist(contentStart, end).every((unit) => unit.code == 32)) {
        return setBlockStyle(offset, TyLogBlockStyle.numberedList);
      }
      final nextNumber = (int.tryParse(match?.group(1) ?? '0') ?? 0) + 1;
      final insertion = '\n$nextNumber. ';
      replace(offset, offset, insertion);
      // Trailing items keep their old numbers after the splice (…2. \n2. b),
      // but Typst `+` enums auto-number 1..n, so the reparse renumbers and
      // `toSource` validation would reject the edit. Renumber to match.
      // ponytail: assumes single→double digit width stays stable for the caret
      // offset; a 9→10 rollover mid-list could shift the caret by one.
      _renumberBlock(_blockAt(offset, preferPrevious: true)?.index);
      return offset + insertion.length;
    }
    if (block.style != TyLogBlockStyle.heading) {
      replace(offset, offset, '\n');
      return offset + 1;
    }
    final units = _units(block.parts);
    final local = (offset - hit.start).clamp(0, units.length);
    final heading = _blockFrom(block, units.sublist(0, local));
    final paragraph = _blockFrom(
      block,
      units.sublist(local),
      style: TyLogBlockStyle.paragraph,
    );
    heading.separator = '\n\n';
    paragraph.separator = block.separator;
    blocks.replaceRange(hit.index, hit.index + 1, [heading, paragraph]);
    return _ranges[hit.index + 1].start;
  }

  /// Merges `blocks[index]` into the block before it — the inverse of
  /// [insertNewline], for Backspace at a block's start (deleting the inter-block
  /// separator, which no block owns as editable text). The merged content
  /// adopts the previous block's style so it round-trips: joined to a list it
  /// becomes a new item (glyph kept in the visible text to match the serialized
  /// `- `/`+ ` prefix), otherwise it joins with a plain line break. Returns the
  /// caret offset at the join (right before the merged-in content).
  int mergeBackward(int index) {
    final prev = blocks[index - 1];
    final cur = blocks[index];
    final joinOffset = _ranges[index - 1].end;
    final glyph = switch (prev.style) {
      TyLogBlockStyle.bulletList => '\n• ',
      TyLogBlockStyle.numberedList => '\n0. ',
      // A heading is a single line — join the text directly onto it
      // (`= Titlebody`) rather than with a `\n`, which would re-parse as a
      // separate paragraph and fail the round-trip.
      TyLogBlockStyle.heading => '',
      _ => '\n',
    };
    final merged = [
      ...prev.parts,
      TyLogInline.text(glyph),
      ...cur.parts.map((part) => part.copy()),
    ];
    // Drop a trailing newline-only tail (the last block often carries the
    // file's trailing blank line) so a list block doesn't emit empty `- `
    // items when serialized.
    while (merged.isNotEmpty) {
      final last = merged.last;
      final trimmed = last.text.replaceFirst(RegExp(r'\n+$'), '');
      if (trimmed == last.text) break;
      if (trimmed.isEmpty) {
        merged.removeLast();
      } else {
        merged[merged.length - 1] = TyLogInline.text(
          trimmed,
          style: last.style,
        );
        break;
      }
    }
    prev.parts = merged;
    prev.dirty = true;
    if (index == blocks.length - 1) prev.separator = cur.separator;
    blocks.removeAt(index);
    if (prev.style == TyLogBlockStyle.numberedList) _renumberBlock(index - 1);
    return joinOffset + glyph.length;
  }

  /// Rewrites a numbered-list block's visible numbers to a contiguous 1..n
  /// (what a Typst `+` enum renders and what the reparse produces) by round-
  /// tripping just that block through the serializer/parser.
  void _renumberBlock(int? index) {
    if (index == null || index < 0 || index >= blocks.length) return;
    final block = blocks[index];
    if (block.style != TyLogBlockStyle.numberedList) return;
    final parsed = parseControlledTypst(_serializeBlock(block));
    if (parsed.blocks.length != 1) return;
    final rebuilt = _parseBlock(parsed.blocks.first, block.separator, index);
    if (rebuilt.style != TyLogBlockStyle.numberedList) return;
    block
      ..parts = rebuilt.parts
      ..dirty = true;
  }

  void _replaceWithParts(TextRange selection, List<TyLogInline> inserted) {
    final hit = _blockAt(selection.start, preferPrevious: true);
    if (hit == null || blocks[hit.index].isProtected) return;
    final block = blocks[hit.index];
    final localStart = (selection.start - hit.start).clamp(
      0,
      block.visibleText.length,
    );
    final localEnd = (selection.end - hit.start).clamp(
      0,
      block.visibleText.length,
    );
    final units = _units(block.parts);
    units.replaceRange(
      localStart,
      localEnd,
      inserted.expand((part) => _units([part])),
    );
    block
      ..parts = _parts(units)
      ..dirty = true;
  }

  List<TyLogInline>? _inlineFragment(TextRange selection) {
    if (!selection.isValid || selection.isCollapsed) return null;
    final start = _blockAt(selection.start, preferPrevious: true);
    final end = _blockAt(selection.end, preferPrevious: true);
    if (start == null ||
        end == null ||
        start.index != end.index ||
        blocks[start.index].isProtected) {
      return null;
    }
    final block = blocks[start.index];
    final units = _units(block.parts);
    final localStart = (selection.start - start.start).clamp(0, units.length);
    final localEnd = (selection.end - start.start).clamp(0, units.length);
    return _parts(units.sublist(localStart, localEnd));
  }

  String toSource({bool validate = true}) {
    final buffer = StringBuffer(prefix);
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      buffer.write(block.dirty ? _serializeBlock(block) : block.originalSource);
      if (block.separator.isNotEmpty) {
        buffer.write(block.separator);
      } else if (i + 1 < blocks.length) {
        buffer.write('\n\n');
      }
    }
    final source = buffer.toString();
    if (validate) {
      final reparsed = TyLogDocument.parse(source);
      // Accept-and-tolerate: a reparse that differs from the live model ONLY in
      // block-structure newlines — a trailing blank line, or a 3+ newline run
      // Typst collapses back to one paragraph break — is a benign
      // normalization, not corruption. The model keeps the user's transient
      // state (e.g. the blank line they just opened with Enter, which re-
      // persists on the next keystroke); the emitted source is its canonical
      // form. Reject only a real content change or a lost protected node.
      if (!_sameProtectedSources(reparsed, this) ||
          _canonicalNewlines(reparsed.visibleText) !=
              _canonicalNewlines(visibleText)) {
        throw const FormatException(_validateFailMessage);
      }
    }
    return source;
  }

  _BlockRange? _blockAt(int offset, {required bool preferPrevious}) {
    final all = _ranges;
    for (final range in all) {
      if (offset >= range.start && offset < range.end) return range;
      if (offset == range.end && preferPrevious) return range;
      if (offset < range.start) return range;
    }
    return all.isEmpty ? null : all.last;
  }
}

class _AutocompleteState {
  const _AutocompleteState({
    required this.trigger,
    required this.mentionItems,
    required this.commandItems,
    required this.highlighted,
    required this.loading,
  });

  final AutocompleteTrigger trigger;
  final List<MentionSuggestion> mentionItems;
  final List<MagicAction> commandItems;
  final int highlighted;
  final bool loading;

  _AutocompleteState copyWith({int? highlighted}) => _AutocompleteState(
    trigger: trigger,
    mentionItems: mentionItems,
    commandItems: commandItems,
    highlighted: highlighted ?? this.highlighted,
    loading: loading,
  );
}

class _Unit {
  const _Unit(this.code, this.style, this.atom);
  final int code;
  final TyLogInlineStyle style;
  final TyLogInline? atom;
}

class _BlockRange {
  const _BlockRange(this.index, this.start, this.end);
  final int index;
  final int start;
  final int end;
}

class _Replacement {
  const _Replacement(this.start, this.oldEnd, this.replacement);
  final int start;
  final int oldEnd;
  final String replacement;
}

class _Snapshot {
  const _Snapshot(this.document, this.value);
  final TyLogDocument document;
  final TextEditingValue value;
}

class _RichClipboard {
  const _RichClipboard(this.plain, this.parts);
  final String plain;
  final List<TyLogInline>? parts;
}
