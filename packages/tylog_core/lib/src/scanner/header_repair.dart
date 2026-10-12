part of '../scanner.dart';

String replaceNoteHeader(String source, NoteMetadataDraft draft) {
  final header = serializeNoteHeader(draft);
  final call = _noteHeader(source);
  final String withHeader;
  if (call != null) {
    withHeader = source.replaceRange(call.start, call.end, header);
  } else {
    final importEnd = source.startsWith('#import ')
        ? source.indexOf('\n') + 1
        : 0;
    withHeader = source.replaceRange(importEnd, importEnd, '$header\n\n');
  }
  // `tylog.note.with(...)` is meaningless without the helper import — a legacy
  // note that never had it (e.g. a hand-authored `.typ`) would fail to compile
  // once we add the managed header. Guarantee the import is present.
  if (withHeader.contains('/_system/tylog.typ')) return withHeader;
  return '#import "/_system/tylog.typ" as tylog\n\n$withHeader';
}

/// Prepends the helper import when [text] calls into `tylog.` without it.
///
/// A `#tylog.ref-note(...)` in a file with no `#import "/_system/tylog.typ"` is
/// `unknown variable: tylog` — the note does not compile, its metadata query
/// fails, and every reader silently falls back to source parsing. It is easy to
/// reach without doing anything strange: empty a starter daily (which deletes
/// it), type a plain line, then pick a note from the link autocomplete. The
/// file is recreated from the buffer, so it never had the import, and the
/// insertion has no idea.
///
/// This is the write-side counterpart to a read-side guard that already
/// existed. [managedNoteSource] has guaranteed the import since notes could be
/// converted; the ordinary save path — the one every editor insertion goes
/// through — did not.
String withTylogImport(String path, String text) {
  if (!path.endsWith('.typ')) return text;
  if (!_tylogCall.hasMatch(text)) return text;
  if (text.contains('/_system/tylog.typ')) return text;
  return '#import "/_system/tylog.typ" as tylog\n\n$text';
}

/// A call into the helper: `#tylog.foo(`, or `#show: tylog.note.with(`.
final RegExp _tylogCall = RegExp(r'#(?:show:\s*)?tylog\.[a-z-]');

/// Repairs markdown-import artifacts that break Typst compilation — so a note's
/// metadata query stops failing (`metadata-query-failed` / "formatting couldn't
/// be read"). Conservative and idempotent: only rewrites the exact patterns the
/// vault audit found, never touching well-formed content.
String repairArticleTypst(String source) {
  var out = source;
  // Inline-function field access: a closing `]`/`)` immediately followed by
  // `.<letter>` (e.g. `#emph[confident guessing].Instead`) re-parses as member
  // access on the function. Insert a space after the dot so the period is prose.
  out = out.replaceAllMapped(
    RegExp(r'([\]\)])\.(\p{L}|_)', unicode: true),
    (m) => '${m[1]}. ${m[2]}',
  );
  // A content block `]` abutting `(` or `[` (e.g. `#link("u")[label](2024)`)
  // re-parses as a call/second-content on the function. Space them apart.
  // (Only `]` — never `)`, so legit `#link("u")[label]` call syntax is kept.)
  out = out.replaceAllMapped(RegExp(r'\]([(\[])'), (m) => '] ${m[1]}');
  // Bare `word@domain.tld` in prose parses as a Typst `@label` ref (e.g.
  // `20251186@iade.pt` -> `<iade.pt>` does not exist). Escape the `@` outside
  // quoted strings (mailto: URLs stay intact) and skip already-escaped `\@`.
  out = out.splitMapJoin(
    RegExp(r'"(?:\\.|[^"\\])*"'),
    onMatch: (m) => m[0]!,
    onNonMatch: (text) => text.replaceAllMapped(
      RegExp(r'(\w)@(\w[\w.-]*\.\w+)'),
      (m) => '${m[1]}\\@${m[2]}',
    ),
  );
  // An odd number of ``` fences (a markdown code block the importer never
  // closed) leaves everything after it inside a raw block — "unclosed raw
  // text" plus an expected-expression cascade through the whole article.
  // Close it at the end of the file. Counting line-leading fences only:
  // that is where markdown fences live, and inline backtick runs in prose
  // must not flip the parity.
  if (RegExp(r'^\s*```', multiLine: true).allMatches(out).length.isOdd) {
    out = '${out.trimRight()}\n```\n';
  }
  return out;
}

