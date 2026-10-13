import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/controlled_editor.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/widgets/audio_sheets.dart';

void main() {
  test('isAudioPath matches the recorder and picker extensions only', () {
    for (final p in ['a.m4a', 'A.MP3', 'x/y.aac', 'z.wav', 'q.opus', 'r.ogg']) {
      expect(isAudioPath(p), isTrue, reason: p);
    }
    for (final p in ['a.pdf', 'a.png', 'm4a', 'a.m4a.txt']) {
      expect(isAudioPath(p), isFalse, reason: p);
    }
  });

  test('inserted audio attachment is scanned back as kind audio', () {
    const request = MagicRequest(
      action: MagicAction.attachment,
      value: '/assets/audio/2026/10/abc.m4a',
      kind: 'audio',
    );
    final edit = applyMagicEdit(
      '',
      const TextSelection.collapsed(offset: 0),
      request,
    );
    final note = scanNote(
      'notes/A.typ',
      '#import "/_system/tylog.typ" as tylog\n'
          '#show: tylog.note.with(id: "a", title: "A")\n\n${edit.text}\n',
    );
    final attachment = note.attachments.single;
    expect(attachment.kind, 'audio');
    expect(attachment.path, 'assets/audio/2026/10/abc.m4a');
  });
}
