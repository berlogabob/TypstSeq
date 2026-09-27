part of '../rich_editor.dart';

/// Edit through [TyLogWindowController] (P12k). Off until the rich-editor
/// parity suite passes against it; tests flip it to run that suite windowed.
bool debugEnableEditorWindow = false;

/// Bounded editing window over a [TyLogEditingController] (P12k).
///
/// The `TextField` edits only the lines around the selection; the main
/// controller keeps the whole document and every editing rule. The window is
/// `[start, end)` of the visible text, where `start` is a line start and
/// `end` a line end, so it works inside one long paragraph as well as across
/// blocks. A user edit is spliced into the main controller's global value,
/// so formatting, Enter/Backspace, paste, composition and undo/redo run on
/// global offsets exactly as before. Text outside the window never changes
/// through the field, which keeps both boundaries valid:
/// `end = main.text.length - _tail`.
class TyLogWindowController extends TextEditingController {
  TyLogWindowController(this.main, {this.margin = 6}) {
    _recenter(force: true);
    _pushWindowValue();
    main.addListener(_mainChanged);
  }

  final TyLogEditingController main;

  /// Lines kept on each side of the selection when the window recenters.
  final int margin;

  int _start = 0;
  int _tail = 0;
  bool _pushing = false;

  /// Global offset of the window's first character (a line start).
  int get start => _start;

  /// Global offset just past the window (a line end: `\n` or text end).
  int get end => main.text.length - _tail;

  /// Bumped when the window moves, so the static regions rebuild.
  final ValueNotifier<int> windowRevision = ValueNotifier(0);

  @override
  set value(TextEditingValue next) {
    if (_pushing) {
      super.value = next;
      return;
    }
    // A user edit inside the window: splice it into the global text.
    final text = main.text.replaceRange(_start, end, next.text);
    _pushing = true;
    try {
      main.value = TextEditingValue(
        text: text,
        selection: _shift(next.selection, _start),
        composing: _shiftRange(next.composing, _start),
      );
    } finally {
      _pushing = false;
    }
    _mainChanged();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => main.rangeSpan(
    context,
    style,
    start: _start,
    end: end,
    withComposing: withComposing,
  );

  /// Moves the caret to global [offset]; the window follows it.
  void placeCaret(int offset) {
    main.selection = TextSelection.collapsed(offset: offset);
  }

  void _mainChanged() {
    if (_pushing) return;
    if (!_boundariesValid()) {
      // An external change (loadSource, undo outside the window) moved text
      // outside the window: start over around the selection.
      _recenter(force: true);
    } else {
      _recenter();
    }
    _pushWindowValue();
  }

  bool _boundariesValid() {
    final text = main.text;
    final windowEnd = end;
    return _start >= 0 &&
        windowEnd >= _start &&
        windowEnd <= text.length &&
        (_start == 0 || text.codeUnitAt(_start - 1) == 0x0A) &&
        (windowEnd == text.length || text.codeUnitAt(windowEnd) == 0x0A);
  }

  void _recenter({bool force = false}) {
    final text = main.text;
    final selection = main.selection;
    final lo = selection.isValid ? selection.start : text.length;
    final hi = selection.isValid ? selection.end : text.length;
    // Keep one full line of slack on each side before recentering, so arrow
    // keys and Backspace/Enter at the window edge have room to act.
    final needStart = _linesBack(text, lo, 1);
    final needEnd = _linesForward(text, hi, 1);
    final inside =
        !force &&
        needStart >= _start &&
        needEnd <= end &&
        // Appends at an edge grow the window line by line; cap it so the
        // per-edit layout stays bounded.
        _lineBreaks(text, _start, end) <= 2 * margin + 8;
    if (inside || (!force && main.value.composing.isValid)) return;
    _start = _linesBack(text, lo, margin);
    _tail = text.length - _linesForward(text, hi, margin);
    windowRevision.value++;
  }

  static int _lineBreaks(String text, int from, int to) {
    var count = 0;
    for (var i = from; i < to; i++) {
      if (text.codeUnitAt(i) == 0x0A) count++;
    }
    return count;
  }

  /// Start of the line [lines] lines above the one containing [offset].
  static int _linesBack(String text, int offset, int lines) {
    var at = offset.clamp(0, text.length);
    for (var n = 0; n <= lines; n++) {
      final previous = at == 0 ? -1 : text.lastIndexOf('\n', at - 1);
      if (previous < 0) return 0;
      if (n == lines) return previous + 1;
      at = previous;
    }
    return 0;
  }

  /// End of the line [lines] lines below the one containing [offset].
  static int _linesForward(String text, int offset, int lines) {
    var at = offset.clamp(0, text.length);
    for (var n = 0; n <= lines; n++) {
      final next = text.indexOf('\n', at);
      if (next < 0) return text.length;
      if (n == lines) return next;
      at = next + 1;
    }
    return text.length;
  }

  void _pushWindowValue() {
    final global = main.value;
    final windowEnd = end;
    final length = windowEnd - _start;
    int local(int offset) => (offset - _start).clamp(0, length);
    final selection = global.selection;
    final composing = global.composing;
    _pushing = true;
    try {
      super.value = TextEditingValue(
        text: global.text.substring(_start, windowEnd),
        // Clamped as ints first: a caret outside the window (only while a
        // composition blocks recentering) must not build a negative range.
        selection: selection.isValid
            ? selection.copyWith(
                baseOffset: local(selection.baseOffset),
                extentOffset: local(selection.extentOffset),
              )
            : selection,
        composing:
            composing.isValid &&
                composing.start >= _start &&
                composing.end <= windowEnd
            ? TextRange(
                start: composing.start - _start,
                end: composing.end - _start,
              )
            : TextRange.empty,
      );
    } finally {
      _pushing = false;
    }
  }

  static TextSelection _shift(TextSelection selection, int by) =>
      selection.isValid
      ? selection.copyWith(
          baseOffset: selection.baseOffset + by,
          extentOffset: selection.extentOffset + by,
        )
      : selection;

  static TextRange _shiftRange(TextRange range, int by) => range.isValid
      ? TextRange(start: range.start + by, end: range.end + by)
      : range;

  @override
  void dispose() {
    main.removeListener(_mainChanged);
    windowRevision.dispose();
    super.dispose();
  }
}
