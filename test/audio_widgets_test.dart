import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/ai/ai_settings.dart';
import 'package:tylog/audio/audio_note_doc.dart';
import 'package:tylog/audio/processing_policy.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/audio_inline_card.dart';
import 'package:tylog/widgets/audio_note_screen.dart';
import 'package:tylog/widgets/audio_processing_settings.dart';
import 'package:tylog/widgets/audio_shelf.dart';
import 'package:tylog/widgets/ai_connections_settings.dart';
import 'package:tylog/widgets/constants.dart';

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
  AiSettingsSection section = AiSettingsSection.all,
  Future<AiSettings> Function()? readAi,
  Future<void> Function(AiSettings)? writeAi,
  Future<List<WorkerStatus>> Function()? readWorkers,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AudioProcessingSettings(
            section: section,
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

const _sectionSettings = AiSettings(
  connections: [
    AiConnection(id: 'studio', label: 'Studio PC', url: 'http://studio/v1'),
  ],
);

void main() {
  testWidgets('parallel row shows muted translation and both lines seek', (
    tester,
  ) async {
    var taps = 0;
    final theme = tyLogTheme(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AudioTranscriptRow(
            segment: (ms: 42000, text: '(?) Olá'),
            translation: 'Привет',
            active: true,
            onTap: () => taps++,
          ),
        ),
      ),
    );

    expect(find.text('00:42'), findsOneWidget);
    expect(find.text('(?) Olá'), findsNothing);
    expect(find.text('?'), findsOneWidget);
    final original = tester.widget<Text>(find.text('Olá'));
    final translated = tester.widget<Text>(find.text('Привет'));
    expect(original.style!.color, theme.colorScheme.onSurfaceVariant);
    expect(original.style!.decoration, TextDecoration.underline);
    expect(translated.style!.color, theme.colorScheme.onSurfaceVariant);
    expect(
      tester.getTopLeft(find.text('Привет')).dy,
      greaterThan(tester.getTopLeft(find.text('Olá')).dy),
    );
    expect(tester.widget<ListTile>(find.byType(ListTile)).selected, isTrue);
    await tester.tap(find.text('Olá'));
    await tester.tap(find.text('Привет'));
    expect(taps, 2);
  });

  testWidgets('missing translation markers stay muted and seekable', (
    tester,
  ) async {
    var taps = 0;
    final theme = tyLogTheme(Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AudioTranscriptRow(
            segment: (ms: 5000, text: 'Olá'),
            translation: '[sem tradução]',
            onTap: () => taps++,
          ),
        ),
      ),
    );

    expect(find.text('[sem tradução]'), findsNothing);
    final text = tester.widget<Text>(find.text('no translation'));
    expect(text.style!.fontStyle, FontStyle.italic);
    expect(text.style!.color, theme.colorScheme.onSurfaceVariant);
    await tester.tap(find.text('Olá'));
    await tester.tap(find.text('no translation'));
    expect(taps, 2);
  });

  testWidgets(
    'sections start collapsed and expand in place with seek targets',
    (tester) async {
      const source =
          '== Summary\n- 00:00 A play about memory.\n'
          '- 00:00 A second summary line.\n'
          '== Scenes\n- 00:10 Opening scene\n'
          '== References\n- 00:30 Pessoa: Portuguese poet (AI)\n';
      final seeks = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: tyLogTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AudioNoteSections(
                summary: parseSummary(source),
                scenes: parseScenes(source),
                references: parseReferences(source),
                onSeek: seeks.add,
              ),
            ),
          ),
        ),
      );

      const summary = 'A play about memory.\nA second summary line.';
      expect(tester.widget<Text>(find.text(summary)).maxLines, 1);
      expect(find.text('Scenes · 1'), findsOneWidget);
      expect(find.text('References · 1'), findsOneWidget);
      expect(find.text('Opening scene'), findsNothing);
      expect(find.text('Pessoa: Portuguese poet (AI)'), findsNothing);
      await tester.tap(find.text('Summary'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(summary)).maxLines, isNull);
      await tester.tap(find.text('Scenes · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Opening scene'), findsOneWidget);
      expect(find.text('Pessoa: Portuguese poet (AI)'), findsNothing);
      await tester.tap(find.text('Opening scene'));
      await tester.tap(find.text('Scenes · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Opening scene'), findsNothing);
      await tester.tap(find.text('References · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pessoa: Portuguese poet (AI)'));
      expect(seeks, [10000, 30000]);
      await tester.tap(find.text('References · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Pessoa: Portuguese poet (AI)'), findsNothing);
    },
  );

  testWidgets('absent summary, scenes and references stay hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioNoteSections(
            summary: const [],
            scenes: const [],
            references: const [],
            onSeek: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Summary'), findsNothing);
    expect(find.text('Scenes'), findsNothing);
    expect(find.text('References'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('servers section shows connections but not audio quality', (
    tester,
  ) async {
    await pumpAudioSettings(
      tester,
      section: AiSettingsSection.servers,
      readAi: () async => _sectionSettings,
      writeAi: (_) async {},
    );

    expect(find.byType(AiConnectionsSection), findsOneWidget);
    expect(find.text('Transcription quality'), findsNothing);
  });

  testWidgets('audio section shows transcription and languages, not articles', (
    tester,
  ) async {
    await pumpAudioSettings(
      tester,
      section: AiSettingsSection.audio,
      readAi: () async => _sectionSettings,
      writeAi: (_) async {},
    );

    expect(find.text('Transcription quality'), findsOneWidget);
    expect(find.text('Transcribe automatically'), findsOneWidget);
    expect(find.text('Translations: ru, en, pt (always)'), findsOneWidget);
    expect(find.text('Translate automatically'), findsNothing);
    expect(find.text('Full text in each of these languages'), findsOneWidget);
    expect(find.text('Articles'), findsNothing);
  });

  testWidgets('articles section shows only the Articles server and model', (
    tester,
  ) async {
    await pumpAudioSettings(
      tester,
      section: AiSettingsSection.articles,
      readAi: () async => _sectionSettings,
      writeAi: (_) async {},
    );

    expect(find.byKey(const ValueKey('Articles')), findsOneWidget);
    expect(find.text('Screenshots'), findsNothing);
    expect(find.byType(AiConnectionsSection), findsNothing);
    expect(find.text('Transcription quality'), findsNothing);
  });

  testWidgets(
    'screenshots section shows only the Screenshots server and model',
    (tester) async {
      await pumpAudioSettings(
        tester,
        section: AiSettingsSection.screenshots,
        readAi: () async => _sectionSettings,
        writeAi: (_) async {},
      );

      expect(find.byKey(const ValueKey('Screenshots')), findsOneWidget);
      expect(find.text('Articles'), findsNothing);
      expect(find.byType(AiConnectionsSection), findsNothing);
      expect(find.text('Transcription quality'), findsNothing);
    },
  );

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

  testWidgets('Articles server selection saves the task connection', (
    tester,
  ) async {
    AiSettings? saved;
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
      writeAi: (next) async => saved = next,
    );
    final server = find
        .descendant(
          of: find.byKey(const ValueKey('Articles')),
          matching: find.byType(DropdownButtonFormField<String>),
        )
        .first;
    await tester.ensureVisible(server);
    await tester.tap(server);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Studio PC').last);
    await tester.pumpAndSettle();
    expect((saved!.toJson()['tasks'] as Map)['articles'], {
      'connection': 'studio',
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('server task cards show a hint when no servers exist', (
    tester,
  ) async {
    await pumpAudioSettings(
      tester,
      readAi: () async => const AiSettings(),
      writeAi: (_) async {},
    );
    expect(
      find.text('Add a server above to choose where this runs'),
      findsOneWidget,
    );
    expect(find.text('Articles'), findsNothing);
    expect(find.text('Screenshots'), findsNothing);
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
        lastSeen: DateTime.now().subtract(const Duration(minutes: 20)),
        connections: const {'studio': (reachable: false, loaded: <String>[])},
      ),
    ];
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(reads, 2);
    expect(find.text('Mac last seen 20 minutes ago (offline)'), findsOneWidget);
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

  testWidgets('mixed transcript retries a failed selected translation', (
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
            translating: const {'en': 'failed'},
            view: 'ru',
            onView: (_) {},
            onRequest: (l) => requested = l,
            canRequest: true,
          ),
        ),
      ),
    );
    expect(find.textContaining('· original'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
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
    expect(find.byIcon(Icons.translate), findsNothing);
    expect(find.text('Translate'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'RU'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'EN'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'PT'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry EN'));
    expect(requested, 'en');
  });

  testWidgets('parallel header marks the source and excludes its translation', (
    tester,
  ) async {
    String? requested;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioLanguageBar(
            selected: const ['ru', 'en', 'pt'],
            original: null,
            sourceLanguage: 'pt',
            parallel: true,
            onParallelChanged: (_) {},
            translated: const {'ru'},
            translating: const {'en': 'failed'},
            view: 'ru',
            onView: (_) {},
            onRequest: (l) => requested = l,
            canRequest: true,
          ),
        ),
      ),
    );

    expect(find.widgetWithText(ActionChip, 'PT'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'PT'), findsOneWidget);
    expect(find.byTooltip('Original'), findsOneWidget);
    expect(find.byTooltip('Side by side'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'RU'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'EN'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry EN'));
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
    'language settings stay editable and translations are always enabled',
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
      expect(find.text('Translations: ru, en, pt (always)'), findsOneWidget);
      expect(find.text('Translate automatically'), findsNothing);
      expect(find.byType(CheckboxListTile), findsOneWidget);
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
      expect(find.text('Translations: ru, en, pt (always)'), findsOneWidget);
      expect(saved!.translate, isFalse);
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

  testWidgets('audio card without waveform uses a progress bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioInlineCard(
            label: 'recording.m4a',
            peaks: const [10, 20, 30],
            readBytes: () async => throw StateError('not needed'),
            extension: 'm4a',
            onExpand: (_) async {},
            waveformAvailable: false,
          ),
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(WaveformSeekBar), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
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

  testWidgets('audio searches title and aliases and retains actions', (
    tester,
  ) async {
    var recorded = false;
    var imported = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioShelf(
            notes: const [
              NoteRef(
                id: 'audio-1',
                path: 'audio/one.typ',
                title: 'Interview',
                kind: 'audio',
                aliases: ['Alice'],
                outgoingLinks: [],
              ),
              NoteRef(
                id: 'audio-2',
                path: 'audio/two.typ',
                title: 'Lecture',
                kind: 'audio',
                outgoingLinks: [],
              ),
            ],
            onOpen: (_) {},
            onRecord: () => recorded = true,
            onImport: () => imported = true,
          ),
        ),
      ),
    );
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