String serializeNoteHeader(NoteMetadataDraft draft) {
  final fields = <String>[
    '  id: ${typstString(draft.id)},',
    '  title: ${typstString(draft.title)},',
    '  kind: ${typstString(draft.kind)},',
    '  date: ${draft.date == null || draft.date!.isEmpty ? 'none' : typstString(draft.date!)},',
    '  tags: ${_typstList(draft.tags)},',
    '  aliases: ${_typstList(draft.aliases)},',
    '  project: ${draft.project == null || draft.project!.isEmpty ? 'none' : typstString(draft.project!)},',
    '  properties: ${_typstDictionary(draft.properties)},',
  ];
  return '#show: tylog.note.with(\n${fields.join('\n')}\n)';
}

/// Migrates the legacy `properties["type"]` entity classifier into `kind`.
///
/// Historically "entities" (people/places/orgs) were modeled as notes with a
/// generic `kind: "note"` and a `properties["type"]` value carrying the real
/// classification. That's a duplicated classifier — this folds `type` into
/// `kind` (the single classifier going forward) and drops it from
/// `properties`. Only touches notes that are still on the generic `kind:
/// "note"` default with a non-empty `properties["type"]`; already-specific
/// kinds are left untouched so this is safe to run repeatedly (idempotent)

/// Removes the org-mode bookkeeping a Logseq export carries into a note:
/// `:LOGBOOK:` drawers with their `CLOCK:` records and state-change lines, and
/// the empty block every page trails.
///
/// Repairs notes imported before the converter learned to drop these — a
/// re-import cannot, because the wizard skips a source whose SHA is unchanged.
/// Returns [source] unchanged when there is nothing to strip, so it is
/// idempotent and safe to run repeatedly.
///
/// Matches by line shape rather than parsing the drawer, exactly like
/// `strip_logseq_noise` in the Rust converter: a real vault has orphan `:END:`
/// lines and unclosed openers, and a state machine would either leak those or
/// swallow real content past an unclosed opener. Only *trailing* empty bullets
/// go; an empty item between two others is deliberate spacing.
String stripLogseqNoise(String source) {
  final lines = source.split('\n');
  // A trailing newline leaves an empty final element. That is the terminator,
  // not a line — leaving it in blocked the trailing sweep below on every file
  // whose only noise was the empty end block.
  final endsWithNewline = lines.isNotEmpty && lines.last.isEmpty;
  if (endsWithNewline) lines.removeLast();

  // A CLOCK: record is the user's time tracking, not noise — the converter
  // captures it into properties("clocked") now. If any survives in this note
  // the drawer is left completely alone rather than deleted, because deleting
  // it is unrecoverable and this runs from a one-tap Settings action. Only
  // genuinely empty drawers are cleaned.
  final holdsTime = lines.any((line) => line.trim().startsWith('CLOCK:'));

  final kept = <String>[];
  var removed = 0;
  for (final line in lines) {
    final trimmed = line.trim();
    final isDrawer =
        trimmed == ':LOGBOOK:' ||
        trimmed == ':END:' ||
        trimmed.startsWith('- State "');
    if (!holdsTime && isDrawer) {
      removed++;
      continue;
    }
    kept.add(line);
  }

  // Trailing empty blocks, plus any blank lines tangled up with them. Blanks
  // alone never count as noise, so a file that merely ends in whitespace is
  // returned untouched.
  var pending = 0;
  while (kept.isNotEmpty) {
    final trimmed = kept.last.trim();
    if (trimmed == '-' || trimmed == '+' || trimmed == r'\-') {
      kept.removeLast();
      removed += 1 + pending;
      pending = 0;
      continue;
    }
    if (trimmed.isEmpty) {
      kept.removeLast();
      pending++;
      continue;
    }
    break;
  }
  // Put back any blanks that turned out not to precede an empty block.
  for (var i = 0; i < pending; i++) {
    kept.add('');
  }

  if (removed == 0) return source;
  return endsWithNewline ? '${kept.join('\n')}\n' : kept.join('\n');
}

