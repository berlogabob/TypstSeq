import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tylog_core/scanner.dart';

import 'controlled_editor.dart';
import 'editor_autocomplete.dart';

export 'editor_autocomplete.dart' show MentionSuggestion;

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
  MagicAction.table: (Icons.table_chart, 'Table'),
  MagicAction.equation: (Icons.functions, 'Equation'),
  MagicAction.report: (Icons.picture_as_pdf, 'Report'),
};

enum TyLogBlockStyle {
  paragraph,
  heading,
  bulletList,
  numberedList,
  protected,
  taskLine,
}

class TyLogInlineStyle {
  const TyLogInlineStyle({this.bold = false, this.italic = false});

  final bool bold;
  final bool italic;

  TyLogInlineStyle copyWith({bool? bold, bool? italic}) =>
      TyLogInlineStyle(bold: bold ?? this.bold, italic: italic ?? this.italic);

  @override
  bool operator ==(Object other) =>
      other is TyLogInlineStyle && bold == other.bold && italic == other.italic;

  @override
  int get hashCode => Object.hash(bold, italic);
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
  });

  final String id;
  TyLogBlockStyle style;
  List<TyLogInline> parts;
  final String originalSource;
  String separator;
  bool dirty;
  final String? protectedLabel;

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

  void toggle(TextRange selection, {bool? bold, bool? italic}) {
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
      );
    }
  }

  int setBlockStyle(int offset, TyLogBlockStyle style) {
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
        style == TyLogBlockStyle.bulletList &&
        block.style == TyLogBlockStyle.bulletList;
    final targetStyle = togglingList ? TyLogBlockStyle.paragraph : style;
    var removedPrefix = 0;
    if (block.style == TyLogBlockStyle.bulletList &&
        line.length >= 2 &&
        line[0].code == 0x2022 &&
        line[1].code == 32) {
      line.removeRange(0, 2);
      removedPrefix = 2;
    }
    if (block.style == TyLogBlockStyle.taskLine &&
        line.length >= 2 &&
        (line[0].code == 0x2610 || line[0].code == 0x2611) &&
        line[1].code == 32) {
      line.removeRange(0, 2);
      removedPrefix = 2;
    }
    if (targetStyle == TyLogBlockStyle.bulletList) {
      final inherited = line.isEmpty
          ? const TyLogInlineStyle()
          : line.first.style;
      line.insertAll(0, [
        _Unit(0x2022, inherited, null),
        _Unit(32, inherited, null),
      ]);
    }

    final replacements = <TyLogBlock>[];
    if (before.isNotEmpty) replacements.add(_blockFrom(block, before));
    final target = _blockFrom(block, line, style: targetStyle);
    replacements.add(target);
    if (after.isNotEmpty) replacements.add(_blockFrom(block, after));
    for (final replacement in replacements) {
      replacement.separator = '\n\n';
    }
    replacements.last.separator = block.separator;
    blocks.replaceRange(hit.index, hit.index + 1, replacements);
    final targetIndex = hit.index + (before.isEmpty ? 0 : 1);
    final insertedPrefix = targetStyle == TyLogBlockStyle.bulletList ? 2 : 0;
    final caretInLine = (local - lineStart - removedPrefix + insertedPrefix)
        .clamp(0, line.length);
    return _ranges[targetIndex].start + caretInLine;
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
    if (parsed.blocks.length != 1) {
      throw const FormatException('Magic block must contain one Typst block.');
    }
    final replacement = _parseBlock(parsed.blocks.single, '', blocks.length);
    final isTask = replacement.style == TyLogBlockStyle.taskLine;
    if (blocks.isEmpty) {
      replacement.separator = '\n\n';
      blocks = [replacement, _newParagraph('', 1, separator: '')];
      return isTask ? replacement.visibleText.length : 3;
    }
    replace(selection.start, selection.end, '');
    final hit = _blockAt(selection.start, preferPrevious: true);
    if (hit == null) {
      replacement.separator = '\n\n';
      final replacementIndex = blocks.length;
      blocks.addAll([
        replacement,
        _newParagraph('', blocks.length + 1, separator: ''),
      ]);
      return isTask ? _ranges[replacementIndex].end : _ranges.last.start;
    }
    final current = blocks[hit.index];
    if (!current.isProtected && current.visibleText.isEmpty) {
      replacement.separator = '\n\n';
      blocks.insert(hit.index, replacement);
      return isTask ? _ranges[hit.index].end : _ranges[hit.index + 1].start;
    }
    final tailSeparator = current.separator;
    replacement.separator = '\n\n';
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
    blocks.insert(hit.index + 1, replacement);
    final next = hit.index + 2;
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
      replacement.separator = '\n\n';
    }
    return isTask ? _ranges[hit.index + 1].end : _ranges[next].start;
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
      final persistedVisible = blocks
          .where((block) => block.isProtected || block.visibleText.isNotEmpty)
          .map((block) => block.visibleText)
          .join('\n\n');
      if ((reparsed.visibleText != visibleText &&
              reparsed.visibleText != persistedVisible) ||
          !_sameProtectedSources(reparsed, this)) {
        throw const FormatException(
          'Rich editor could not validate Typst output.',
        );
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

class TyLogEditingController extends TextEditingController {
  TyLogEditingController({
    required String source,
    required this.onSourceChanged,
    required this.onError,
    required this.onProtectedTap,
  }) : document = TyLogDocument.parse(source),
       super(text: TyLogDocument.parse(source).visibleText) {
    _lastValue = value;
    addListener(_handleValue);
  }

  TyLogDocument document;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<Object> onError;
  final ValueChanged<String> onProtectedTap;
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  static _RichClipboard? _richClipboard;
  late TextEditingValue _lastValue;
  _Snapshot? _compositionStart;
  bool _updating = false;
  TyLogInlineStyle _typingStyle = const TyLogInlineStyle();

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get isComposing => _isComposing(value);
  String get selectedPlainText =>
      selection.isValid ? document.plainText(selection) : '';
  String protectedSource(String id) => document.sourceFor(id);

  void loadSource(String source) {
    _updating = true;
    document = TyLogDocument.parse(source);
    value = TextEditingValue(
      text: document.visibleText,
      selection: TextSelection.collapsed(offset: document.visibleText.length),
    );
    _lastValue = value;
    _compositionStart = null;
    _undo.clear();
    _redo.clear();
    _updating = false;
    notifyListeners();
  }

  void _handleValue() {
    if (_updating) return;
    final next = value;
    if (next.text == _lastValue.text) {
      if (_compositionStart != null && !_isComposing(next)) {
        _commitComposition(next);
        return;
      }
      _lastValue = next;
      return;
    }
    final before = _Snapshot(document.copy(), _lastValue);
    final composing = _isComposing(next);
    if (composing) _compositionStart ??= before;
    try {
      final change = _replacement(_lastValue.text, next.text);
      if (change.replacement == '\n' && change.start == change.oldEnd) {
        final previousCaret = _lastValue.selection.extentOffset;
        final enterOffset =
            previousCaret >= 0 &&
                next.selection.extentOffset == previousCaret + 1
            ? previousCaret
            : change.start;
        final offset = document.insertNewline(enterOffset);
        _updating = true;
        value = TextEditingValue(
          text: document.visibleText,
          selection: TextSelection.collapsed(offset: offset),
        );
        _lastValue = value;
        _updating = false;
        final source = document.toSource();
        _addUndo(_compositionStart ?? before);
        _compositionStart = null;
        _redo.clear();
        onSourceChanged(source);
        return;
      }
      if (change.replacement.isEmpty && change.oldEnd - change.start == 1) {
        // Backspace at the start of a task's text (deleting inside its 2-char
        // "☐ "/"☑ " prefix) demotes the whole line to a plain paragraph
        // rather than mangling the checkbox glyph.
        final hit = document._blockAt(change.start, preferPrevious: true);
        if (hit != null &&
            document.blocks[hit.index].style == TyLogBlockStyle.taskLine &&
            change.start - hit.start >= 0 &&
            change.oldEnd - hit.start <= 2) {
          final offset = document.setBlockStyle(
            hit.start + 2,
            TyLogBlockStyle.paragraph,
          );
          _updating = true;
          value = TextEditingValue(
            text: document.visibleText,
            selection: TextSelection.collapsed(offset: offset),
          );
          _lastValue = value;
          _updating = false;
          final source = document.toSource();
          _addUndo(_compositionStart ?? before);
          _compositionStart = null;
          _redo.clear();
          onSourceChanged(source);
          return;
        }
      }
      if (change.start == change.oldEnd && change.replacement.isNotEmpty) {
        final hit = document._blockAt(change.start, preferPrevious: true);
        if (hit != null &&
            document.blocks[hit.index].isProtected &&
            (change.start == hit.end || change.start == hit.start)) {
          // Typing at the chip's edge: open a paragraph next to the protected
          // node and put the typed text there (before the chip at its leading
          // edge, after it at its trailing edge).
          final leading = change.start == hit.start;
          final opened = document.insertNewline(change.start);
          final start = leading ? change.start : opened;
          document.replace(
            start,
            start,
            change.replacement,
            insertionStyle: _typingStyle,
          );
          _updating = true;
          value = TextEditingValue(
            text: document.visibleText,
            selection: TextSelection.collapsed(
              offset: start + change.replacement.length,
            ),
          );
          _lastValue = value;
          _updating = false;
          final source = document.toSource();
          _addUndo(_compositionStart ?? before);
          _compositionStart = null;
          _redo.clear();
          onSourceChanged(source);
          return;
        }
      }
      document.replace(
        change.start,
        change.oldEnd,
        change.replacement,
        insertionStyle: _typingStyle,
      );
      var accepted = next;
      if (document.visibleText != next.text) {
        final removedProtected = _lastValue.text
            .substring(change.start, change.oldEnd)
            .contains(_object);
        if (!removedProtected) {
          throw const FormatException('Edit crossed a protected Typst node.');
        }
        final offset = math.min(
          next.selection.baseOffset,
          document.visibleText.length,
        );
        _updating = true;
        value = TextEditingValue(
          text: document.visibleText,
          selection: TextSelection.collapsed(offset: math.max(0, offset)),
        );
        accepted = value;
        _updating = false;
      }
      _lastValue = accepted;
      if (composing) return;
      final source = document.toSource();
      _addUndo(_compositionStart ?? before);
      _compositionStart = null;
      _redo.clear();
      onSourceChanged(source);
    } catch (error) {
      _restore(_compositionStart ?? before, emit: false);
      _compositionStart = null;
      onError(error);
    }
  }

  void _commitComposition(TextEditingValue next) {
    final before = _compositionStart!;
    try {
      final source = document.toSource();
      _lastValue = next;
      _compositionStart = null;
      _addUndo(before);
      _redo.clear();
      onSourceChanged(source);
    } catch (error) {
      _restore(before, emit: false);
      _compositionStart = null;
      onError(error);
    }
  }

  void _addUndo(_Snapshot snapshot) {
    _undo.add(snapshot);
    if (_undo.length > 100) _undo.removeAt(0);
  }

  static bool _isComposing(TextEditingValue value) =>
      value.composing.isValid && !value.composing.isCollapsed;

  void toggleBold() {
    _clearComposition();
    if (selection.isCollapsed) {
      _typingStyle = _typingStyle.copyWith(bold: !_typingStyle.bold);
      notifyListeners();
      return;
    }
    _format(
      () => document.toggle(
        selection,
        bold: !_selectionHas((style) => style.bold),
      ),
    );
  }

  void toggleItalic() {
    _clearComposition();
    if (selection.isCollapsed) {
      _typingStyle = _typingStyle.copyWith(italic: !_typingStyle.italic);
      notifyListeners();
      return;
    }
    _format(
      () => document.toggle(
        selection,
        italic: !_selectionHas((style) => style.italic),
      ),
    );
  }

  void setHeading() {
    var offset = selection.isValid ? selection.baseOffset : text.length;
    _format(() {
      offset = document.setBlockStyle(offset, TyLogBlockStyle.heading);
    }, selectionOffset: () => offset);
  }

  void setBulletList() {
    var offset = selection.isValid ? selection.baseOffset : text.length;
    _format(() {
      offset = document.setBlockStyle(offset, TyLogBlockStyle.bulletList);
    }, selectionOffset: () => offset);
  }

  bool _selectionHas(bool Function(TyLogInlineStyle style) test) {
    if (!selection.isValid) return false;
    if (selection.isCollapsed) return test(_typingStyle);
    for (final range in document._ranges) {
      final block = document.blocks[range.index];
      if (block.isProtected) continue;
      var cursor = range.start;
      for (final part in block.parts) {
        final end = cursor + part.text.length;
        if (!part.isAtom &&
            cursor < selection.end &&
            end > selection.start &&
            test(part.style)) {
          return true;
        }
        cursor = end;
      }
    }
    return false;
  }

  void _clearComposition() {
    if (!_isComposing(value)) return;
    value = value.copyWith(composing: TextRange.empty);
  }

  void _format(VoidCallback change, {int Function()? selectionOffset}) {
    _clearComposition();
    final before = _snapshot();
    try {
      change();
      final source = document.toSource();
      _undo.add(before);
      _redo.clear();
      if (value.text != document.visibleText) {
        final offset = math.min(
          selectionOffset?.call() ?? selection.baseOffset,
          document.visibleText.length,
        );
        _updating = true;
        value = TextEditingValue(
          text: document.visibleText,
          selection: TextSelection.collapsed(offset: offset),
        );
        _updating = false;
      }
      _lastValue = value;
      notifyListeners();
      onSourceChanged(source);
    } catch (error) {
      _restore(before, emit: false);
      onError(error);
    }
  }

  void applyMagic(MagicRequest request) {
    _clearComposition();
    switch (request.action) {
      case MagicAction.bold:
        toggleBold();
        return;
      case MagicAction.italic:
        toggleItalic();
        return;
      case MagicAction.heading:
        setHeading();
        return;
      default:
        final selection = this.selection.isValid
            ? this.selection
            : TextSelection.collapsed(offset: text.length);
        final selected = selectedPlainText;
        final edit = applyMagicEdit(
          selected,
          TextSelection(baseOffset: 0, extentOffset: selected.length),
          request,
        );
        final label = switch (request.action) {
          MagicAction.noteLink ||
          MagicAction.mention ||
          MagicAction.project => request.value ?? selected,
          MagicAction.tag => request.value ?? selected,
          MagicAction.task => request.value ?? selected,
          MagicAction.date => request.value ?? selected,
          MagicAction.citation => request.value ?? selected,
          MagicAction.attachment =>
            request.value?.split('/').last ?? 'Attachment',
          MagicAction.table => 'Table',
          MagicAction.equation => request.value ?? selected,
          MagicAction.report => 'Report',
          MagicAction.bold || MagicAction.italic || MagicAction.heading => '',
        };
        final before = _snapshot();
        try {
          final isBlock = const {
            MagicAction.task,
            MagicAction.table,
            MagicAction.equation,
          }.contains(request.action);
          final offset = isBlock
              ? document.insertBlock(selection, edit.text)
              : document.insertSource(selection, edit.text, label: label);
          final nextText = document.visibleText;
          _updating = true;
          value = TextEditingValue(
            text: nextText,
            selection: TextSelection.collapsed(offset: offset),
          );
          _lastValue = value;
          _updating = false;
          final source = document.toSource();
          _undo.add(before);
          _redo.clear();
          onSourceChanged(source);
        } catch (error) {
          _restore(before, emit: false);
          onError(error);
        }
    }
  }

  void replaceProtected(String id, String source) => _format(() {
    document.replaceProtected(id, source);
    _updating = true;
    value = value.copyWith(text: document.visibleText);
    _lastValue = value;
    _updating = false;
  });

  void toggleTask(String id) {
    final block = document.blocks.firstWhere((block) => block.id == id);
    final base = block.dirty ? _serializeBlock(block) : block.originalSource;
    final taskId = taskField(base, 'id')!;
    final next = taskField(base, 'status') == 'done' ? 'todo' : 'done';
    replaceProtected(id, replaceTaskStatus(base, taskId, next));
  }

  /// If the caret sits on a taskLine's checkbox glyph (its first two
  /// characters), tapping toggles the task instead of just placing the
  /// caret there.
  void handleEditorTap() {
    if (!selection.isValid || !selection.isCollapsed) return;
    final offset = selection.baseOffset;
    for (final range in document._ranges) {
      final block = document.blocks[range.index];
      if (block.style != TyLogBlockStyle.taskLine) continue;
      if (offset < range.start || offset >= range.start + 2) continue;
      toggleTask(block.id);
      selection = TextSelection.collapsed(offset: range.start + 2);
      return;
    }
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  Future<void> copySelection() async {
    if (!selection.isValid || selection.isCollapsed) return;
    final plain = selectedPlainText;
    _richClipboard = _RichClipboard(plain, document._inlineFragment(selection));
    await Clipboard.setData(ClipboardData(text: plain));
  }

  Future<void> cutSelection() async {
    if (!selection.isValid || selection.isCollapsed) return;
    await copySelection();
    value = value.copyWith(
      text: text.replaceRange(selection.start, selection.end, ''),
      selection: TextSelection.collapsed(offset: selection.start),
      composing: TextRange.empty,
    );
  }

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text ?? _richClipboard?.plain;
    if (pasted == null) return;
    final rich = _richClipboard;
    if (rich != null && rich.plain == pasted && rich.parts != null) {
      final before = _snapshot();
      try {
        document._replaceWithParts(
          selection,
          rich.parts!.map((part) => part.copy()).toList(),
        );
        final start = selection.isValid ? selection.start : text.length;
        final inserted = rich.parts!.fold<int>(
          0,
          (length, part) => length + part.text.length,
        );
        _updating = true;
        value = TextEditingValue(
          text: document.visibleText,
          selection: TextSelection.collapsed(offset: start + inserted),
        );
        _lastValue = value;
        _updating = false;
        final source = document.toSource();
        _undo.add(before);
        _redo.clear();
        onSourceChanged(source);
        return;
      } catch (error) {
        _restore(before, emit: false);
        onError(error);
        return;
      }
    }
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    value = value.copyWith(
      text: text.replaceRange(start, end, pasted),
      selection: TextSelection.collapsed(offset: start + pasted.length),
      composing: TextRange.empty,
    );
  }

  _Snapshot _snapshot() => _Snapshot(document.copy(), value);

  void _restore(_Snapshot snapshot, {bool emit = true}) {
    _updating = true;
    document = snapshot.document.copy();
    value = snapshot.value.copyWith(text: document.visibleText);
    _lastValue = value;
    _compositionStart = null;
    _updating = false;
    notifyListeners();
    if (emit) onSourceChanged(document.toSource());
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => _textSpan(context, style, withComposing: withComposing);

  TextSpan readTextSpan(BuildContext context, {TextStyle? style}) =>
      _textSpan(context, style, withComposing: false, interactive: false);

  TextSpan _textSpan(
    BuildContext context,
    TextStyle? style, {
    required bool withComposing,
    bool interactive = true,
  }) {
    final children = <InlineSpan>[];
    var global = 0;
    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      if (block.isProtected) {
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _ProtectedChip(
              label: block.protectedLabel ?? 'Custom Typst',
              block: true,
              onTap: interactive ? () => onProtectedTap(block.id) : null,
            ),
          ),
        );
        global++;
      } else {
        final taskDone =
            block.style == TyLogBlockStyle.taskLine &&
            block.visibleText.startsWith('☑');
        for (final part in block.parts) {
          if (part.isAtom) {
            children.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _ProtectedChip(
                  label: part.label!,
                  block: false,
                  onTap: interactive ? () => onProtectedTap(part.id!) : null,
                ),
              ),
            );
            global++;
          } else {
            var partStyle = _styleFor(context, style, block.style, part.style);
            if (taskDone) {
              partStyle = partStyle.copyWith(
                decoration: TextDecoration.lineThrough,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              );
            }
            _addTextSpans(
              children,
              part.text,
              global,
              style: partStyle,
              composing: withComposing ? value.composing : TextRange.empty,
            );
            global += part.text.length;
          }
        }
      }
      if (i + 1 < document.blocks.length) {
        children.add(TextSpan(text: '\n\n', style: style));
        global += 2;
      }
    }
    return TextSpan(style: style, children: children);
  }
}

