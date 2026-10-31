import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/audio_note_screen.dart';

const _attachment =
    '#tylog.attachment("/assets/theatre.m4a", kind: "audio")[Theatre]\n';

Future<void> _pumpNote(
  WidgetTester tester, {
  required Future<String> Function(String) readSource,
  Future<Uint8List> Function(String)? readBytes,
  String? sourceLanguage,
}) => tester.pumpWidget(
  MaterialApp(
    home: AudioNoteScreen(
      note: const NoteRef(
        id: 'theatre',
        path: 'notes/theatre.typ',
        title: 'Theatre',
        kind: 'audio',
        outgoingLinks: [],
      ),
      initialTab: AudioTab.transcribe,
      readSource: readSource,
      readBytes: readBytes ?? (_) => Completer<Uint8List>().future,
      writeBytes: (_, _) async {},
      mutate: (_, _) async => true,
      transcriptStatus: (_) async => null,
      transcriptLang: (_) async => sourceLanguage,
      requestTranscript: (_, _) async {},
    ),
  ),
);

void main() {
  testWidgets('language selection changes sections and transcript rows', (
    tester,
  ) async {
    await _pumpNote(
      tester,
      sourceLanguage: 'pt',
      readSource: (_) async =>
          '$_attachment'
          '== Summary pt\n- 00:00 Resumo\n'
          '== Summary ru\n- 00:00 Краткое содержание\n'
          '== Summary en\n- 00:00 English summary\n'
          '== Scenes pt\n- 00:05 Cena\n'
          '== Scenes en\n- 00:05 Scene\n'
          '== References pt\n- 00:05 Referência\n'
          '== References en\n- 00:05 Reference\n'
          '== Transcript\n- 00:05 Olá\n'
          '== Translation ru\n- 00:05 Привет\n'
          '== Translation en\n- 00:05 Hello\n',
    );
    await tester.pump();

    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'RU')).selected,
      isTrue,
    );
    expect(find.text('Краткое содержание'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'EN'));
    await tester.pump();
    expect(find.text('English summary'), findsOneWidget);
    expect(find.text('Краткое содержание'), findsNothing);
    expect(find.text('Olá'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    var sections = tester.widget<AudioNoteSections>(
      find.byType(AudioNoteSections),
    );
    expect(sections.scenes.single.text, 'Scene');
    expect(sections.references.single.text, 'Reference');
    expect(find.text('Scene'), findsNothing);
    expect(find.text('Reference'), findsNothing);

    await tester.tap(find.byTooltip('Side by side'));
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Olá'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'PT'));
    await tester.pump();
    expect(find.text('Resumo'), findsOneWidget);
    expect(find.text('English summary'), findsNothing);
    expect(find.text('Olá'), findsOneWidget);
    sections = tester.widget<AudioNoteSections>(find.byType(AudioNoteSections));
    expect(sections.scenes.single.text, 'Cena');
    expect(sections.references.single.text, 'Referência');
    await tester.tap(find.byTooltip('Side by side'));
    await tester.pump();
    expect(find.text('Olá'), findsOneWidget);
    expect(find.text('Hello'), findsNothing);
    expect(find.text('Привет'), findsNothing);
    expect(
      tester
          .widget<AudioTranscriptRow>(find.byType(AudioTranscriptRow))
          .translation,
      isNull,
    );
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'PT')).selected,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'long note keeps transcript visible below aligned header chips on a phone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: AudioNoteScreen(
            note: const NoteRef(
              id: 'theatre',
              path: 'notes/theatre.typ',
              title: 'Theatre',
              kind: 'audio',
              outgoingLinks: [],
            ),
            initialTab: AudioTab.transcribe,
            readSource: (_) async =>
                '$_attachment== Summary\n- 00:00 A long theatre note.\n'
                '== Scenes\n${List.generate(25, (i) => '- 00:05 Scene $i\n').join()}'
                '== References\n${List.generate(11, (i) => '- 00:05 Reference $i\n').join()}'
                '== Transcript\n- 00:05 Olá\n'
                '${List.generate(494, (i) => '- 00:10 Line $i\n').join()}'
                '== Translation ru\n- 00:05 Привет\n'
                '== Translation en\n- 00:05 Hello\n',
            readBytes: (_) => Completer<Uint8List>().future,
            writeBytes: (_, _) async {},
            mutate: (_, _) async => true,
            transcriptStatus: (_) async => null,
            transcriptLang: (_) async => 'pt',
            requestTranscript: (_, _) async {},
            requestTranslation: (_, _, _, _, _) async {},
            selectedLanguages: const ['pt', 'ru', 'en'],
          ),
        ),
      );
      await tester.pump();

      final header = find.byType(AudioLanguageBar);
      final toggle = find.byTooltip('Side by side');
      final controls = [
        toggle,
        find.widgetWithText(ChoiceChip, 'PT'),
        find.widgetWithText(ChoiceChip, 'RU'),
        find.widgetWithText(ChoiceChip, 'EN'),
        find.byTooltip('Translate into another language'),
      ];
      expect(find.textContaining('Language:'), findsNothing);
      expect(find.byTooltip('Original'), findsOneWidget);
      expect(toggle, findsOneWidget);
      expect(find.text('Scenes · 25'), findsOneWidget);
      expect(find.text('References · 11'), findsOneWidget);
      expect(find.text('Scene 0'), findsNothing);
      expect(find.text('Reference 0'), findsNothing);
      expect(find.text('Olá').hitTestable(), findsOneWidget);
      expect(tester.getSize(header).height, closeTo(40, 2));
      for (final control in controls) {
        expect(
          tester.getCenter(control).dy,
          closeTo(tester.getCenter(header).dy, 1),
        );
      }
      final scroll = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: header,
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(scroll.scrollDirection, Axis.horizontal);
      expect(scroll.child, isA<Row>());
      final chip = find.widgetWithIcon(FilterChip, Icons.view_column);
      expect(tester.widget<FilterChip>(chip).selected, isTrue);
      expect(tester.widget<FilterChip>(chip).showCheckmark, isFalse);
      expect(
        tester.getSize(chip).height,
        tester.getSize(find.widgetWithText(ChoiceChip, 'RU')).height,
      );
      await tester.tap(toggle);
      await tester.pump();
      expect(find.text('Olá'), findsNothing);
      expect(find.text('Привет'), findsOneWidget);
      expect(find.byIcon(Icons.view_column_outlined), findsOneWidget);
      expect(header, findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();
      expect(find.text('Привет'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'EN'));
      await tester.pump();
      expect(find.text('Hello').hitTestable(), findsOneWidget);
      expect(find.text('Привет'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a parallel gap is one muted seekable row without chips', (
    tester,
  ) async {
    var taps = 0;
    final theme = ThemeData();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AudioTranscriptRow(
            segment: (ms: 5000, text: '[—]'),
            translation: '[—]',
            onTap: () => taps++,
          ),
        ),
      ),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(tester.widget<ListTile>(find.byType(ListTile)).subtitle, isNull);
    for (final text in ['00:05', '—']) {
      expect(
        tester.widget<Text>(find.text(text)).style!.color,
        theme.colorScheme.onSurfaceVariant,
      );
      await tester.tap(find.text(text));
    }
    expect(taps, 2);
  });

  testWidgets('waits for note text before showing the transcript empty state', (
    tester,
  ) async {
    final source = Completer<String>();
    await _pumpNote(tester, readSource: (_) => source.future);

    expect(find.text('No transcript yet'), findsNothing);
    expect(find.text('Request transcription'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Translate'));
    await tester.pump();
    expect(find.text('Transcribe the audio first'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Transcribe'));
    await tester.pump();

    source.complete(_attachment);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No transcript yet'), findsOneWidget);
    expect(find.text('Request transcription'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'transcript and translations appear before waveform/audio reads',
    (tester) async {
      final source = Completer<String>();
      final reads = <String>[];
      await _pumpNote(
        tester,
        readSource: (_) => source.future,
        readBytes: (path) {
          reads.add(path);
          return Completer<Uint8List>().future;
        },
      );
      source.complete(
        '$_attachment== Transcript\n- 00:05 Olá\n'
        '== Translation en\n- 00:05 Hello\n',
      );
      await tester.pump();

      expect(reads, ['assets/theatre.m4a.peaks']);
      expect(find.text('Olá'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Request transcription'), findsNothing);
      await tester.tap(find.text('Translate'));
      await tester.pump();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Transcribe the audio first'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('three consecutive parallel gaps share one row and first time', (
    tester,
  ) async {
    await _pumpNote(
      tester,
      readSource: (_) async =>
          '$_attachment== Transcript\n'
          '- 00:05 [—]\n- 00:10 [—]\n- 00:15 [—]\n- 00:20 Olá\n'
          '== Translation en\n'
          '- 00:05 [—]\n- 00:10 [—]\n- 00:15 [—]\n- 00:20 Hello\n',
    );
    await tester.pump();

    expect(find.byType(AudioTranscriptRow), findsNWidgets(2));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('00:05'), findsOneWidget);
    expect(find.text('00:10'), findsNothing);
    expect(find.text('00:15'), findsNothing);
    expect(find.text('Olá'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    final gap = tester.widget<AudioTranscriptRow>(
      find.byType(AudioTranscriptRow).first,
    );
    expect(gap.segment.ms, 5000);
    await tester.tap(find.text('—'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
