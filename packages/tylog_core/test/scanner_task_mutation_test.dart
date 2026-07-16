import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  group('replaceTaskStatus', () {
    test(
      'does not corrupt a text field that contains a status:-shaped literal',
      () {
        // The text value ends in "status: " right before its own closing
        // quote. The naive `status\s*:\s*"[^"]*"` regex latches onto the
        // word "status:" inside the text, treats the text field's own
        // closing quote as the opening quote of the "value", and then
        // greedily eats forward through the comma/newline/field-name up to
        // the *real* status field's opening quote — corrupting everything
        // in between.
        const source = '''
#tylog.task(
  id: "t1",
  text: "please review status: ",
  status: "todo",
  priority: "normal",
)
''';
        final updated = replaceTaskStatus(source, 't1', 'doing');

        // Everything except the status value must survive byte-identical:
        // only "todo" -> "doing" should change.
        expect(updated, source.replaceFirst('status: "todo"', 'status: "doing"'));
      },
    );

    test('escaped quotes in text field do not confuse the field locator', () {
      const source = '''
#tylog.task(
  id: "t1",
  text: "say \\"hi\\" to status: \\"blocked\\"",
  status: "todo",
)
''';
      final updated = replaceTaskStatus(source, 't1', 'done');

      expect(updated, contains('status: "done"'));
      expect(
        updated,
        contains(r'text: "say \"hi\" to status: \"blocked\""'),
      );
    });

    test('a // comment containing status: does not confuse the locator', () {
      const source = '''
// status: "fake" pretend field
#tylog.task(
  id: "t1",
  text: "hello",
  status: "todo",
)
''';
      final updated = replaceTaskStatus(source, 't1', 'done');

      expect(updated, contains('status: "done"'));
      expect(updated, contains('// status: "fake" pretend field'));
    });

    test('only mutates the task whose id matches, among adjacent tasks', () {
      const source = '''
#tylog.task(id: "a", text: "first", status: "todo")
#tylog.task(id: "b", text: "second", status: "todo")
''';
      final updated = replaceTaskStatus(source, 'b', 'done');

      expect(
        updated,
        contains('#tylog.task(id: "a", text: "first", status: "todo")'),
      );
      expect(
        updated,
        contains('#tylog.task(id: "b", text: "second", status: "done")'),
      );
    });

    test('round trip: parsing after replace changes exactly one field', () {
      const source = '''
#tylog.task(
  id: "t1",
  text: "review status: \\"done\\" field",
  status: "todo",
  priority: "normal",
  project: "demo",
)
''';
      final before = scanNote('notes/a.typ', source);
      final updated = replaceTaskStatus(source, 't1', 'done');
      final after = scanNote('notes/a.typ', updated);

      // NoteRef itself is untouched by task mutation.
      expect(after.id, before.id);
      expect(after.title, before.title);

      // The only textual difference between source and updated is the
      // status field value.
      expect(updated, isNot(equals(source)));
      final beforeTasks = _fallbackTasksFor(source);
      final afterTasks = _fallbackTasksFor(updated);
      expect(afterTasks.single.status, 'done');
      expect(beforeTasks.single.status, 'todo');
      expect(afterTasks.single.text, beforeTasks.single.text);
      expect(afterTasks.single.id, beforeTasks.single.id);
      expect(afterTasks.single.priority, beforeTasks.single.priority);
      expect(afterTasks.single.project, beforeTasks.single.project);
    });
  });

  group('completeTaskOccurrence', () {
    test('does not corrupt text field shaped like completed: (...)', () {
      const source = '''
#tylog.task(
  id: "t1",
  text: "note completed: (\\"2020-01-01\\",) already",
  status: "todo",
  completed: (),
)
''';
      final updated = completeTaskOccurrence(source, 't1', '2024-01-02T00:00:00');

      // Everything except the completed tuple must survive byte-identical.
      expect(
        updated,
        source.replaceFirst('completed: ()', 'completed: ("2024-01-02T00:00:00",)'),
      );
    });

    test(
      'a text field with nested parens shaped like completed: (...) does '
      'not truncate the naive [^)]* match into the wrong place',
      () {
        // The old `completed\s*:\s*\(([^)]*)\)` regex stops at the FIRST
        // `)` it sees, so a fake "completed: (info (nested) more)" inside
        // free text truncates right after the inner ")" of "(nested)",
        // splicing the timestamp into the middle of the text field.
        const source = '''
#tylog.task(
  id: "t1",
  text: "completed: (info (nested) more) noted",
  completed: ("2024-01-01T00:00:00",),
)
''';
        final updated = completeTaskOccurrence(
          source,
          't1',
          '2024-02-02T00:00:00',
        );

        // Everything except the completed tuple must survive byte-identical.
        expect(
          updated,
          source.replaceFirst(
            'completed: ("2024-01-01T00:00:00",)',
            'completed: ("2024-01-01T00:00:00","2024-02-02T00:00:00",)',
          ),
        );
      },
    );

    test('only mutates the task whose id matches, among adjacent tasks', () {
      const source = '''
#tylog.task(id: "a", text: "first", completed: ())
#tylog.task(id: "b", text: "second", completed: ())
''';
      final updated = completeTaskOccurrence(source, 'b', '2024-01-01T00:00:00');

      expect(
        updated,
        contains('#tylog.task(id: "a", text: "first", completed: ())'),
      );
      expect(
        updated,
        contains(
          '#tylog.task(id: "b", text: "second", completed: ("2024-01-01T00:00:00",))',
        ),
      );
    });
  });

  group('replaceTaskText', () {
    test('replaces only the text field on a full-fat task fixture', () {
      const source = '''
#tylog.task(
  id: "t1",
  text: "old",
  due: "2024-01-01",
  project: "demo",
  status: "todo",
  priority: "normal",
  scheduled: "2024-01-01",
  remind: "2024-01-01T09:00:00",
  timezone: "UTC",
  recurrence: "weekly",
  dependencies: ("dep-1", "dep-2"),
  assignees: ("alice", "bob"),
  tags: ("home", "urgent"),
  completed: ("2023-12-31T00:00:00",),
  properties: (note: "value", nested: (inner: "deep")),
)
''';
      final updated = replaceTaskText(source, 't1', 'new');

      expect(updated, source.replaceFirst('text: "old"', 'text: "new"'));
    });

    test('escape round trip preserves quotes and backslashes', () {
      const source = '''
#tylog.task(
  id: "t1",
  text: "old",
  status: "todo",
)
''';
      const tricky = r'she said "hi" \o/ back\slash';
      final updated = replaceTaskText(source, 't1', tricky);

      expect(taskField(updated, 'text'), tricky);
    });

    test('does not corrupt a properties decoy shaped like a text field', () {
      const source = '''
#tylog.task(
  id: "t1",
  text: "old",
  status: "todo",
  properties: (note: "text: \\"decoy\\""),
)
''';
      final updated = replaceTaskText(source, 't1', 'new');

      expect(updated, source.replaceFirst('text: "old"', 'text: "new"'));
      expect(updated, contains(r'properties: (note: "text: \"decoy\"")'));
    });

    test('existing escaped quotes in the text value do not confuse the locator', () {
      const source = '''
#tylog.task(
  id: "t1",
  text: "say \\"hi\\" already",
  status: "todo",
)
''';
      final updated = replaceTaskText(source, 't1', 'new');

      expect(
        updated,
        source.replaceFirst(r'text: "say \"hi\" already"', 'text: "new"'),
      );
    });

    test('inserts a missing text field before the closing paren', () {
      const source = '''
#tylog.task(
  id: "t1",
  status: "todo",
)
''';
      final updated = replaceTaskText(source, 't1', 'new');

      expect(taskField(updated, 'text'), 'new');
      expect(taskField(updated, 'status'), 'todo');
    });

    test('throws on duplicate ids instead of guessing', () {
      const source = '''
#tylog.task(id: "dup", text: "first", status: "todo")
#tylog.task(id: "dup", text: "second", status: "todo")
''';
      expect(
        () => replaceTaskText(source, 'dup', 'new'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Duplicate task id'),
          ),
        ),
      );
    });

    test('throws when the id is missing', () {
      const source = '#tylog.task(id: "t1", text: "first", status: "todo")\n';
      expect(
        () => replaceTaskText(source, 'missing', 'new'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not found'),
          ),
        ),
      );
    });
  });

  group('taskField', () {
    const source = '''
#tylog.task(
  id: "t1",
  text: "review status: \\"done\\" pretend field",
  status: "todo",
  due: none,
)
''';

    test('reads text, status, and id', () {
      expect(taskField(source, 'id'), 't1');
      expect(taskField(source, 'status'), 'todo');
      expect(
        taskField(source, 'text'),
        'review status: "done" pretend field',
      );
    });

    test('a status-shaped decoy inside the text value does not fool it', () {
      expect(taskField(source, 'status'), 'todo');
    });

    test('returns null for an absent field', () {
      expect(taskField(source, 'priority'), isNull);
    });

    test('returns null for a non-string value like due: none', () {
      expect(taskField(source, 'due'), isNull);
    });
  });

  group('duplicate task ids', () {
    test('replaceTaskStatus throws on duplicate ids instead of guessing', () {
      const source = '''
#tylog.task(id: "dup", text: "first", status: "todo")
#tylog.task(id: "dup", text: "second", status: "todo")
''';
      expect(
        () => replaceTaskStatus(source, 'dup', 'done'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Duplicate task id'),
          ),
        ),
      );
    });

    test(
      'completeTaskOccurrence throws on duplicate ids instead of guessing',
      () {
        const source = '''
#tylog.task(id: "dup", text: "first", completed: ())
#tylog.task(id: "dup", text: "second", completed: ())
''';
        expect(
          () => completeTaskOccurrence(source, 'dup', '2024-01-01T00:00:00'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Duplicate task id'),
            ),
          ),
        );
      },
    );
  });
}

List<TaskRef> _fallbackTasksFor(String source) {
  final note = scanNote('notes/a.typ', source);
  // scanNote does not expose tasks directly; use scanVaultStorage-free path
  // via the public fallback by scanning the note's tasks through the vault
  // storage helper is overkill here, so we reach into locateTypstCalls.
  final calls = locateTypstCalls(source, names: const {'tylog.task'});
  return calls
      .map(
        (call) => TaskRef(
          id: _fieldFrom(call.source, 'id') ?? '',
          notePath: note.path,
          text: _fieldFrom(call.source, 'text') ?? '',
          status: _fieldFrom(call.source, 'status') ?? 'todo',
          priority: _fieldFrom(call.source, 'priority') ?? 'normal',
          project: _fieldFrom(call.source, 'project'),
        ),
      )
      .toList();
}

String? _fieldFrom(String source, String name) =>
    RegExp('$name\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"')
        .firstMatch(source)
        ?.group(1)
        ?.replaceAllMapped(RegExp(r'\\(.)'), (match) => match.group(1)!);
