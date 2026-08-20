/// Pure trigger-detection logic for the rich editor's inline "@"/"/"/"[["
/// autocomplete. Kept Flutter-widget-free so it can be unit tested without
/// pumping a widget tree.
library;

import 'package:tylog_core/models.dart';

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
    this.noteKind,
    this.subtitle,
    this.create = false,
  });

  /// For a note, its note id; for a concept, the tag key (what goes inside
  /// `#tylog.tag(...)`).
  final String id;
  final String title;

  /// What selecting this row *emits* — a note reference or a tag. Not the
  /// note's own kind; see [noteKind].
  final MentionKind kind;

  /// The referenced note's `kind` (`project`, `person`, `article`, …), for the
  /// row icon. Null for concepts and for the create row.
  final String? noteKind;

  /// One line under the title telling two same-titled notes apart — an
  /// article's source host, else its path. Falls back to [id] when null,
  /// which is all a concept has.
  final String? subtitle;

  /// This row creates the page instead of linking an existing one, the way
  /// Logseq materialises `[[X]]` on the spot.
  final bool create;

  @override
  bool operator ==(Object other) =>
      other is MentionSuggestion &&
      id == other.id &&
      title == other.title &&
      kind == other.kind &&
      noteKind == other.noteKind &&
      subtitle == other.subtitle &&
      create == other.create;

  @override
  int get hashCode =>
      Object.hash(id, title, kind, noteKind, subtitle, create);
}

/// How strongly a note answers a mention query. Tiers are lifted from
/// `PkmsSearchIndex.searchPrefix`, which was written for this feature but was
/// never wired up; matching them keeps `@` and the Search screen consistent.
///
/// Sorting by title alone put two scraped articles above the page the user
/// meant. A tier always outranks a kind bonus — an exactly-titled article
/// still beats a merely prefix-matching project — but among equally good
/// matches an entity outranks a note, and a note outranks an imported article.
///
/// [recencyByPath] maps a note path to its position in the recently-opened
/// list (0 = most recent); build it once per query, not per candidate.
int mentionScore(NoteRef note, String query, Map<String, int> recencyByPath) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 0;
  final title = note.title.toLowerCase();
  final tier = title == q
      ? 1000
      : title.startsWith(q)
      ? 500
      : note.aliases.any((alias) => alias.toLowerCase().startsWith(q))
      ? 300
      : note.id.toLowerCase().startsWith(q)
      ? 200
      // Substring last: "assistant" must reach "Home Assistant", but any
      // prefix match still outranks it.
      : title.contains(q)
      ? 100
      : note.aliases.any((alias) => alias.toLowerCase().contains(q))
      ? 80
      : 0;
  if (tier == 0) return 0;
  final kindBonus = switch (note.kind) {
    'person' || 'place' || 'organization' || 'event' || 'website' => 120,
    'project' => 120,
    'article' => 0,
    _ => 60,
  };
  final position = recencyByPath[note.path];
  final recencyBonus = position == null ? 0 : 50 - position;
  return tier + kindBonus + (recencyBonus < 0 ? 0 : recencyBonus);
}

/// The line under a mention row. A raw note id (`md-3b7a2305beedce32`) tells
/// the user nothing, and two scraped copies of the same page are otherwise
/// indistinguishable — so prefer the article's source host, then its path.
String mentionSubtitle(NoteRef note) {
  final url = note.properties['url'];
  if (url is String) {
    final host = Uri.tryParse(url)?.host;
    if (host != null && host.isNotEmpty) return '${note.kind} · $host';
  }
  return '${note.kind} · ${note.path}';
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

/// Any Unicode letter or digit, plus `_`/`-`. The old ASCII-only class made
/// `@Илья` undetectable while `[[Илья` worked — two triggers for the same
/// job with different alphabets.
bool _isWordChar(int code) {
  if (code == 0x5f || code == 0x2d) return true; // _ -
  return _wordChar.hasMatch(String.fromCharCode(code));
}

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isWhitespace(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