class TyLogRichEditor extends StatefulWidget {
  const TyLogRichEditor({
    super.key,
    required this.controller,
    required this.onInsert,
    this.onMentionQuery,
    this.commandActions,
    this.onCommandSelected,
  });

  final TyLogEditingController controller;
  final Future<void> Function() onInsert;

  /// Resolves candidates for the inline "@" mention popup. Kept decoupled
  /// from tylog_core's search index — the parent maps its own search
  /// results into [MentionSuggestion]s.
  final Future<List<MentionSuggestion>> Function(String query)?
  onMentionQuery;

  /// Actions offered by the inline "/" command palette. Defaults to the
  /// same action set as the Magic bottom-sheet menu, in the same order.
  final List<MagicAction> Function()? commandActions;

  /// Invoked when a "/" palette entry is selected — the parent should run
  /// the exact same handler the Magic menu uses for that action.
  final Future<void> Function(MagicAction action)? onCommandSelected;

  @override
  State<TyLogRichEditor> createState() => _TyLogRichEditorState();
}

class TyLogReadView extends StatefulWidget {
  const TyLogReadView({super.key, required this.source});

  final String source;

  @override
  State<TyLogReadView> createState() => _TyLogReadViewState();
}

class _TyLogReadViewState extends State<TyLogReadView> {
  late final TyLogEditingController controller = TyLogEditingController(
    source: widget.source,
    onSourceChanged: (_) {},
    onError: (_) {},
    onProtectedTap: (_) {},
  );

