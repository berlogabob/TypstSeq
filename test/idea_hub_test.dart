import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/calendar_feeds.dart';
import 'package:tylog/models.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/widgets/idea_hub.dart';
import 'package:tylog/widgets/property_select_chip.dart';

const idea = NoteRef(
  id: 'idea',
  path: 'ideas/i.typ',
  title: 'An idea',
  kind: 'idea',
  date: '2026-09-01',
  outgoingLinks: [],
);
const history = '''- 2026-10-05: outside
= History
- 2026-10-04: submitted
- 2026-10-05: approved
- 2026-10-05: connected
- invalid: ignored
= Matches
- 2026-10-05: outside again
''';
void main() {
  test('idea History accepts Typst-escaped dates', () {
    const source = r'''= History
- 2026\-09\-25: submitted
- 2026-09-25: approved
- 2026\-09\-26: ignored
''';
    expect(ideaHistoryOnDay(source, '2026-09-25'), ['submitted', 'approved']);
  });
  test('idea kind and status preserve header fields and body', () {
    const source =
        '#show: tylog.note.with(id: "n", title: "Draft", kind: "note", tags: ("test",), properties: (email: "a@b.c",))\nMy writing';
    final updated = setIdeaKind('notes/n.typ', source, true);
    final note = scanNote('notes/n.typ', updated);
    expect(standardNoteKinds, contains('idea'));
    expect(note.kind, 'idea');
    expect(note.properties['status'], 'new');
    expect(note.properties['email'], 'a@b.c');
    expect(note.tags, contains('test'));
    expect(updated, endsWith('My writing'));
    expect(
      scanNote('notes/n.typ', setIdeaKind('notes/n.typ', updated, false)).kind,
      'note',
    );
    expect(ideaHistoryOnDay(history, '2026-10-05'), ['approved', 'connected']);
    expect(
      ideaHistoryOnDay(
        history.replaceAll('= History', '## History'),
        '2026-10-04',
      ),
      ['submitted'],
    );
  });
  test('consultation labels include worker time, student and status', () {
    final label = materializedEventLabel(
      const NoteRef(
        id: 'c',
        path: 'events/c.typ',
        title: 'Project review',
        kind: 'event',
        date: '2026-10-05',
        outgoingLinks: [],
        properties: {
          'event_type': 'consultation',
          'start': '10:00',
          'end': '11:00',
          'student': 'Ada',
          'status': 'confirmed',
        },
      ),
    );
    expect(
      label,
      'Project review · Consultation · 10:00–11:00 · Ada · confirmed',
    );
  });
  testWidgets('idea controls toggle and select status', (tester) async {
    final changes = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeaProperties(
            note: idea,
            onToggle: changes.add,
            onStatus: changes.add,
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(PropertySelectChip, 'New'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approved'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Idea'));
    expect(changes, ['approved', false]);
  });
  testWidgets(
    'day strip reads History via IO, skips missing notes, opens idea',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('idea-day-'),
      ))!;
      addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
      final file = File('${dir.path}/idea.typ');
      late Future<String> sourceRead;
      await tester.runAsync(() async {
        await file.writeAsString(history);
        sourceRead = file.readAsString();
      });
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdeaHubStrip(
              index: VaultIndex(
                notesByPath: {
                  idea.path: idea,
                  'ideas/missing.typ': const NoteRef(
                    id: 'missing',
                    path: 'ideas/missing.typ',
                    title: 'Missing',
                    kind: 'idea',
                    outgoingLinks: [],
                  ),
                },
                backlinksByTarget: {},
                tasks: [],
              ),
              day: '2026-10-05',
              readSource: (path) {
                if (path != idea.path) {
                  return Future.error(const FileSystemException('removed'));
                }
                return sourceRead;
              },
              onOpenPath: opened.add,
            ),
          ),
        ),
      );
      await tester.runAsync(() => sourceRead);
      await tester.pump();
      await tester.pump();
      expect(find.text('Idea hub (2)'), findsOneWidget);
      expect(find.text('approved'), findsOneWidget);
      expect(find.text('submitted'), findsNothing);
      await tester.tap(find.text('approved'));
      expect(opened, [idea.path]);
    },
  );
}
