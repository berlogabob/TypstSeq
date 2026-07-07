import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controlled_editor.dart';

const _object = '\uFFFC';

enum TyLogBlockStyle { paragraph, heading, bulletList, numberedList, protected }

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
      final block = parsed.blocks[i];
      final nextStart = i + 1 < parsed.blocks.length
          ? parsed.blocks[i + 1].start
          : source.length;
      final separator = source.substring(block.end, nextStart);
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
      _replaceInBlock(
        block,
        localStart,
        localEnd,
        replacement,
        insertionStyle: insertionStyle,
      );
      return;
    }

    _replaceAcrossBlocks(start, end, replacement, startHit, endHit);
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
    blocks.replaceRange(first, last + 1, replacements);
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

  void setBlockStyle(int offset, TyLogBlockStyle style) {
    final hit = _blockAt(offset, preferPrevious: true);
    if (hit == null || blocks[hit.index].isProtected) return;
    blocks[hit.index]
      ..style = style
      ..dirty = true;
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

  void insertSource(
    TextRange selection,
    String source, {
    required String label,
  }) {
    _replaceWithParts(selection, [
      TyLogInline.atom(
        source: source,
        label: label,
        id: 'atom-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ]);
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
      if (reparsed.visibleText != visibleText ||
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
  bool _updating = false;
  TyLogInlineStyle _typingStyle = const TyLogInlineStyle();

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
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
    _undo.clear();
    _redo.clear();
    _updating = false;
    notifyListeners();
  }

  void _handleValue() {
    if (_updating) return;
    final next = value;
    if (next.text == _lastValue.text) {
      _lastValue = next;
      return;
    }
    final before = _snapshot();
    try {
      final change = _replacement(_lastValue.text, next.text);
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
      final source = document.toSource();
      _undo.add(before);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
      _lastValue = accepted;
      onSourceChanged(source);
    } catch (error) {
      _restore(before, emit: false);
      onError(error);
    }
  }

  void toggleBold() {
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

  void setHeading() => _format(
    () => document.setBlockStyle(selection.baseOffset, TyLogBlockStyle.heading),
  );

  void setBulletList() => _format(
    () => document.setBlockStyle(
      selection.baseOffset,
      TyLogBlockStyle.bulletList,
    ),
  );

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

  void _format(VoidCallback change) {
    final before = _snapshot();
    try {
      change();
      final source = document.toSource();
      _undo.add(before);
      _redo.clear();
      _lastValue = value;
      notifyListeners();
      onSourceChanged(source);
    } catch (error) {
      _restore(before, emit: false);
      onError(error);
    }
  }

  void applyMagic(MagicRequest request) {
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
        final selected = selectedPlainText;
        final edit = applyMagicEdit(
          selected,
          TextSelection(baseOffset: 0, extentOffset: selected.length),
          request,
        );
        final label = switch (request.action) {
          MagicAction.noteLink ||
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
          document.insertSource(selection, edit.text, label: label);
          final nextText = document.visibleText;
          final offset = math.min(selection.start + 1, nextText.length);
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
    _updating = false;
    notifyListeners();
    if (emit) onSourceChanged(document.toSource());
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
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
              onTap: () => onProtectedTap(block.id),
            ),
          ),
        );
        global++;
      } else {
        for (final part in block.parts) {
          if (part.isAtom) {
            children.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _ProtectedChip(
                  label: part.label!,
                  block: false,
                  onTap: () => onProtectedTap(part.id!),
                ),
              ),
            );
            global++;
          } else {
            _addTextSpans(
              children,
              part.text,
              global,
              style: _styleFor(context, style, block.style, part.style),
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
    required this.readOnly,
    required this.onInsert,
  });

  final TyLogEditingController controller;
  final bool readOnly;
  final VoidCallback onInsert;

  @override
  State<TyLogRichEditor> createState() => _TyLogRichEditorState();
}

class _TyLogRichEditorState extends State<TyLogRichEditor> {
  late final FocusNode focusNode;

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode(onKeyEvent: _handleKey);
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
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

  @override
  void didUpdateWidget(covariant TyLogRichEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readOnly && !widget.readOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: TextField(
          key: const Key('rich-journal-editor'),
          controller: widget.controller,
          focusNode: focusNode,
          readOnly: widget.readOnly,
          showCursor: !widget.readOnly,
          expands: true,
          minLines: null,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
          decoration: const InputDecoration(
            hintText: 'Start writing…',
            contentPadding: EdgeInsets.all(18),
          ),
          contextMenuBuilder: (context, state) =>
              AdaptiveTextSelectionToolbar.buttonItems(
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
                  if (!widget.readOnly &&
                      !widget.controller.selection.isCollapsed)
                    ContextMenuButtonItem(
                      type: ContextMenuButtonType.cut,
                      onPressed: () {
                        state.hideToolbar();
                        widget.controller.cutSelection();
                      },
                    ),
                  if (!widget.readOnly)
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
      if (!widget.readOnly)
        SafeArea(
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
                    tooltip: 'Heading',
                    onPressed: widget.controller.setHeading,
                    icon: const Icon(Icons.title),
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
                    onPressed: widget.onInsert,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
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
  final trimmed = source.trim();
  final id = 'block-$index-${source.hashCode}';
  if (block.kind == ControlledBlockKind.task ||
      block.kind == ControlledBlockKind.table ||
      block.kind == ControlledBlockKind.equation ||
      block.kind == ControlledBlockKind.raw) {
    return TyLogBlock(
      id: id,
      style: TyLogBlockStyle.protected,
      parts: const [],
      originalSource: source,
      separator: separator,
      protectedLabel: switch (block.kind) {
        ControlledBlockKind.task => 'Task: ${controlledBlockPreview(block)}',
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
    if (source.codeUnitAt(i) == 35) return null;
    plain.writeCharCode(source.codeUnitAt(i));
    i++;
  }
  flush();
  return _normalize(parts);
}

String _atomLabel(String source) {
  final content = RegExp(r'\[([^\]]*)\]$').firstMatch(source)?.group(1);
  if (content != null && content.isNotEmpty) return content;
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
