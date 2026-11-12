import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('cluster keeps labels stable and respects rejected proposals', () async {
    final vault = await Directory.systemTemp.createTemp('tylog_cluster_');
    final home = await Directory.systemTemp.createTemp('tylog_cluster_home_');
    addTearDown(() => vault.delete(recursive: true));
    addTearDown(() => home.delete(recursive: true));
    final settings = File('${vault.path}/.tylog/settings.json');
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"version":5}');

    Future<void> note(String id, String tags) async {
      final file = File('${vault.path}/notes/$id.typ');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '#import "/_system/tylog.typ" as tylog\n'
        '#show: tylog.note.with(id: "$id", title: "$id", tags: ($tags))\n\n'
        'Body\n',
      );
    }

    Future<void> write(String path, Object json) async {
      final file = File('${vault.path}/$path');
      await file.parent.create(recursive: true);
      await file.writeAsString('${jsonEncode(json)}\n');
    }

    Future<Map<String, Object?>> read(String path) async =>
        jsonDecode(await File('${vault.path}/$path').readAsString())
            as Map<String, Object?>;

    var clusterRequestCount = 0;
    Future<void> cluster() async {
      await write('_system/clusters/run-request.json', {
        'requested_at': 'test-${++clusterRequestCount}',
      });
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/tylog.dart', 'cluster', vault.path],
        environment: {'HOME': home.path},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    for (var i = 1; i <= 6; i++) {
      await note('a$i', '"ai", "llm",');
      await note('c$i', '"cooking", "food",');
    }
    await cluster();
    expect((await read('_system/clusters/snapshot.json'))['clusters'], {
      'ai': ['ai', 'llm'],
      'cooking': ['cooking', 'food'],
    });

    // "agents" now dominates the AI notes: the label stays, a rename is proposed.
    for (var i = 1; i <= 9; i++) {
      await note('a$i', '"agents", "ai", "llm",');
    }
    for (var i = 7; i <= 9; i++) {
      await note('x$i', '"agents",');
    }
    await write('_system/clusters/run-request.json', {'requested_at': 'r2'});
    await cluster();
    expect(
      ((await read('_system/clusters/snapshot.json'))['clusters'] as Map)['ai'],
      ['ai', 'llm'],
    );
    expect((await read('_system/clusters/proposals.json'))['changes'], [
      {
        'id': 'rename:ai->agents',
        'kind': 'rename',
        'from': ['ai'],
        'to': ['agents'],
      },
    ]);

    await write('_system/decisions/t.jsonl', {
      'at': '2026-11-06T17:00:00Z',
      'device': 't',
      'item': 'rename:ai->agents',
      'source': 'clusters',
      'action': 'accepted',
      'target': 'rename:ai->agents',
      'context': {},
    });
    await write('_system/clusters/run-request.json', {'requested_at': 'r3'});
    await cluster();
    expect(
      ((await read('_system/clusters/snapshot.json'))['clusters'] as Map),
      {
        'agents': ['agents', 'ai', 'llm'],
        'cooking': ['cooking', 'food'],
      },
    );
    expect((await read('_system/clusters/proposals.json'))['changes'], isEmpty);

    // Rejected changes remain unapplied and are excluded from proposals.
    await write('_system/clusters/snapshot.json', {
      'schema': 1,
      'generated_at': '2026-11-06T17:00:00Z',
      'clusters': {
        'ai': ['ai', 'llm'],
        'cooking': ['cooking', 'food'],
      },
    });
    await write('_system/decisions/t.jsonl', {
      'at': '2026-11-06T17:00:00Z',
      'device': 't',
      'item': 'rename:ai->agents',
      'source': 'clusters',
      'action': 'rejected',
      'target': 'rename:ai->agents',
      'context': {},
    });
    await write('_system/clusters/run-request.json', {'requested_at': 'r4'});
    await cluster();
    expect(
      ((await read('_system/clusters/snapshot.json'))['clusters'] as Map),
      {
        'ai': ['ai', 'llm'],
        'cooking': ['cooking', 'food'],
      },
    );
    expect((await read('_system/clusters/proposals.json'))['changes'], isEmpty);
  });
}
