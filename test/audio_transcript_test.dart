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
}
