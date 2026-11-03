import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/entity_header.dart';
import 'package:tylog/widgets/whiteboard.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  late Directory dir;
  late LocalVaultStorage storage;

  Future<void> settleIo(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }

  Future<T?> pollIo<T>(WidgetTester tester, Future<T?> Function() read) async {
    for (var i = 0; i < 20; i++) {
      final value = await tester.runAsync(read);
      if (value != null && (value is! List || value.isNotEmpty)) return value;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    return null;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('whiteboard-test');
    storage = LocalVaultStorage(dir);
  });
  tearDown(() async => dir.delete(recursive: true));

  testWidgets('Library Boards lists board titles and card counts', (
    tester,
  ) async {
    await tester.runAsync(
      () => writeBoard(
        storage,
        Board(
          id: 'listed',
          title: 'Research map',
          layout: 'free',
          cards: const [
            BoardCard(id: 'one', type: 'text', text: 'One'),
            BoardCard(id: 'two', type: 'text', text: 'Two'),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BoardsTab(storage: storage, index: null)),
      ),
    );
    for (
      var i = 0;
      i < 30 && find.text('Research map').evaluate().isEmpty;
      i++
    ) {
      await settleIo(tester);
    }
    expect(find.text('Research map'), findsOneWidget);
    expect(find.text('free · 2 cards'), findsOneWidget);
  });

  testWidgets("New whiteboard creates a board file", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BoardsTab(storage: storage, index: null)),
      ),
    );
    await tester.tap(find.text('New whiteboard'));
    await tester.pump();
    final files = await pollIo(tester, () async {
      final entries = await storage.list(path: 'boards');
      return entries
          .where((entry) => entry.path.endsWith('.board.json'))
          .toList();
    });
    expect(files, hasLength(1));
  });

  testWidgets('culls offscreen cards and renders missing references', (
    tester,
  ) async {
    await tester.runAsync(
      () => writeBoard(
        storage,
        Board(
          id: 'culling',
          title: 'Cull',
          layout: 'free',
          cards: const [
            BoardCard(
              id: 'missing-ref',
              type: 'note',
              ref: 'deleted',
              x: 30,
              y: 30,
            ),
            BoardCard(
              id: 'far-away',
              type: 'text',
              text: 'Far away',
              x: 5000,
              y: 5000,
            ),
          ],
        ),
      ),
    );
    final cullingBoard = await tester.runAsync<Board?>(
      () => readBoard(storage, 'culling'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(board: cullingBoard!, storage: storage, index: null),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('missing'), findsOneWidget);
    expect(find.byKey(const ValueKey('board-card-far-away')), findsNothing);
    expect(find.text('Far away'), findsNothing);
  });

  testWidgets('dragging saves the new snapped position after debounce', (
    tester,
  ) async {
    const original = BoardCard(
      id: 'drag',
      type: 'text',
      text: 'Drag me',
      x: 30,
      y: 30,
    );
    await tester.runAsync(
      () => writeBoard(
        storage,
        const Board(
          id: 'drag-board',
          title: 'Drag',
          layout: 'free',
          cards: [original],
        ),
      ),
    );
    final board = (await tester.runAsync(
      () => readBoard(storage, 'drag-board'),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(board: board, storage: storage, index: null),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('board-card-drag'))),
    );
    await gesture.moveBy(const Offset(20, 20));
    await gesture.moveBy(const Offset(40, 40));
    await gesture.moveBy(const Offset(40, 40));
    await gesture.up();
    await tester.pump();
    final uiPosition = tester.getTopLeft(
      find.byKey(const ValueKey('board-card-drag')),
    );
    expect(uiPosition.dx, greaterThan(30));
    await tester.pump(const Duration(milliseconds: 600));
    Board? saved;
    for (var i = 0; i < 20; i++) {
      saved = await tester.runAsync<Board?>(
        () => readBoard(storage, 'drag-board'),
      );
      if (saved?.cards.single.x != 30) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(saved, isNotNull);
    expect(saved!.cards.single.x, greaterThan(30));
    expect(saved.cards.single.x % 8, 0);
    expect(saved.cards.single.y % 8, 0);
  });

  testWidgets('entity header Whiteboard action creates and opens its board', (
    tester,
  ) async {
    const entity = NoteRef(
      id: 'person-42',
      path: 'people/person-42.typ',
      title: 'Ada',
      outgoingLinks: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: EntityHeader(
              note: entity,
              onOpenUrl: (_) {},
              onOpenWhiteboard: () => openEntityWhiteboard(
                context,
                storage: storage,
                index: null,
                entityId: entity.id,
                title: entity.title,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Whiteboard'));
    await tester.pump();
    final created = await pollIo(
      tester,
      () async => readBoard(storage, 'person-42-wb'),
    );
    expect(created, isNotNull);
    expect(created!.title, 'Ada');
    expect(created.scopeEntity, 'person-42');
    expect(find.text('Ada'), findsOneWidget);
  });
  testWidgets(
    'entity Tree opens and pins nodes and edges without duplicate cards',
    (tester) async {
      const root = NoteRef(
        id: 'root',
        path: 'root.typ',
        title: 'Root',
        kind: 'person',
        outgoingLinks: [],
      );
      const child = NoteRef(
        id: 'child',
        path: 'child.typ',
        title: 'Child',
        kind: 'person',
        outgoingLinks: [],
        partOf: ['root'],
      );
      const index = VaultIndex(
        notesByPath: {'root.typ': root, 'child.typ': child},
        backlinksByTarget: {},
      );
      await tester.runAsync(() async {
        await storage.writeText('root.typ', 'root');
        await storage.writeText('child.typ', 'child');
        await writeBoard(
          storage,
          const Board(
            id: 'root-wb',
            title: 'Root',
            layout: 'free',
            scopeEntity: 'root',
            cards: [BoardCard(id: 'existing', type: 'entity', ref: 'child')],
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: EntityHeader(
                note: root,
                onOpenUrl: (_) {},
                onOpenTree: () => openEntityWhiteboard(
                  context,
                  storage: storage,
                  index: index,
                  entityId: root.id,
                  title: root.title,
                  initialTree: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tree'));
      await tester.pump();
      for (
        var i = 0;
        i < 30 && find.text('Pin to whiteboard').evaluate().isEmpty;
        i++
      ) {
        await settleIo(tester);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Pin to whiteboard'), findsOneWidget);
      expect(find.byKey(const ValueKey('board-card-root')), findsOneWidget);
      await tester.tap(find.text('Pin to whiteboard'));
      await tester.pump();
      Board? saved;
      for (var i = 0; i < 30; i++) {
        saved = await tester.runAsync<Board?>(
          () => readBoard(storage, 'root-wb'),
        );
        if (saved?.edges.isNotEmpty == true) break;
        await settleIo(tester);
      }
      expect(saved!.cards, hasLength(2));
      expect(saved.cards.where((c) => c.ref == 'child'), hasLength(1));
      expect(saved.edges.single.to, 'existing');
      expect(
        saved.edges.single.from,
        saved.cards.singleWhere((c) => c.ref == 'root').id,
      );
    },
  );
  testWidgets('adds note, task, text and link cards', (tester) async {
    const note = NoteRef(
      id: 'n',
      path: 'n.typ',
      title: 'Chosen note',
      outgoingLinks: [],
    );
    const index = VaultIndex(
      notesByPath: {'n.typ': note},
      backlinksByTarget: {},
      tasks: [TaskRef(id: 't', notePath: 'n.typ', text: 'Chosen task')],
    );
    await tester.runAsync(() => storage.writeText('n.typ', 'content'));
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(
          board: const Board(id: 'adds', title: 'Adds', layout: 'free'),
          storage: storage,
          index: index,
        ),
      ),
    );
    Future<void> menu(String item) async {
      await tester.tap(find.byTooltip('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(item));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await menu('Note/entity');
    await tester.tap(find.text('Chosen note'));
    await tester.pump(const Duration(milliseconds: 400));
    await menu('Task');
    await tester.tap(find.text('Chosen task'));
    await tester.pump(const Duration(milliseconds: 400));
    await menu('Text');
    await tester.enterText(find.byType(TextField).last, 'Hello card');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));
    await menu('Link');
    await tester.enterText(find.byType(TextField).last, 'https://example.com');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 600));
    Board? saved;
    for (var i = 0; i < 100; i++) {
      saved = await tester.runAsync<Board?>(() => readBoard(storage, 'adds'));
      if (saved?.cards.length == 4) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(saved?.cards.map((c) => c.type), ['note', 'task', 'text', 'url']);
    expect(saved?.cards[2].text, 'Hello card');
    expect(saved?.cards[3].ref, 'https://example.com');
  });

  testWidgets('connects and deletes edges and moves a frame with its card', (
    tester,
  ) async {
    const board = Board(
      id: 'edges',
      title: 'Edges',
      layout: 'free',
      cards: [
        BoardCard(
          id: 'a',
          type: 'text',
          text: 'A',
          x: 40,
          y: 80,
          w: 100,
          h: 70,
        ),
        BoardCard(
          id: 'b',
          type: 'text',
          text: 'B',
          x: 340,
          y: 80,
          w: 100,
          h: 70,
        ),
      ],
      frames: [
        BoardFrame(id: 'f', title: 'Group', x: 20, y: 20, w: 200, h: 180),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(board: board, storage: storage, index: null),
      ),
    );
    await tester.tap(find.byTooltip('Connect'));
    await tester.pump();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('connect-a'))),
    );
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('board-card-b'))),
    );
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('edge-')), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    final frameDrag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('frame-f'))),
    );
    await frameDrag.moveBy(const Offset(30, 30));
    await frameDrag.moveBy(const Offset(40, 40));
    await frameDrag.up();
    await tester.pump(const Duration(milliseconds: 600));
    Board? saved;
    for (var i = 0; i < 100; i++) {
      saved = await tester.runAsync<Board?>(() => readBoard(storage, 'edges'));
      if (saved != null &&
          saved.edges.isNotEmpty &&
          saved.frames.single.x > 20) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(saved?.edges, hasLength(1));
    expect(saved!.cards.first.x, greaterThan(40));
    await tester.tap(find.byKey(ValueKey('edge-${saved.edges.single.id}')));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete selected card'));
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 100; i++) {
      saved = await tester.runAsync<Board?>(() => readBoard(storage, 'edges'));
      if (saved != null && saved.edges.isEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(saved?.edges, isEmpty);
  });
  testWidgets('copies a picked image into the board assets', (tester) async {
    final input = File('${dir.path}/picture.png');
    await tester.runAsync(() => input.writeAsBytes([1, 2, 3, 4]));
    const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => [
        {'name': 'picture.png', 'path': input.path, 'size': 4},
      ],
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(
          board: const Board(id: 'images', title: 'Images', layout: 'free'),
          storage: storage,
          index: null,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Image from file'));
    await tester.pump(const Duration(milliseconds: 600));
    Board? saved;
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      saved = await tester.runAsync<Board?>(() => readBoard(storage, 'images'));
      if (saved?.cards.isNotEmpty == true) break;
    }
    expect(saved?.cards.single.type, 'asset');
    expect(saved?.cards.single.ref, 'assets/boards/images/9f64a747.png');
    expect(
      await tester.runAsync(() => storage.readBytes(saved!.cards.single.ref!)),
      [1, 2, 3, 4],
    );
  });
  testWidgets('creates a frame and pastes text and URLs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(
          board: const Board(id: 'paste', title: 'Paste', layout: 'free'),
          storage: storage,
          index: null,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Frame'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'Ideas');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    var clipboard = 'Pasted text';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    clipboard = 'https://example.org';
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 600));
    Board? saved;
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      saved = await tester.runAsync<Board?>(() => readBoard(storage, 'paste'));
      if (saved?.cards.length == 2 && saved?.frames.length == 1) break;
    }
    expect(saved?.frames.single.title, 'Ideas');
    expect(saved?.cards.map((c) => c.type), ['text', 'url']);
    expect(saved?.cards.first.text, 'Pasted text');
  });
}