  @override
  void didUpdateWidget(TyLogReadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source) controller.loadSource(widget.source);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectableText.rich(
    controller.readTextSpan(
      context,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
    ),
  );
}

const _defaultAutocompleteDebounce = Duration(milliseconds: 150);
const _autocompleteRowHeight = 48.0;
const _autocompleteMaxVisible = 6;

class _TyLogRichEditorState extends State<TyLogRichEditor> {
  late final FocusNode focusNode;
  final LayerLink _layerLink = LayerLink();
  final ValueNotifier<_AutocompleteState?> _autocomplete = ValueNotifier(null);
  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  int _mentionQueryToken = 0;

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode(onKeyEvent: _handleKey);
    focusNode.addListener(_focusChanged);
    if (kEnableInlineAutocomplete) {
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  void _focusChanged() {
    if (!focusNode.hasFocus) _cancelAutocomplete();
    setState(() {});
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent && _autocomplete.value != null) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        _moveHighlight(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _moveHighlight(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _activateHighlighted();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _cancelAutocomplete();
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyZ) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    keyboard.isShiftPressed
        ? widget.controller.redo()
        : widget.controller.undo();
    return KeyEventResult.handled;
  }

  void _handleControllerChanged() {
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _cancelAutocomplete();
      return;
    }
    final trigger = detectTrigger(widget.controller.text, selection.baseOffset);
    if (trigger == null) {
      _cancelAutocomplete();
      return;
    }
    if (trigger.kind == AutocompleteTriggerKind.command) {
      _debounce?.cancel();
      _autocomplete.value = _AutocompleteState(
        trigger: trigger,
        mentionItems: const [],
        commandItems: _filterCommands(trigger.query),
        highlighted: 0,
        loading: false,
      );
      _ensureOverlay();
      return;
    }
    final previous = _autocomplete.value;
    final samePosition =
        previous != null &&
        previous.trigger.kind == AutocompleteTriggerKind.mention &&
        previous.trigger.start == trigger.start;
    _autocomplete.value = _AutocompleteState(
      trigger: trigger,
      mentionItems: samePosition ? previous.mentionItems : const [],
      commandItems: const [],
      highlighted: 0,
      loading: true,
    );
    _ensureOverlay();
    _debounce?.cancel();
    _debounce = Timer(_defaultAutocompleteDebounce, () => _runMentionQuery(trigger));
  }

