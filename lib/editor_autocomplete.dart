/// Pure trigger-detection logic for the rich editor's inline "@"/"/"/"[["
/// autocomplete. Kept Flutter-widget-free so it can be unit tested without
/// pumping a widget tree.
library;

enum AutocompleteTriggerKind { mention, command, wikiLink }

/// What a wiki-link/mention candidate resolves to, so selection can emit the
/// right Typst — `#tylog.ref-note(...)` for a note, `#tylog.tag(...)` for a tag.
enum MentionKind { note, concept }

class AutocompleteTrigger {
  const AutocompleteTrigger({
    required this.kind,
    required this.query,
    required this.start,
  });

  /// Which popup this trigger should open.
  final AutocompleteTriggerKind kind;

  /// The text typed after the trigger character (e.g. "Fer" for "@Fer").
  final String query;

  /// Index of the trigger character (`@` or `/`) itself within the source
  /// text — the range `[start, caret)` is what gets replaced on selection.
  final int start;

  @override
  bool operator ==(Object other) =>
      other is AutocompleteTrigger &&
      kind == other.kind &&
      query == other.query &&
      start == other.start;

  @override
  int get hashCode => Object.hash(kind, query, start);

  @override
  String toString() =>
      'AutocompleteTrigger(kind: $kind, query: $query, start: $start)';
}

/// A minimal, Flutter-independent description of a mention candidate —
/// the rich editor only needs an id and a display title to build the
/// `#tylog.ref-note(...)` snippet via [applyMagicEdit].
class MentionSuggestion {
  const MentionSuggestion({
    required this.id,
    required this.title,
    this.kind = MentionKind.note,
  });

  /// For a note, its note id; for a concept, the tag key (what goes inside
  /// `#tylog.tag(...)`).
  final String id;
  final String title;
  final MentionKind kind;

  @override
  bool operator ==(Object other) =>
      other is MentionSuggestion &&
      id == other.id &&
      title == other.title &&
      kind == other.kind;

  @override
  int get hashCode => Object.hash(id, title, kind);
}

/// Scans backward from [caret] in [text] to see whether the caret is
/// currently positioned right after a `@word` or `/word` trigger, e.g.
/// typing "@Fer" (mention) or "/table" (command).
///
/// Returns null when there is no active trigger:
/// - the trigger character must be at the very start of [text] or preceded
///   by whitespace/newline (so "a@b" or "x/y" never trigger);
/// - any whitespace between the trigger character and the caret cancels
///   the trigger;
/// - the caret must sit at the end of the query word — if there are more
///   word characters immediately after the caret, the trigger is cancelled.
AutocompleteTrigger? detectTrigger(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  final wiki = _detectWikiLink(text, caret);
  if (wiki != null) return wiki;
  if (caret < text.length && _isWordChar(text.codeUnitAt(caret))) {
    // Caret sits inside a word, not at its end.
    return null;
  }
  var index = caret - 1;
  while (index >= 0 && _isWordChar(text.codeUnitAt(index))) {
    index--;
  }
  if (index < 0) return null;
  final triggerChar = text[index];
  if (triggerChar != '@' && triggerChar != '/') return null;
  final precedingIndex = index - 1;
  final precededByBoundary =
      precedingIndex < 0 || _isWhitespace(text.codeUnitAt(precedingIndex));
  if (!precededByBoundary) return null;
  return AutocompleteTrigger(
    kind: triggerChar == '@'
        ? AutocompleteTriggerKind.mention
        : AutocompleteTriggerKind.command,
    query: text.substring(index + 1, caret),
    start: index,
  );
}

/// Detects an open `[[` wiki-link the caret sits inside, e.g. `[[Home Ass`.
/// Unlike `@`/`/`, the query may contain spaces and Unicode (`[[игровые движки`),
/// so it is delimited structurally, not by a word-char class.
///
/// Returns null unless, scanning back from [caret] on the current line, an
/// unclosed `[[` is found first: a newline, a `]` (the link is closing/closed),
/// or a stray `[` inside the query cancels it. The replaced range is
/// `[start, caret)` where start is the `[[`.
AutocompleteTrigger? _detectWikiLink(String text, int caret) {
  for (var i = caret - 1; i >= 1; i--) {
    final code = text.codeUnitAt(i);
    if (code == 0x0a || code == 0x0d || code == 0x5d) return null; // \n \r ]
    if (code == 0x5b && text.codeUnitAt(i - 1) == 0x5b) {
      final query = text.substring(i + 1, caret);
      if (query.contains('[')) return null;
      return AutocompleteTrigger(
        kind: AutocompleteTriggerKind.wikiLink,
        query: query,
        start: i - 1,
      );
    }
  }
  return null;
}

bool _isWordChar(int code) =>
    (code >= 0x30 && code <= 0x39) || // 0-9
    (code >= 0x41 && code <= 0x5a) || // A-Z
    (code >= 0x61 && code <= 0x7a) || // a-z
    code == 0x5f || // _
    code == 0x2d; // -

bool _isWhitespace(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
