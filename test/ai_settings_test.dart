import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/ai/ai_settings.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('model profiles and explicit overrides match the worker contract', () {
    for (final (quality, whisper, translate) in [
      ('fast', 'small', 'ollama/ornith-1.5:9b'),
      ('balanced', 'large-v3-turbo', 'ollama/ornith-1.5:35b'),
      ('best', 'large-v3', 'ollama/ornith-1.5:35b'),
    ]) {
      expect(whisperModelFor(AiTask(quality: quality)), whisper);
      expect(translateModelFor(AiTask(quality: quality)), translate);
      final override = AiTask(quality: quality, model: 'custom/model');
      expect(whisperModelFor(override), 'custom/model');
      expect(translateModelFor(override), 'custom/model');
    }
  });

  late Directory dir;
  late LocalVaultStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tylog_ai_');
    storage = LocalVaultStorage(dir);
    addTearDown(() => dir.delete(recursive: true));
  });

  test(
    'missing and corrupt settings mean best quality with no overrides',
    () async {
      expect((await readAiSettings(storage)).toJson(), {
        'schema': 1,
        'connections': [],
        'tasks': {
          'transcribe': {'quality': 'best'},
          'translate': {'quality': 'best'},
        },
      });
      await storage.createDirectory('_system/settings');
      await storage.writeText(aiSettingsPath, '{bad');
      expect(
        (await readAiSettings(storage)).toJson(),
        const AiSettings().toJson(),
      );
      await storage.writeText(aiSettingsPath, '[]');
      expect(
        (await readAiSettings(storage)).toJson(),
        const AiSettings().toJson(),
      );
    },
  );

  test(
    'settings tolerate wrong types and drop connections without id or url',
    () {
      for (final json in [
        null,
        [],
        7,
        {},
        {'connections': false, 'tasks': []},
      ]) {
        expect(AiSettings.fromJson(json).toJson(), const AiSettings().toJson());
      }
      final settings = AiSettings.fromJson({
        'connections': [
          null,
          {'id': 'missing-url'},
          {'url': 'http://localhost/v1'},
          {'id': 7, 'url': 'http://localhost/v1'},
          {'id': 'studio', 'url': false},
          {'id': '', 'url': 'http://localhost/v1'},
          {'id': 'studio', 'url': ' '},
          {
            'id': 'studio',
            'url': 'http://localhost/v1',
            'kind': 7,
            'label': [],
          },
        ],
        'tasks': {
          'transcribe': {'quality': 'unknown', 'model': 7, 'connection': false},
          'translate': {
            'quality': 'balanced',
            'model': 'llm',
            'connection': 'studio',
          },
        },
      });
      expect(settings.connections.single.toJson(), {
        'id': 'studio',
        'kind': 'openai-compatible',
        'label': '',
        'url': 'http://localhost/v1',
      });
      expect(settings.transcribe.toJson(), {'quality': 'best'});
      expect(settings.translate.toJson(), {
        'quality': 'balanced',
        'model': 'llm',
        'connection': 'studio',
      });
      for (final quality in ['fast', 'balanced', 'best']) {
        expect(AiTask.fromJson({'quality': quality}).quality, quality);
      }
      expect(AiTask.fromJson({'quality': 7}).quality, 'best');
    },
  );

  test('round trip keeps other keys and the worker contract names', () async {
    const settings = AiSettings(
      connections: [
        AiConnection(
          id: 'studio',
          label: 'Studio PC',
          url: 'http://desktop:8888/v1',
        ),
      ],
      transcribe: AiTask(quality: 'fast', model: 'small'),
      translate: AiTask(connection: 'studio'),
    );
    await writeAiSettings(storage, settings);
    await storage.writeText(
      aiSettingsPath,
      jsonEncode({
        ...settings.toJson(),
        'other': {'enabled': true},
      }),
    );
    await writeAiSettings(storage, settings);
    final raw = jsonDecode(await storage.readText(aiSettingsPath)) as Map;
    expect(raw, {
      'schema': 1,
      'other': {'enabled': true},
      'connections': [
        {
          'id': 'studio',
          'kind': 'openai-compatible',
          'label': 'Studio PC',
          'url': 'http://desktop:8888/v1',
        },
      ],
      'tasks': {
        'transcribe': {'quality': 'fast', 'model': 'small'},
        'translate': {'quality': 'best', 'connection': 'studio'},
      },
    });
    expect((await readAiSettings(storage)).toJson(), settings.toJson());
  });

  test('copyWith retains values and can clear nullable overrides', () {
    const task = AiTask(quality: 'fast', model: 'small', connection: 'studio');
    expect(task.copyWith().toJson(), task.toJson());
    expect(task.copyWith(quality: 'balanced').model, 'small');
    expect(task.copyWith(model: null, connection: null).toJson(), {
      'quality': 'fast',
    });
    expect(task.copyWith(model: 'large', connection: 'other').toJson(), {
      'quality': 'fast',
      'model': 'large',
      'connection': 'other',
    });
    const connection = AiConnection(
      id: 'studio',
      label: 'PC',
      url: 'http://localhost',
    );
    expect(connection.copyWith().toJson(), connection.toJson());
    expect(
      connection
          .copyWith(
            id: 'other',
            kind: 'ollama',
            label: 'Laptop',
            url: 'http://other',
          )
          .toJson(),
      {
        'id': 'other',
        'kind': 'ollama',
        'label': 'Laptop',
        'url': 'http://other',
      },
    );
    final settings = const AiSettings().copyWith(
      connections: [connection],
      transcribe: task,
      translate: task,
    );
    expect(settings.copyWith().toJson(), settings.toJson());
    expect(
      settings.copyWith(connections: [], translate: const AiTask()).connections,
      isEmpty,
    );
    expect(
      settings.copyWith(translate: const AiTask()).transcribe.model,
      'small',
    );
  });

  test(
    'workers reading skips corrupt files and non-heartbeat entries',
    () async {
      expect(await readWorkers(storage), isEmpty);
      await storage.createDirectory('_system/workers/nested.json');
      for (final host in ['desktop', 'laptop']) {
        await storage.writeText(
          '_system/workers/$host.json',
          jsonEncode({
            'host': host,
            'last_seen': '2026-10-14T12:00:00Z',
            'whisper_models': ['small', 'large-v3'],
            'connections': {
              'studio': {
                'reachable': true,
                'loaded': ['llm'],
              },
            },
          }),
        );
      }
      await storage.writeText('_system/workers/broken.json', '{bad');
      await storage.writeText('_system/workers/list.json', '[]');
      await storage.writeText('_system/workers/ignored.txt', '{}');
      await storage.writeText('_system/workers/nested.json/ignored.json', '{}');
      final workers = await readWorkers(storage);
      expect(
        workers.map((worker) => worker.host),
        unorderedEquals(['desktop', 'laptop']),
      );
      for (final worker in workers) {
        expect(worker.lastSeen, DateTime.utc(2026, 10, 14, 12));
        expect(worker.whisperModels, ['small', 'large-v3']);
        expect(worker.connections['studio']!.reachable, isTrue);
        expect(worker.connections['studio']!.loaded, ['llm']);
      }
    },
  );

  test('worker parsing tolerates wrong types and invalid timestamps', () {
    for (final json in [null, [], 7, {}]) {
      final worker = WorkerStatus.fromJson(json);
      expect(worker.host, '');
      expect(worker.lastSeen, isNull);
      expect(worker.whisperModels, isEmpty);
      expect(worker.connections, isEmpty);
    }
    final worker = WorkerStatus.fromJson({
      'host': false,
      'last_seen': 'bad',
      'whisper_models': ['small', 7],
      'connections': {
        'studio': {
          'reachable': 'true',
          'loaded': ['llm', false],
        },
        'empty': {'reachable': true, 'loaded': 7},
        'bad': 7,
        7: {},
      },
    });
    expect(worker.host, '');
    expect(worker.lastSeen, isNull);
    expect(worker.whisperModels, ['small']);
    expect(worker.connections.keys, unorderedEquals(['studio', 'empty']));
    expect(worker.connections['studio']!.reachable, isFalse);
    expect(worker.connections['studio']!.loaded, ['llm']);
    expect(worker.connections['empty']!.reachable, isTrue);
    expect(worker.connections['empty']!.loaded, isEmpty);
    final wrongTypes = WorkerStatus.fromJson({
      'last_seen': 7,
      'whisper_models': false,
      'connections': [],
    });
    expect(wrongTypes.lastSeen, isNull);
    expect(wrongTypes.whisperModels, isEmpty);
    expect(wrongTypes.connections, isEmpty);
  });

  test(
    'online includes the boundary and excludes stale or future heartbeats',
    () {
      final seen = DateTime.utc(2026, 10, 14, 12);
      final worker = WorkerStatus(lastSeen: seen);
      expect(const WorkerStatus().isOnline(now: seen), isFalse);
      expect(worker.isOnline(now: seen), isTrue);
      expect(
        worker.isOnline(now: seen.add(const Duration(minutes: 5))),
        isTrue,
      );
      expect(
        worker.isOnline(
          now: seen.add(const Duration(minutes: 5, microseconds: 1)),
        ),
        isFalse,
      );
      expect(
        worker.isOnline(now: seen.subtract(const Duration(microseconds: 1))),
        isFalse,
      );
      expect(
        worker.isOnline(
          within: const Duration(seconds: 30),
          now: seen.add(const Duration(seconds: 30)),
        ),
        isTrue,
      );
      expect(
        worker.isOnline(
          within: const Duration(seconds: 30),
          now: seen.add(const Duration(seconds: 31)),
        ),
        isFalse,
      );
      expect(
        worker.isOnline(now: DateTime.parse('2026-10-14T13:05:00+01:00')),
        isTrue,
      );
    },
  );
}
