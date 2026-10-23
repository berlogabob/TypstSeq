import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tylog/ai/api_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/ai/ai_settings.dart';
import 'package:tylog/ai/connection_probe.dart';
import 'package:tylog/audio/processing_policy.dart';
import 'package:tylog/widgets/ai_connections_settings.dart';
import 'package:tylog/widgets/audio_processing_settings.dart';

const studio = AiConnection(
  id: 'studio',
  label: 'Studio',
  url: 'http://studio/v1',
);

Future<ProbeResult> fakeProbe(
  String url, {
  String? key,
  String kind = 'openai-compatible',
  HttpClient? client,
}) async => const ProbeResult(
  ok: true,
  latencyMs: 12,
  models: [
    ProbeModel(id: 'llm', loaded: true, contextLength: 4096),
    ProbeModel(id: 'other', loaded: false),
  ],
);
Future<ModelTestResult> fakeTest(
  String url,
  String model, {
  String? key,
  String kind = 'openai-compatible',
  HttpClient? client,
}) async => const ModelTestResult(ok: true, reply: 'Bom dia', latencyMs: 25);

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Finder dropdown(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.decoration.labelText == label,
);
Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> pumpSection(
  WidgetTester tester, {
  AiSettings initial = const AiSettings(),
  required ValueChanged<AiSettings> onChanged,
  ServerProbe probe = fakeProbe,
  ModelTest testModel = fakeTest,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  var settings = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: AiConnectionsSection(
              settings: settings,
              probe: probe,
              testModel: testModel,
              onChanged: (next) {
                setState(() => settings = next);
                onChanged(next);
              },
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'add validates URL, normalizes, makes unique ids and omits keys',
    (tester) async {
      AiSettings? saved;
      await pumpSection(
        tester,
        initial: const AiSettings(connections: [studio]),
        onChanged: (next) => saved = next,
      );
      await tap(tester, find.text('Add server'));
      await tap(tester, find.text('Other server…'));
      await tester.enterText(field('Name'), 'Studio');
      await tester.enterText(field('Server URL'), 'ftp://studio');
      await tap(tester, find.text('Save'));
      expect(saved, isNull);
      expect(
        find.text('Enter an http or https URL with a server host'),
        findsOneWidget,
      );
      await tester.enterText(field('Server URL'), 'http://localhost:8888');
      await tester.enterText(field('API key'), 'secret');
      await tap(tester, find.text('Save'));
      expect(saved!.connections.last.id, 'studio-2');
      expect(saved!.connections.last.url, 'http://localhost:8888/v1');
      expect(saved!.toJson().toString(), isNot(contains('secret')));
    },
  );

  testWidgets(
    'Test discovers models, shows loaded state, tests selected model and remembers',
    (tester) async {
      String? testedModel;
      String? testedKey;
      await pumpSection(
        tester,
        initial: const AiSettings(connections: [studio]),
        onChanged: (_) {},
        testModel:
            (url, model, {key, kind = 'openai-compatible', client}) async {
              testedModel = model;
              testedKey = key;
              return fakeTest(url, model);
            },
      );
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      await tap(tester, find.text('Studio'));
      await tester.enterText(field('API key'), 'test-key');
      await tap(tester, find.text('Test connection'));
      expect(find.text('Reachable · 12 ms'), findsOneWidget);
      expect(find.text('llm · loaded · context 4096'), findsOneWidget);
      expect(find.text('other · not loaded'), findsOneWidget);
      await tap(tester, dropdown('Test model'));
      await tap(tester, find.text('other').last);
      await tap(tester, find.widgetWithText(TextButton, 'Test model'));
      expect(testedModel, 'other');
      expect(testedKey, 'test-key');
      expect(find.text('Bom dia · 25 ms'), findsOneWidget);
      await tap(tester, find.text('Save'));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tap(tester, find.text('Studio'));
      expect(find.text('llm · loaded · context 4096'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('API key')).controller!.text,
        'test-key',
      );
      await tap(tester, find.text('Save'));
    },
  );

  testWidgets('a cloud preset saves a cloud connection, key kept off it', (
    tester,
  ) async {
    AiSettings? saved;
    await pumpSection(
      tester,
      initial: const AiSettings(connections: [studio]),
      onChanged: (next) => saved = next,
    );
    await tap(tester, find.text('Add server'));
    await tap(tester, find.text('OpenAI (cloud)'));
    expect(
      tester.widget<TextField>(field('Server URL')).controller!.text,
      'https://api.openai.com/v1',
    );
    await tester.enterText(field('API key'), 'sk-cloud');
    await tap(tester, find.text('Save'));
    final added = saved!.connections.last;
    expect(added.cloud, isTrue);
    expect(saved!.toJson().toString(), isNot(contains('sk-cloud')));
    expect(await readApiKey(added.id), 'sk-cloud');
    expect(saved!.defaultConnection?.id, 'studio');
  });

  testWidgets('Test failures are visible', (tester) async {
    await pumpSection(
      tester,
      initial: const AiSettings(connections: [studio]),
      onChanged: (_) {},
      probe: (url, {key, kind = 'openai-compatible', client}) async =>
          const ProbeResult(ok: false, error: 'Timed out'),
    );
    await tap(tester, find.text('Studio'));
    await tap(tester, find.text('Test connection'));
    expect(find.text('Timed out'), findsOneWidget);
    await tap(tester, find.text('Save'));
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('delete requires confirmation and clears references', (
    tester,
  ) async {
    AiSettings? saved;
    await pumpSection(
      tester,
      initial: const AiSettings(
        connections: [studio],
        translate: AiTask(connection: 'studio', model: 'llm'),
      ),
      onChanged: (next) => saved = next,
    );
    await tap(tester, find.text('Studio'));
    await tap(tester, find.text('Delete'));
    expect(find.text('Delete server?'), findsOneWidget);
    expect(saved, isNull);
    await tap(tester, find.text('Cancel'));
    expect(saved, isNull);
    await tap(tester, find.text('Delete'));
    await tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    expect(saved!.connections, isEmpty);
    expect(saved!.translate.connection, isNull);
    expect(saved!.translate.model, isNull);
    expect(find.text('Studio'), findsNothing);
  });

  testWidgets(
    'translation Server and Model write and clear the contract keys',
    (tester) async {
      AiSettings? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AudioProcessingSettings(
                read: () async => const AudioPolicy(),
                write: (_) async {},
                processNow: () async {},
                readAi: () async => const AiSettings(
                  connections: [studio],
                  translate: AiTask(model: 'explicit'),
                ),
                writeAi: (next) async => saved = next,
                readWorkers: () async => [
                  WorkerStatus(
                    host: 'Mac',
                    lastSeen: DateTime.now(),
                    connections: const {
                      'studio': (reachable: true, loaded: ['llm']),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, dropdown('Server').first);
      await tap(tester, find.text('Studio').last);
      expect(saved!.translate.connection, 'studio');
      expect(saved!.translate.model, 'explicit');
      tester
          .widget<AiConnectionsSection>(find.byType(AiConnectionsSection))
          .onModelsChanged!('studio', const [ProbeModel(id: 'discovered')]);
      await tester.pump();
      await tap(tester, dropdown('Model').first);
      expect(find.text('discovered'), findsWidgets);
      expect(find.text('explicit'), findsWidgets);
      await tap(tester, find.text('llm').last);
      expect(saved!.toJson()['tasks'], {
        'articles': {},
        'screenshots': {},
        'enrich': {},
        'transcribe': {'quality': 'best'},
        'translate': {
          'quality': 'best',
          'connection': 'studio',
          'model': 'llm',
        },
      });
      await tap(tester, dropdown('Model').first);
      await tap(tester, find.text('Auto (ollama/ornith-1.5:35b)').last);
      expect(saved!.translate.model, isNull);
      await tap(tester, dropdown('Server').first);
      await tap(tester, find.text('Default (worker config)').last);
      expect(saved!.translate.connection, isNull);
      expect(saved!.translate.toJson(), {'quality': 'best'});
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
