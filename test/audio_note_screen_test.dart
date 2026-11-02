import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
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
  Future<String?> Function(String, String)? translationStatus,
  Future<void> Function(String, String)? requestTranscript,
  Future<void> Function(String, String, String, String, List<String>)?
  requestTranslation,
  VoidCallback? onOpenProcessing,
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
      requestTranscript: requestTranscript ?? (_, _) async {},
      requestTranslation: requestTranslation,
      translationStatus: translationStatus,
      onOpenProcessing: onOpenProcessing,
    ),
  ),
);

void main() {
  late List<String> copied;
  setUp(() {
    copied = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final reprocess in [false, true]) {
    testWidgets(
      '${reprocess ? 'Re-process' : 'Transcription'} links to Processing',
      (tester) async {
        var requested = 0;
        var opened = 0;
        await _pumpNote(
          tester,
          readSource: (_) async => _attachment,
          requestTranscript: (audio, note) async {
            expect(audio, 'assets/theatre.m4a');
            expect(note, 'notes/theatre.typ');
            requested++;
          },
          onOpenProcessing: () => opened++,
        );
        await tester.pump();
        if (reprocess) {
          await tester.tap(find.byTooltip('Audio note menu'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Re-process'));
        } else {
          await tester.tap(find.text('Request transcription'));
        }
        await tester.pumpAndSettle();
        expect(requested, 1);
        expect(find.text('Queued — see Processing'), findsOneWidget);
        await tester.tap(find.widgetWithText(SnackBarAction, 'Processing'));
        expect(opened, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('failed translation retry links to Processing', (tester) async {
    var requested = 0;
    var opened = 0;
    await _pumpNote(
      tester,
      sourceLanguage: 'pt',
      translationStatus: (_, target) async =>
          target == 'en' ? (requested == 0 ? 'failed' : 'queued') : null,
      readSource: (_) async => '$_attachment== Transcript\n- 00:05 Olá\n',
      requestTranslation: (audio, note, target, source, sourceLangs) async {
        expect(target, 'en');
        expect(source, 'pt');
        requested++;
      },
      onOpenProcessing: () => opened++,
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Retry EN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(requested, 1);
    expect(find.text('Queued — see Processing'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Processing'));
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Text replaces Translate and has no translate popup', (
    tester,
  ) async {
    await _pumpNote(
      tester,
      sourceLanguage: 'pt',
      readSource: (_) async => '$_attachment== Transcript\n- 00:05 Olá\n',
      requestTranslation: (_, _, _, _, _) async {},
    );
    await tester.pump();
    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Properties'), findsOneWidget);
    expect(find.text('Transcribe'), findsNothing);
    expect(find.text('Translate'), findsNothing);
    expect(find.byTooltip('Translate into another language'), findsNothing);
    expect(find.byIcon(Icons.translate), findsNothing);
    await tester.tap(find.byTooltip('Audio note menu'));
    await tester.pumpAndSettle();
    expect(find.text('Re-process'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final status in ['queued', 'processing', 'failed']) {
    testWidgets('discovers missing translation $status on open', (
      tester,
    ) async {
      await _pumpNote(
        tester,
        sourceLanguage: 'pt',
        readSource: (_) async => '$_attachment== Transcript\n- 00:05 Olá\n',
        translationStatus: (_, target) async => target == 'en' ? status : null,
        requestTranslation: (_, _, _, _, _) async {},
      );
      await tester.pump();
      final chip = find.widgetWithText(Chip, 'EN');
      expect(chip, findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'PT'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'PT'), findsNothing);
      expect(
        find.descendant(
          of: chip,
          matching: find.byType(CircularProgressIndicator),
        ),
        status == 'failed' ? findsNothing : findsOneWidget,
      );
      expect(
        find.byTooltip('Retry EN'),
        status == 'failed' ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'missing language jobs and synced text refresh while Text is open',
    (tester) async {
      String? status;
      var source = '$_attachment== Transcript\n- 00:05 Olá\n';
      await _pumpNote(
        tester,
        sourceLanguage: 'pt',
        readSource: (_) async => source,
        translationStatus: (_, target) async => target == 'en' ? status : null,
      );
      await tester.pump();
      expect(find.widgetWithText(Chip, 'EN'), findsOneWidget);
      for (final next in ['queued', 'processing', 'done']) {
        status = next;
        await tester.pump(const Duration(seconds: 8));
        await tester.pump();
        if (next != 'done') {
          expect(
            find.descendant(
              of: find.widgetWithText(Chip, 'EN'),
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
        }
      }
      source += '== Translation en\n- 00:05 Hello\n';
      await tester.pump(const Duration(seconds: 8));
      await tester.pump();
      expect(find.widgetWithText(ChoiceChip, 'EN'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('long press copies the original or translation line', (
    tester,
  ) async {
    await _pumpNote(
      tester,
      sourceLanguage: 'pt',
      readSource: (_) async =>
          '$_attachment== Transcript\n- 00:05 Olá\n'
          '== Translation en\n- 00:05 Hello\n',
    );
    await tester.pump();
    await tester.longPress(find.text('Olá'));
    await tester.pump();
    expect(copied, ['Olá']);
    expect(find.text('Copied'), findsOneWidget);
    await tester.longPress(find.text('Hello'));
    await tester.pump();
    expect(copied, ['Olá', 'Hello']);
    await tester.tap(find.byTooltip('Side by side'));
    await tester.pump();
    await tester.longPress(find.text('Hello'));
    await tester.pump();
    expect(copied.last, 'Hello');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final choice in ['Original', 'English', 'Português', 'Side by side']) {
    testWidgets(
      'Copy all $choice uses timestamps and the selected translation',
      (tester) async {
        await _pumpNote(
          tester,
          sourceLanguage: 'ru',
          readSource: (_) async =>
              '$_attachment== Transcript\n'
              '- 00:05 Привет\n- 01:10 Мир\n'
              '== Translation pt\n- 00:05 Olá\n- 01:10 Mundo\n'
              '== Translation en\n- 00:05 Hello\n- 01:10 World\n',
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(ChoiceChip, 'EN'));
        await tester.pump();
        await tester.tap(find.byTooltip('Audio note menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy all'));
        await tester.pumpAndSettle();
        expect(find.text('Original'), findsOneWidget);
        expect(find.text('Português'), findsOneWidget);
        await tester.tap(
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.text(choice),
              )
              .first,
        );
        await tester.pumpAndSettle();
        final expected = switch (choice) {
          'Original' => '00:05 Привет\n01:10 Мир',
          'English' => '00:05 Hello\n01:10 World',
          'Português' => '00:05 Olá\n01:10 Mundo',
          _ => '00:05 Привет\n00:05 Hello\n01:10 Мир\n01:10 World',
        };
        expect(copied, [expected]);
        expect(find.text('Copied'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

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
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Translate'), findsNothing);

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
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Translate'), findsNothing);
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
