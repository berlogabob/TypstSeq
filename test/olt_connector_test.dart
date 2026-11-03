import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/connectors/connector.dart';
import 'package:tylog/widgets/external_entity_page.dart';
import 'package:tylog/connectors/olt_connector.dart';
import 'package:tylog/widgets/entity_tree.dart';
import 'package:tylog_core/models.dart';

void main() {
  test('cached places and notes nest under their external parents', () async {
    final connector = OltConnector(
      () async => {
        'items': [
          {'id': 5, 'name': 'Microscope', 'unit': 'pcs'},
        ],
        'assets': [
          {
            'id': 7,
            'tag': 'A7',
            'item_id': 5,
            'condition': 'good',
            'seen_at': '2026-11-03',
          },
        ],
        'asset_place': [
          {'asset_id': 7, 'place_id': 2},
        ],
        'stock': [
          {'item_id': 5, 'place_id': 2, 'qty': 3},
        ],
        'places': [
          {'id': 1, 'name': 'Building', 'code': 'B'},
          {'id': 2, 'name': 'Room', 'code': 'R15', 'parent_id': 1},
          {'id': 3, 'name': 'Desk', 'parent_id': 2},
        ],
      },
    );
    await connector.refresh();
    final places = connector.entities().map((e) => e.toNoteRef()).toList();
    final note = NoteRef(
      id: 'note',
      path: 'note.typ',
      title: 'Note',
      outgoingLinks: const [],
      partOf: const ['olt:place:R15'],
    );
    final all = [...places, note];
    final tree = buildEntityTree(all, all.map((n) => n.path).toSet());
    expect(tree.single.note.id, 'olt:place:B');
    final room = tree.single.children.single;
    expect(room.note.id, 'olt:place:R15');
    expect(
      room.children.map((n) => n.note.id),
      containsAll(['olt:place:3', 'olt:asset:A7', 'note']),
    );
  });

  testWidgets('place displays cached assets and stock', (tester) async {
    late OltConnector connector;
    await tester.runAsync(() async {
      connector = OltConnector(
        () async => {
          'places': [
            {'id': 1, 'name': 'Room', 'code': 'R'},
          ],
          'items': [
            {'id': 2, 'name': 'Lens', 'unit': 'pcs'},
          ],
          'assets': [
            {
              'id': 3,
              'tag': 'A3',
              'item_id': 2,
              'condition': 'good',
              'seen_at': '2026-11-03',
            },
          ],
          'asset_place': [
            {'asset_id': 3, 'place_id': 1},
          ],
          'stock': [
            {'item_id': 2, 'place_id': 1, 'qty': 4},
          ],
        },
      );
      await connector.refresh();
    });
    final entities = connector.entities();
    await tester.pumpWidget(
      MaterialApp(
        home: ExternalEntityPage(
          entity: entities.first,
          notes: entities.map((e) => e.toNoteRef()).toList(),
          onOpen: (_) {},
        ),
      ),
    );
    expect(find.text('Assets here'), findsOneWidget);
    expect(find.text('A3'), findsOneWidget);
    expect(find.text('Lens · good · 2026-11-03'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Lens'), findsOneWidget);
    expect(find.text('4 pcs'), findsOneWidget);
  });
  testWidgets('external page displays children and references without writes', (
    tester,
  ) async {
    const entity = ExternalEntity(
      id: 'olt:place:R15',
      kind: 'place',
      title: 'Room',
    );
    final notes = [
      entity.toNoteRef(),
      const NoteRef(
        id: 'child',
        path: 'child.typ',
        title: 'Child',
        outgoingLinks: [],
        partOf: ['olt:place:R15'],
      ),
      const NoteRef(
        id: 'ref',
        path: 'ref.typ',
        title: 'Reference',
        outgoingLinks: ['olt:place:R15'],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: ExternalEntityPage(entity: entity, notes: notes, onOpen: (_) {}),
      ),
    );
    expect(find.text('Read only'), findsOneWidget);
    expect(find.text('Child'), findsOneWidget);
    expect(find.text('Reference'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
