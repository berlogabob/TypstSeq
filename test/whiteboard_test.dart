import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/entity_header.dart';
import 'package:tylog/widgets/whiteboard.dart';
import 'package:tylog/widgets/entity_board.dart';
import 'package:tylog/vault.dart';
import 'package:tylog_core/tylog_core.dart';

import 'support/temp_dir.dart';

class CountingStorage extends LocalVaultStorage {
  CountingStorage(super.root);
  int reads = 0;
  @override
  Future<Uint8List> readBytes(String path) {
    reads++;
    return super.readBytes(path);
  }
}

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
      await tester.pump(const Duration(milliseconds: 50));
    }
    return null;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('whiteboard-test');
    storage = LocalVaultStorage(dir);
  });
  tearDown(() => deleteTempDir(dir));

  testWidgets('adds OpenLabTwin hierarchy and shows cached asset stock', (
    tester,
  ) async {
    const room = NoteRef(
      id: 'olt:place:1',
      path: 'olt:place:1',
      title: 'Room',
      kind: 'place',
      outgoingLinks: [],
    );
    const asset = NoteRef(
      id: 'olt:asset:2',
      path: 'olt:asset:2',
      title: 'Microscope',
      kind: 'asset',
      outgoingLinks: [],
      partOf: ['olt:place:1'],
      properties: {
        'stock': [
          {'qty': 0, 'unit': 'pcs'},
        ],
      },
    );
    final index = VaultIndex(
      notesByPath: {room.path: room, asset.path: asset},
      backlinksByTarget: {},
    );
    await tester.runAsync(
      () => writeBoard(
        storage,
        const Board(id: 'olt', title: 'Board', layout: 'free'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(
          board: const Board(id: 'olt', title: 'Board', layout: 'free'),
          storage: storage,
          index: index,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add from OpenLabTwin'));
    await tester.pumpAndSettle();
    expect(find.text('Room'), findsOneWidget);
    expect(find.text('Microscope'), findsOneWidget);
    expect(find.text('Stock: 0 pcs'), findsOneWidget);
    final saved = await pollIo(tester, () async {
      final value = parseBoard(await storage.readText(boardPath('olt')));
      return value.cards.isEmpty ? null : value;
    });
    expect(saved!.cards.length, 2);
    expect(saved.edges.length, 1);
  });

  testWidgets('empty whiteboard guides the first add-card action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(
          board: const Board(id: 'empty', title: 'Empty', layout: 'free'),
          storage: storage,
          index: null,
        ),
      ),
    );
    expect(find.text('This whiteboard is empty'), findsOneWidget);
    expect(find.text('Choose Add to place your first card.'), findsOneWidget);
    expect(find.byTooltip('Add'), findsOneWidget);
    await tester.tap(find.text('Add text card'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'First card');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('First card'), findsOneWidget);
  });

  test('Tree note preview removes the import and metadata header', () {
    expect(
      boardNotePreview('''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "child", title: "Child", kind: "note")

= First body line
'''),
      '= First body line\n',
    );
    expect(
      boardNotePreview('''#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "castle",
  title: "Castle (old)",
  kind: "place",
  properties: (note: "a \\" ) b",),
)

= Castle
Body
'''),
      '= Castle\nBody\n',
    );
  });

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

  testWidgets('Library opens each board layout in its matching editor', (
    tester,
  ) async {
    const entity = NoteRef(
      id: 'project',
      path: 'p.typ',
      title: 'Project',
      outgoingLinks: [],
    );
    const index = VaultIndex(
      notesByPath: {'p.typ': entity},
      backlinksByTarget: {},
    );
    await tester.runAsync(() async {
      await writeBoard(
        storage,
        const Board(id: 'cols', title: 'Columns', scopeEntity: 'project'),
      );
      await writeBoard(
        storage,
        const Board(id: 'free', title: 'Canvas', layout: 'free'),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BoardsTab(
            storage: storage,
            index: index,
            onOpenColumns: (context, board) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EntityBoard(
                  entity: entity,
                  boardId: board.id,
                  vault: Vault.withStorage(storage),
                  index: index,
                  setStatus: (_, _) async {},
                  mutateNote: (_, _) async => false,
                  refreshIndex: () async => index,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30 && find.text('Project').evaluate().isEmpty; i++) {
      await settleIo(tester);
    }
    await tester.tap(find.text('Project'));
    await tester.pump(const Duration(milliseconds: 400));
    for (
      var i = 0;
      i < 30 &&
          find.byKey(const ValueKey('board-column-todo')).evaluate().isEmpty;
      i++
    ) {
      await settleIo(tester);
    }
    expect(find.byType(EntityBoard), findsOneWidget);
    expect(find.byKey(const ValueKey('board-column-todo')), findsOneWidget);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Canvas'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Whiteboard), findsOneWidget);
  });

  testWidgets('Library lists an entity with children without a board file', (
    tester,
  ) async {
    const parent = NoteRef(
      id: 'parent',
      path: 'parent.typ',
      title: 'Parent',
      kind: 'person',
      outgoingLinks: [],
    );
    const child = NoteRef(
      id: 'child',
      path: 'child.typ',
      title: 'Child',
      kind: 'person',
      partOf: ['parent'],
      outgoingLinks: [],
    );
    const index = VaultIndex(
      notesByPath: {'parent.typ': parent, 'child.typ': child},
      backlinksByTarget: {},
    );
    Board? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BoardsTab(
            storage: storage,
            index: index,
            onOpenColumns: (_, board) => opened = board,
          ),
        ),
      ),
    );
    for (var i = 0; i < 30 && find.text('Parent').evaluate().isEmpty; i++) {
      await settleIo(tester);
    }
    expect(find.text('Parent'), findsOneWidget);
    expect(find.text('0 tasks · 0 issues · 1 child'), findsOneWidget);
    await tester.tap(find.text('Parent'));
    expect(opened?.scopeEntity, 'parent');
    expect(
      await tester.runAsync(() => storage.exists(boardPath('parent'))),
      isFalse,
    );
  });

  testWidgets('back waits for a dragged card to save', (tester) async {
    const board = Board(
      id: 'back',
      title: 'Back board',
      layout: 'free',
      cards: [BoardCard(id: 'card', type: 'text', text: 'Move', x: 30, y: 30)],
    );
    await tester.runAsync(() => writeBoard(storage, board));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      Whiteboard(board: board, storage: storage, index: null),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('board-card-card'))),
    );
    await gesture.moveBy(const Offset(50, 50));
    await gesture.moveBy(const Offset(50, 50));
    await gesture.up();
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    for (
      var i = 0;
      i < 30 && find.byType(Whiteboard).evaluate().isNotEmpty;
      i++
    ) {
      await settleIo(tester);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Whiteboard), findsNothing);
    final saved = await pollIo(tester, () async {
      final b = await readBoard(storage, 'back');
      return b != null && b.cards.single.x != 30 ? b : null;
    });
    expect(saved?.cards.single.x, greaterThan(30));
  });

  testWidgets('disk change preserves local board as a conflict copy', (
    tester,
  ) async {
    const board = Board(
      id: 'conflict',
      title: 'Local',
      layout: 'free',
      cards: [BoardCard(id: 'card', type: 'text', text: 'Move', x: 30, y: 30)],
    );
    await tester.runAsync(() => writeBoard(storage, board));
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(
          board: board,
          storage: storage,
          index: null,
          deviceId: 'phone',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('board-card-card'))),
    );
    await gesture.moveBy(const Offset(50, 50));
    await gesture.moveBy(const Offset(50, 50));
    await gesture.up();
    await tester.pump();
    await tester.runAsync(
      () => writeBoard(
        storage,
        const Board(id: 'conflict', title: 'Remote', layout: 'free'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final copy = await pollIo(
      tester,
      () => readBoard(storage, 'conflict.conflict-phone'),
    );
    for (var i = 0; i < 20 && find.text('Remote').evaluate().isEmpty; i++) {
      await settleIo(tester);
    }
    expect(copy?.cards.single.x, greaterThan(30));
    expect(find.text('Remote'), findsOneWidget);
    expect(
      find.text(
        'Board changed on another device - your version saved as a copy',
      ),
      findsOneWidget,
    );
    final remote = await tester.runAsync(() => readBoard(storage, 'conflict'));
    expect(remote?.title, 'Remote');
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
              onOpenBoard: () => openEntityWhiteboard(
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
    await tester.tap(find.byKey(const Key('entity-board-button')));
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
                onOpenBoard: () => openEntityWhiteboard(
                  context,
                  storage: storage,
                  index: index,
                  entityId: root.id,
                  title: root.title,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('entity-board-button')));
      await tester.pump();
      for (
        var i = 0;
        i < 250 &&
            find.byKey(const Key('board-add-contents')).evaluate().isEmpty;
        i++
      ) {
        await settleIo(tester);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('board-add-contents')));
      await tester.pump();
      Board? saved;
      for (var i = 0; i < 250; i++) {
        saved = await tester.runAsync<Board?>(() async {
          try {
            return await readBoard(storage, 'root-wb');
          } on FormatException {
            return null; // A concurrent save may still be writing the file.
          }
        });
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
  testWidgets('tap selects a card and Open edits it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(
          board: const Board(
            id: 'select',
            title: 'Select',
            layout: 'free',
            cards: [
              BoardCard(id: 'a', type: 'text', text: 'Hello', x: 30, y: 30),
            ],
          ),
          storage: storage,
          index: null,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('board-card-a')));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byTooltip('Open selected card'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('frame drag does not pick up cards it sweeps over', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(
          board: const Board(
            id: 'sweep',
            title: 'Sweep',
            layout: 'free',
            frames: [
              BoardFrame(id: 'f', title: 'Frame', x: 10, y: 10, w: 100, h: 100),
            ],
            cards: [
              BoardCard(
                id: 'outside',
                type: 'text',
                text: 'Outside',
                x: 130,
                y: 30,
                w: 80,
                h: 50,
              ),
            ],
          ),
          storage: storage,
          index: null,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('frame-f'))),
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));
    Board? saved;
    for (var i = 0; i < 50; i++) {
      saved = await tester.runAsync<Board?>(() => readBoard(storage, 'sweep'));
      if (saved != null) break;
      await settleIo(tester);
    }
    expect(saved!.cards.single.x, 130);
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
    await tester.tap(find.byTooltip('Paste'));
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
  testWidgets('drag reuses reads and decodes a sized thumbnail', (
    tester,
  ) async {
    final counted = CountingStorage(dir);
    await tester.runAsync(() async {
      await counted.writeBytes(
        'image.png',
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aXkAAAAASUVORK5CYII=',
        ),
      );
      await counted.writeText('note.typ', 'Note excerpt');
    });
    const note = NoteRef(
      id: 'n',
      path: 'note.typ',
      title: 'Note',
      outgoingLinks: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(
          board: const Board(
            id: 'cache',
            title: 'Cache',
            layout: 'free',
            cards: [
              BoardCard(
                id: 'image',
                type: 'asset',
                ref: 'image.png',
                x: 20,
                y: 20,
              ),
              BoardCard(id: 'note', type: 'note', ref: 'n', x: 300, y: 20),
            ],
          ),
          storage: counted,
          index: const VaultIndex(
            notesByPath: {'note.typ': note},
            backlinksByTarget: {},
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 30 && find.text('Note excerpt').evaluate().isEmpty;
      i++
    ) {
      await settleIo(tester);
    }
    expect(find.text('Note excerpt'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, greaterThan(0));
    final reads = counted.reads;
    await tester.drag(
      find.byKey(const ValueKey('board-card-note')),
      const Offset(30, 30),
    );
    await tester.pump();
    expect(counted.reads, reads);
  });

  testWidgets('keyboard moves and deletes selected card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Whiteboard(
          board: const Board(
            id: 'keys',
            title: 'Keys',
            layout: 'free',
            cards: [
              BoardCard(
                id: 'key-card',
                type: 'text',
                text: 'Keyboard',
                x: 32,
                y: 32,
              ),
            ],
          ),
          storage: storage,
          index: null,
        ),
      ),
    );
    final card = find.byKey(const ValueKey('board-card-key-card'));
    await tester.tap(card);
    await tester.pump();
    final before = tester.getTopLeft(card);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.getTopLeft(card).dx, before.dx + 8);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(card, findsNothing);
  });
}
