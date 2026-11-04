import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/widgets/entity_board.dart';
import 'package:tylog/widgets/unified_board.dart';

void main() {
  testWidgets('large columns build cards lazily and scroll to the end', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('large-board'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => dir.delete(recursive: true));
    const entity = NoteRef(
      id: 'p',
      path: 'p.typ',
      title: 'P',
      outgoingLinks: [],
    );
    final index = VaultIndex(
      notesByPath: const {'p.typ': entity},
      backlinksByTarget: const {},
      tasks: [
        for (var i = 0; i < 100; i++)
          TaskRef(id: '$i', notePath: 'p.typ', text: 'Task $i'),
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
    expect(find.text('Task 0'), findsOneWidget);
    expect(find.text('Task 99', skipOffstage: false), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Task 99'),
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('board-column-todo')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Task 99'), findsOneWidget);
  });
  testWidgets('reordering tasks persists and reloads their order', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('ordered-board'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    const entity = NoteRef(
      id: 'p',
      path: 'p.typ',
      title: 'P',
      outgoingLinks: [],
    );
    const index = VaultIndex(
      notesByPath: {'p.typ': entity},
      backlinksByTarget: {},
      tasks: [
        TaskRef(id: 'a', notePath: 'p.typ', text: 'First task'),
        TaskRef(id: 'b', notePath: 'p.typ', text: 'Second task'),
      ],
    );
    Widget view() => MaterialApp(
      home: EntityBoard(
        boardId: 'order',
        entity: entity,
        vault: vault,
        index: index,
        setStatus: (_, _) async {},
        mutateNote: (_, _) async => false,
        refreshIndex: () async => index,
      ),
    );
    Future<void> io() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
    }

    await tester.pumpWidget(view());
    await io();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('First task')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
      tester.getBottomLeft(find.byKey(const ValueKey('board-column-todo'))) +
          const Offset(100, -30),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await io();
      if (await tester.runAsync(
            () => vault.storage.exists(boardPath('order')),
          ) ==
          true)
        break;
    }
    final saved = await tester.runAsync(
      () => readBoard(vault.storage, 'order'),
    );
    expect(saved?.order['todo'], ['b', 'a']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(view());
    for (
      var i = 0;
      i < 10 && find.text('Second task').evaluate().isEmpty;
      i++
    ) {
      await io();
    }
    expect(
      tester.getTopLeft(find.text('Second task')).dy,
      lessThan(tester.getTopLeft(find.text('First task')).dy),
    );
  });

  testWidgets(
    'repository setting persists and displays refreshed GitHub issues',
    (tester) async {
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('repo-board'),
      );
      if (dir == null) throw StateError('No temp directory');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(dir);
      final client = _FakeGitHub();
      const entity = NoteRef(
        id: 'p',
        path: 'p.typ',
        title: 'P',
        outgoingLinks: [],
      );
      const index = VaultIndex(
        notesByPath: {'p.typ': entity},
        backlinksByTarget: {},
      );
      Widget view() => MaterialApp(
        home: EntityBoard(
          entity: entity,
          vault: vault,
          index: index,
          setStatus: (_, _) async {},
          mutateNote: (_, _) async => false,
          refreshIndex: () async => index,
          githubClient: () async => client,
        ),
      );
      Future<void> io() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump();
      }

      await tester.pumpWidget(view());
      await io();
      await tester.tap(find.byTooltip('GitHub repository'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'owner/repo');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 20 && find.text('Remote issue').evaluate().isEmpty;
        i++
      ) {
        await io();
      }
      expect(find.text('Remote issue'), findsOneWidget);
      expect(client.repo, 'owner/repo');
      client.remoteTitle = 'Refreshed issue';
      await tester.tap(find.byTooltip('Sync with GitHub'));
      await io();
      expect(find.text('Refreshed issue'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view());
      for (
        var i = 0;
        i < 20 && find.text('Refreshed issue').evaluate().isEmpty;
        i++
      ) {
        await io();
      }
      expect(find.text('Refreshed issue'), findsOneWidget);
    },
  );

  testWidgets('repository board controls fit and refresh at 360 dp', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('phone-repo-board'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await tester.runAsync(
      () => writeBoard(
        vault.storage,
        Board.fromJson({
          'id': 'board',
          'title': 'P',
          'scopeEntity': 'p',
          'github_repo': 'owner/repo',
        }),
      ),
    );
    const entity = NoteRef(
      id: 'p',
      path: 'p.typ',
      title: 'A very long project title for a phone screen',
      outgoingLinks: [],
    );
    const index = VaultIndex(
      notesByPath: {'p.typ': entity},
      backlinksByTarget: {},
    );
    final client = _FakeGitHub();
    await tester.pumpWidget(
      MaterialApp(
        home: EntityBoard(
          boardId: 'board',
          entity: entity,
          vault: vault,
          index: index,
          setStatus: (_, _) async {},
          mutateNote: (_, _) async => false,
          refreshIndex: () async => index,
          githubClient: () async => client,
        ),
      ),
    );
    for (
      var i = 0;
      i < 20 && find.text('Remote issue').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
    }
    expect(find.text('owner/repo'), findsOneWidget);
    expect(find.byTooltip('Sync with GitHub'), findsOneWidget);
    expect(tester.takeException(), isNull);
    client.remoteTitle = 'Phone refresh';
    await tester.tap(find.byTooltip('Sync with GitHub'));
    for (
      var i = 0;
      i < 20 && find.text('Phone refresh').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
    }
    expect(find.text('Phone refresh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GitHub cards move between columns and stale moves lose', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('remote-board'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await tester.runAsync(
      () => writeBoard(
        vault.storage,
        Board.fromJson({
          'id': 'board',
          'title': 'P',
          'scopeEntity': 'p',
          'github_repo': 'owner/repo',
        }),
      ),
    );
    const entity = NoteRef(
      id: 'p',
      path: 'p.typ',
      title: 'P',
      outgoingLinks: [],
    );
    const index = VaultIndex(
      notesByPath: {'p.typ': entity},
      backlinksByTarget: {},
    );
    final client = _FakeGitHub();
    await tester.pumpWidget(
      MaterialApp(
        home: EntityBoard(
          boardId: 'board',
          entity: entity,
          vault: vault,
          index: index,
          setStatus: (_, _) async {},
          mutateNote: (_, _) async => false,
          refreshIndex: () async => index,
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

    for (
      var i = 0;
      i < 20 && find.text('Remote issue').evaluate().isEmpty;
      i++
    ) {
      await io();
    }
    Future<void> move(String column) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Remote issue')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getBottomLeft(find.byKey(ValueKey('board-column-$column'))) +
            const Offset(100, -30),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await io();
    }

    await move('doing');
    expect(client.remoteStatus, 'doing');
    await move('done');
    expect(client.remoteStatus, 'done');
    await move('todo');
    expect(client.remoteStatus, 'todo');
    client.remoteStatus = 'doing';
    await move('done');
    expect(client.remoteStatus, 'doing');
    String? log;
    for (var i = 0; i < 20; i++) {
      await io();
      log = await tester.runAsync(() async {
        const path = '_system/decisions/github.jsonl';
        return await vault.storage.exists(path)
            ? vault.storage.readText(path)
            : '';
      });
      if (log?.contains('owner/repo#42') == true) break;
    }
    expect(log, contains('owner/repo#42'));
    expect(log, contains('conflict'));
  });

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
        home: UnifiedBoard(
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
    for (var i = 0; i < 50 && find.text('A task').evaluate().isEmpty; i++) {
      await settleIo();
    }
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
  testWidgets('linked issue moves push and stale remote status wins', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('linked-move'),
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
    var source =
        '- #tylog.ref-note("p")[P] fixit broken #metadata(("tylog-issue-gh": 123))\nunsaved edit';
    VaultIndex makeIndex() => VaultIndex(
      notesByPath: const {'p.typ': project},
      backlinksByTarget: const {},
      issues: [
        IssueRef(
          notePath: 'log.typ',
          line: 1,
          text: source.split('\n').first,
          projectId: 'p',
          marker: 'fixit',
          status: source.contains('"done"')
              ? 'done'
              : source.contains('"doing"')
              ? 'doing'
              : 'todo',
          githubNumber: 123,
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
    Future<void> move(String column) async {
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.ancestor(
            of: find.text('#123'),
            matching: find.byType(LongPressDraggable<Object>),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(find.byKey(ValueKey('board-$column-0'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await io();
    }

    await move('doing');
    expect(client.linkedDoing, isTrue);
    expect(source, contains('"tylog-issue-status": "doing"'));
    expect(source, contains('unsaved edit'));
    client.state = 'closed';
    await move('todo');
    for (var i = 0; i < 30 && !source.contains('\"done\"'); i++) {
      await io();
    }
    expect(client.state, 'closed');
    expect(source, contains('"tylog-issue-status": "done"'));
    final log = await tester.runAsync(
      () => vault.storage.readText('_system/decisions/github.jsonl'),
    );
    expect(log, contains('GitHub conflict'));

    client.failAfterReopen = true;
    await move('doing');
    for (var i = 0; i < 30 && !source.contains('\"todo\"'); i++) {
      await io();
    }
    expect(client.state, 'open');
    expect(source, contains('\"tylog-issue-status\": \"todo\"'));
    expect(source, contains('unsaved edit'));
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
          status: source.contains('"done"')
              ? 'done'
              : source.contains('"doing"')
              ? 'doing'
              : 'todo',
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
      await tester.tap(find.byTooltip('Sync with GitHub'));
      for (var i = 0; i < 200 && !source.contains('"done"'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(source, contains('"tylog-issue-status": "done"'));
    await io();
    client.state = 'open';
    client.linkedDoing = true;
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Sync with GitHub'));
      for (var i = 0; i < 200 && !source.contains('"doing"'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(source, contains('"tylog-issue-status": "doing"'));
    expect(client.closed, isNull);
    final conflicts = await tester.runAsync(
      () => vault.storage.readText('_system/decisions/github.jsonl'),
    );
    expect(conflicts, contains('GitHub conflict'));
  });
}

class _FakeGitHub extends GitHubClient {
  String? repo;
  String remoteTitle = 'Remote issue';
  String remoteStatus = 'todo';
  @override
  Future<List<Map<String, dynamic>>> repositoryIssues(String repo) async {
    this.repo = repo;
    return [
      {
        'number': 42,
        'title': remoteTitle,
        'state': remoteStatus == 'done' ? 'closed' : 'open',
        'labels': [
          if (remoteStatus == 'doing') {'name': 'doing'},
        ],
      },
    ];
  }

  String state = 'open';
  bool linkedDoing = false;
  bool failAfterReopen = false;
  int? closed;
  List<String>? labels;
  @override
  Future<Map<String, dynamic>> updateIssueColumn(
    String repo,
    int number,
    String column,
    List<String> labels, {
    String? currentColumn,
  }) async {
    if (failAfterReopen) {
      failAfterReopen = false;
      if (number == 42) {
        remoteStatus = 'done';
      } else {
        state = 'open';
        linkedDoing = false;
      }
      throw StateError('label update failed');
    }
    if (number == 42) {
      remoteStatus = column;
    } else {
      state = column == 'done' ? 'closed' : 'open';
      linkedDoing = column == 'doing';
    }
    return {};
  }

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
  Future<Map<String, dynamic>> issue(String repo, int number) async =>
      number == 42
      ? {
          'state': remoteStatus == 'done' ? 'closed' : 'open',
          'labels': [
            if (remoteStatus == 'doing') {'name': 'doing'},
          ],
        }
      : {
          'state': state,
          'labels': [
            if (linkedDoing) {'name': 'doing'},
          ],
        };
  @override
  Future<Map<String, dynamic>> closeIssue(String repo, int number) async {
    closed = number;
    return {};
  }
}
