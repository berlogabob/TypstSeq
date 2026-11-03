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
      containsAll(['olt:place:3', 'note']),
    );
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
