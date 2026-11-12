import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/widgets/constants.dart';
import 'package:tylog/widgets/entity_relationships.dart';

void main() {
  const lab = NoteRef(
    id: 'lab',
    path: 'notes/lab.typ',
    title: 'Lab',
    kind: 'organization',
    outgoingLinks: [],
  );
  const university = NoteRef(
    id: 'uni',
    path: 'notes/uni.typ',
    title: 'University',
    kind: 'place',
    outgoingLinks: [],
  );
  const person = NoteRef(
    id: 'person',
    path: 'notes/person.typ',
    title: 'Ada',
    kind: 'person',
    outgoingLinks: [],
    partOf: ['lab', 'uni'],
  );
  const paper = NoteRef(
    id: 'paper',
    path: 'notes/paper.typ',
    title: 'Paper',
    kind: 'article',
    outgoingLinks: [],
    partOf: ['lab'],
  );
  final index = VaultIndex(
    notesByPath: {
      for (final note in [lab, university, person, paper]) note.path: note,
    },
    backlinksByTarget: const {},
  );

  testWidgets('parent chips open, remove by id, and offer adding', (
    tester,
  ) async {
    String? opened;
    String? removed;
    var added = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: EntityRelationships(
              note: person,
              index: index,
              onAdd: () => added = true,
              onRemove: (id) => removed = id,
              onOpen: (path) => opened = path,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(InputChip), findsNWidgets(2));
    expect(find.byIcon(iconForKind(lab.kind)), findsOneWidget);
    await tester.tap(find.text('University'));
    expect(opened, university.path);
    final chip = find.widgetWithText(InputChip, 'Lab');
    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(Icons.close)),
    );
    expect(removed, 'lab');
    await tester.tap(find.byTooltip('Add parent'));
    expect(added, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Contains groups kinds and lists a child under each parent', (
    tester,
  ) async {
    String? opened;
    for (final parent in [lab, university]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntityRelationships(
              note: parent,
              index: index,
              onAdd: () {},
              onRemove: (_) {},
              onOpen: (path) => opened = path,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contains ${parent == lab ? 2 : 1}'));
      await tester.pumpAndSettle();
      expect(find.text('Person (1)'), findsOneWidget);
      expect(find.byIcon(iconForKind('person')), findsOneWidget);
      expect(find.text('Paper'), parent == lab ? findsOneWidget : findsNothing);
      await tester.ensureVisible(find.text('Ada'));
      await tester.tap(find.text('Ada'));
      expect(opened, person.path);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('long parent names remain actionable on a 360 dp screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const parent = NoteRef(
      id: 'long-parent',
      path: 'notes/long-parent.typ',
      title: 'A very long organization name that cannot fit on a phone chip',
      kind: 'organization',
      outgoingLinks: [],
    );
    const child = NoteRef(
      id: 'child',
      path: 'notes/child.typ',
      title: 'Child',
      outgoingLinks: [],
      partOf: ['long-parent'],
    );
    final phoneIndex = VaultIndex(
      notesByPath: {parent.path: parent, child.path: child},
      backlinksByTarget: {},
    );
    String? opened;
    String? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityRelationships(
            note: child,
            index: phoneIndex,
            onAdd: () {},
            onRemove: (id) => removed = id,
            onOpen: (path) => opened = path,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final parentLabel = tester.widget<Text>(find.text(parent.title));
    expect(parentLabel.maxLines, 1);
    expect(parentLabel.overflow, TextOverflow.ellipsis);
    await tester.tap(find.text(parent.title));
    expect(opened, parent.path);
    await tester.tap(find.byIcon(Icons.close));
    expect(removed, parent.id);
    await tester.tap(find.text('Contains 0'));
    await tester.pumpAndSettle();
    expect(find.text('No children'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy project parent can be removed from the saved header', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('entity-relationship'),
    );
    final file = File('${dir!.path}/person.typ');
    const body = '\n\nBody stays byte-for-byte.\n';
    const source =
        '#import "/_system/tylog.typ" as tylog\n'
        '#show: tylog.note.with(id: "person", title: "Ada", '
        'kind: "person", project: "lab", '
        'properties: (part_of: ("lab", "uni"),))$body';
    await tester.runAsync(() => file.writeAsString(source));
    final legacyPerson = NoteRef(
      id: 'person',
      path: file.path,
      title: 'Ada',
      kind: 'person',
      outgoingLinks: const [],
      project: 'lab',
      partOf: const ['lab', 'uni'],
    );
    var removed = false;
    Future<void>? saveOnRemove;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityRelationships(
            note: legacyPerson,
            index: index,
            onAdd: () {},
            onOpen: (_) {},
            onRemove: (id) {
              removed = true;
              saveOnRemove = tester.runAsync(() async {
                var updated = await file.readAsString();
                updated = replaceNoteFields(updated, const {'project': 'none'});
                updated = replaceNotePartOf(
                  updated,
                  NoteMetadataDraft.fromNote(legacyPerson),
                  const ['uni'],
                );
                await file.writeAsString(updated);
              });
            },
          ),
        ),
      ),
    );
    final chip = find.widgetWithText(InputChip, 'Lab');
    expect(tester.widget<InputChip>(chip).onDeleted, isNotNull);
    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(Icons.close)),
    );
    await tester.pump();
    await saveOnRemove;
    final saved = await tester.runAsync(file.readAsString);
    expect(removed, isTrue);
    expect(saved, contains('project: none'));
    expect(saved, contains('"part_of": ("uni",)'));
    expect(saved, endsWith(body));
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