/// and never clobbers a deliberately-set kind.
String migrateEntityTypeToKind(String source) {
  final call = _noteHeader(source);
  if (call == null) return source;
  final header = call.source;
  final kind = _field(header, 'kind') ?? 'note';
  final properties = _parseProperties(header);
  final type = properties['type'];
  if (kind != 'note' || type is! String || type.isEmpty) {
    return source;
  }
  final newProperties = Map<String, Object?>.from(properties)..remove('type');
  final draft = NoteMetadataDraft(
    id: _field(header, 'id') ?? '',
    title: _field(header, 'title') ?? '',
    kind: type,
    project: _field(header, 'project'),
    date: _field(header, 'date'),
    tags: _parseList(header, 'tags'),
    aliases: _parseList(header, 'aliases'),
    properties: newProperties,
  );
  return replaceNoteHeader(source, draft);
}

/// The `[start, end)` byte range of a `"key": value` entry inside a
/// dictionary's source text (parens included), trimmed of any leading
/// whitespace/newline so callers can replace it without disturbing
/// formatting around it.
class _DictEntry {
  const _DictEntry(this.start, this.end, this.valueStart);

  /// Bounds of the whole `"key": value` entry.
  final int start;
  final int end;

  /// Where the value begins, for readers that want it without the key.
  final int valueStart;
}

/// Locates the top-level `"key": value` entry for [key] inside [dictSource]
/// (a full `(...)` dictionary literal). TyLog writes quoted keys (see
/// [_typstDictionary]), but hand-edited Typst commonly uses bare identifier
/// keys (`status: "read"`), so both spellings match — otherwise a write
/// would append a duplicate key. Reuses [_splitTopLevel], the same
/// nesting-aware comma splitter [_parseProperties] already relies on to read
/// this shape, so strings/comments/nested `(...)`/`[...]` can't be mistaken
/// for a top-level boundary. Returns null if [key] isn't present.
_DictEntry? _locateDictEntry(String dictSource, String key) {
  if (!dictSource.startsWith('(') || !dictSource.endsWith(')')) return null;
  final inner = dictSource.substring(1, dictSource.length - 1);
  final quotedPattern = RegExp(r'^(\s*)"((?:\\.|[^"\\])*)"\s*:', dotAll: true);
  final barePattern = RegExp(r'^(\s*)([A-Za-z_][A-Za-z0-9_-]*)\s*:');
  var offset = 1;
  for (final part in _splitTopLevel(inner)) {
    final quoted = quotedPattern.firstMatch(part);
    final match = quoted ?? barePattern.firstMatch(part);
    if (match != null) {
      final rawKey = match.group(2)!;
      final decodedKey = quoted != null
          ? rawKey.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!)
          : rawKey;
      if (decodedKey == key) {
        final leading = match.group(1)!.length;
        var valueStart = match.end;
        while (valueStart < part.length &&
            _space(part.codeUnitAt(valueStart))) {
          valueStart++;
        }
        return _DictEntry(
          offset + leading,
          offset + part.length,
          offset + valueStart,
        );
      }
    }
    offset += part.length + 1;
  }
  return null;
}

/// Surgically sets `properties[key] = value` inside a note header's
/// `properties: (...)` dictionary, leaving the rest of the header
/// (including comments/formatting on unrelated fields) untouched — unlike
/// [replaceNoteHeader], which regenerates the whole call.
String replaceNoteProperty(String source, String key, Object? value) {
  final call = _noteHeader(source);
  if (call == null) {
    throw StateError('No tylog.note header found');
  }
  final header = call.source;
  final encodedValue = _typstValue(value);
  final propsField = _locateTopLevelField(header, 'properties');
  if (propsField == null) {
    // Must go through the same separator-aware append as every other writer:
    // a blind splice before `)` drops the comma on a single-line header
    // (`kind: "note"  properties: (…)`), which is exactly the defect that made
    // 406 task calls unparseable. `_noteSource` only ever writes multi-line
    // headers today, so this is the latent half of that bug, not a live one.
    final newHeader = _appendCallField(
      header,
      'properties',
      '(${typstString(key)}: $encodedValue,)',
      allowed: writableNoteFields,
    );
    return source.replaceRange(call.start, call.end, newHeader);
  }
  final dictSource = header.substring(
    propsField.valueStart,
    propsField.valueEnd,
  );
  final entry = _locateDictEntry(dictSource, key);
  final String newDict;
  if (entry != null) {
    newDict = dictSource.replaceRange(
      entry.start,
      entry.end,
      '${typstString(key)}: $encodedValue',
    );
  } else {
    newDict = _appendDictEntry(dictSource, key, encodedValue);
  }
  final newHeader = header.replaceRange(
    propsField.valueStart,
    propsField.valueEnd,
    newDict,
  );
  return source.replaceRange(call.start, call.end, newHeader);
}

