import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

NoteRef _note(String id, List<String> tags) => NoteRef(
  id: id,
  path: '$id.typ',
  title: id,
  outgoingLinks: const [],
  tags: tags,
);

VaultIndex _index({required bool renamed}) => VaultIndex(
  notesByPath: {
    for (var i = 1; i <= 9; i++)
      'a$i.typ': _note(
        'a$i',
        renamed ? ['agents', 'ai', 'llm'] : ['ai', 'llm'],
      ),
    for (var i = 1; i <= 6; i++) 'c$i.typ': _note('c$i', ['cooking', 'food']),
    if (renamed)
      for (var i = 7; i <= 9; i++) 'x$i.typ': _note('x$i', ['agents']),
  },
  backlinksByTarget: const {},
);

void main() {
  test('applies accepted changes and omits rejected proposals', () async {
    final root = await Directory.systemTemp.createTemp('tylog_cluster_step_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await runClusterStep(
      storage,
      _index(renamed: false),
      now: DateTime.utc(2026),
    );
    await runClusterStep(
      storage,
      _index(renamed: true),
      now: DateTime.utc(2026, 1, 2),
    );
    var snapshot =
        jsonDecode(await storage.readText('_system/clusters/snapshot.json'))
            as Map;
    expect((snapshot['clusters'] as Map).containsKey('ai'), isTrue);
    expect(
      (jsonDecode(await storage.readText('_system/clusters/proposals.json'))
          as Map)['changes'],
      hasLength(1),
    );

    await storage.writeText(
      '_system/decisions/accepted.jsonl',
      jsonEncode({
        'source': 'clusters',
        'action': 'accepted',
        'target': 'rename:ai->agents',
      }),
    );
    await runClusterStep(
      storage,
      _index(renamed: true),
      now: DateTime.utc(2026, 1, 3),
    );
    snapshot =
        jsonDecode(await storage.readText('_system/clusters/snapshot.json'))
            as Map;
    expect((snapshot['clusters'] as Map).containsKey('agents'), isTrue);

    await storage.writeText(
      '_system/clusters/snapshot.json',
      jsonEncode({
        'schema': 1,
        'generated_at': '2026-01-01T00:00:00Z',
        'clusters': {
          'ai': ['ai', 'llm'],
          'cooking': ['cooking', 'food'],
        },
      }),
    );
    await storage.writeText(
      '_system/decisions/accepted.jsonl',
      jsonEncode({
        'source': 'clusters',
        'action': 'rejected',
        'target': 'rename:ai->agents',
      }),
    );
    await runClusterStep(
      storage,
      _index(renamed: true),
      now: DateTime.utc(2026, 1, 4),
    );
    snapshot =
        jsonDecode(await storage.readText('_system/clusters/snapshot.json'))
            as Map;
    expect((snapshot['clusters'] as Map).containsKey('ai'), isTrue);
    expect(
      (jsonDecode(await storage.readText('_system/clusters/proposals.json'))
          as Map)['changes'],
      isEmpty,
    );
  });

  test('drops a previous label for a tag no longer in any cluster', () async {
    final root = await Directory.systemTemp.createTemp('tylog_cluster_step_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText(
      '_system/clusters/snapshot.json',
      jsonEncode({
        'schema': 1,
        'generated_at': '2026-01-01T00:00:00Z',
        'clusters': {
          'journal': ['journal', 'ai', 'llm'],
        },
      }),
    );
    await runClusterStep(
      storage,
      _index(renamed: false),
      now: DateTime.utc(2026, 1, 2),
    );
    final snapshot =
        jsonDecode(await storage.readText('_system/clusters/snapshot.json'))
            as Map;
    expect((snapshot['clusters'] as Map).containsKey('journal'), isFalse);
    expect(
      (snapshot['clusters'] as Map).values.any(
        (members) => members.contains('ai') && members.contains('llm'),
      ),
      isTrue,
    );
  });
}
