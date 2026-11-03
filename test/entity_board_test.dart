import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/widgets/entity_board.dart';

void main() {
  testWidgets('dragging a card to done writes the task status', (tester) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('entity-board'),
    );
    if (dir == null) throw StateError('Could not create test vault');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    const entity = NoteRef(
      id: 'project',
      path: 'notes/project.typ',
      title: 'Project',
      outgoingLinks: [],
    );
    var source = '#tylog.task(id: "task", text: "A task", status: "todo")';
    VaultIndex makeIndex() => VaultIndex(
      notesByPath: const {'notes/project.typ': entity},
      backlinksByTarget: const {},
      tasks: [
        TaskRef(
          id: 'task',
          notePath: 'notes/project.typ',
          text: 'A task',
          status: taskField(
            locateTypstCalls(source, names: const {'tylog.task'}).first.source,
            'status',
          )!,
        ),
      ],
    );
    // Real file IO (board load) only completes inside runAsync; frames are
    // pumped outside it. No pumpAndSettle: the loading spinner never settles.
    Future<void> settleIo() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: EntityBoard(
          entity: entity,
          vault: vault,
          index: makeIndex(),
          setStatus: (task, status) async {
            source = applyTaskStatus(
              source,
              task.id,
              status,
              DateTime.utc(2026),
            );
          },
          mutateNote: (_, _) async => false,
          refreshIndex: () async => makeIndex(),
        ),
      ),
    );
    await settleIo();
    expect(find.text('A task'), findsOneWidget);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('A task')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
      tester.getBottomLeft(find.byKey(const ValueKey('board-column-done'))) +
          const Offset(100, -30),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await settleIo();
    expect(source, contains('status: "done"'));
    expect(
      await tester.runAsync(() => vault.storage.exists('boards')),
      isFalse,
    );
  });
  testWidgets('default priority is hidden and due date is shown', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('board-subtitle'),
    );
    if (dir == null) throw StateError('Could not create test vault');
    addTearDown(() => dir.delete(recursive: true));
    const entity = NoteRef(
      id: 'p',
      path: 'notes/p.typ',
      title: 'P',
      outgoingLinks: [],
    );
    const index = VaultIndex(
      notesByPath: {'notes/p.typ': entity},
      backlinksByTarget: {},
      tasks: [
        TaskRef(id: 'a', notePath: 'notes/p.typ', text: 'Ordinary'),
        TaskRef(
          id: 'b',
          notePath: 'notes/p.typ',
          text: 'Urgent',
          priority: 'high',
          due: '2026-12-01',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EntityBoard(
          entity: entity,
          vault: Vault(dir),
          index: index,
          setStatus: (_, _) async {},
          mutateNote: (_, _) async => false,
          refreshIndex: () async => index,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('normal'), findsNothing);
    expect(find.text('high · 2026-12-01'), findsOneWidget);
  });

  testWidgets('issue from descendant is shown and dragged to done', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('issue-board'),
    );
    if (dir == null) throw StateError('Could not create test vault');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    const root = NoteRef(
      id: 'root',
      path: 'notes/root.typ',
      title: 'Root',
      kind: 'project',
      outgoingLinks: [],
    );
    const child = NoteRef(
      id: 'child',
      path: 'notes/child.typ',
      title: 'Child',
      kind: 'project',
      outgoingLinks: [],
      partOf: ['root'],
    );
    const line =
        '- 14:50 #tylog.ref-note("child")[Child] #tylog.ref-note("fixit")[fixit] bug #metadata(("tylog-issue-status": "todo"))';
    await tester.runAsync(() => vault.storage.writeText('notes/log.typ', line));
    var buffer = '$line\nunsaved edit';
    VaultIndex makeIndex(String text) => VaultIndex(
      notesByPath: const {'root': root, 'child': child},
      backlinksByTarget: const {},
      issues: [
        IssueRef(
          notePath: 'notes/log.typ',
          line: 1,
          text: text,
          projectId: 'child',
          marker: 'fixit',
          status: text.contains('"done"') ? 'done' : 'todo',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EntityBoard(
          entity: root,
          vault: vault,
          index: makeIndex(line),
          setStatus: (_, _) async {},
          mutateNote: (path, transform) async {
            buffer = transform(buffer);
            await vault.storage.writeText(path, buffer);
            return true;
          },
          refreshIndex: () async {
            final next = makeIndex(
              await vault.storage.readText('notes/log.typ'),
            );
            return next;
          },
        ),
      ),
    );
    Future<void> settleIo() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    await settleIo();
    expect(find.text('fixit'), findsOneWidget);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('bug')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('board-done-0'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    // The drop does real file IO; poll the file on the real clock.
    String? result;
    for (var i = 0; i < 40; i++) {
      await settleIo();
      result = await tester.runAsync(
        () => vault.storage.readText('notes/log.typ'),
      );
      if (result?.contains('"done"') ?? false) break;
    }
    expect(result, contains('#metadata(("tylog-issue-status": "done"))'));
    expect(result, contains('unsaved edit'));
  });
  testWidgets('sends and syncs linked issues using a fake client', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('github-issue'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    final client = _FakeGitHub();
    const project = NoteRef(
      id: 'p',
      path: 'p.typ',
      title: 'P',
      kind: 'project',
      outgoingLinks: [],
      properties: {'github': 'owner/repo'},
    );
    var source = '- #tylog.ref-note("p")[P] fixit broken';
    VaultIndex makeIndex() => VaultIndex(
      notesByPath: const {'p.typ': project},
      backlinksByTarget: const {},
      issues: [
        IssueRef(
          notePath: 'log.typ',
          line: 1,
          text: source,
          projectId: 'p',
          marker: 'fixit',
          status: source.contains('"done"') ? 'done' : 'todo',
          githubNumber: source.contains('tylog-issue-gh') ? 123 : null,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EntityBoard(
          entity: project,
          vault: vault,
          index: makeIndex(),
          setStatus: (_, _) async {},
          mutateNote: (_, edit) async {
            source = edit(source);
            return true;
          },
          refreshIndex: () async => makeIndex(),
          githubClient: () async => client,
        ),
      ),
    );
    Future<void> io() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
    }

    await io();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Send to GitHub'));
      for (
        var i = 0;
        i < 200 &&
            !await vault.storage.exists('_system/decisions/github.jsonl');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(source, contains('"tylog-issue-gh": 123'));
    final log = await tester.runAsync(
      () => vault.storage.readText('_system/decisions/github.jsonl'),
    );
    expect(log, contains('owner/repo#123'));
    expect(client.labels, ['fixit']);
    client.state = 'closed';
    await tester.runAsync(() async {
      await tester.tap(find.text('Sync with GitHub'));
      for (var i = 0; i < 200 && !source.contains('"done"'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(source, contains('"tylog-issue-status": "done"'));
    client.state = 'open';
    await tester.runAsync(() async {
      await tester.tap(find.text('Sync with GitHub'));
      for (var i = 0; i < 200 && client.closed == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(client.closed, 123);
  });
}

class _FakeGitHub extends GitHubClient {
  String state = 'open';
  int? closed;
  List<String>? labels;
  @override
  Future<List<Map<String, dynamic>>> searchIssues(String repo, String marker) =>
      Future.error(StateError('Search unavailable'));

  @override
  Future<Map<String, dynamic>> createIssue(
    String repo,
    String title,
    String body,
    List<String> labels,
  ) async {
    this.labels = labels;
    return {'number': 123};
  }

  @override
  Future<Map<String, dynamic>> issue(String repo, int number) async => {
    'state': state,
  };
  @override
  Future<Map<String, dynamic>> closeIssue(String repo, int number) async {
    closed = number;
    return {};
  }
}
