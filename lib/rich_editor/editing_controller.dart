part of '../rich_editor.dart';

class TyLogEditingController extends TextEditingController {
  TyLogEditingController({
    required String source,
    required ValueChanged<String> onSourceChanged,
    required ValueChanged<Object> onError,
    required ValueChanged<String> onProtectedTap,
    Future<Uint8List?> Function(String path)? imageResolver,
    String? Function(String target)? resolveKind,
  }) : this._(
         TyLogDocument.parse(source),
         onSourceChanged,
         onError,
         onProtectedTap,
         imageResolver,
         resolveKind,
       );

  TyLogEditingController._(
    this.document,
    this.onSourceChanged,
    this.onError,
    this.onProtectedTap,
    this.imageResolver,
    this.resolveKind,
  ) : super(text: document.visibleText) {
    _lastValue = value;
    addListener(_handleValue);
  }

  TyLogDocument document;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<Object> onError;
  final ValueChanged<String> onProtectedTap;

  /// Resolves a `#tylog.ref-note("target")` reference to the target note's
  /// `kind` (person/place/project/…) so the chip shows a matching icon. Null
  /// (no vault index) falls back to a generic note icon.
  final String? Function(String target)? resolveKind;

  /// Resolves a vault-relative asset path to its bytes so `#image(...)` atoms
  /// render as real pictures. Null (e.g. read-only previews without a vault)
  /// keeps the old path chip.
  final Future<Uint8List?> Function(String path)? imageResolver;
  final Map<String, Future<Uint8List?>> _imageCache = {};

