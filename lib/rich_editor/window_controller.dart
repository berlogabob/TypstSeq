part of '../rich_editor.dart';

/// Bounded editing window over a [TyLogEditingController] (P12k).
///
/// The `TextField` edits only blocks [first]..[last]; the main controller
/// keeps the whole document and every editing rule. A user edit is spliced
/// into the main controller's global value, so formatting, cross-block
/// Enter/Backspace inside the window, paste, composition and undo/redo run on
/// global offsets exactly as before. Text outside the window never changes
/// through the field, which keeps the window boundaries stable:
/// `end = main.text.length - _tail`.
class TyLogWindowController extends TextEditingController {
  TyLogWindowController(this.main, {this.margin = 4}) {
    _recenter(force: true);
    _pushWindowValue();
    main.addListener(_mainChanged);
  }

  final TyLogEditingController main;

  /// Blocks kept on each side of the selection when the window recenters.
  final int margin;

  int first = 0;
  int last = 0;
  int _start = 0;
  int _tail = 0;
  bool _pushing = false;

  /// Global offset of the window's first character.
  int get start => _start;
  int get end => main.text.length - _tail;

  /// Fired when [first]/[last] change so the static regions rebuild.
  final ValueNotifier<int> windowRevision = ValueNotifier(0);

  @override
  set value(TextEditingValue next) {
    if (_pushing) {
      super.value = next;
      return;
    }
    // A user edit inside the window: splice it into the global text.
    final global = main.value;
    final text = global.text.replaceRange(_start, end, next.text);
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
  }) {
    final span = main.windowTextSpan(
      context,
      style,
      first: first,
      last: last,
      withComposing: withComposing,
    );
    return span;
  }

  /// Moves the caret to global [offset], recentering the window around it.
  void placeCaret(int offset) {
    main.selection = TextSelection.collapsed(offset: offset);
  }

  /// Makes the whole document editable (select-all, document-wide ops).
  void expandToDocument() {
    final count = main.document.blocks.length;
    if (first == 0 && last == count - 1) return;
    _setWindow(0, count - 1);
    _mainChanged();
  }

  void _mainChanged() {
    if (_pushing) return;
    final ranges = main.document.blockRanges;
    if (ranges.isEmpty) return;
    // Structural edits (Enter/Backspace/paste) change the block count; the
    // text outside the window is unchanged, so re-derive the window blocks
    // from the stable boundaries before deciding whether to recenter.
    _rederiveBlocks(ranges);
    _recenter();
    _pushWindowValue();
  }

  void _rederiveBlocks(List<({int start, int end})> ranges) {
    final windowEnd = end;
    final firstIndex = ranges.indexWhere((r) => r.start >= _start);
    var lastIndex = ranges.lastIndexWhere((r) => r.end <= windowEnd);
    if (firstIndex < 0 ||
        lastIndex < firstIndex ||
        ranges[firstIndex].start != _start ||
        ranges[lastIndex].end != windowEnd) {
      // Boundaries no longer align (e.g. an external loadSource): start over.
      _recenter(force: true);
      return;
    }
    if (firstIndex != first || lastIndex != last) {
      first = firstIndex;
      last = lastIndex;
      windowRevision.value++;
    }
  }

  void _recenter({bool force = false}) {
    final blocks = main.document.blocks.length;
    if (blocks == 0) return;
    final ranges = main.document.blockRanges;
    final selection = main.selection;
    final lo = selection.isValid ? selection.start : main.text.length;
    final hi = selection.isValid ? selection.end : main.text.length;
    final loBlock = _blockAt(ranges, lo);
    final hiBlock = _blockAt(ranges, hi);
    final composing = main.value.composing.isValid;
    final wantFirst = math.max(0, loBlock - 1);
    final wantLast = math.min(blocks - 1, hiBlock + 1);
    final inside = !force && wantFirst >= first && wantLast <= last;
    if (inside || (!force && composing)) return;
    _setWindow(
      math.max(0, loBlock - margin),
      math.min(blocks - 1, hiBlock + margin),
    );
  }

  void _setWindow(int firstBlock, int lastBlock) {
    final ranges = main.document.blockRanges;
    first = firstBlock;
    last = lastBlock;
    _start = ranges[first].start;
    _tail = main.text.length - ranges[last].end;
    windowRevision.value++;
  }

  static int _blockAt(List<({int start, int end})> ranges, int offset) {
    for (var i = 0; i < ranges.length; i++) {
      // A caret in the gap after block i belongs to block i.
      final next = i + 1 < ranges.length ? ranges[i + 1].start : 1 << 62;
      if (offset < next) return i;
    }
    return ranges.length - 1;
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
