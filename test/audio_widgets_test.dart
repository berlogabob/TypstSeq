import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/ai/ai_settings.dart';
import 'package:tylog/audio/processing_policy.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/audio_note_screen.dart';
import 'package:tylog/widgets/audio_processing_settings.dart';
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

Future<void> pumpAudioSettings(
  WidgetTester tester, {
  Future<AiSettings> Function()? readAi,
  Future<void> Function(AiSettings)? writeAi,
  Future<List<WorkerStatus>> Function()? readWorkers,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AudioProcessingSettings(
            read: () async => const AudioPolicy(),
            write: (_) async {},
            processNow: () async {},
            readAi: readAi,
            writeAi: writeAi,
            readWorkers: readWorkers,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('AI quality saves immediately and preserves other settings', (
    tester,
  ) async {
    const settings = AiSettings(
      connections: [
        AiConnection(id: 'studio', label: 'Studio PC', url: 'http://studio/v1'),
      ],
      transcribe: AiTask(connection: 'local'),
      translate: AiTask(connection: 'studio', model: 'custom/translation'),
    );
    AiSettings? saved;
    await pumpAudioSettings(
      tester,
      readAi: () async => settings,
      writeAi: (next) async => saved = next,
      readWorkers: () async => [
        const WorkerStatus(host: 'Old Mac'),
        WorkerStatus(
          host: 'Mac',
          lastSeen: DateTime.now(),
          connections: const {
            'studio': (
              reachable: true,
              loaded: ['ollama/ornith-1.5:35b', 'provider/model'],
            ),
          },
        ),
      ],
    );
    expect(find.text('Mac online'), findsOneWidget);
    expect(find.byIcon(Icons.computer), findsOneWidget);
    expect(
      find.text('Server Studio PC: reachable, loaded: ornith-1.5:35b, model'),
      findsOneWidget,
    );
    expect(find.text('large-v3'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<String>).at(1),
        matching: find.text('Fast'),
      ),
    );
    await tester.pump();
    expect(saved!.transcribe.quality, 'fast');
    expect(saved!.transcribe.connection, 'local');
    expect(saved!.translate.toJson(), settings.translate.toJson());
    expect(saved!.connections, settings.connections);
    expect(find.text('small'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('worker status refreshes every 30 seconds and stops on dispose', (
    tester,
  ) async {
    var reads = 0;
    List<WorkerStatus> workers = [];
    await pumpAudioSettings(
      tester,
      readAi: () async => const AiSettings(
        connections: [
          AiConnection(
            id: 'studio',
            label: 'Studio PC',
            url: 'http://studio/v1',
          ),
        ],
      ),
      writeAi: (_) async {},
      readWorkers: () async {
        reads++;
        return workers;
      },
    );
    expect(reads, 1);
    expect(
      find.text(
        'No computer is processing yet. Start the TyLog worker on your computer.',
      ),
      findsOneWidget,
    );
    workers = [
      WorkerStatus(
        host: 'Mac',
        lastSeen: DateTime.now().subtract(const Duration(minutes: 10)),
        connections: const {'studio': (reachable: false, loaded: <String>[])},
      ),
    ];
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(reads, 2);
    expect(find.text('Mac last seen 10 minutes ago (offline)'), findsOneWidget);
    expect(find.byIcon(Icons.computer_outlined), findsOneWidget);
    expect(find.text('Server Studio PC: not reachable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
    expect(reads, 2);
  });

  testWidgets('AI area is absent unless both settings callbacks are supplied', (
    tester,
  ) async {
    for (final readable in [false, true]) {
      await pumpAudioSettings(
        tester,
        readAi: readable ? () async => const AiSettings() : null,
        writeAi: readable ? null : (_) async {},
      );
      expect(find.byType(SegmentedButton<String>), findsNothing);
      expect(find.text('Transcription quality'), findsNothing);
      expect(find.text('Translation quality'), findsNothing);
      expect(find.byIcon(Icons.computer_outlined), findsNothing);
      expect(find.text('Transcribe automatically'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('mixed transcript requests a missing selected translation', (
    tester,
  ) async {
    String? requested;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioLanguageBar(
            selected: const ['ru', 'en', 'pt'],
            original: null,
            translated: const {'ru'},
            translating: const {},
            view: 'ru',
            onView: (_) {},
            onRequest: (l) => requested = l,
            canRequest: true,
          ),
        ),
      ),
    );
    expect(find.textContaining('· original'), findsNothing);
    expect(find.byIcon(Icons.add), findsNWidgets(2));
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
    expect(
      scroll.padding,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
    expect(scroll.child, isA<Row>());
    expect((scroll.child! as Row).spacing, 8);
    expect(find.byType(Wrap), findsNothing);
    expect(find.byIcon(Icons.translate), findsOneWidget);
    expect(find.text('Translate'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'RU'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'EN'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'PT'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'EN'));
    expect(requested, 'en');
  });

  testWidgets('monolingual original chip allows viewing a translation', (
    tester,
  ) async {
    String? viewed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioLanguageBar(
            selected: const ['ru', 'en', 'pt'],
            original: 'pt',
            translated: const {'ru'},
            translating: const {},
            view: 'pt',
            onView: (l) => viewed = l,
            onRequest: (_) {},
            canRequest: true,
          ),
        ),
      ),
    );
    expect(find.widgetWithText(ChoiceChip, 'PT'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'PT'), findsNothing);
    final original = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'PT'),
    );
    expect(original.selected, isTrue);
    expect(original.showCheckmark, isFalse);
    expect(original.visualDensity, VisualDensity.compact);
    expect(original.materialTapTargetSize, MaterialTapTargetSize.shrinkWrap);
    await tester.tap(find.widgetWithText(ChoiceChip, 'RU'));
    expect(viewed, 'ru');
  });

  testWidgets(
    'language settings stay editable with both automation switches off',
    (tester) async {
      AudioPolicy? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AudioProcessingSettings(
                read: () async => const AudioPolicy(translateTo: ['pt', 'ru']),
                write: (p) async => saved = p,
                processNow: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('Full text in each of these languages'), findsOneWidget);
      expect(
        tester
            .widgetList<InputChip>(find.byType(InputChip))
            .map((c) => (c.label as Text).data),
        ['Português', 'Русский'],
      );
      await tester.tap(find.text('Add language'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'English'));
      await tester.pumpAndSettle();
      expect(saved!.translateTo, ['pt', 'ru', 'en']);
      expect(saved!.transcribe, isFalse);
      expect(saved!.translate, isFalse);
      final chip = tester.widget<InputChip>(
        find.widgetWithText(InputChip, 'Русский'),
      );
      chip.onDeleted!();
      await tester.pumpAndSettle();
      expect(saved!.translateTo, ['pt', 'en']);
      await tester.tap(find.text('Translate automatically'));
      await tester.pumpAndSettle();
      expect(saved!.translate, isTrue);
      expect(saved!.transcribe, isFalse);
    },
  );

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

  testWidgets('audio searches title and aliases and retains actions', (tester) async {
    var recorded = false;
    var imported = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AudioShelf(
        notes: const [
          NoteRef(
            id: 'audio-1', path: 'audio/one.typ', title: 'Interview', kind: 'audio',
            aliases: ['Alice'], outgoingLinks: [],
          ),
          NoteRef(
            id: 'audio-2', path: 'audio/two.typ', title: 'Lecture', kind: 'audio',
            outgoingLinks: [],
          ),
        ],
        onOpen: (_) {},
        onRecord: () => recorded = true,
        onImport: () => imported = true,
      )),
    ));
    await tester.enterText(find.byKey(const Key('audio-search')), 'INTERVIEW');
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Lecture'), findsNothing);
    await tester.enterText(find.byKey(const Key('audio-search')), 'ALICE');
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('audio-search')), 'missing');
    await tester.pump();
    expect(find.text('Nothing matches'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Lecture'), findsOneWidget);
    await tester.tap(find.text('Record'));
    await tester.tap(find.text('Import file'));
    expect(recorded, isTrue);
    expect(imported, isTrue);
  });

  test('activeIndex picks the last comment at or before the playhead', () {
    const c = [(ms: 1000, text: 'a'), (ms: 5000, text: 'b')];
    expect(activeIndex(c, 500), -1);
    expect(activeIndex(c, 1000), 0);
    expect(activeIndex(c, 9000), 1);
  });
}