  /// Cached bytes for [path] — loaded at most once per note so a rebuild on
  /// every keystroke doesn't re-hit SAF/disk.
  Future<Uint8List?> imageBytes(String path) => imageResolver == null
      ? Future.value(null)
      : _imageCache.putIfAbsent(path, () => imageResolver!(path));
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
    _imageCache.clear();
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
        final delinked = _autolinkEmailAt(enterOffset);
        _updating = true;
        value = TextEditingValue(
          text: document.visibleText,
          selection: TextSelection.collapsed(offset: offset - delinked),
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
      // Backspace deleting a newline that sits in the inter-block separator (no
      // block owns it) — merge this block into the previous one. Without this
      // the generic replace no-ops on the separator, the visible text doesn't
      // shrink, and the mismatch trips the crossed-protected-node guard and
      // reverts ("Backspace does nothing before a paragraph after a blank line").
      if (change.replacement.isEmpty &&
          change.oldEnd - change.start == 1 &&
          _lastValue.text.codeUnitAt(change.start) == 10) {
        final ranges = document._ranges;
        const mergeable = {
          TyLogBlockStyle.paragraph,
          TyLogBlockStyle.bulletList,
          TyLogBlockStyle.numberedList,
          TyLogBlockStyle.heading,
        };
        for (var i = 1; i < ranges.length; i++) {
          final gapStart = ranges[i - 1].end;
          final gapEnd = ranges[i].start;
          if (gapEnd <= gapStart ||
              change.start < gapStart ||
              change.oldEnd > gapEnd) {
            continue;
          }
          final prev = document.blocks[i - 1];
          if (prev.isProtected ||
              document.blocks[i].isProtected ||
              !mergeable.contains(prev.style)) {
            // Boundary backspace that can't merge (next to a protected node or
            // a task line) — consume it as a no-op instead of falling through
            // to the "crossed a protected node" guard, which would revert with
            // an error. The separator char isn't real content, so the model is
            // already correct; just discard the keystroke and keep the caret.
            _updating = true;
            value = TextEditingValue(
              text: _lastValue.text,
              selection: TextSelection.collapsed(offset: gapEnd),
            );
            _lastValue = value;
            _updating = false;
            return;
          }
          final offset = document.mergeBackward(i);
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
      // Typing a break char right after an address turns it into a link chip.
      if (!composing &&
          change.replacement.isNotEmpty &&
          _isEmailBreak(
            change.replacement.codeUnitAt(change.replacement.length - 1),
          )) {
        final breakOffset = change.start + change.replacement.length - 1;
        final delinked = _autolinkEmailAt(breakOffset);
        if (delinked > 0) {
          _updating = true;
          value = TextEditingValue(
            text: document.visibleText,
            selection: TextSelection.collapsed(
              offset: (accepted.selection.baseOffset - delinked).clamp(
                0,
                document.visibleText.length,
              ),
            ),
          );
          accepted = value;
          _updating = false;
        }
      }
      _lastValue = accepted;
      if (composing) return;
      final source = document.toSource();
      _addUndo(_compositionStart ?? before);
      _compositionStart = null;
      _redo.clear();
      onSourceChanged(source);
    } on FormatException catch (error) {
      // Accept-and-resync — ONLY for the round-trip validation failure (a benign
      // normalization: a char repositioned relative to a list glyph, a
      // paragraph line that re-parses as a list). If the canonical reparse keeps
      // every protected node the *pre-edit* document had, adopt it and remap the
      // caret. Task-integrity and protected-crossing guards raise their own
      // FormatExceptions and must still revert.
      var resynced = false;
      if (error.message == _validateFailMessage) {
        final raw = document.toSource(validate: false);
        final reparsed = TyLogDocument.parse(raw);
        if (_sameProtectedSources(reparsed, before.document)) {
          document.blocks = reparsed.blocks;
          document.prefix = reparsed.prefix;
          _updating = true;
          value = TextEditingValue(
            text: document.visibleText,
            selection: TextSelection.collapsed(
              offset: math.min(
                next.selection.baseOffset,
                document.visibleText.length,
              ),
            ),
          );
          _lastValue = value;
          _updating = false;
          _addUndo(_compositionStart ?? before);
          _compositionStart = null;
          _redo.clear();
          onSourceChanged(raw);
          resynced = true;
        }
      }
      if (!resynced) {
        _restore(_compositionStart ?? before, emit: false);
        _compositionStart = null;
        onError(error);
      }
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

  /// Flips one inline-style flag: on a collapsed caret it only moves the
  /// pending typing style, otherwise it rewrites the selected runs.
  ///
  /// ponytail: three closures because `copyWith` and `document.toggle` take
  /// named args, so the flag can't be passed as a value. Flatten back into
  /// per-flag methods if that ever reads better than the indirection.
  void _toggleFlag({
    required bool Function(TyLogInlineStyle style) read,
    required TyLogInlineStyle Function(TyLogInlineStyle style, bool value)
    write,
    required void Function(bool value) apply,
  }) {
    _clearComposition();
    if (selection.isCollapsed) {
      _typingStyle = write(_typingStyle, !read(_typingStyle));
      notifyListeners();
      return;
    }
    _format(() => apply(!_selectionHas(read)));
  }

  void toggleBold() => _toggleFlag(
    read: (style) => style.bold,
    write: (style, value) => style.copyWith(bold: value),
    apply: (value) => document.toggle(selection, bold: value),
  );

  void toggleItalic() => _toggleFlag(
    read: (style) => style.italic,
    write: (style, value) => style.copyWith(italic: value),
    apply: (value) => document.toggle(selection, italic: value),
  );

  void toggleStrike() => _toggleFlag(
    read: (style) => style.strike,
    write: (style, value) => style.copyWith(strike: value),
    apply: (value) => document.toggle(selection, strike: value),
  );

  void toggleUnderline() => _toggleFlag(
    read: (style) => style.underline,
    write: (style, value) => style.copyWith(underline: value),
    apply: (value) => document.toggle(selection, underline: value),
  );

  void toggleMono() => _toggleFlag(
    read: (style) => style.mono,
    write: (style, value) => style.copyWith(mono: value),
    apply: (value) => document.toggle(selection, mono: value),
  );

  /// Sets the highlight fill explicitly — `null` clears it, `''` is Typst's
  /// default fill, anything else is a verbatim `fill:` expression. Used by
  /// the toolbar's long-press palette and by [setHighlight] callers that
  /// already know the target fill.
  void setHighlight(String? fill) {
    _clearComposition();
    if (selection.isCollapsed) {
      _typingStyle = _typingStyle.copyWith(highlight: fill);
      notifyListeners();
      return;
    }
    _format(() => document.toggle(selection, highlight: fill));
  }

  /// Tap behavior for the highlight toolbar button and the "highlight"
  /// magic/slash action: toggles the default fill on/off.
  void toggleHighlight() {
    final active = selection.isCollapsed
        ? _typingStyle.highlight != null
        : _selectionHas((style) => style.highlight != null);
    setHighlight(active ? null : '');
  }

  void clearFormatting() {
    _clearComposition();
    if (selection.isCollapsed) {
      _typingStyle = const TyLogInlineStyle();
      notifyListeners();
      return;
    }
    _format(() => document.toggle(selection, reset: true));
  }

  void setHeading({int level = 1}) {
    // A heading is a one-line construct: with a ranged selection, apply it to
    // the FIRST selected line (selection.start), never the anchor/base, which
    // sits at the selection end when the user selected bottom-up.
    var offset = selection.isValid ? selection.start : text.length;
    _format(() {
      offset = document.setBlockStyle(
        offset,
        TyLogBlockStyle.heading,
        headingLevel: level,
      );
    }, selectionOffset: () => offset);
  }

  void setBulletList() => _setListStyle(TyLogBlockStyle.bulletList);

  void setNumberedList() => _setListStyle(TyLogBlockStyle.numberedList);

  void _setListStyle(TyLogBlockStyle style) {
    final sel = selection;
    if (sel.isValid && !sel.isCollapsed) {
      var offset = sel.end;
      _format(() {
        offset = document.setBlockStyleRange(sel.start, sel.end, style);
      }, selectionOffset: () => offset);
      return;
    }
    var offset = sel.isValid ? sel.baseOffset : text.length;
    _format(() {
      offset = document.setBlockStyle(offset, style);
    }, selectionOffset: () => offset);
  }

  /// Replaces the current selection with one task block per entry — the
  /// multiline convert-to-tasks flow. One `_format` call: one undo entry,
  /// one round-trip validation, one `onSourceChanged`.
  void insertTasks(List<({String id, String text})> tasks) {
    if (tasks.isEmpty) return;
    _clearComposition();
    final sel = selection.isValid
        ? selection
        : TextSelection.collapsed(offset: text.length);
    final source = tasks
        .map((task) => taskSnippet(id: task.id, text: task.text))
        .join('\n\n');
    var offset = sel.end;
    _format(() {
      offset = document.insertBlock(sel, source);
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
      case MagicAction.strike:
        toggleStrike();
        return;
      case MagicAction.underline:
        toggleUnderline();
        return;
      case MagicAction.mono:
        toggleMono();
        return;
      case MagicAction.highlight:
        toggleHighlight();
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
        // The formatting actions all returned early above, so only the
        // insert-style actions reach here.
        final label = switch (request.action) {
          MagicAction.attachment =>
            request.value?.split('/').last ?? 'Attachment',
          MagicAction.table => 'Table',
          MagicAction.report => 'Report',
          _ => request.value ?? selected,
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

  /// A character that ends a just-typed email so it can be auto-linked
  /// (whitespace or common trailing punctuation; newline is handled on Enter).
  static bool _isEmailBreak(int c) =>
      c == 32 || c == 9 || c == 44 || c == 59 || c == 41 || c == 93;

  /// If a bare email ends exactly at [endOffset] in the visible text, replace
  /// it in place with a mailto link atom (instant "type an address → chip").
  /// Returns how many characters shorter the visible text became so the caller
  /// can shift the caret; 0 if nothing was converted.
  int _autolinkEmailAt(int endOffset) {
    final text = document.visibleText;
    if (endOffset <= 0 || endOffset > text.length) return 0;
    var start = endOffset;
    while (start > 0 &&
        (_emailLocalChar(text.codeUnitAt(start - 1)) ||
            text.codeUnitAt(start - 1) == 64)) {
      start--;
    }
    final token = text.substring(start, endOffset);
    if (token.contains(_object)) return 0;
    final match = _emailPattern.matchAsPrefix(token);
    if (match == null || match.end != token.length) return 0;
    final hit = document._blockAt(start, preferPrevious: true);
    if (hit == null || document.blocks[hit.index].isProtected) return 0;
    document._replaceWithParts(TextRange(start: start, end: endOffset), [
      TyLogInline.atom(
        source: mailtoLinkSource(token),
        label: token,
        id: 'atom-email-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ]);
    return token.length - 1;
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

  TextSpan readTextSpan(
    BuildContext context, {
    TextStyle? style,
    bool tappable = false,
  }) => _textSpan(
    context,
    style,
    withComposing: false,
    interactive: false,
    tappable: tappable,
  );

  TextSpan _textSpan(
    BuildContext context,
    TextStyle? style, {
    required bool withComposing,
    bool interactive = true,
    bool tappable = false,
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
              onTap: interactive || tappable
                  ? () => onProtectedTap(block.id)
                  : null,
              icon: Icons.code,
            ),
          ),
        );
        global++;
      } else {
        final taskDone =
            block.style == TyLogBlockStyle.taskLine &&
            block.visibleText.startsWith(taskCheckedGlyph);
        for (final part in block.parts) {
          if (part.isAtom) {
            // Read mode never writes back to source, so an unknown wrapper
            // call (e.g. a hand-authored `#step[...]`) can safely be shown
            // as its real inner text instead of a truncated chip. Known
            // reference atoms (links, tags, citations, mentions) stay chips
            // in both modes since they're navigable, not just prose.
            if (!interactive && !_isReferenceAtom(part.source!)) {
              final body = _atomBody(part.source!);
              final nested = _parseInline(body) ?? [TyLogInline.text(body)];
              for (final nestedPart in nested) {
                if (nestedPart.isAtom) {
                  final resolvedKind = _refNoteKind(
                    nestedPart.source!,
                    resolveKind,
                  );
                  children.add(
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _ProtectedChip(
                        label: nestedPart.label!,
                        block: false,
                        onTap: null,
                        unresolved: resolvedKind == 'unresolved',
                        icon: _atomIcon(
                          nestedPart.source!,
                          resolvedKind: resolvedKind,
                        ),
                        textStyle: _styleFor(
                          context,
                          style,
                          block.style,
                          block.headingLevel,
                          nestedPart.style,
                        ),
                      ),
                    ),
                  );
                  global++;
                } else {
                  _addTextSpans(
                    children,
                    nestedPart.text,
                    global,
                    style: _styleFor(
                      context,
                      style,
                      block.style,
                      block.headingLevel,
                      nestedPart.style,
                    ),
                    composing: TextRange.empty,
                  );
                  global += nestedPart.text.length;
                }
              }
              continue;
            }
            final imagePath = _imageAtomPath(part.source!);
            final onTap = interactive || (tappable && imagePath == null)
                ? () => onProtectedTap(part.id!)
                : null;
            final resolvedKind = _refNoteKind(part.source!, resolveKind);
            final chip = _ProtectedChip(
              label: part.label!,
              block: false,
              onTap: onTap,
              unresolved: resolvedKind == 'unresolved',
              icon: _atomIcon(part.source!, resolvedKind: resolvedKind),
              textStyle: _styleFor(
                context,
                style,
                block.style,
                block.headingLevel,
                part.style,
              ),
            );
            final isImage = imagePath != null && imageResolver != null;
            children.add(
              WidgetSpan(
                // A chip sits on the text baseline like a word; an inline
                // image is a block and stays centred on the line.
                alignment: isImage
                    ? PlaceholderAlignment.middle
                    : PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: isImage
                    ? _InlineImage(
                        bytes: imageBytes(imagePath),
                        fallback: chip,
                        onTap: onTap,
                      )
                    : chip,
              ),
            );
            global++;
          } else {
            var partStyle = _styleFor(
              context,
              style,
              block.style,
              block.headingLevel,
              part.style,
            );
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