  List<MagicAction> _filterCommands(String query) {
    final actions = widget.commandActions?.call() ?? kMagicActionDisplay.keys.toList();
    if (query.isEmpty) return actions;
    final normalized = query.toLowerCase();
    return actions
        .where(
          (action) => (kMagicActionDisplay[action]?.$2 ?? action.name)
              .toLowerCase()
              .contains(normalized),
        )
        .toList();
  }

  Future<void> _runMentionQuery(AutocompleteTrigger trigger) async {
    final onMentionQuery = widget.onMentionQuery;
    if (onMentionQuery == null) return;
    final token = ++_mentionQueryToken;
    final results = await onMentionQuery(trigger.query);
    if (!mounted || token != _mentionQueryToken) return;
    final current = _autocomplete.value;
    if (current == null ||
        current.trigger.kind != AutocompleteTriggerKind.mention ||
        current.trigger.start != trigger.start) {
      return;
    }
    _autocomplete.value = _AutocompleteState(
      trigger: current.trigger,
      mentionItems: results,
      commandItems: const [],
      highlighted: 0,
      loading: false,
    );
  }

  void _moveHighlight(int delta) {
    final state = _autocomplete.value;
    if (state == null) return;
    final count = state.trigger.kind == AutocompleteTriggerKind.mention
        ? state.mentionItems.length
        : state.commandItems.length;
    if (count == 0) return;
    final next = (state.highlighted + delta) % count;
    _autocomplete.value = state.copyWith(
      highlighted: next < 0 ? next + count : next,
    );
  }

