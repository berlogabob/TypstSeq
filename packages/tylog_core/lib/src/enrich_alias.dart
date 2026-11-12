import 'enrich.dart';
import 'models.dart';

/// Deterministic scan of a note's body for equipment titles and aliases.
///
/// The LLM drops distinguishing words ("the yellow Quest 3" -> "Quest 3"), so
/// resolution never depends on what it returned: every body line is searched
/// for every equipment title or alias, folded like [enrichEquipmentKey] (case,
/// diacritics, brackets, hyphens, "num/no./#") at whole-word boundaries,
/// longest match first. A note's `color` property also yields the aliases
/// `color item`, `item color` and `color <last word of an alias>`
/// without the note listing them, in English, Portuguese and Russian.
class EnrichAliasHit {
  const EnrichAliasHit(this.line, this.surface, this.ids);

  final int line;

  /// The text as written in the line.
  final String surface;

  /// One id: a unique alias. Several: a generic name ("Quest 3", "headset")
  /// that no longer alias disambiguates; the user chooses.
  final List<String> ids;
}

const _colourForms = <String, List<String>>{
  'yellow': ['yellow', 'amarelo', 'amarela', 'amarelos', 'amarelas'],
  'blue': ['blue', 'azul', 'azuis'],
  'red': ['red', 'vermelho', 'vermelha', 'vermelhos', 'vermelhas'],
  'green': ['green', 'verde', 'verdes'],
  'black': ['black', 'preto', 'preta', 'pretos', 'pretas'],
  'white': ['white', 'branco', 'branca', 'brancos', 'brancas'],
};

const _russianStems = <String, String>{
  'yellow': 'жёлт',
  'blue': 'син',
  'red': 'красн',
  'green': 'зелён',
  'black': 'чёрн',
  'white': 'бел',
};

// Adjective endings, so "синюю", "жёлтого", "белой" count but "синхрон" not.
const _russianEndings = [
  '', 'ый', 'ий', 'ой', 'ая', 'яя', 'ое', 'ее', 'ые', 'ие', 'ого', 'его',
  'ому', 'ему', 'ым', 'им', 'ом', 'ем', 'ую', 'юю', 'ей', 'ых', 'их', 'ыми',
  'ими', //
];

/// colour class -> folded forms.
final Map<String, Set<String>> _colours = {
  for (final e in _colourForms.entries)
    e.key: {
      for (final form in e.value) enrichKey(form),
      for (final end in _russianEndings)
        enrichKey('${_russianStems[e.key]}$end'),
    },
};

String? _colourClass(String word) {
  final key = enrichKey(word);
  for (final e in _colours.entries) {
    if (e.value.contains(key)) return e.key;
  }
  return null;
}

class _Tok {
  _Tok(this.key, this.start, this.end);
  final String key;
  final int start;
  final int end;
}

List<_Tok> _tokens(String text) => [
  for (final m in RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(text))
    // "no", "num", "nº" fold to nothing: they are unit-number markers.
    if (enrichEquipmentKey(m[0]!) case final key when key.isNotEmpty)
      _Tok(key, m.start, m.end),
];

/// One element of a pattern: an exact folded word, a colour class, or a word
/// matched by stem (Russian case endings).
class _Elem {
  const _Elem.word(this.value) : kind = 0;
  const _Elem.colour(this.value) : kind = 1;
  const _Elem.stem(this.value) : kind = 2;
  final int kind;
  final String value;

  String get sig => '$kind:$value';

  bool matches(String key) => switch (kind) {
    0 => key == value,
    1 => _colours[value]!.contains(key),
    _ => key == value || _sameStemKey(key, value),
  };
}

bool _sameStemKey(String a, String b) {
  if (a.length < 4 || b.length < 4) return false;
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  return i >= 3 && a.length - i <= 2 && b.length - i <= 2;
}

/// A scan index over the equipment notes of [entities]; build once per memory.
class EnrichAliasIndex {
  EnrichAliasIndex._(this._patterns);

  /// pattern signature -> (elements, equipment ids).
  final Map<String, (List<_Elem>, Set<String>, bool)> _patterns;

  factory EnrichAliasIndex.build(Iterable<NoteRef> entities) {
    final patterns = <String, (List<_Elem>, Set<String>, bool)>{};
    // A pattern is specific when some title/alias/colour alias spells it;
    // generic ones (item names) only matter when they are shared.
    void add(List<_Elem> elems, String id, {bool specific = true}) {
      if (elems.isEmpty || elems.fold(0, (n, e) => n + e.value.length) < 3) {
        return;
      }
      final sig = elems.map((e) => e.sig).join(' ');
      final old = patterns[sig];
      patterns[sig] = (
        elems,
        {...?old?.$2, id},
        specific || (old?.$3 ?? false),
      );
    }

    List<_Elem> words(Iterable<_Tok> toks) => [
      for (final t in toks) _Elem.word(t.key),
    ];
    for (final note in entities.where((e) => e.kind == 'equipment')) {
      final names = [note.title, note.id, ...note.aliases];
      for (final name in names) {
        add(words(_tokens(name)), note.id);
      }
      // Generic names: an alias minus its unit number ("VR headset 1" ->
      // "VR headset", "headset"), shared by every unit of the same item.
      final bases = <List<_Tok>>[];
      final item = note.properties['item'];
      if (item is String) bases.add(_tokens(item));
      for (final name in note.aliases) {
        final toks = _tokens(name);
        if (toks.any((t) => _colourClass(t.key) != null)) continue;
        if (toks.length > 1 && RegExp(r'^\d+$').hasMatch(toks.last.key)) {
          toks.removeLast();
        }
        if (toks.isNotEmpty) bases.add(toks);
      }
      for (final base in bases) {
        if (base.isEmpty) continue;
        add(words(base), note.id, specific: false);
        if (base.last.key.length >= 4 &&
            !RegExp(r'^\d+$').hasMatch(base.last.key)) {
          add([_Elem.stem(base.last.key)], note.id, specific: false);
        }
      }
      final colour = note.properties['color'];
      final cls = colour is String ? _colourClass(colour) : null;
      if (cls == null) continue;
      final c = _Elem.colour(cls);
      for (final base in bases) {
        if (base.isEmpty) continue;
        add([c, ...words(base)], note.id);
        add([...words(base), c], note.id);
        if (base.last.key.length >= 4) {
          add([c, _Elem.stem(base.last.key)], note.id);
        }
      }
    }
    return EnrichAliasIndex._(patterns);
  }

