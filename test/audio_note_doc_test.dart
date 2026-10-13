import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/audio/audio_note_doc.dart';

void main() {
  composedNote();
  test('stamp, title and peaks round-trip', () {
    final t = DateTime(2026, 10, 14, 15, 30, 42, 7);
    expect(audioStamp(t), '20261014-153042');
    expect(audioStamp(t, withMillis: true), '20261014-153042-007');
    expect(audioTitle(audioStamp(t)), 'Audio 20261014-153042');
    expect(decodePeaks(encodePeaks([0, 5, 255, 300])), [0, 5, 255, 255]);
    expect(decodePeaks(null), isEmpty);
  });

  test('comments append, parse sorted, escape markup, and remove one line', () {
    var s = '= A\n${audioNoteBody('assets/audio/x.m4a', 'x.m4a')}';
    expect(audioPathOf(s), 'assets/audio/x.m4a');
    s = appendComment(s, 65000, 'second #chorus [x]');
    s = appendComment(s, 12000, 'first');
    s = appendComment(s, 12000, '   ');
    expect(s.split('== Comments').length, 2);
    final comments = parseComments(s);
    expect(comments.map((c) => c.ms), [12000, 65000]);
    expect(comments.last.text, 'second #chorus [x]');
    expect(s, contains(r'- 01:05 second \#chorus \[x\]'));
    final removed = removeComment(s, 12000, 'first');
    expect(parseComments(removed).map((c) => c.text), ['second #chorus [x]']);
    expect(audioPathOf('no attachment'), isNull);
  });
}

void composedNote() {
  test('composed audio note scans back and compiles with typst', () async {
    const id = 'audio-20261014-153042';
    final base =
        '#import "/_system/tylog.typ" as tylog\n\n'
        '#show: tylog.note.with(id: "$id", title: "Audio 20261014-153042", kind: "audio")\n\n= Audio 20261014-153042\n';
    var s = replaceNoteHeader(
      base,
      NoteMetadataDraft(
        id: id,
        title: 'Audio 20261014-153042',
        kind: 'audio',
        properties: {
          'duration_ms': 65000,
          'peaks': encodePeaks([1, 2, 255]),
        },
      ),
    );
    s += audioNoteBody(
      'assets/audio/2026/10/20261014-153042.m4a',
      '20261014-153042.m4a',
    );
    s = appendComment(s, 12000, 'chorus #1 [x]');
    final note = scanNote('notes/a.typ', s);
    expect(note.kind, 'audio');
    expect(note.properties['duration_ms'], 65000);
    expect(decodePeaks(note.properties['peaks']), [1, 2, 255]);
    expect(note.attachments.single.kind, 'audio');
    expect(parseComments(s).single.text, 'chorus #1 [x]');

    if ((await Process.run('typst', ['--version'])).exitCode != 0) return;
    final dir = await Directory.systemTemp.createTemp('audio_note_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/_system').create();
    await File('typst/tylog/lib.typ').copy('${dir.path}/_system/tylog.typ');
    await File('${dir.path}/a.typ').writeAsString(s);
    final r = await Process.run('typst', [
      'compile',
      '--root',
      dir.path,
      '${dir.path}/a.typ',
      '${dir.path}/a.pdf',
    ]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
  });
}
