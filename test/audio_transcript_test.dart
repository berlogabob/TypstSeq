import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/audio/audio_note_doc.dart';

const kSource =
    '= Recording\n'
    '#tylog.attachment("assets/audio/take.m4a", kind: "audio")\n'
    '\n'
    '== Comments\n'
    '- 00:42 good chorus entry\n'
    '- 01:10 nice bridge\n'
    '\n'
    '== Transcript\n'
    '- 00:43 hello world\n'
    '- 01:11 the bridge\n';

void main() {
  test('transcript markers are parsed without changing ordinary text', () {
    expect(parseTranscriptText('hello (?) world'), (
      text: 'hello (?) world',
      doubtful: false,
      nonSpeech: false,
      untranslated: false,
    ));
    expect(parseTranscriptText('(?) talvez'), (
      text: 'talvez',
      doubtful: true,
      nonSpeech: false,
      untranslated: false,
    ));
    expect(parseTranscriptText('[—]'), (
      text: '—',
      doubtful: false,
      nonSpeech: true,
      untranslated: false,
    ));
    expect(parseTranscriptText('[sem tradução]'), (
      text: 'no translation',
      doubtful: false,
      nonSpeech: false,
      untranslated: true,
    ));
    expect(parseTranscriptText('(?) [sem tradução]'), (
      text: 'no translation',
      doubtful: true,
      nonSpeech: false,
      untranslated: true,
    ));
  });

  test('markers are recognized after timestamped text is unescaped', () {
    const source = r'''
== Transcript
- 00:01 (?) Talvez
- 00:02 \[—\]
== Translation ru
- 00:01 (?) Может быть
- 00:02 \[sem tradução\]
''';
    final transcript = parseTranscript(source);
    final translated = parseTranslation(source, 'ru');
    expect(parseTranscriptText(transcript.first.text).doubtful, isTrue);
    expect(parseTranscriptText(transcript.last.text).nonSpeech, isTrue);
    expect(parseTranscriptText(translated.first.text).text, 'Может быть');
    expect(parseTranscriptText(translated.last.text).untranslated, isTrue);
    expect(transcript.map((c) => c.ms), translated.map((c) => c.ms));
  });

  test('context sections parse separately and keep reference AI labels', () {
    const source = r'''
== Summary
- 00:00 A play about \[memory\].
== Scenes
- 01:20 Second scene
- 00:10 First scene
- 00:10 Same-second scene
== References
- 00:30 Pessoa: Portuguese poet (AI)
== Context
- 00:05 User programme
== Transcript
- 00:10 The play begins
''';
    expect(parseSummary(source), [(ms: 0, text: 'A play about [memory].')]);
    expect(parseScenes(source), [
      (ms: 10000, text: 'First scene'),
      (ms: 10000, text: 'Same-second scene'),
      (ms: 80000, text: 'Second scene'),
    ]);
    expect(parseReferences(source), [
      (ms: 30000, text: 'Pessoa: Portuguese poet (AI)'),
    ]);
    expect(parseTranscript(source).single.text, 'The play begins');
  });

  test('absent context sections parse as empty lists', () {
    expect(parseSummary(kSource), isEmpty);
    expect(parseScenes(kSource), isEmpty);
    expect(parseReferences(kSource), isEmpty);
  });

  for (final (heading, parse) in [
    ('Summary', parseSummary),
    ('Scenes', parseScenes),
    ('References', parseReferences),
  ]) {
    test(
      '$heading selects its language and falls back to the legacy section',
      () {
        final legacy = '== $heading\n- 00:05 Legacy\n';
        final source =
            '$legacy'
            '== $heading pt\n- 00:10 Depois\n- 00:05 Antes \\[x\\]\n'
            '== $heading ru\n- 00:05 Русский\n'
            '== $heading en\n- 00:05 English\n';
        expect(parse(source, 'pt'), [
          (ms: 5000, text: 'Antes [x]'),
          (ms: 10000, text: 'Depois'),
        ]);
        expect(parse(source, 'ru'), [(ms: 5000, text: 'Русский')]);
        expect(parse(source, 'en'), [(ms: 5000, text: 'English')]);
        expect(parse(source, 'de'), [(ms: 5000, text: 'Legacy')]);
        expect(parse(source), [(ms: 5000, text: 'Legacy')]);
        for (final lang in ['pt', 'ru', 'en']) {
          expect(parse(legacy, lang), [(ms: 5000, text: 'Legacy')]);
          expect(parse('== $heading $lang\n$legacy', lang), isEmpty);
          expect(parse(kSource, lang), isEmpty);
        }
      },
    );
  }

  test(
    'parseComments ignores transcript lines and parseTranscript ignores comments',
    () {
      final comments = parseComments(kSource);
      expect(comments.map((c) => c.text), ['good chorus entry', 'nice bridge']);

      final transcript = parseTranscript(kSource);
      expect(transcript.map((c) => c.text), ['hello world', 'the bridge']);
    },
  );

  test(
    'appendComment adds inside Comments before Transcript, parseTranscript unchanged',
    () {
      final appended = appendComment(kSource, 30000, 'late note');
      final idxComments = appended.indexOf('== Comments');
      final idxTranscript = appended.indexOf('== Transcript');
      expect(appended, contains('- 00:30 late note'));
      expect(appended.indexOf('- 00:30 late note'), lessThan(idxTranscript));
      expect(appended.indexOf('- 00:30 late note'), greaterThan(idxComments));

      final transcript = parseTranscript(appended);
      expect(transcript.map((c) => c.text), ['hello world', 'the bridge']);
    },
  );

  test(
    'removeComment removes only the Comments line even when text matches a transcript line',
    () {
      // 'hello world' also appears in the transcript (at 00:43); this comment is at 00:05.
      final source = kSource.replaceFirst(
        '- 01:10 nice bridge',
        '- 00:05 hello world',
      );
      final removed = removeComment(source, 5000, 'hello world');
      // Only the comment line is gone; the chorus comment remains.
      expect(parseComments(removed).map((c) => c.text), ['good chorus entry']);
      // The transcript copy survives, untouched.
      expect(parseTranscript(removed).map((c) => c.text), [
        'hello world',
        'the bridge',
      ]);
    },
  );

  test('parseComments of a source with no Comments heading is empty', () {
    const noComments =
        '= Nothing\n'
        '== Transcript\n'
        '- 00:43 hello world\n';
    expect(parseComments(noComments), isEmpty);
    expect(parseTranscript(noComments).map((c) => c.text), ['hello world']);
  });

  test(
    'translation sections are listed and parsed apart from the transcript',
    () {
      const src =
          '= T\n\n== Transcript\n\n- 00:01 Ola\n\n'
          '== Translation ru\n\n- 00:01 Привет\n\n== Comments\n\n- 00:02 c\n';
      expect(translationLangs(src), ['ru']);
      expect(parseTranslation(src, 'ru').single.text, 'Привет');
      expect(parseTranscript(src).single.text, 'Ola');
      expect(parseComments(src).single.text, 'c');
    },
  );

  test('same-second segments keep file order', () {
    // A long run of equal timestamps: an unstable sort reorders it.
    final same = [
      for (var i = 0; i < 60; i++)
        '- 00:05 part ${i.toString().padLeft(2, '0')}',
    ];
    final src = '= T\n\n== Transcript\n\n${same.join('\n')}\n- 00:01 early\n';
    expect(parseTranscript(src).map((c) => c.text), [
      'early',
      for (var i = 0; i < 60; i++) 'part ${i.toString().padLeft(2, '0')}',
    ]);
  });
}