  /// Hits per body line of [source], skipping Typst code lines.
  List<EnrichAliasHit> scan(String source) {
    if (_patterns.isEmpty) return const [];
    final lines = source.split('\n');
    final code = enrichCodeLines(source);
    final hits = <EnrichAliasHit>[];
    for (var i = 0; i < lines.length; i++) {
      if (code.contains(i + 1)) continue;
      // Blank out `#tylog.x(...)` heads, keeping their `[text]`, so ids inside
      // an existing link are not found again.
      final line = lines[i].replaceAllMapped(
        RegExp(r'#tylog\.[\w-]+\((?:\\.|[^)])*\)'),
        (m) => ' ' * m[0]!.length,
      );
      final toks = _tokens(line);
      final found = <(int, int, Set<String>)>[];
      for (final (elems, ids, specific) in _patterns.values) {
        if (!specific && ids.length < 2) continue;
        for (var s = 0; s + elems.length <= toks.length; s++) {
          var ok = true;
          for (var k = 0; k < elems.length && ok; k++) {
            ok = elems[k].matches(toks[s + k].key);
          }
          if (ok) found.add((s, s + elems.length, ids));
        }
      }
      // Longest first (words, then characters), no overlaps.
      int chars((int, int, Set<String>) h) =>
          toks[h.$2 - 1].end - toks[h.$1].start;
      found.sort((a, b) {
        final byWords = (b.$2 - b.$1).compareTo(a.$2 - a.$1);
        return byWords != 0 ? byWords : chars(b).compareTo(chars(a));
      });
      final taken = <int>{};
      final chosen = <(int, int, Set<String>)>[];
      for (final h in found) {
        final span = [for (var k = h.$1; k < h.$2; k++) k];
        if (span.any(taken.contains)) continue;
        taken.addAll(span);
        chosen.add(h);
      }
      chosen.sort((a, b) => a.$1.compareTo(b.$1));
      for (final h in chosen) {
        var end = toks[h.$2 - 1].end;
        final start = toks[h.$1].start;
        if (end < line.length &&
            line[end] == ']' &&
            line.substring(start, end).contains('[')) {
          end++;
        }
        hits.add(
          EnrichAliasHit(i + 1, lines[i].substring(start, end), [...h.$3]),
        );
      }
    }
    return hits;
  }
}

final _studentWord = RegExp(
  r'(?<![\p{L}\p{N}])(?:students?|студент\p{L}*|alun[oa]s?|estudantes?)(?![\p{L}\p{N}])',
  unicode: true,
  caseSensitive: false,
);

/// [mentions] with the alias [hits] applied:
/// - an LLM equipment mention on the hit's line whose words lie inside the
///   hit's surface is replaced by it (the model dropped "yellow");
/// - a hit with no mention is added;
/// - loan rule: a line with an equipment hit gets a loan hint, if the sidecar
///   has none, when it has a person mention or a student word. The offer
///   itself still waits for the equipment to be settled.
EnrichMentions applyAliasHits(
  EnrichMentions mentions,
  List<EnrichAliasHit> hits,
  List<String> lines,
) {
  if (hits.isEmpty) return mentions;
  final result = [...mentions.mentions];
  final loans = [...mentions.loans];
  for (final hit in hits) {
    final key = enrichEquipmentKey(hit.surface);
    result.removeWhere(
      (m) =>
          m.line == hit.line &&
          m.type == 'equipment' &&
          key.contains(enrichEquipmentKey(m.surface)),
    );
    result.add(
      EnrichMention(
        surface: hit.surface,
        type: 'equipment',
        line: hit.line,
        candidateIds: hit.ids,
      ),
    );
    if (!loans.any((l) => l.line == hit.line)) {
      final person = mentions.mentions
          .where((m) => m.line == hit.line && m.type == 'person')
          .firstOrNull;
      final line = lines[hit.line - 1];
      if (person != null || _studentWord.hasMatch(line)) {
        loans.add(
          EnrichLoanHint(
            line: hit.line,
            borrower: person?.surface ?? _studentWord.firstMatch(line)?[0],
          ),
        );
      }
    }
  }
  return EnrichMentions(
    note: mentions.note,
    contentSha: mentions.contentSha,
    model: mentions.model,
    mentions: result,
    keywords: mentions.keywords,
    markers: mentions.markers,
    loans: loans,
  );
}