  void _activateHighlighted() {
    final state = _autocomplete.value;
    if (state == null) return;
    if (state.trigger.kind == AutocompleteTriggerKind.mention) {
      if (state.highlighted < state.mentionItems.length) {
        _selectMention(state.mentionItems[state.highlighted]);
      }
    } else {
      if (state.highlighted < state.commandItems.length) {
        _selectCommand(state.commandItems[state.highlighted]);
      }
    }
  }

  void _selectMention(MentionSuggestion item) {
    final trigger = _autocomplete.value?.trigger;
    if (trigger == null) return;
    final caret = widget.controller.selection.baseOffset;
    _cancelAutocomplete();
    widget.controller.selection = TextSelection(
      baseOffset: trigger.start,
      extentOffset: caret,
    );
    widget.controller.applyMagic(
      MagicRequest(action: MagicAction.mention, id: item.id, value: item.title),
    );
    focusNode.requestFocus();
  }

  Future<void> _selectCommand(MagicAction action) async {
    final trigger = _autocomplete.value?.trigger;
    if (trigger == null) return;
    final caret = widget.controller.selection.baseOffset;
    _cancelAutocomplete();
    // Remove the "/query" text first so the chosen action's own handler
    // inserts at the trigger's position, exactly as if invoked from the
    // Magic menu with the cursor there.
    widget.controller.value = widget.controller.value.copyWith(
      text: widget.controller.text.replaceRange(trigger.start, caret, ''),
      selection: TextSelection.collapsed(offset: trigger.start),
      composing: TextRange.empty,
    );
    final handler = widget.onCommandSelected;
    if (handler != null) await handler(action);
    if (mounted) focusNode.requestFocus();
  }

  void _cancelAutocomplete() {
    _debounce?.cancel();
    _debounce = null;
    _mentionQueryToken++;
    if (_autocomplete.value != null) _autocomplete.value = null;
    _removeOverlay();
  }

