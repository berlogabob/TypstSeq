import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/github/github_outbox.dart';
import 'package:tylog_core/tylog_core.dart';

class FakeClient extends GitHubClient {
  final calls = <String>[];
  final shas = <String?>[];
  final conflicts = <String>{};

  @override
  Future<String> putContent(
    String repo,
    String path,
    List<int> bytes,
    String message, {
    String? sha,
    required String branch,
  }) async {
    calls.add('$repo:$path:$branch:$message:${utf8.decode(bytes)}');
    shas.add(sha);
    if (conflicts.contains(path)) throw GitHubConflict();
    return 'new-sha';
  }

  @override
  Future<({String sha, Uint8List bytes})> getContent(
    String repo,
    String path,
    String ref,
  ) async =>
      (sha: 'remote-sha', bytes: Uint8List.fromList(utf8.encode('theirs')));
}

void main() {
  late Directory root;
  late File meta;
  late GitHubOutbox outbox;
  late FakeClient client;
  final mount = Mount(
    id: 'notes',
    name: 'Notes',
    push: true,
    source: MountSource(
      kind: 'github',
      repo: 'owner/repo',
      ref: 'main',
      subdir: 'docs',
    ),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('outbox-test');
    final cache = await Directory(
      '${root.path}/cache/notes',
    ).create(recursive: true);
    meta = File('${cache.path}/.tylog-mount.json');
    await meta.writeAsString(
      jsonEncode({
        'blobs': {'a.typ': 'old', 'b.typ': 'old'},
      }),
    );
    await File('${cache.path}/a.typ').writeAsString('mine');
    await File('${cache.path}/b.typ').writeAsString('second');
    outbox = GitHubOutbox(Directory('${root.path}/outbox'));
    client = FakeClient();
  });
  tearDown(() async => root.delete(recursive: true));

  Future<GitHubOutboxEntry> add(String path, int second) => outbox.enqueue(
    mountId: mount.id,
    path: path,
    baseSha: 'old',
    message: 'edit $path',
    device: 'device',
    at: DateTime.utc(2026, 1, 1, 0, 0, second),
  );

  test('pushes in order, prefixes paths and updates metadata', () async {
    await add('b.typ', 2);
    await add('a.typ', 1);
    expect((await outbox.entriesFor('notes')).map((e) => e.path), [
      'a.typ',
      'b.typ',
    ]);
    await outbox.pushAll(client, mount, meta);
    expect(client.calls, [
      'owner/repo:docs/a.typ:main:edit a.typ:mine',
      'owner/repo:docs/b.typ:main:edit b.typ:second',
    ]);
    expect(client.shas, ['old', 'old']);
    expect((jsonDecode(await meta.readAsString()) as Map)['blobs'], {
      'a.typ': 'new-sha',
      'b.typ': 'new-sha',
    });
    expect(await outbox.entriesFor('notes'), isEmpty);
  });

  test(
    'conflict preserves local, blocks same path and continues others',
    () async {
      await add('a.typ', 1);
      await add('a.typ', 2);
      await add('b.typ', 3);
      client.conflicts.add('docs/a.typ');
      await outbox.pushAll(client, mount, meta);
      expect(client.calls.length, 2);
      expect(await File('${meta.parent.path}/a.typ').readAsString(), 'mine');
      expect(
        await File('${meta.parent.path}/a.remote.typ').readAsString(),
        'theirs',
      );
      final entries = await outbox.entriesFor('notes');
      expect(entries.map((e) => e.state), ['conflict', 'pending']);
      client.conflicts.clear();
      await outbox.keepMine(entries.first, client, mount, meta);
      expect(client.shas.last, 'remote-sha');
      expect(await File('${meta.parent.path}/a.remote.typ').exists(), false);
      expect((await outbox.entriesFor('notes')).length, 1);
    },
  );

  test('take theirs replaces local and removes conflict', () async {
    await add('a.typ', 1);
    client.conflicts.add('docs/a.typ');
    await outbox.pushAll(client, mount, meta);
    await outbox.takeTheirs((await outbox.entriesFor('notes')).single, meta);
    expect(await File('${meta.parent.path}/a.typ').readAsString(), 'theirs');
    expect(await File('${meta.parent.path}/a.remote.typ').exists(), false);
    expect(await outbox.entriesFor('notes'), isEmpty);
    expect(
      (jsonDecode(await meta.readAsString()) as Map)['blobs']['a.typ'],
      '228068dbe790983c15535164cd483eb77ade97e4',
    );
  });
}
