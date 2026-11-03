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
      }).moveCard('a', 'done');
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
      ).moveCard('card', 'done');

      expect(result.order, {
        'todo': ['x'],
        'doing': ['y'],
        'done': ['card'],
      });
    });

    test('moves within a column to an index', () {
      expect(board().moveCard('a', 'todo', index: 1).order['todo'], ['b', 'a']);
    });

    test('clamps indices below and above the column bounds', () {
      expect(board().moveCard('c', 'todo', index: -10).order['todo'], [
        'c',
        'a',
        'b',
      ]);
      expect(board().moveCard('c', 'todo', index: 99).order['todo'], [
        'a',
        'b',
        'c',
      ]);
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