  void _ensureOverlay() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _overlayEntry = OverlayEntry(builder: _buildOverlayContent);
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildOverlayContent(BuildContext context) => Positioned(
    width: 320,
    child: CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(16, 44),
      child: TextFieldTapRegion(
        child: ValueListenableBuilder<_AutocompleteState?>(
          valueListenable: _autocomplete,
          builder: (context, state, _) {
            if (state == null) return const SizedBox.shrink();
            return Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _autocompleteRowHeight * _autocompleteMaxVisible,
                ),
                child: state.trigger.kind == AutocompleteTriggerKind.mention
                    ? _mentionList(state)
                    : _commandList(state),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _mentionList(_AutocompleteState state) {
    if (state.loading && state.mentionItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (state.mentionItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No matches'),
      );
    }
    return ListView.builder(
      key: const Key('autocomplete-mention-list'),
      shrinkWrap: true,
      itemCount: state.mentionItems.length,
      itemBuilder: (context, index) {
        final item = state.mentionItems[index];
        return ListTile(
          key: Key('autocomplete-mention-${item.id}'),
          dense: true,
          tileColor: index == state.highlighted
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
          leading: const Icon(Icons.alternate_email),
          title: Text(item.title),
          subtitle: Text(item.id),
          onTap: () => _selectMention(item),
        );
      },
    );
  }

  Widget _commandList(_AutocompleteState state) {
    if (state.commandItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No matching commands'),
      );
    }
    return ListView.builder(
      key: const Key('autocomplete-command-list'),
      shrinkWrap: true,
      itemCount: state.commandItems.length,
      itemBuilder: (context, index) {
        final action = state.commandItems[index];
        final display = kMagicActionDisplay[action];
        return ListTile(
          key: Key('autocomplete-command-${action.name}'),
          dense: true,
          tileColor: index == state.highlighted
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
          leading: Icon(display?.$1 ?? Icons.bolt),
          title: Text(display?.$2 ?? action.name),
          onTap: () => _selectCommand(action),
        );
      },
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    if (kEnableInlineAutocomplete) {
      widget.controller.removeListener(_handleControllerChanged);
    }
    focusNode.removeListener(_focusChanged);
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: CompositedTransformTarget(
          link: _layerLink,
          child: TextField(
            key: const Key('rich-journal-editor'),
            controller: widget.controller,
            focusNode: focusNode,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.55),
            decoration: const InputDecoration(
              hintText: 'Start writing…',
              contentPadding: EdgeInsets.all(18),
            ),
            onTap: () => widget.controller.handleEditorTap(),
            onTapOutside: (_) => focusNode.unfocus(),
            contextMenuBuilder: (context, state) => TextFieldTapRegion(
              child: AdaptiveTextSelectionToolbar.buttonItems(
                anchors: state.contextMenuAnchors,
                buttonItems: [
                  if (!widget.controller.selection.isCollapsed)
                    ContextMenuButtonItem(
                      type: ContextMenuButtonType.copy,
                      onPressed: () {
                        state.hideToolbar();
                        widget.controller.copySelection();
                      },
                    ),
                  if (!widget.controller.selection.isCollapsed)
                    ContextMenuButtonItem(
                      type: ContextMenuButtonType.cut,
                      onPressed: () {
                        state.hideToolbar();
                        widget.controller.cutSelection();
                      },
                    ),
                  ContextMenuButtonItem(
                    type: ContextMenuButtonType.paste,
                    onPressed: () {
                      state.hideToolbar();
                      widget.controller.paste();
                    },
                  ),
                  ContextMenuButtonItem(
                    type: ContextMenuButtonType.selectAll,
                    onPressed: () {
                      state.selectAll(SelectionChangedCause.toolbar);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (focusNode.hasFocus)
        TextFieldTapRegion(
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 48,
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  scrollDirection: Axis.horizontal,
                  children: [
                    IconButton(
                      tooltip: 'Undo',
                      onPressed: widget.controller.canUndo
                          ? widget.controller.undo
                          : null,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: 'Redo',
                      onPressed: widget.controller.canRedo
                          ? widget.controller.redo
                          : null,
                      icon: const Icon(Icons.redo),
                    ),
                    IconButton(
                      tooltip: 'Heading 1',
                      onPressed: widget.controller.setHeading,
                      icon: Text(
                        'H1',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bold',
                      onPressed: widget.controller.toggleBold,
                      icon: const Icon(Icons.format_bold),
                    ),
                    IconButton(
                      tooltip: 'Italic',
                      onPressed: widget.controller.toggleItalic,
                      icon: const Icon(Icons.format_italic),
                    ),
                    IconButton(
                      tooltip: 'Bulleted list',
                      onPressed: widget.controller.setBulletList,
                      icon: const Icon(Icons.format_list_bulleted),
                    ),
                    IconButton(
                      tooltip: 'Insert',
                      onPressed: () async {
                        try {
                          await widget.onInsert();
                        } finally {
                          if (mounted) focusNode.requestFocus();
                        }
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _ProtectedChip extends StatelessWidget {
  const _ProtectedChip({
    required this.label,
    required this.block,
    required this.onTap,
  });

  final String label;
  final bool block;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: '$label, protected Typst',
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: block ? 0 : 2, vertical: 2),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: block ? 12 : 7,
              vertical: block ? 10 : 3,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(block ? Icons.code : Icons.link, size: 16),
                const SizedBox(width: 5),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

TyLogBlock _parseBlock(ControlledBlock block, String separator, int index) {
  final source = block.source;
  final trimmed = source.trimLeft();
  final id = 'block-$index-${source.hashCode}';
  if (block.kind == ControlledBlockKind.task) {
    final taskId = taskField(source, 'id');
    final taskText = taskField(source, 'text');
    if (taskId != null && taskText != null) {
      final glyph = taskField(source, 'status') == 'done' ? '☑' : '☐';
      return TyLogBlock(
        id: id,
        style: TyLogBlockStyle.taskLine,
        parts: [TyLogInline.text('$glyph $taskText')],
        originalSource: source,
        separator: separator,
      );
    }
    return TyLogBlock(
      id: id,
      style: TyLogBlockStyle.protected,
      parts: const [],
      originalSource: source,
      separator: separator,
      protectedLabel: 'Task: ${controlledBlockPreview(block)}',
    );
  }
  if (block.kind == ControlledBlockKind.table ||
      block.kind == ControlledBlockKind.equation ||
      block.kind == ControlledBlockKind.raw) {
    return TyLogBlock(
      id: id,
      style: TyLogBlockStyle.protected,
      parts: const [],
      originalSource: source,
      separator: separator,
      protectedLabel: switch (block.kind) {
        ControlledBlockKind.table => 'Table',
        ControlledBlockKind.equation => 'Equation',
        _ => 'Custom Typst',
      },
    );
  }

  var style = TyLogBlockStyle.paragraph;
  var body = trimmed;
  if (block.kind == ControlledBlockKind.heading) {
    style = TyLogBlockStyle.heading;
    body = trimmed.replaceFirst(RegExp(r'^=+\s*'), '');
  } else if (block.kind == ControlledBlockKind.list) {
    final numbered = RegExp(r'^(?:\d+\. |\+ )').hasMatch(trimmed);
    style = numbered
        ? TyLogBlockStyle.numberedList
        : TyLogBlockStyle.bulletList;
    var number = 1;
    body = trimmed
        .split('\n')
        .map((line) {
          final content = line.replaceFirst(RegExp(r'^(?:[-+] |\d+\. )'), '');
          return numbered ? '${number++}. $content' : '• $content';
        })
        .join('\n');
  }
  final parts = _parseInline(body);
  if (parts == null) {
    return TyLogBlock(
      id: id,
      style: TyLogBlockStyle.protected,
      parts: const [],
      originalSource: source,
      separator: separator,
      protectedLabel: 'Custom Typst',
    );
  }
  return TyLogBlock(
    id: id,
    style: style,
    parts: parts,
    originalSource: source,
    separator: separator,
  );
}

List<TyLogInline>? _parseInline(
  String source, {
  TyLogInlineStyle inherited = const TyLogInlineStyle(),
}) {
  final parts = <TyLogInline>[];
  final plain = StringBuffer();
  var atom = 0;
  void flush() {
    if (plain.isEmpty) return;
    parts.add(TyLogInline.text(plain.toString(), style: inherited));
    plain.clear();
  }

  for (var i = 0; i < source.length;) {
    if (source.codeUnitAt(i) == 92 && i + 1 < source.length) {
      plain.write(source[i + 1]);
      i += 2;
      continue;
    }
    final styled = <(String, bool, bool)>[
      ('#strong[', true, false),
      ('#emph[', false, true),
    ];
    var consumedStyle = false;
    for (final entry in styled) {
      if (!source.startsWith(entry.$1, i)) continue;
      final open = i + entry.$1.length - 1;
      final close = _squareEnd(source, open);
      if (close == null) return null;
      final nested = _parseInline(
        source.substring(open + 1, close - 1),
        inherited: inherited.copyWith(
          bold: inherited.bold || entry.$2,
          italic: inherited.italic || entry.$3,
        ),
      );
      if (nested == null) return null;
      flush();
      parts.addAll(nested);
      i = close;
      consumedStyle = true;
      break;
    }
    if (consumedStyle) continue;

    final delimiter = source[i];
    if (delimiter == '*' || delimiter == '_') {
      final close = _unescapedIndexOf(source, delimiter, i + 1);
      if (close > i + 1) {
        final nested = _parseInline(
          source.substring(i + 1, close),
          inherited: inherited.copyWith(
            bold: inherited.bold || delimiter == '*',
            italic: inherited.italic || delimiter == '_',
          ),
        );
        if (nested == null) return null;
        flush();
        parts.addAll(nested);
        i = close + 1;
        continue;
      }
    }

    final atomMatch = RegExp(
      r'^(#(?:link|tylog\.(?:ref-note|date-ref|attachment))\([^\n]*?\)\[[^\]]*\]|#tylog\.tag\("(?:\\.|[^"])*"\)|#cite\([^)]*\)|#[iI]mage\([^)]*\)|@[A-Za-z0-9_.:+-]+)',
    ).firstMatch(source.substring(i));
    if (atomMatch != null) {
      final raw = atomMatch.group(0)!;
      flush();
      parts.add(
        TyLogInline.atom(
          source: raw,
          label: _atomLabel(raw),
          id: 'atom-${source.hashCode}-${atom++}',
        ),
      );
      i += raw.length;
      continue;
    }
    if (source.codeUnitAt(i) == 35) {
      // Any other cleanly delimited call (e.g. #footnote[…], #link("url"))
      // becomes an inline protected atom so the surrounding prose stays
      // editable instead of collapsing the whole paragraph.
      final end = inlineCallEnd(source, i);
      if (end == null) return null;
      final raw = source.substring(i, end);
      flush();
      parts.add(
        TyLogInline.atom(
          source: raw,
          label: _atomLabel(raw),
          id: 'atom-${source.hashCode}-${atom++}',
        ),
      );
      i = end;
      continue;
    }
    plain.writeCharCode(source.codeUnitAt(i));
    i++;
  }
  flush();
  return _normalize(parts);
}

String _atomLabel(String source) {
  final content = RegExp(r'\[([^\]]*)\]$').firstMatch(source)?.group(1);
  if (content != null && content.isNotEmpty) {
    return content.replaceAll(r'\@', '@');
  }
  final quoted = RegExp(r'"((?:\\.|[^"])*)"').firstMatch(source)?.group(1);
  if (quoted != null) {
    return quoted.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  }
  if (source.startsWith('@')) return source.substring(1);
  if (source.startsWith('#cite(')) {
    return source.substring(6, source.length - 1);
  }
  return source.startsWith('#image') ? 'Image' : 'Reference';
}

int? _squareEnd(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source.codeUnitAt(i) == 92) {
      i++;
      continue;
    }
    if (source.codeUnitAt(i) == 91) depth++;
    if (source.codeUnitAt(i) == 93 && --depth == 0) return i + 1;
  }
  return null;
}

int _unescapedIndexOf(String source, String value, int start) {
  var index = source.indexOf(value, start);
  while (index >= 0 && index > 0 && source.codeUnitAt(index - 1) == 92) {
    index = source.indexOf(value, index + 1);
  }
  return index;
}

void _replaceInBlock(
  TyLogBlock block,
  int start,
  int end,
  String replacement, {
  TyLogInlineStyle? insertionStyle,
}) {
  final units = _units(block.parts);
  final inherited =
      insertionStyle ??
      (start > 0 && start <= units.length
          ? units[start - 1].style
          : start < units.length
          ? units[start].style
          : const TyLogInlineStyle());
  units.replaceRange(
    start,
    end,
    replacement.codeUnits.map((code) => _Unit(code, inherited, null)),
  );
  block
    ..parts = _parts(units)
    ..dirty = true;
}

void _styleBlock(
  TyLogBlock block,
  int start,
  int end, {
  bool? bold,
  bool? italic,
}) {
  final units = _units(block.parts);
  for (var i = start; i < end && i < units.length; i++) {
    if (units[i].atom != null) continue;
    units[i] = _Unit(
      units[i].code,
      units[i].style.copyWith(bold: bold, italic: italic),
      null,
    );
  }
  block
    ..parts = _parts(units)
    ..dirty = true;
}

List<_Unit> _units(Iterable<TyLogInline> parts) => [
  for (final part in parts)
    if (part.isAtom)
      _Unit(0xFFFC, part.style, part)
    else
      for (final code in part.text.codeUnits) _Unit(code, part.style, null),
];

List<TyLogInline> _parts(List<_Unit> units) {
  final result = <TyLogInline>[];
  final codes = <int>[];
  TyLogInlineStyle? style;
  void flush() {
    if (codes.isEmpty) {
      return;
    }
    result.add(TyLogInline.text(String.fromCharCodes(codes), style: style!));
    codes.clear();
  }

  for (final unit in units) {
    if (unit.atom != null) {
      flush();
      result.add(unit.atom!.copy());
      style = null;
      continue;
    }
    if (style != null && style != unit.style) flush();
    style = unit.style;
    codes.add(unit.code);
  }
  flush();
  return _normalize(result);
}

List<TyLogInline> _normalize(List<TyLogInline> parts) {
  final result = <TyLogInline>[];
  for (final part in parts) {
    if (!part.isAtom && part.text.isEmpty) continue;
    if (!part.isAtom &&
        result.isNotEmpty &&
        !result.last.isAtom &&
        result.last.style == part.style) {
      result.last.text += part.text;
    } else {
      result.add(part);
    }
  }
  return result;
}

TyLogBlock _newParagraph(String text, int id, {required String separator}) =>
    TyLogBlock(
      id: 'new-$id',
      style: TyLogBlockStyle.paragraph,
      parts: [TyLogInline.text(text)],
      originalSource: '',
      separator: separator,
      dirty: true,
    );

TyLogBlock _blockFrom(
  TyLogBlock original,
  List<_Unit> units, {
  TyLogBlockStyle? style,
}) => TyLogBlock(
  id: 'split-${DateTime.now().microsecondsSinceEpoch}-${units.hashCode}',
  style: style ?? original.style,
  parts: _parts(units),
  originalSource: '',
  separator: original.separator,
  dirty: true,
);

String _serializeBlock(TyLogBlock block) {
  if (block.isProtected) return block.originalSource;
  final content = block.parts.map(_serializePart).join();
  return switch (block.style) {
    TyLogBlockStyle.heading => '= $content',
    TyLogBlockStyle.bulletList =>
      content
          .split('\n')
          .map((line) => '- ${line.replaceFirst(RegExp(r'^•\s*'), '')}')
          .join('\n'),
    TyLogBlockStyle.numberedList =>
      content
          .split('\n')
          .map((line) => '+ ${line.replaceFirst(RegExp(r'^\d+\.\s*'), '')}')
          .join('\n'),
    TyLogBlockStyle.paragraph => content,
    TyLogBlockStyle.protected => block.originalSource,
    TyLogBlockStyle.taskLine => replaceTaskText(
      block.originalSource,
      taskField(block.originalSource, 'id')!,
      block.visibleText.replaceFirst(RegExp('^[☐☑] '), ''),
    ),
  };
}

String _serializePart(TyLogInline part) {
  if (part.isAtom) return part.source!;
  var value = typstContent(part.text);
  if (part.style.italic) value = '#emph[$value]';
  if (part.style.bold) value = '#strong[$value]';
  return value;
}

bool _sameProtectedSources(TyLogDocument a, TyLogDocument b) {
  final aSources = [
    for (final block in a.blocks)
      if (block.isProtected) block.originalSource,
    for (final block in a.blocks)
      for (final part in block.parts)
        if (part.isAtom) part.source,
  ];
  final bSources = [
    for (final block in b.blocks)
      if (block.isProtected) block.originalSource,
    for (final block in b.blocks)
      for (final part in block.parts)
        if (part.isAtom) part.source,
  ];
  return aSources.length == bSources.length &&
      List.generate(
        aSources.length,
        (i) => aSources[i] == bSources[i],
      ).every((same) => same);
}

_Replacement _replacement(String oldText, String newText) {
  var start = 0;
  while (start < oldText.length &&
      start < newText.length &&
      oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
    start++;
  }
  var oldEnd = oldText.length;
  var newEnd = newText.length;
  while (oldEnd > start &&
      newEnd > start &&
      oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }
  return _Replacement(start, oldEnd, newText.substring(start, newEnd));
}

void _addTextSpans(
  List<InlineSpan> target,
  String text,
  int global, {
  required TextStyle style,
  required TextRange composing,
}) {
  final start = math.max(global, composing.start);
  final end = math.min(global + text.length, composing.end);
  if (!composing.isValid || start >= end) {
    target.add(TextSpan(text: text, style: style));
    return;
  }
  if (start > global) {
    target.add(TextSpan(text: text.substring(0, start - global), style: style));
  }
  target.add(
    TextSpan(
      text: text.substring(start - global, end - global),
      style: style.copyWith(decoration: TextDecoration.underline),
    ),
  );
  if (end < global + text.length) {
    target.add(TextSpan(text: text.substring(end - global), style: style));
  }
}

TextStyle _styleFor(
  BuildContext context,
  TextStyle? base,
  TyLogBlockStyle block,
  TyLogInlineStyle inline,
) {
  var style = base ?? DefaultTextStyle.of(context).style;
  if (block == TyLogBlockStyle.heading) {
    style = style.merge(Theme.of(context).textTheme.headlineSmall);
  }
  if (block == TyLogBlockStyle.bulletList) {
    style = style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }
  return style.copyWith(
    fontWeight: inline.bold ? FontWeight.bold : style.fontWeight,
    fontStyle: inline.italic ? FontStyle.italic : style.fontStyle,
  );
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
