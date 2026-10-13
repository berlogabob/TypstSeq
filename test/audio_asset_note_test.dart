import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/audio/audio_note_doc.dart';

void main() {
  test('module audio has a deterministic id and readable title', () {
    expect(
      audioAssetNote('assets/modules/pt-pt-a2b1/audio/0001-dialogue.mp3'),
      (
        id: 'audio-modules-pt-pt-a2b1-audio-0001-dialogue',
        title: 'Audio 0001-dialogue',
      ),
    );
  });

  test('recorded audio includes its directories in the id', () {
    expect(audioAssetNote('assets/audio/2026/10/20261014-153042.m4a'), (
      id: 'audio-audio-2026-10-20261014-153042',
      title: 'Audio 20261014-153042',
    ));
  });

  test('a path without an extension still works', () {
    expect(audioAssetNote('audio/hello__world'), (
      id: 'audio-audio-hello-world',
      title: 'Audio hello__world',
    ));
  });
}
