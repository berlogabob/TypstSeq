import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/editor_autocomplete.dart';
import 'package:tylog_core/models.dart';

NoteRef _note(
  String id,
  String path,
  String title, {
  String kind = 'note',
  Map<String, Object?> properties = const {},
  List<String> aliases = const [],
}) => NoteRef(
  id: id,
  path: path,
  title: title,
  kind: kind,
  aliases: aliases,
  properties: properties,
  outgoingLinks: const [],
);

VaultIndex _mentionIndex() => VaultIndex(
  notesByPath: {
    for (var i = 0; i < 5000; i++)
      'notes/$i.typ': NoteRef(
        id: 'id-$i-fix',
        path: 'notes/$i.typ',
        title: [
          'Fix',
          'FIX pipeline',
          'Prefix fix suffix',
          'Илья',
          'Игровые движки',
          'Ética',
          'Unrelated',
        ][i % 7],
        kind: ['note', 'project', 'article', 'person'][i % 4],
        aliases: [
          'Alias $i',
          ['fix alias', 'ИЛЬЯ alias', 'ÉTI alias'][i % 3],
        ],
        outgoingLinks: const [],
      ),
  },
  backlinksByTarget: const {},
);
const _mentionQueries = [
  'fix',
  'FiX',
  '  FIX  ',
  'иЛь',
  'ИГРО',
  'eTi',
  'id-',
  '999-fix',
  'missing',
];
const _mentionRecency = {
  'notes/0.typ': 0,
  'notes/7.typ': 1,
  'notes/14.typ': 55,
};
const _mentionExcluded = {'id-0-fix', 'id-11-fix'};

