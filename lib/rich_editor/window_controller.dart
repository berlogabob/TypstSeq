part of '../rich_editor.dart';

/// Edit through [TyLogWindowController] (P12k). Off until the rich-editor
/// parity suite passes against it; tests flip it to run that suite windowed.
bool debugEnableEditorWindow = false;

/// P12k A/B switch: when false, the editor does not compensate the scroll
/// offset when lines move between the editing window and the static text
/// above it.
bool debugWindowScrollCompensation = true;

/// Long lines are split into display units of about this many characters;
/// the window shows complete units, so a long line need not be laid out whole.
const int kWindowUnitChars = 100;

/// Upper bound on the editing window's text length.
const int kWindowMaxChars = 400;

/// Bounded editing window over a [TyLogEditingController] (P12k).
///
/// The `TextField` edits only the units around the selection; the main
/// controller keeps the whole document and every editing rule. The window is
/// `[start, end)` of the visible text (exclusive end: a line end or `\n`). It
/// spans whole display units rather than whole lines: each line is either its
/// own unit or is cut into ~[kWindowUnitChars]-character units at spaces, so a
/// single long line is laid out in bounded pieces. It therefore works inside
/// one long paragraph as well as across blocks. A user edit is spliced into the
/// main controller's global value, so formatting, Enter/Backspace, paste,
/// composition and undo/redo run on global offsets exactly as before.
/// Text outside the window never changes through the field, so `_before` and
/// `_after` fingerprints ([_fingerprint]) stay valid: `end = main.text.length - _tail`.
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
  // Up to 32 characters on each side of the window, to detect edits made
  // outside it (loadSource, undo) now that boundaries can sit mid-line.
  String _before = '';
  String _after = '';
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
    final t = main.text;
    final e = end;
    if (_start < 0 || e < _start || e > t.length) return false;
    return t.substring((_start - 32).clamp(0, _start), _start) == _before &&
        t.substring(e, (e + 32).clamp(e, t.length)) == _after;
  }

  void _recenter({bool force = false}) {
    final text = main.text;
    final selection = main.selection;
    // No caret yet (a note just opened): show its top, as the plain field did.
    final lo = selection.isValid ? selection.start : 0;
    final hi = selection.isValid ? selection.end : 0;
    // Keep whole units of slack on each side before recentering, so arrow
    // keys and Backspace/Enter at the window edge have room to act.
    final needStart = _prevUnitStart(text, unitStart(text, lo));
    final needEnd = _nextUnitEnd(text, unitEnd(text, hi));
    final inside =
        !force &&
        needStart >= _start &&
        needEnd <= end &&
        // Appends at an edge grow the window unit by unit; cap it so the
        // per-edit layout stays bounded.
        end - _start <= kWindowMaxChars &&
        _lineBreaks(text, _start, end) <= 2 * margin + 8;
    if (inside || (!force && main.value.composing.isValid)) return;
    var s = unitStart(text, lo);
    var e = unitEnd(text, hi);
    // One unit of slack on each side always (else the next edit recenters
    // again), then more units while the window stays under half the cap, so
    // typing has room to grow it before the next recenter.
    // ponytail: a single unit has no size bound (a long line without
    // spaces); split such lines at a hard offset if that shows up.
    for (var i = 0; i < margin; i++) {
      final ps = _prevUnitStart(text, s);
      if (ps < s && (i == 0 || e - ps <= kWindowMaxChars ~/ 2)) s = ps;
      final ne = _nextUnitEnd(text, e);
      if (ne > e && (i == 0 || ne - s <= kWindowMaxChars ~/ 2)) e = ne;
    }
    _start = s;
    _tail = text.length - e;
    _fingerprint();
    windowRevision.value++;
  }

  void _fingerprint() {
    final t = main.text;
    final e = end;
    _before = t.substring((_start - 32).clamp(0, _start), _start);
    _after = t.substring(e, (e + 32).clamp(e, t.length));
  }

  static int _lineBreaks(String text, int from, int to) {
    var count = 0;
    for (var i = from; i < to; i++) {
      if (text.codeUnitAt(i) == 0x0A) count++;
    }
    return count;
  }

  /// Soft breaks inside the line [ls, le): for k = 1, 2, … the position just
  /// after the first space at or after ls + k*kWindowUnitChars, if that space
  /// is before le - 1. Ascending, strictly increasing (skip duplicates).
  static List<int> softBreaks(String text, int ls, int le) {
    final out = <int>[];
    final start = ls.clamp(0, text.length);
    final end = le.clamp(0, text.length);
    for (var k = 1; ; k++) {
      final p = start + k * kWindowUnitChars;
      if (p >= end) break;
      final sp = text.indexOf(' ', p);
      if (sp < 0 || sp >= end - 1) break;
      final breakAt = sp + 1;
      if (out.isEmpty || breakAt > out.last) out.add(breakAt);
    }
    return out;
  }

  static int _lineStart(String text, int offset) =>
      offset <= 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;

  static int _lineEnd(String text, int offset) {
    final i = text.indexOf('\n', offset);
    return i < 0 ? text.length : i;
  }

  /// Start of the unit containing [offset]: the largest soft break <= offset in
  /// its line, else the line start. The offset clamps to [0, text.length]; the
  /// line is found from [offset] itself, so the `\n` at [offset] belongs to the
  /// previous line (its last unit start is its line start).
  static int unitStart(String text, int offset) {
    final off = offset.clamp(0, text.length);
    var at = _lineStart(text, off);
    for (final b in softBreaks(text, at, _lineEnd(text, off))) {
      if (b > off) break;
      at = b;
    }
    return at;
  }

  /// Exclusive end of the unit containing [offset]: the smallest soft break >
  /// offset in its line, else the line end (index of `\n` or text.length).
  static int unitEnd(String text, int offset) {
    final off = offset.clamp(0, text.length);
    final lineEnd = _lineEnd(text, off);
    for (final b in softBreaks(text, _lineStart(text, off), lineEnd)) {
      if (b > off) return b;
    }
    return lineEnd;
  }

  /// Start of the unit before the one starting at [s] (s itself when s == 0).
  static int _prevUnitStart(String text, int s) =>
      s == 0 ? 0 : unitStart(text, s - 1);

  /// End of the unit after the one ending at [e]: e == length -> length;
  /// text[e] == '\n' -> unitEnd(e + 1); else unitEnd(e).
  static int _nextUnitEnd(String text, int e) {
    final end = e.clamp(0, text.length);
    if (end == text.length) return text.length;
    if (text[end] == '\n') return unitEnd(text, end + 1);
    return unitEnd(text, end);
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
