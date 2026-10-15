import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/controlled_editor.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/widgets/audio_note_screen.dart';
import 'package:tylog/widgets/audio_inline_card.dart';

void main() {
  testWidgets('sidecar peaks skip loading audio and codec backfill', (tester) async {
    var reads = 0;
    var backfills = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AudioInlineCard(
          label: 'lesson.mp3',
          peaks: const [],
          readPeaks: () async => [0, 128, 255],
          readBytes: () async {
            reads++;
            throw StateError('audio should stay unloaded');
          },
          extension: 'mp3',
          onExpand: (_) async {},
          onPeaks: (_, _) => backfills++,
        ),
      ),
    ));
    await tester.pump();
    final wave = tester.widget<WaveformSeekBar>(find.byType(WaveformSeekBar));
    expect(wave.peaks, [0, 128, 255]);
    expect(reads, 0);
    expect(backfills, 0);
  });

  bars();
  tearDown(() => TyLogEditingController.audioBuilder = null);

  testWidgets('audio attachment renders through audioBuilder, with or without /',
      (tester) async {
    final seen = <String>[];
    TyLogEditingController.audioBuilder = (path, label) {
      seen.add(path);
      return Text('CARD $label');
    };
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TyLogReadView(
            source:
                '#tylog.attachment("/assets/audio/a.m4a", kind: "audio")[a.m4a]\n\n'
                '#tylog.attachment("assets/audio/b.mp3", kind: "audio")[b.mp3]',
          ),
        ),
      ),
    );
    expect(find.text('CARD a.m4a'), findsOneWidget);
    expect(find.text('CARD b.mp3'), findsOneWidget);
    expect(seen, ['assets/audio/a.m4a', 'assets/audio/b.mp3']);
  });
}

void bars() {
  test('displayBars always yields a stretched wave', () {
    expect(displayBars(const []).length, 64);
    final quiet = displayBars([for (var i = 0; i < 30; i++) 10 + (i % 5) * 10]);
    expect(quiet.length, 64);
    expect(quiet.reduce((a, b) => a > b ? a : b), greaterThan(200));
    expect(displayBars(List.filled(110, 30)).toSet().length, 1); // flat, visible
  });

  test('audio inserts as its own block, splitting the paragraph', () {
    final c = TyLogEditingController(
      source: 'before after',
      onSourceChanged: (_) {},
      onError: (e) => fail('$e'),
      onProtectedTap: (_) {},
    );
    c.selection = const TextSelection.collapsed(offset: 7);
    c.applyMagic(
      const MagicRequest(
        action: MagicAction.attachment,
        value: '/assets/audio/x.m4a',
        kind: 'audio',
      ),
    );
    final src = c.document.toSource();
    expect(
      src,
      matches(
        RegExp(r'^before\s*\n\n#tylog\.attachment\([^\n]*\)\[x\.m4a\]\n\nafter$'),
      ),
    );
  });
}
