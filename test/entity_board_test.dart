import 'dart:async';
import 'dart:convert';

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/github/github_client.dart';
import 'package:tylog/widgets/entity_board.dart';
import 'package:tylog/widgets/unified_board.dart';
import 'support/temp_dir.dart';

void main() {
  testWidgets('blocked issue move opens GitHub with instructions', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('manual-move'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => deleteTempDir(dir));
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
    final client = _FakeGitHub()..blockMove = true;
    String? opened;
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
          onOpenUrl: (url) => opened = url,
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
      i < 40 && find.text('Remote issue').evaluate().isEmpty;
      i++
    ) {
      await io();
    }
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Remote issue')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
      tester.getBottomLeft(find.byKey(const ValueKey('board-column-doing'))) +
          const Offset(100, -30),
    );
    await tester.pump();
    await gesture.up();
    for (
      var i = 0;
      i < 40 && find.text('Open GitHub').evaluate().isEmpty;
      i++
    ) {
      await io();
    }
    expect(find.textContaining('add the doing label'), findsOneWidget);
    expect(client.remoteStatus, 'todo');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Open GitHub'));
    expect(opened, 'https://github.com/owner/repo/issues/42');
  });

  testWidgets('board reconciles an interrupted repository issue move', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('interrupted-move'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => deleteTempDir(dir));
    final vault = Vault(dir);
    await tester.runAsync(() async {
      await writeBoard(
        vault.storage,
        Board.fromJson({
          'id': 'board',
          'title': 'P',
          'scopeEntity': 'p',
          'github_repo': 'owner/repo',
        }),
      );
      await vault.storage.createDirectory(decisionsDir);
      await vault.storage.writeText(
        '$decisionsDir/github.jsonl',
        encodeDecisions([
          const Decision(
            at: '2026-11-06T10:00:00',
            device: 'github',
            item: 'owner/repo#42',
            source: 'repository-issue-move',
            action: 'sent',
            target: 'doing',
            context: 'move-1',
          ),
        ]),
      );
    });
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
    String log = '';
    for (
      var i = 0;
      i < 30 &&
          !Decision.parseLog(
            log,
          ).any((d) => d.context == 'move-1' && d.action == 'seen');
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      log =
          (await tester.runAsync(
            () => vault.storage.readText('$decisionsDir/github.jsonl'),
          )) ??
          '';
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    expect(log, contains('interrupted move'));
    expect(log, contains('move-1'));
    expect(
      Decision.parseLog(log).any(
        (decision) =>
            decision.action == 'seen' &&
            decision.target == 'todo' &&
            decision.context?.contains('reconciled on board refresh') == true,
      ),
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board-column-todo')),
        matching: find.text('Remote issue'),
      ),
      findsOneWidget,
    );
    final count = Decision.parseLog(
      log,
    ).where((d) => d.context == 'move-1' && d.action == 'seen').length;
    expect(count, 1);
    await tester.tap(find.byTooltip('Sync with GitHub'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    log =
        (await tester.runAsync(
          () => vault.storage.readText('$decisionsDir/github.jsonl'),
        )) ??
        '';
    expect(
      Decision.parseLog(
        log,
      ).where((d) => d.context == 'move-1' && d.action == 'seen').length,
      1,
    );
  });

  testWidgets('large columns build cards lazily and scroll to the end', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('large-board'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => deleteTempDir(dir));
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
    for (var i = 0; i < 100 && find.text('Task 0').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
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
  testWidgets('empty board explains itself and adds a task to the page', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('add-task-board'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => deleteTempDir(dir));
    final vault = Vault(dir);
    const entity = NoteRef(
      id: 'p',
      path: 'notes/p.typ',
      title: 'Trip',
      outgoingLinks: [],
    );
    const index = VaultIndex(
      notesByPath: {'notes/p.typ': entity},
      backlinksByTarget: {},
    );
    var source =
        '#import "/_system/tylog.typ" as tylog\n#show: tylog.note.with(id: "p", title: "Trip", kind: "project")\n\n= Trip';
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EntityBoard(
          boardId: 'add',
          entity: entity,
          vault: vault,
          index: index,
          setStatus: (_, _) async {},
          mutateNote: (path, edit) async {
            expect(path, 'notes/p.typ');
            source = edit(source);
            return true;
          },
          refreshIndex: () async {
            refreshed++;
            await Completer<void>().future; // a slow refresh never finishes
            return index;
          },
        ),
      ),
    );
    for (
      var i = 0;
      i < 100 && find.byKey(const Key('board-add-task')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.textContaining('No tasks yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('board-add-task')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('board-new-task-text')),
      'Book the table',
    );
    await tester.tap(find.text('Add'));
    for (var i = 0; i < 50 && refreshed == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(refreshed, 1);
    // The card shows before the (slow) index refresh returns.
    await tester.pump();
    expect(find.widgetWithText(Card, 'Book the table'), findsOneWidget);
    expect(source, contains('= Trip\n#tylog.task('));
    expect(source, contains('text: "Book the table"'));
    await tester.runAsync(() async {
      await Directory('${dir.path}/_system').create(recursive: true);
      await File('typst/tylog/lib.typ').copy('${dir.path}/_system/tylog.typ');
      await File('${dir.path}/p.typ').writeAsString(source);
      final result = await Process.run('typst', [
        'compile',
        '--root',
        dir.path,
        '${dir.path}/p.typ',
        '${dir.path}/p.pdf',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reordering tasks persists and reloads their order', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('ordered-board'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => deleteTempDir(dir));
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
    for (
      var i = 0;
      i < 100 && find.text('First task').evaluate().isEmpty;
      i++
    ) {
      await io();
    }
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
          true) {
        break;
      }
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
      addTearDown(() => deleteTempDir(dir));
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
      for (
        var i = 0;
        i < 100 &&
            find.byKey(const ValueKey('board-column-todo')).evaluate().isEmpty;
        i++
      ) {
        await io();
      }
      await tester.tap(find.byTooltip('GitHub repository'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextFormField), 'owner/repo');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
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
      for (
        var i = 0;
        i < 100 && find.text('Refreshed issue').evaluate().isEmpty;
        i++
      ) {
        await io();
      }
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
    addTearDown(() => deleteTempDir(dir));
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
    addTearDown(() => deleteTempDir(dir));
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
      Future<String> readLog() async {
        const path = '_system/decisions/github.jsonl';
        return await vault.storage.exists(path)
            ? vault.storage.readText(path)
            : '';
      }

      final before = await tester.runAsync(readLog) ?? '';
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Remote issue')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(
        tester.getCenter(find.byKey(ValueKey('board-$column-0'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await io();
        final button = tester.widget<IconButton>(
          find
              .ancestor(
                of: find.byTooltip('Sync with GitHub'),
                matching: find.byType(IconButton),
              )
              .first,
        );
        final log = await tester.runAsync(readLog) ?? '';
        final added = Decision.parseLog(
          log,
        ).skip(Decision.parseLog(before).length);
        if (added.isNotEmpty &&
            added.last.action != 'sent' &&
            button.onPressed != null) {
          return;
        }
      }
      fail('Move to $column did not finish');
    }

    await move('doing');
    expect(client.remoteStatus, 'doing');
    final recorded = await tester.runAsync(
      () => vault.storage.readText('$decisionsDir/github.jsonl'),
    );
    final moves = Decision.parseLog(
      recorded!,
    ).where((d) => d.source == 'repository-issue-move').toList();
    expect(moves.map((d) => d.action), ['sent', 'seen']);
    expect(moves.first.target, 'doing');
    expect(moves.first.context, moves.last.context);
    await move('done');
    expect(client.remoteStatus, 'done');
    await move('todo');
    expect(client.remoteStatus, 'todo');
    // A successful request can still lose a race, and the list reload can fail.
    await io();
    client.moveResult = 'doing';
    client.failNextList = true;
    await move('done');
    expect(client.remoteStatus, 'doing');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board-column-doing')),
        matching: find.text('Remote issue'),
      ),
      findsOneWidget,
    );
    String? log;
    for (var i = 0; i < 20; i++) {
      await io();
      log = await tester.runAsync(() async {
        const path = '_system/decisions/github.jsonl';
        return await vault.storage.exists(path)
            ? vault.storage.readText(path)
            : '';
      });
      if (log?.contains('status changed during move') == true) break;
    }
    expect(log, contains('status changed during move'));
    await io();
    expect(client.failNextList, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board-column-doing')),
        matching: find.text('Remote issue'),
      ),
      findsOneWidget,
    );
    client.remoteStatus = 'todo';
    await move('done');
    expect(client.remoteStatus, 'todo');
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

  testWidgets('repository card recovers when issue reload fails', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('remote-recovery'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => deleteTempDir(dir));
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
    final client = _FakeGitHub()..failIssueAfterMove = true;
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
      i < 40 && find.text('Remote issue').evaluate().isEmpty;
      i++
    ) {
      await io();
    }
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Remote issue')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
      tester.getBottomLeft(find.byKey(const ValueKey('board-column-doing'))) +
          const Offset(100, -30),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    String? log;
    for (var i = 0; i < 40; i++) {
      await io();
      log = await tester.runAsync(() async {
        const path = '_system/decisions/github.jsonl';
        return await vault.storage.exists(path)
            ? vault.storage.readText(path)
            : '';
      });
      if (log?.contains('could not be verified individually') == true) break;
    }
    expect(client.remoteStatus, 'doing');
    expect(log, contains('could not be verified individually'));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board-column-doing')),
        matching: find.text('Remote issue'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('repository card reconciles after both reloads fail', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('remote-recovery'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => deleteTempDir(dir));
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
    final client = _FakeGitHub()
      ..failIssueAfterMove = true
      ..failListAfterMove = true;
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
      i < 40 && find.text('Remote issue').evaluate().isEmpty;
      i++
    ) {
      await io();
    }
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Remote issue')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
      tester.getBottomLeft(find.byKey(const ValueKey('board-column-doing'))) +
          const Offset(100, -30),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    String? log;
    for (var i = 0; i < 40; i++) {
      await io();
      log = await tester.runAsync(() async {
        const path = '_system/decisions/github.jsonl';
        return await vault.storage.exists(path)
            ? vault.storage.readText(path)
            : '';
      });
      if (log?.contains('remote status unknown') == true) break;
    }
    expect(client.remoteStatus, 'doing');
    expect(log, contains('remote status unknown'));
    await io();
    client.issueUnavailable = false;
    await tester.tap(find.byTooltip('Sync with GitHub'));
    for (var i = 0; i < 40; i++) {
      await io();
      if (find
          .descendant(
            of: find.byKey(const ValueKey('board-column-doing')),
            matching: find.text('Remote issue'),
          )
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board-column-doing')),
        matching: find.text('Remote issue'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('dragging a card to done writes the task status', (tester) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('entity-board'),
    );
    if (dir == null) throw StateError('Could not create test vault');
    addTearDown(() => deleteTempDir(dir));
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
    addTearDown(() => deleteTempDir(dir));
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
    for (
      var i = 0;
      i < 100 && find.text('high · 2026-12-01').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
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
    addTearDown(() => deleteTempDir(dir));
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

    for (var i = 0; i < 100 && find.text('fixit').evaluate().isEmpty; i++) {
      await settleIo();
    }
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
    addTearDown(() => deleteTempDir(dir));
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

    for (var i = 0; i < 5; i++) {
      await io();
    }
    Future<void> waitUntilReady() async {
      for (var i = 0; i < 50; i++) {
        await io();
        if (tester
                .widget<IconButton>(
                  find.ancestor(
                    of: find.byTooltip('Sync with GitHub'),
                    matching: find.byType(IconButton),
                  ),
                )
                .onPressed !=
            null) {
          return;
        }
      }
      fail('Board stayed busy');
    }

    Future<void> move(String column) async {
      await waitUntilReady();
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
      await waitUntilReady();
    }

    await move('doing');
    for (var i = 0; i < 30 && !source.contains('"doing"'); i++) {
      await io();
    }
    expect(client.linkedDoing, isTrue);
    expect(source, contains('"tylog-issue-status": "doing"'));
    expect(source, contains('unsaved edit'));
    var moveRows = <Decision>[];
    for (var i = 0; i < 30; i++) {
      final moveLog = await tester.runAsync(
        () => vault.storage.readText('_system/decisions/github.jsonl'),
      );
      moveRows = Decision.parseLog(
        moveLog!,
      ).where((row) => row.source == 'linked-issue-move').toList();
      if (moveRows.length == 2) break;
      await io();
    }
    expect(moveRows.map((row) => row.action), ['sent', 'seen']);
    expect(moveRows.first.context, moveRows.last.context);
    for (var i = 0; i < 5; i++) {
      await io();
    }
    client.state = 'closed';
    await move('todo');
    for (var i = 0; i < 30 && !source.contains('"done"'); i++) {
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
    for (var i = 0; i < 30 && !source.contains('"todo"'); i++) {
      await io();
    }
    expect(client.state, 'open');
    expect(source, contains('"tylog-issue-status": "todo"'));
    expect(source, contains('unsaved edit'));

    client.failIssueAfterMove = true;
    await move('doing');
    for (var i = 0; i < 30 && !source.contains('"doing"'); i++) {
      await io();
    }
    expect(source, contains('"tylog-issue-status": "doing"'));
    expect(source, contains('unsaved edit'));
    final recovered = await tester.runAsync(
      () => vault.storage.readText('_system/decisions/github.jsonl'),
    );
    expect(recovered, contains('could not be verified individually'));

    client.failIssueAfterMove = false;
    client.issueUnavailable = false;
    client.failAfterReopen = true;
    client.failIssueOnFailedMove = true;
    await move('done');
    for (var i = 0; i < 30 && !source.contains('"todo"'); i++) {
      await io();
    }
    expect(source, contains('"tylog-issue-status": "todo"'));
    final failed = await tester.runAsync(
      () => vault.storage.readText('_system/decisions/github.jsonl'),
    );
    expect(failed, contains('move to done failed'));

    client.issueUnavailable = false;
    client.failIssueOnFailedMove = false;
    client.failIssueAfterMove = true;
    client.failListAfterMove = true;
    await move('doing');
    String? unknown;
    for (var i = 0; i < 30; i++) {
      await io();
      unknown = await tester.runAsync(
        () => vault.storage.readText('_system/decisions/github.jsonl'),
      );
      if (unknown?.contains('remote status unknown') == true) break;
    }
    expect(unknown, contains('remote status unknown'));
    await io();
    expect(source, contains('"tylog-issue-status": "todo"'));
    client.issueUnavailable = false;
    await tester.tap(find.byTooltip('Sync with GitHub'));
    for (var i = 0; i < 30 && !source.contains('"doing"'); i++) {
      await io();
    }
    expect(source, contains('"tylog-issue-status": "doing"'));
  });

  testWidgets(
    'opening a board recovers a linked move from the repository listing',
    (tester) async {
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('github-interrupted-move'),
      );
      if (dir == null) throw StateError('No temp directory');
      addTearDown(() => deleteTempDir(dir));
      final vault = Vault(dir);
      final client = _FakeGitHub()
        ..state = 'closed'
        ..issueUnavailable = true;
      const project = NoteRef(
        id: 'p',
        path: 'p.typ',
        title: 'P',
        kind: 'project',
        outgoingLinks: [],
        properties: {'github': 'owner/repo'},
      );
      var source = '- #tylog.ref-note("p")[P] fixit broken';
      await tester.runAsync(() async {
        await vault.storage.createDirectory('_system/decisions');
        await vault.storage.appendBytes(
          '_system/decisions/github.jsonl',
          utf8.encode(
            encodeDecisions([
              Decision(
                at: '2026-01-01',
                device: 'github',
                item: 'owner/repo#123',
                source: 'linked-issue-move',
                action: 'sent',
                target: 'doing',
                context: 'interrupted',
              ),
            ]),
          ),
        );
      });
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
            status: 'todo',
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
      for (var i = 0; i < 30 && !source.contains('"done"'); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
      }
      expect(source, contains('"tylog-issue-status": "done"'));
      for (var i = 0; i < 30; i++) {
        if (await tester.runAsync(
              () => vault.storage.exists('_system/decisions/github.jsonl'),
            ) ==
            true) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
      }
      String? log;
      for (var i = 0; i < 30; i++) {
        log = await tester.runAsync(
          () => vault.storage.readText('_system/decisions/github.jsonl'),
        );
        if (log != null &&
            Decision.parseLog(log).any(
              (row) =>
                  row.source == 'linked-issue-move' && row.action == 'seen',
            )) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
      }
      final rows = Decision.parseLog(log!);
      expect(
        rows
            .where((row) => row.source == 'linked-issue-move')
            .map((row) => row.action),
        ['sent', 'seen'],
      );
      expect(log, contains('interrupted move to doing'));
      expect(log, contains('owner/repo#123'));
    },
  );

  testWidgets('sends and syncs linked issues using a fake client', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('github-issue'),
    );
    if (dir == null) throw StateError('No temp directory');
    addTearDown(() => deleteTempDir(dir));
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
  bool blockMove = false;
  String remoteTitle = 'Remote issue';
  String remoteStatus = 'todo';
  String? moveResult;
  bool failNextList = false;
  bool failListAfterMove = false;
  bool failIssueAfterMove = false;
  bool issueUnavailable = false;
  @override
  Future<List<Map<String, dynamic>>> repositoryIssues(String repo) async {
    this.repo = repo;
    if (failNextList) {
      failNextList = false;
      throw StateError('list unavailable');
    }
    return [
      {
        'number': 42,
        'title': remoteTitle,
        'state': remoteStatus == 'done' ? 'closed' : 'open',
        'labels': [
          if (remoteStatus == 'doing') {'name': 'doing'},
        ],
      },
      {
        'number': 123,
        'title': 'Linked issue',
        'state': state,
        'labels': [
          if (linkedDoing) {'name': 'doing'},
        ],
      },
    ];
  }

  String state = 'open';
  bool linkedDoing = false;
  bool failAfterReopen = false;
  bool failIssueOnFailedMove = false;
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
    if (blockMove) throw GitHubManualMoveRequired();
    if (failAfterReopen) {
      failAfterReopen = false;
      if (number == 42) {
        remoteStatus = 'done';
      } else {
        state = 'open';
        linkedDoing = false;
      }
      issueUnavailable = failIssueOnFailedMove;
      throw StateError('label update failed');
    }
    if (failListAfterMove) {
      failNextList = true;
      failListAfterMove = false;
    }
    if (number == 42) {
      remoteStatus = moveResult ?? column;
      moveResult = null;
      issueUnavailable = failIssueAfterMove;
    } else {
      state = column == 'done' ? 'closed' : 'open';
      linkedDoing = column == 'doing';
      issueUnavailable = failIssueAfterMove;
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
  Future<Map<String, dynamic>> issue(String repo, int number) async {
    if (issueUnavailable) throw StateError('issue unavailable');
    return number == 42
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
  }

  @override
  Future<Map<String, dynamic>> closeIssue(String repo, int number) async {
    closed = number;
    return {};
  }
}