void main() {
  test('cached mention query preserves old ordering on 5000 notes', () {
    final index = _mentionIndex();
    final cache = MentionQueryCache();
    // Captured from the original filter/comparator before changing production
    // code. Duplicate titles also lock down List.sort's existing tie order.
    const oldOrder = <String, List<int>>{
      'fix': [7, 2499, 2177, 1001, 987, 2401, 2387, 973],
      'FiX': [7, 2499, 2177, 1001, 987, 2401, 2387, 973],
      '  FIX  ': [7, 2499, 2177, 1001, 987, 2401, 2387, 973],
      'иЛь': [2033, 101, 1011, 983, 1025, 1039, 1053, 969],
      'ИГРО': [4743, 1019, 1033, 1047, 1061, 1075, 1089, 109],
      'eTi': [4555, 1013, 1027, 985, 103, 1041, 1055, 1069],
      'id-': [7, 1849, 99, 1009, 981, 1023, 1037, 967],
      '999-fix': [4999, 3999, 999, 1999, 2999],
      'missing': [],
    };
    for (final query in _mentionQueries) {
      final expected = oldOrder[query]!.map(
        (i) => index.notesByPath['notes/$i.typ']!,
      );
      expect(
        cache.query(
          index,
          query,
          _mentionRecency,
          excludedIds: _mentionExcluded,
        ),
        orderedEquals(expected),
        reason: query,
      );
    }
  });

  test('mention cache rebuilds for replacement and in-place index refresh', () {
    final cache = MentionQueryCache();
    final first = _note('first', 'notes/first.typ', 'First');
    final second = _note('second', 'notes/second.typ', 'Second');
    final index = VaultIndex(
      notesByPath: {first.path: first},
      backlinksByTarget: const {},
    );
    expect(cache.query(index, 'first', const {}), [first]);
    index.notesByPath
      ..clear()
      ..[second.path] = second;
    expect(cache.query(index, 'second', const {}, revision: 1), [second]);
    expect(cache.query(index, 'first', const {}, revision: 1), isEmpty);
    final replacement = VaultIndex(
      notesByPath: {first.path: first},
      backlinksByTarget: const {},
    );
    expect(cache.query(replacement, 'first', const {}, revision: 1), [first]);
    expect(cache.query(null, 'first', const {}), isEmpty);
  });

  test('mention query micro-benchmark on 5000 notes', () {
    final index = _mentionIndex();
    final cache = MentionQueryCache();
    for (final query in _mentionQueries) {
      for (var i = 0; i < 3; i++) {
        cache.query(
          index,
          query,
          _mentionRecency,
          excludedIds: _mentionExcluded,
        );
      }
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        cache.query(
          index,
          query,
          _mentionRecency,
          excludedIds: _mentionExcluded,
        );
      }
      // Informational only: timings are machine-dependent, never a CI gate.
      // ignore: avoid_print
      print(
        '$query: ${(stopwatch.elapsedMicroseconds / 10000).toStringAsFixed(3)} ms/query',
      );
    }
  });

  group('detectTrigger', () {
    test('@ alone at start of text triggers a mention with an empty query', () {
      final trigger = detectTrigger('@', 1);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.mention);
      expect(trigger.query, '');
      expect(trigger.start, 0);
    });

    test('@Fer triggers a mention with query "Fer"', () {
      final trigger = detectTrigger('@Fer', 4);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.mention);
      expect(trigger.query, 'Fer');
      expect(trigger.start, 0);
    });

    test('@ accepts Unicode names (Cyrillic)', () {
      const text = '@Илья';
      final trigger = detectTrigger(text, text.length);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.mention);
      expect(trigger.query, 'Илья');
    });

    test('a space after the query cancels the trigger', () {
      expect(detectTrigger('@Fer ', 5), isNull);
    });

    test('/ triggers a command palette', () {
      final trigger = detectTrigger('/table', 6);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.command);
      expect(trigger.query, 'table');
      expect(trigger.start, 0);
    });

    test('foo@bar does not trigger (no preceding whitespace)', () {
      expect(detectTrigger('foo@bar', 7), isNull);
    });

    test('a path like x/y does not trigger (no preceding whitespace)', () {
      expect(detectTrigger('x/y', 3), isNull);
    });

    test('@ preceded by whitespace triggers mid-sentence', () {
      final trigger = detectTrigger('Hello @Fer', 10);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.mention);
      expect(trigger.query, 'Fer');
      expect(trigger.start, 6);
    });

    test('@ preceded by a newline triggers', () {
      final trigger = detectTrigger('line one\n@Fer', 13);
      expect(trigger, isNotNull);
      expect(trigger!.query, 'Fer');
      expect(trigger.start, 9);
    });

    test('deleting back past @ cancels the trigger', () {
      // Simulates backspacing "@Fer" down to "" — nothing left to trigger on.
      expect(detectTrigger('', 0), isNull);
    });

    test('deleting the @ itself while query text remains cancels', () {
      // "Fer" with no leading "@" — no trigger character at all.
      expect(detectTrigger('Fer', 3), isNull);
    });

    test('caret not at the end of the word cancels the trigger', () {
      // Caret sits between "Fer" and "nando" in "@Fernando".
      expect(detectTrigger('@Fernando', 4), isNull);
    });

    test('whitespace inside the query cancels the trigger', () {
      expect(detectTrigger('@Fer Nando', 10), isNull);
    });

    test('no trigger character present at all returns null', () {
      expect(detectTrigger('just plain text', 16), isNull);
    });

    test('caret at position 0 with preceding text returns null', () {
      expect(detectTrigger('@Fer', 0), isNull);
    });

    test('command trigger cancels the same way a mention trigger does', () {
      expect(detectTrigger('/foo bar', 8), isNull);
    });
  });

  group('detectTrigger wiki-links', () {
    test('[[ alone triggers a wiki-link with an empty query', () {
      final trigger = detectTrigger('[[', 2);
      expect(trigger, isNotNull);
      expect(trigger!.kind, AutocompleteTriggerKind.wikiLink);
      expect(trigger.query, '');
      expect(trigger.start, 0);
    });

    test('[[ESP32 triggers with query "ESP32"', () {
      final trigger = detectTrigger('[[ESP32', 7);
      expect(trigger!.kind, AutocompleteTriggerKind.wikiLink);
      expect(trigger.query, 'ESP32');
      expect(trigger.start, 0);
    });

    test('the query may contain spaces (Home Assistant)', () {
      final trigger = detectTrigger('see [[Home Assist', 17);
      expect(trigger!.kind, AutocompleteTriggerKind.wikiLink);
      expect(trigger.query, 'Home Assist');
      expect(trigger.start, 4);
    });

    test('the query may contain Unicode (Cyrillic)', () {
      const text = '[[игровые движ';
      final trigger = detectTrigger(text, text.length);
      expect(trigger!.query, 'игровые движ');
    });

    test('a completed [[link]] does not re-trigger from after it', () {
      expect(detectTrigger('[[ESP32]]', 9), isNull);
    });

    test('a newline between [[ and the caret cancels', () {
      expect(detectTrigger('[[ESP32\nmore', 12), isNull);
    });

    test('a ] before the caret cancels', () {
      expect(detectTrigger('[[ESP32] ', 9), isNull);
    });

    test('wiki-link takes precedence over @ inside the brackets', () {
      final trigger = detectTrigger('[[@Fer', 6);
      expect(trigger!.kind, AutocompleteTriggerKind.wikiLink);
      expect(trigger.query, '@Fer');
    });
  });

  // The real vault's "@flowgroove" case: sorting by title alone put two
  // scraped articles — indistinguishable rows subtitled md-3b7a2305beedce32
  // and md-bc14d696f4420a94 — above everything else.
  group('mention ranking', () {
    final project = _note(
      'fg',
      'projects/FlowGroove.typ',
      'FlowGroove',
      kind: 'project',
    );
    final articleA = _note(
      'md-3b7a2305beedce32',
      'articles/FlowGroove.typ',
      'FlowGroove',
      kind: 'article',
      properties: {'url': 'https://flowgroove.app/join/?code=VHEE8I'},
    );
    final audit = _note(
      'flowgroove-ux-ui-audit-ru',
      'notes/FlowGroove_UX_UI_Audit_RU.typ',
      'UX/UI-аудит бета-версии FlowGroove',
    );

    test('an equally-titled project outranks an imported article', () {
      expect(
        mentionScore(project, 'flowgroove', const {}),
        greaterThan(mentionScore(articleA, 'flowgroove', const {})),
      );
    });

    test('tier dominates the kind bonus', () {
      // An exactly-titled article still beats a project matching only by
      // prefix — otherwise a kind bonus could bury the page you named.
      expect(
        mentionScore(articleA, 'flowgroove', const {}),
        greaterThan(mentionScore(project, 'flow', const {})),
      );
      // The audit note matches on its *id*, so it belongs in the list — but
      // below both notes whose title matches.
      final auditScore = mentionScore(audit, 'flowgroove', const {});
      expect(auditScore, greaterThan(0));
      expect(
        auditScore,
        lessThan(mentionScore(articleA, 'flowgroove', const {})),
      );
      // A word inside the title now matches too (substring tier), but stays
      // below any prefix-tier match so it can't bury the page you named.
      final substring = mentionScore(audit, 'аудит', const {});
      expect(substring, greaterThan(0));
      expect(
        substring,
        lessThan(mentionScore(articleA, 'flowgroove', const {})),
      );
    });

    test('recently opened breaks a tie between identical titles', () {
      const recency = {'articles/FlowGroove.typ': 0};
      expect(
        mentionScore(articleA, 'flowgroove', recency),
        greaterThan(mentionScore(articleA, 'flowgroove', const {})),
      );
    });

    test('subtitle names the kind and source instead of an opaque id', () {
      expect(mentionSubtitle(articleA), 'article · flowgroove.app');
      expect(mentionSubtitle(project), 'project · projects/FlowGroove.typ');
    });

    test('a non-prefix substring still matches, below prefix tiers', () {
      const home = NoteRef(
        id: 'home-assistant',
        path: 'notes/Home Assistant.typ',
        title: 'Home Assistant',
        outgoingLinks: [],
      );
      expect(
        mentionScore(home, 'assistant', const {}),
        greaterThan(0),
        reason: '"assistant" must reach "Home Assistant"',
      );
      expect(
        mentionScore(home, 'home', const {}),
        greaterThan(mentionScore(home, 'assistant', const {})),
        reason: 'prefix outranks substring',
      );
    });
  });
}
