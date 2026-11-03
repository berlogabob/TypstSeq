import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog_core/sync_paths.dart';
import 'dart:io';

void main() {
  test(
    'scope includes project and transitive containing notes, and handles cycles',
    () {
      const root = NoteRef(
        id: 'root',
        path: 'notes/root.typ',
        title: 'Root',
        outgoingLinks: [],
        partOf: ['leaf'],
      );
      const child = NoteRef(
        id: 'child',
        path: 'notes/child.typ',
        title: 'Child',
        outgoingLinks: [],
        partOf: ['Root'],
      );
      const leaf = NoteRef(
        id: 'leaf',
        path: 'notes/leaf.typ',
        title: 'Leaf',
        outgoingLinks: [],
        partOf: ['child'],
      );
      const index = VaultIndex(
        notesByPath: {'root': root, 'child': child, 'leaf': leaf},
        backlinksByTarget: {},
        tasks: [
          TaskRef(
            id: 'direct',
            notePath: 'elsewhere',
            text: '',
            project: 'root',
          ),
          TaskRef(id: 'nested', notePath: 'notes/leaf.typ', text: ''),
          TaskRef(
            id: 'assigned',
            notePath: 'elsewhere',
            text: '',
            project: 'Child',
          ),
          TaskRef(id: 'other', notePath: 'elsewhere', text: ''),
        ],
      );
      expect(tasksForEntity('root', index).map((t) => t.id), [
        'direct',
        'nested',
        'assigned',
      ]);
      expect(isSyncableVaultPath('boards/root.board.json'), isTrue);
    },
  );

  test('board file persists through storage', () async {
    final dir = await Directory.systemTemp.createTemp('board-test');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalVaultStorage(dir);
    expect(await readBoard(storage, 'a'), isNull);
    final board = Board(
      id: 'a',
      title: 'A',
      scopeEntity: 'entity',
      order: {
        'todo': ['x'],
      },
    );
    await writeBoard(storage, board);
    expect((await readBoard(storage, 'a'))!.toJson(), board.toJson());
  });

  group('Board JSON', () {
    test('reorder preserves nested future fields', () {
      final board = Board.fromJson({
        'id': 'b',
        'scope': {'entity': 'p', 'future': 3},
        'columns': {'future': true},
      }).moveCardToColumn('a', 'done');
      expect(board.toJson()['scope'], containsPair('future', 3));
      expect(board.toJson()['columns'], containsPair('future', true));
    });
    test('round trips through JSON', () {
      final board = Board.fromJson({
        'schema': 1,
        'id': 'work',
        'title': 'Work',
        'layout': 'tree',
        'scope': {'entity': 'project'},
        'columns': {
          'field': 'priority',
          'values': ['high', 'low'],
          'showCancelled': true,
        },
        'order': {
          'high': ['a', 'b'],
        },
      });

      expect(Board.fromJson(board.toJson()).toJson(), board.toJson());
    });

    test('preserves unknown keys', () {
      final input = <String, Object?>{
        'id': 'work',
        'title': 'Work',
        'futureOption': {'enabled': true},
      };
      expect(
        Board.fromJson(input).toJson(),
        containsPair('futureOption', input['futureOption']),
      );
    });

    test('uses defaults for missing fields', () {
      final board = Board.fromJson({'id': 'inbox', 'title': 'Inbox'});

      expect(board.schema, 1);
      expect(board.layout, 'columns');
      expect(board.scopeEntity, isNull);
      expect(board.columns.field, 'status');
      expect(board.columns.values, ['todo', 'doing', 'done']);
      expect(board.columns.showCancelled, isFalse);
      expect(board.order, isEmpty);
    });

    test('defaults empty JSON and retains required identity fields', () {
      final empty = Board.fromJson({});
      expect(empty.id, '');
      expect(empty.title, '');
      final board = Board.fromJson({'id': 'x', 'title': 'X'});
      expect(board.id, 'x');
      expect(board.title, 'X');
      expect(board.toJson()['id'], 'x');
    });

    test('parseBoard rejects a non-object JSON value', () {
      expect(() => parseBoard('[]'), throwsFormatException);
    });

    test('encodeBoard uses indented JSON', () {
      expect(encodeBoard(Board(id: 'x', title: 'X')), contains('\n  "schema"'));
    });

    test('boardPath follows the board file convention', () {
      expect(boardPath('work'), 'boards/work.board.json');
    });
  });

  group('moveCard', () {
    Board board() => Board(
      id: 'b',
      title: 'T',
      order: {
        'todo': ['a', 'b'],
        'doing': ['c'],
      },
    );

    test('moves between columns and removes duplicate occurrences', () {
      final result = Board(
        id: 'b',
        title: 'T',
        order: {
          'todo': ['x', 'card', 'card'],
          'doing': ['card', 'y'],
        },
      ).moveCardToColumn('card', 'done');

      expect(result.order, {
        'todo': ['x'],
        'doing': ['y'],
        'done': ['card'],
      });
    });

    test('moves within a column to an index', () {
      expect(board().moveCardToColumn('a', 'todo', index: 1).order['todo'], [
        'b',
        'a',
      ]);
    });

    test('clamps indices below and above the column bounds', () {
      expect(board().moveCardToColumn('c', 'todo', index: -10).order['todo'], [
        'c',
        'a',
        'b',
      ]);
      expect(board().moveCardToColumn('c', 'todo', index: 99).order['todo'], [
        'a',
        'b',
        'c',
      ]);
    });
  });

  group('free board', () {
    test('schema 2 and unknown fields survive serialization and edits', () {
      final board = Board.fromJson({
        'schema': 2,
        'id': 'b',
        'title': 'Map',
        'layout': 'free',
        'future': 1,
        'scope': {'entity': 'e', 'future': 2},
        'columns': {'future': 3},
        'cards': [
          {
            'id': 'a',
            'type': 'note',
            'ref': 'n',
            'x': 1,
            'y': 2,
            'w': 20,
            'h': 20,
            'future': 4,
          },
        ],
        'frames': [
          {
            'id': 'f',
            'title': 'F',
            'x': 0,
            'y': 0,
            'w': 100,
            'h': 100,
            'future': 5,
          },
        ],
        'edges': [
          {'id': 'e', 'from': 'a', 'to': 'b', 'label': '', 'future': 6},
        ],
        'viewport': {'x': 1, 'y': 2, 'zoom': 2, 'future': 7},
      }).moveCard('a', 9, -9).moveFrame('f', 10, 10);
      final json = board.toJson();
      expect(Board.fromJson(json).toJson(), json);
      expect(json['future'], 1);
      expect(json['scope'], containsPair('future', 2));
      expect(json['columns'], containsPair('future', 3));
      expect((json['cards'] as List).first, containsPair('future', 4));
      expect((json['frames'] as List).first, containsPair('future', 5));
      expect((json['edges'] as List).first, containsPair('future', 6));
      expect(json['viewport'], containsPair('future', 7));
      expect(Board(id: 'b', title: 'T', layout: 'free').schema, 2);
    });

    test('card, edge, culling and frame helpers', () {
      final board =
          Board(
                id: 'b',
                title: 'T',
                layout: 'free',
                frames: [
                  BoardFrame(id: 'f', title: 'F', x: 0, y: 0, w: 100, h: 100),
                ],
              )
              .addCard(
                BoardCard(id: 'a', type: 'text', x: 1, y: 1, w: 20, h: 20),
              )
              .addCard(
                BoardCard(id: 'b', type: 'note', x: 90, y: 90, w: 30, h: 30),
              )
              .addCard(BoardCard(id: 'c', type: 'text', x: 200, y: 200));
      final moved = board.moveCard('a', 13, -5).resizeCard('a', 30, 40);
      expect(
        [
          moved.cards.first.x,
          moved.cards.first.y,
          moved.cards.first.w,
          moved.cards.first.h,
        ],
        [16, -8, 30, 40],
      );
      expect(board.cardsInRect(100, 100, 10, 10).map((c) => c.id), ['b']);
      final framed = board.moveFrame('f', 10, 20);
      expect([framed.cards[0].x, framed.cards[0].y], [11, 21]);
      expect([framed.cards[1].x, framed.cards[1].y], [90, 90]);
      expect([framed.frames.first.x, framed.frames.first.y], [10, 20]);
      final edges = board
          .addEdge(BoardEdge(id: '1', from: 'a', to: 'b'))
          .addEdge(BoardEdge(id: '2', from: 'a', to: 'b'))
          .addEdge(BoardEdge(id: '3', from: 'a', to: 'a'))
          .addEdge(BoardEdge(id: '4', from: 'b', to: 'c'));
      expect(edges.edges.map((e) => e.id), ['1', '4']);
      final removed = edges.removeCard('a');
      expect(removed.cards.map((c) => c.id), ['b', 'c']);
      expect(removed.edges.map((e) => e.id), ['4']);
    });
  });

  group('orderCards', () {
    final board = Board(
      id: 'b',
      title: 'T',
      order: {
        'todo': ['x', 'y', 'stale'],
      },
    );

    test('uses saved order first and appends new ids in input order', () {
      expect(board.orderCards('todo', ['y', 'x', 'new']), ['x', 'y', 'new']);
    });

    test('returns no ids for an empty input', () {
      expect(board.orderCards('todo', const []), isEmpty);
    });
  });
}
