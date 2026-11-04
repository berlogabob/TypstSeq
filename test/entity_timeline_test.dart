import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/widgets/entity_timeline.dart';

void main() {
  testWidgets('shows indexed links and matching tasks in dated pages', (
    tester,
  ) async {
    const entity = NoteRef(
      id: 'p',
      path: 'p.typ',
      title: 'Person',
      kind: 'person',
      outgoingLinks: [],
    );
    final notes = <String, NoteRef>{'p.typ': entity};
    for (var i = 0; i < 21; i++) {
      notes['$i.typ'] = NoteRef(
        id: '$i',
        path: '$i.typ',
        title: 'Note $i',
        kind: i == 0 ? 'audio' : 'note',
        date: '2026-11-${(i + 1).toString().padLeft(2, '0')}',
        outgoingLinks: const ['p'],
      );
    }
    final index = VaultIndex(
      notesByPath: notes,
      backlinksByTarget: {
        'p.typ': [for (var i = 0; i < 21; i++) '$i.typ'],
      },
      tasks: const [
        TaskRef(
          id: 't',
          notePath: '0.typ',
          text: 'Call',
          assignees: ['p'],
          due: '2026-12-01',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntityTimeline(
            entity: entity,
            index: index,
            onOpenPath: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Timeline (22)'), findsOneWidget);
    expect(find.text('2026-12-01'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Show more'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Show more'), findsOneWidget);
    await tester.tap(find.text('Show more'));
    await tester.pump();
    expect(find.text('Show more'), findsNothing);
  });
}
