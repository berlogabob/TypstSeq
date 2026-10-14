import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/ai/ai_settings.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('presets require matching qualities and no model overrides', () {
    expect(const AiSettings().preset, AiPreset.best);
    for (final transcribe in ['fast', 'balanced', 'best']) {
      for (final translate in ['fast', 'balanced', 'best']) {
        final settings = AiSettings(
          transcribe: AiTask(quality: transcribe, connection: 'a'),
          translate: AiTask(quality: translate, connection: 'b'),
        );
        expect(
          settings.preset,
          transcribe == translate && transcribe == 'fast'
              ? AiPreset.light
              : transcribe == translate && transcribe == 'best'
              ? AiPreset.best
              : null,
        );
        expect(
          settings.copyWith(
            transcribe: settings.transcribe.copyWith(model: 'custom'),
          ).preset,
          isNull,
        );
        expect(
          settings.copyWith(
            translate: settings.translate.copyWith(model: 'custom'),
          ).preset,
          isNull,
        );
      }
    }
  });

  test('applying presets clears models and keeps connections', () {
    const settings = AiSettings(
      connections: [AiConnection(id: 'a', url: 'http://a/v1')],
      transcribe: AiTask(quality: 'balanced', model: 'whisper', connection: 'a'),
      translate: AiTask(model: 'llm', connection: 'b'),
    );
    for (final preset in AiPreset.values) {
      final next = settings.withPreset(preset);
      final quality = preset == AiPreset.light ? 'fast' : 'best';
      expect(next.preset, preset);
      expect(next.connections, same(settings.connections));
      expect(next.transcribe.toJson(), {'quality': quality, 'connection': 'a'});
      expect(next.translate.toJson(), {'quality': quality, 'connection': 'b'});
      expect(next.withPreset(preset).toJson(), next.toJson());
    }
    expect(settings.transcribe.model, 'whisper');
    expect(settings.translate.model, 'llm');
  });

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

  test('upsert preserves order and remove clears referencing tasks', () {
    const a = AiConnection(id: 'a', label: 'A', url: 'http://a/v1');
    const b = AiConnection(id: 'b', url: 'http://b/v1');
    final settings = const AiSettings(
      connections: [a],
      transcribe: AiTask(connection: 'a', model: 'small', quality: 'fast'),
      translate: AiTask(connection: 'b', model: 'llm'),
      articles: AiServerTask(connection: 'a', model: 'article/model'),
      screenshots: AiServerTask(connection: 'b', model: 'vision/model'),
    ).upsertConnection(b).upsertConnection(a.copyWith(label: 'Updated'));
    expect(settings.connections.map((c) => c.id), ['a', 'b']);
    expect(settings.connections.first.label, 'Updated');
    final removed = settings.removeConnection('a');
    expect(removed.connections.single.id, 'b');
    expect(removed.articles.toJson(), isEmpty);
    expect(removed.screenshots.toJson(), settings.screenshots.toJson());
    expect(settings.removeConnection('b').screenshots.toJson(), isEmpty);
    expect(removed.transcribe.toJson(), {'quality': 'fast'});
    expect(removed.translate.toJson(), settings.translate.toJson());
    expect(settings.removeConnection('b').translate.toJson(), {
      'quality': 'best',
    });
  });

  test('URLs require http and a host, normalization keeps explicit paths', () {
    for (final url in ['', 'localhost:8080', 'ftp://host', 'http:///']) {
      expect(validateConnectionUrl(url), isNotNull);
    }
    for (final url in [
      'http://host',
      'https://host/v1/',
      'http://localhost:8080/api',
    ]) {
      expect(validateConnectionUrl(url), isNull);
    }
    expect(normalizeConnectionUrl(' http://host '), 'http://host/v1');
    expect(normalizeConnectionUrl('http://host/'), 'http://host/v1');
    expect(normalizeConnectionUrl('https://host/api/'), 'https://host/api');
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
          'articles': {},
          'screenshots': {},
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

  test('AI settings use priority reads and tolerate corrupt data', () async {
    final priority = _PriorityOnlyStorage(dir);
    expect(
      (await readAiSettings(priority)).toJson(),
      const AiSettings().toJson(),
    );
    const settings = AiSettings(
      connections: [
        AiConnection(id: 'pc', label: 'Компьютер', url: 'http://pc/v1'),
      ],
      transcribe: AiTask(quality: 'fast'),
    );
    await writeAiSettings(storage, settings);
    expect((await readAiSettings(priority)).toJson(), settings.toJson());
    await storage.writeText(aiSettingsPath, '{bad');
    expect(
      (await readAiSettings(priority)).toJson(),
      const AiSettings().toJson(),
    );
  });

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
      articles: AiServerTask(connection: 'studio', model: 'article/model'),
      screenshots: AiServerTask(connection: 'studio', model: 'vision/model'),
    );
    await writeAiSettings(storage, settings);
    await storage.writeText(
      aiSettingsPath,
      jsonEncode({
        ...settings.toJson(),
        'other': {'enabled': true},
        'tasks': {
          'articles': {
            'connection': 'old',
            'model': 'old/model',
            'fallback_model': 'fallback/model',
          },
          'screenshots': {'connection': 'old', 'custom': true},
          'future_task': {'enabled': true},
          'transcribe': {'quality': 'best', 'unknown': true},
          'translate': {'quality': 'fast', 'unknown': true},
        },
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
        'articles': {
          'connection': 'studio',
          'model': 'article/model',
          'fallback_model': 'fallback/model',
        },
        'screenshots': {
          'connection': 'studio',
          'model': 'vision/model',
          'custom': true,
        },
        'future_task': {'enabled': true},
        'transcribe': {'quality': 'fast', 'model': 'small'},
        'translate': {'quality': 'best', 'connection': 'studio'},
      },
    });
    expect((await readAiSettings(storage)).toJson(), settings.toJson());
    await writeAiSettings(storage, settings.removeConnection('studio'));
    final cleared = jsonDecode(await storage.readText(aiSettingsPath)) as Map;
    expect(cleared['tasks']['articles'], {'fallback_model': 'fallback/model'});
    expect(cleared['tasks']['screenshots'], {'custom': true});
    expect(cleared['other'], {'enabled': true});
  });

  test('server tasks round trip, tolerate invalid data and clear overrides', () {
    const task = AiServerTask(connection: 'studio', model: 'custom/model');
    expect(AiServerTask.fromJson(task.toJson()).toJson(), task.toJson());
    expect(task.copyWith().toJson(), task.toJson());
    expect(task.copyWith(connection: null, model: null).toJson(), isEmpty);
    for (final value in [null, [], 7, {'connection': false, 'model': 7}]) {
      expect(AiServerTask.fromJson(value).toJson(), isEmpty);
    }
    const settings = AiSettings(articles: task, screenshots: task);
    expect(settings.copyWith().toJson(), settings.toJson());
    expect(settings.withPreset(AiPreset.light).articles, same(task));
    expect(settings.withPreset(AiPreset.light).screenshots, same(task));
    expect(AiSettings.fromJson(settings.toJson()).toJson(), settings.toJson());
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
      final priority = _PriorityOnlyStorage(dir);
      expect(await readWorkers(priority), isEmpty);
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
      final workers = await readWorkers(priority);
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

class _PriorityOnlyStorage extends LocalVaultStorage {
  _PriorityOnlyStorage(super.root);

  @override
  Future<bool> exists(String path) => throw StateError('Queued exists');

  @override
  Future<String> readText(String path) => throw StateError('Queued readText');

  @override
  Future<Uint8List> readBytes(String path) => throw StateError('Queued read');

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) => throw StateError('Queued list');

  @override
  Future<bool> existsNow(String path) => super.exists(path);

  @override
  Future<Uint8List> readBytesNow(String path) => super.readBytes(path);

  @override
  Future<List<VaultStorageEntry>> listNow({String path = ''}) =>
      super.list(path: path);
}
