import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

class _MemoryStorage extends VaultStorage {
  final files = <String, Uint8List>{};
  @override
  Future<bool> exists(String path) async => files.containsKey(path);
  @override
  Future<Uint8List> readBytes(String path) async => files[path]!;
  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async => [
    for (final key in files.keys.toList().reversed)
      if (key.startsWith('$path/') &&
          (recursive || !key.substring(path.length + 1).contains('/')))
        VaultStorageEntry(path: key, isDirectory: false),
  ];
  @override
  Future<void> createDirectory(String path) async {}
  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }

  @override
  Future<VaultStorageEntry?> stat(String path) async => null;
  @override
  Future<String> hash(String path) => throw UnimplementedError();
}

void main() {
  const notePath = 'daily/2026/10/2026-10-01.typ';
  final notes = [
    for (final (id, title, kind, path) in [
      ('day', 'Day', 'daily', notePath),
      ('silva', 'André Silva', 'person', 'notes/silva.typ'),
      ('costa', 'André Costa', 'person', 'notes/costa.typ'),
    ])
      NoteRef(
        id: id,
        title: title,
        kind: kind,
        path: path,
        outgoingLinks: const [],
      ),
  ];
  final index = VaultIndex(
    notesByPath: {for (final n in notes) n.path: n},
    backlinksByTarget: const {},
  );
  late _MemoryStorage storage;
  final gold = jsonEncode({
    'note': notePath,
    'surface': 'André',
    'entity': 'silva',
  });

  Future<void> ledger(String note) => storage.writeText(
    '$enrichFeedbackDir/device.jsonl',
    [
      for (final (entity, decision) in [
        ('silva', 'accept'),
        ('costa', 'reject'),
      ])
        jsonEncode({
          'note': note,
          'surface': 'André',
          'entity': entity,
          'decision': decision,
          'at': '2026-10-01',
          'context': [],
        }),
    ].join('\n'),
  );

  setUp(() async {
    storage = _MemoryStorage();
    await storage.writeBytes(
      TylogVaultPaths.index,
      encodeVaultIndexBytes(index),
    );
    await storage.writeText(
      enrichMentionsPath(notePath),
      jsonEncode({
        'schema': 1,
        'note': notePath,
        'content_sha': 'fixture',
        'mentions': [
          {'surface': 'André', 'type': 'person', 'line': 1},
          {'surface': 'André', 'type': 'person', 'line': 2},
          {'surface': 'Nobody', 'type': 'person', 'line': 3},
          {'surface': 'André Silva', 'type': 'person', 'line': 4},
        ],
      }),
    );
  });

  test('held-out ledger turns ambiguous review into a correct link', () async {
    await ledger('daily/other.typ');
    final report = await evaluateLinks(storage, index, gold);
    expect(
      report,
      contains('| Empty ledger | 1 | 0 | 0 | 1 | 0 | n/a | 0.0000 | 0.0000 |'),
    );
    expect(
      report,
      contains(
        '| Held-out ledger | 1 | 1 | 0 | 0 | 0 | 1.0000 | 1.0000 | 1.0000 |',
      ),
    );
  });

  test(
    'own note+surface feedback is excluded, including folded surfaces',
    () async {
      await ledger(notePath);
      final report = await evaluateLinks(storage, index, gold);
      expect(report, contains('| Held-out ledger | 1 | 0 | 0 | 1 | 0 |'));
      await storage.writeText(
        '$enrichFeedbackDir/second.jsonl',
        jsonEncode({
          'note': notePath,
          'surface': 'ANDRE',
          'entity': 'silva',
          'decision': 'accept',
        }),
      );
      expect(
        await evaluateLinks(storage, index, gold),
        contains('| Held-out ledger | 1 | 0 | 0 | 1 | 0 |'),
      );
    },
  );

  test('none, proposals, empty gold and unlabelled rows', () async {
    final rows = [
      {'note': notePath, 'surface': 'Nobody', 'entity': 'none'},
      {'note': notePath, 'surface': 'André Silva', 'entity': 'none'},
    ];
    expect(
      await evaluateLinks(storage, index, rows.map(jsonEncode).join('\n')),
      contains(
        '| Empty ledger | 2 | 0 | 1 | 0 | 1 | 0.0000 | 0.5000 | 0.0000 |',
      ),
    );
    expect(
      await evaluateLinks(storage, index, ''),
      contains('| Empty ledger | 0 | 0 | 0 | 0 | 0 | n/a | n/a | n/a |'),
    );
    await expectLater(
      evaluateLinks(
        storage,
        index,
        jsonEncode({'note': notePath, 'surface': 'André', 'entity': null}),
      ),
      throwsFormatException,
    );
    await expectLater(
      evaluateLinks(storage, index, gold.replaceFirst('André', 'Missing')),
      throwsFormatException,
    );
  });

  test(
    'samples are deterministic, unique, labelled null, and contain candidates',
    () async {
      final first = await sampleLinks(storage, index, 3);
      final entries = storage.files.entries.toList().reversed.toList();
      storage.files
        ..clear()
        ..addEntries(entries);
      expect(await sampleLinks(storage, index, 3), first);
      expect(first.map((r) => r['surface']).toSet(), hasLength(3));
      final andre = first.singleWhere((r) => r['surface'] == 'André');
      expect(andre, {
        'note': notePath,
        'surface': 'André',
        'type': 'person',
        'candidates': ['silva', 'costa'],
        'entity': null,
      });
      await expectLater(sampleLinks(storage, index, 4), throwsStateError);
    },
  );

  test(
    'CLI dispatch samples without reading gold and evaluates a saved index',
    () async {
      final root = await Directory.systemTemp.createTemp('eval_links_');
      addTearDown(() => root.delete(recursive: true));
      for (final entry in storage.files.entries) {
        final file = File('${root.path}/${entry.key}');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value);
      }
      final out = '${root.path}/labels.jsonl';
      final sample = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/tylog.dart',
        'eval-links',
        '--vault',
        root.path,
        '--gold',
        'does-not-exist',
        '--sample',
        '2',
        '--out',
        out,
      ]);
      expect(sample.exitCode, 0, reason: '${sample.stderr}');
      expect(
        const LineSplitter().convert(await File(out).readAsString()),
        hasLength(2),
      );
      await File(out).writeAsString(gold);
      final eval = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/tylog.dart',
        'eval-links',
        '--vault',
        root.path,
        '--gold',
        out,
      ]);
      expect(eval.exitCode, 0, reason: '${eval.stderr}');
      expect(eval.stdout, contains('| Empty ledger | 1 | 0 | 0 | 1 |'));
    },
  );
}