/// Parses the `properties: (...)` dictionary out of a `tylog.note.with(...)`
/// header's source text. Keys are always quoted strings (see
/// [_typstDictionary]); values are decoded when they're strings, numbers,
/// booleans, or `none`, and otherwise kept as their raw Typst source text.
Map<String, Object?> _parseProperties(String callSource) {
  final field = _locateTopLevelField(callSource, 'properties');
  if (field == null) return const {};
  final value = callSource.substring(field.valueStart, field.valueEnd).trim();
  if (!value.startsWith('(') || !value.endsWith(')')) return const {};
  final inner = value.substring(1, value.length - 1).trim();
  if (inner.isEmpty || inner == ':') return const {};
  // Typst allows a bare identifier as a dictionary key, and hand-written and
  // imported headers use it: `properties: (type: "person",)`. Reading only
  // quoted keys made those properties invisible — which silently disabled
  // `migrateEntityTypeToKind` on exactly the notes it exists to fix, and let
  // `replaceNoteHeader` drop the key on the next write. `_locateDictEntry`
  // already accepts both forms; this is the reader catching up.
  final entryKeyValue = RegExp(
    r'^\s*(?:"((?:\\.|[^"\\])*)"|([A-Za-z_][A-Za-z0-9_\-]*))\s*:\s*(.*)$',
    dotAll: true,
  );
  final result = <String, Object?>{};
  for (final entry in _splitTopLevel(inner)) {
    if (entry.trim().isEmpty) continue;
    final match = entryKeyValue.firstMatch(entry);
    if (match == null) continue;
    final key = (match.group(1) ?? match.group(2)!).replaceAllMapped(
      RegExp(r'\\(.)'),
      (m) => m.group(1)!,
    );
    result[key] = _parsePropertyValue(match.group(3)!.trim());
  }
  return result;
}

/// Splits a Typst argument/dictionary body on top-level commas, skipping
/// commas nested inside strings, raw blocks, comments, or `(...)`/`[...]`.
List<String> _splitTopLevel(String source) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final nl = source.indexOf('\n', i);
      i = nl < 0 ? source.length : nl;
      continue;
    }
    if (source.startsWith('/*', i)) {
      i = _skipBlockComment(source, i);
      continue;
    }
    final code = source.codeUnitAt(i);
    if (code == 34) {
      i = _skipString(source, i);
      continue;
    }
    if (code == 96) {
      i = _skipRaw(source, i);
      continue;
    }
    if (code == 40 || code == 91) {
      depth++;
      i++;
      continue;
    }
    if (code == 41 || code == 93) {
      depth--;
      i++;
      continue;
    }
    if (code == 44 && depth == 0) {
      parts.add(source.substring(start, i));
      i++;
      start = i;
      continue;
    }
    i++;
  }
  if (start < source.length) parts.add(source.substring(start));
  return parts;
}

Object? _parsePropertyValue(String raw) {
  final trimmed = raw.trim();
  if (trimmed == 'none') return null;
  if (trimmed == 'true') return true;
  if (trimmed == 'false') return false;
  final quoted = RegExp(r'^"((?:\\.|[^"\\])*)"$').firstMatch(trimmed);
  if (quoted != null) {
    return quoted
        .group(1)!
        .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
  }
  final number = num.tryParse(trimmed);
  if (number != null) return number;
  return trimmed;
}

