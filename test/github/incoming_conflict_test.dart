import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/github/github_outbox.dart';
import 'package:tylog/widgets/screenshot_strip.dart';
import 'package:tylog_core/tylog_core.dart';

class FakeClient extends GitHubClient {
  int puts = 0;
  @override
  Future<({String sha, Uint8List bytes})> getContent(
    String repo,
    String path,
    String ref,
  ) async => (sha: 'remote', bytes: Uint8List.fromList(utf8.encode('theirs')));
  @override
  Future<String> putContent(
    String repo,
    String path,
    List<int> bytes,
    String message, {
    String? sha,
    required String branch,
  }) async {
    puts++;
    return 'new';
  }
}

void main() {
  for (final action in ['Keep mine', 'Take theirs']) {
    testWidgets('$action resolves an incoming conflict', (tester) async {
      late Directory root;
      late File meta;
      late GitHubOutbox outbox;
      late GitHubOutboxEntry entry;
      final client = FakeClient();
      final mount = Mount(
        id: 'notes',
        name: 'Notes',
        push: true,
        source: MountSource(kind: 'github', repo: 'owner/repo', ref: 'main'),
      );
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('incoming-conflict');
        final cache = await Directory('${root.path}/cache').create();
        meta = File('${cache.path}/.tylog-mount.json');
        await meta.writeAsString(
          jsonEncode({
            'blobs': {'a.typ': 'old'},
          }),
        );
        await File('${cache.path}/a.typ').writeAsString('mine');
        await File('${cache.path}/a.remote.typ').writeAsString('theirs');
        outbox = GitHubOutbox(Directory('${root.path}/outbox'));
        final pending = await outbox.enqueue(
          mountId: 'notes',
          path: 'a.typ',
          baseSha: 'old',
          message: 'edit',
          device: 'device',
        );
        final json = pending.toJson()..['state'] = 'conflict';
        await File(
          '${root.path}/outbox/notes/${pending.id}.json',
        ).writeAsString(jsonEncode(json));
        entry = (await outbox.entriesFor('notes')).single;
      });
      var notes = githubConflictNotes([entry]);
      expect(notes.single.title, 'GitHub conflict: a.typ');
      Future<dynamic>? decision;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return ScreenshotStrip(
                  index: null,
                  day: '2026-11-03',
                  onOpenPath: (_) {},
                  incoming: true,
                  external: notes,
                  onDecide: (_, choice) {
                    decision = tester.runAsync(() async {
                      if (choice == 'keep-mine') {
                        await outbox.keepMine(entry, client, mount, meta);
                      } else {
                        await outbox.takeTheirs(entry, meta);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.longPress(find.text('GitHub conflict: a.typ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(action));
      await tester.pump();
      expect(decision, isNotNull);
      await decision;
      await tester.runAsync(() async {
        expect(await outbox.entriesFor('notes'), isEmpty);
        expect(
          await File('${meta.parent.path}/a.typ').readAsString(),
          action == 'Keep mine' ? 'mine' : 'theirs',
        );
        notes = githubConflictNotes(await outbox.entriesFor('notes'));
        await root.delete(recursive: true);
      });
      update(() {});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('GitHub conflict: a.typ'), findsNothing);
      expect(client.puts, action == 'Keep mine' ? 1 : 0);
    });
  }
}
