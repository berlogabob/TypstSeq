import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/connectors/connector.dart';
import 'package:tylog/connectors/olt_connector.dart';
import 'package:tylog/widgets/external_entity_page.dart';
import 'package:tylog_core/models.dart';

void main() {
  test('entities are empty while bookings remain in Incoming', () async {
    final connector = OltConnector(
      () async => {
        'activities': [
          {
            'id': 42,
            'title': 'Microscope booking',
            'status': 'requested',
            'starts_at': '2026-11-17T10:00:00Z',
          },
        ],
      },
    );
    await connector.refresh();
    expect(connector.entities(), isEmpty);
    expect(connector.incoming('2026-11-17').single.title, 'Microscope booking');
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
