import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/audio_note_screen.dart';
import 'package:tylog/widgets/audio_shelf.dart';

NoteRef note(String id, String kind, {Map<String, Object?> p = const {}}) =>
    NoteRef(
      id: id,
      path: 'notes/$id.typ',
      title: 'Audio $id',
      kind: kind,
      outgoingLinks: const [],
      properties: p,
    );

void main() {
  testWidgets('waveform maps a tap to a fraction of its width', (tester) async {
    double? seek;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: WaveformSeekBar(
              peaks: const [10, 200, 100, 50],
              progress: 0.25,
              markers: const [0.5],
              onSeek: (f) => seek = f,
            ),
          ),
        ),
      ),
    );
    final box = tester.getTopLeft(find.byType(WaveformSeekBar));
    await tester.tapAt(box + const Offset(150, 20));
    expect(seek, closeTo(0.75, 0.01));
  });

  testWidgets('shelf lists only audio notes, newest id first', (tester) async {
    NoteRef? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioShelf(
            notes: [
              note('audio-20261014-100000', 'audio', p: {'duration_ms': 65000}),
              note('audio-20261015-100000', 'audio'),
              note('n1', 'note'),
            ],
            onOpen: (n) => opened = n,
            onRecord: () {},
            onImport: () {},
          ),
        ),
      ),
    );
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles, [
      'Audio audio-20261015-100000',
      'Audio audio-20261014-100000',
    ]);
    expect(find.text('01:05'), findsOneWidget);
    await tester.tap(find.text('Audio audio-20261014-100000'));
    expect(opened?.id, 'audio-20261014-100000');
  });

  test('activeIndex picks the last comment at or before the playhead', () {
    const c = [(ms: 1000, text: 'a'), (ms: 5000, text: 'b')];
    expect(activeIndex(c, 500), -1);
    expect(activeIndex(c, 1000), 0);
    expect(activeIndex(c, 9000), 1);
  });
}
