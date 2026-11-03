import 'dart:io';

import 'package:flutter/material.dart';
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
      i < 10 && find.text('Research map').evaluate().isEmpty;
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
}
