import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/entity_header.dart';
import 'package:tylog/widgets/linked_references.dart';

NoteRef _note({
  required String id,
  required String title,
  String kind = 'note',
  List<String> aliases = const [],
  Map<String, Object?> properties = const {},
}) => NoteRef(
  id: id,
  path: 'notes/$id.typ',
  title: title,
  kind: kind,
  aliases: aliases,
  properties: properties,
  outgoingLinks: const [],
);

void main() {
  testWidgets('EntityHeader shows aliases + a tappable email', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityHeader(
            note: _note(
              id: 'fernando',
              title: 'Fernando Marson',
              kind: 'person',
              aliases: ['Fernando'],
              properties: {'email': 'fernando@example.com'},
            ),
            onOpenUrl: tapped.add,
          ),
        ),
      ),
    );
    expect(find.text('Fernando Marson'), findsOneWidget);
    expect(find.text('person'), findsOneWidget);
    expect(find.text('Fernando'), findsOneWidget); // alias chip
    expect(find.text('fernando@example.com'), findsOneWidget);
    await tester.tap(find.text('fernando@example.com'));
    expect(tapped, ['mailto:fernando@example.com']);
  });

  testWidgets('LinkedReferences shows the referencing note + mention excerpt', (
    tester,
  ) async {
    const index = VaultIndex(
      notesByPath: {
        'daily/2026-07-21.typ': NoteRef(
          id: '2026-07-21',
          path: 'daily/2026-07-21.typ',
          title: '2026-07-21',
          kind: 'daily',
          outgoingLinks: [],
        ),
      },
      backlinksByTarget: {},
    );
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkedReferences(
            backlinks: const ['daily/2026-07-21.typ'],
            index: index,
            targets: const {'fernando', 'fernando marson'},
            readSource: (path) async =>
                'met #tylog.ref-note("fernando")[Fernando] about the launch',
            onOpenPath: opened.add,
          ),
        ),
      ),
    );
    await tester.pump(); // resolve the source future
    await tester.pump();
    expect(find.text('Linked references (1)'), findsOneWidget);
    expect(find.text('2026-07-21'), findsOneWidget);
    expect(find.text('met Fernando about the launch'), findsOneWidget);
    await tester.tap(find.text('2026-07-21'));
    expect(opened, ['daily/2026-07-21.typ']);
  });
}
