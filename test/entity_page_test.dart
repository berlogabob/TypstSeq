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
  testWidgets('narrow header keeps title and actions accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityHeader(
            note: _note(id: 'tylog', title: 'TyLog', kind: 'project'),
            onOpenUrl: (_) {},
            onOpenBoard: () => opened.add('Board'),
          ),
        ),
      ),
    );
    final title = tester.widget<Text>(find.text('TyLog'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Tree'), findsNothing);
    expect(find.text('Whiteboard'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Board')).dy,
      greaterThan(tester.getTopLeft(find.text('TyLog')).dy),
    );
    await tester.tap(find.text('Board'));
    expect(opened, ['Board']);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('Person'), findsOneWidget);
    // Collapsed by default: details stay hidden so the body is on screen.
    expect(find.text('Fernando'), findsNothing);
    expect(find.text('fernando@example.com'), findsNothing);
    expect(find.text('person'), findsNothing); // kind tag is not repeated
    await tester.tap(find.text('Details (2)'));
    await tester.pump();
    expect(find.text('Fernando'), findsOneWidget); // alias chip
    expect(find.text('fernando@example.com'), findsOneWidget);
    await tester.tap(find.text('fernando@example.com'));
    expect(tapped, ['mailto:fernando@example.com']);
    await tester.tap(find.text('Hide details'));
    await tester.pump();
    expect(find.text('fernando@example.com'), findsNothing);
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
