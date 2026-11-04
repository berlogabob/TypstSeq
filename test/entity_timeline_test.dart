import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/widgets/entity_timeline.dart';

void main() {
  testWidgets('reuses entries and defers changed index while collapsed', (
    tester,
  ) async {
    const entity = NoteRef(
      id: 'p',
      path: 'p.typ',
      title: 'Person',
      kind: 'person',
      outgoingLinks: [],
    );
    final tasks = _CountingTasks([
      const TaskRef(
        id: 't',
        notePath: 'p.typ',
        text: 'First',
        assignees: ['p'],
      ),
    ]);
    VaultIndex indexFor(_CountingTasks tasks) => VaultIndex(
      notesByPath: {'p.typ': entity},
      backlinksByTarget: const {},
      tasks: tasks,
    );
    var index = indexFor(tasks);
    Widget build() => MaterialApp(
      home: Scaffold(
        body: EntityTimeline(entity: entity, index: index, onOpenPath: (_) {}),
      ),
    );
    await tester.pumpWidget(build());
    expect(find.text('First'), findsOneWidget);
    expect(tasks.reads, greaterThan(0));
    tasks.reads = 0;
    await tester.pumpWidget(build());
    expect(tasks.reads, 0);
    await tester.tap(find.text('Timeline (1)'));
    await tester.pump();
    final changed = _CountingTasks([
      const TaskRef(
        id: 't2',
        notePath: 'p.typ',
        text: 'Second',
        assignees: ['p'],
      ),
    ]);
    index = indexFor(changed);
    await tester.pumpWidget(build());
    expect(changed.reads, 0);
    await tester.tap(find.text('Timeline'));
    await tester.pump();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });

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

class _CountingTasks extends ListBase<TaskRef> {
  _CountingTasks(this.items);
  final List<TaskRef> items;
  int reads = 0;
  @override
  int get length => items.length;
  @override
  set length(int value) => items.length = value;
  @override
  TaskRef operator [](int index) {
    reads++;
    return items[index];
  }

  @override
  void operator []=(int index, TaskRef value) => items[index] = value;
}
