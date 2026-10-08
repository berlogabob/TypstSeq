import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  final repoRoot = Directory.current.path.endsWith('packages/tylog_core')
      ? Directory.current.parent.parent.path
      : Directory.current.path;
  final tmp = Directory('$repoRoot/.dart_tool/tylog_task_fields_test');
  var serial = 0;

  String expectCompiles(String body) {
    final file = File('${tmp.path}/${serial++}.typ')
      ..writeAsStringSync('#import "/typst/tylog/lib.typ" as tylog\n$body');
    final result = Process.runSync('typst', [
      'compile',
      '--root',
      repoRoot,
      file.path,
      '${file.path}.pdf',
    ]);
    expect(
      result.exitCode,
      0,
      reason: '${result.stderr}\n--- source ---\n$body',
    );
    return body;
  }

  const source = r'''// due: "fake", status: "fake"
#tylog.task(id: "other", text: "Untouched", due: none)
#tylog.task(
  id: "t1", text: "Журнал \"status:\" (due: none)",
  status: "todo", priority: "normal",
  scheduled: "2026-10-09", due: "2026-10-10", recurrence: "FREQ=WEEKLY",
  completed: ("2026-10-01T09:00:00Z",),
  properties: ("due": "nested", "custom": (key: "ação",)),
)
After the task.
''';
  const headers = {
    'single line': '#tylog.task(id: "t1", text: "Ship it")\n',
    'multiple lines': '#tylog.task(\n  id: "t1",\n  text: "Ship it",\n)\n',
  };
  final setters = <String, (String, String, String Function(String))>{
    'status': (
      '"todo"',
      '"doing"',
      (s) => setTaskFields(s, 't1', status: 'doing'),
    ),
    'priority': (
      '"normal"',
      '"high"',
      (s) => setTaskFields(s, 't1', priority: 'high'),
    ),
    'scheduled': (
      '"2026-10-09"',
      '"2026-10-15"',
      (s) => setTaskFields(s, 't1', scheduled: '2026-10-15'),
    ),
    'due': (
      '"2026-10-10"',
      '"2026-10-16T14:30:00"',
      (s) => setTaskFields(s, 't1', due: '2026-10-16T14:30:00'),
    ),
    'recurrence': (
      '"FREQ=WEEKLY"',
      '"FREQ=DAILY"',
      (s) => setTaskFields(s, 't1', recurrence: 'FREQ=DAILY'),
    ),
  };
  final now = DateTime.utc(2026, 10, 8, 14, 30);
  final iso = now.toIso8601String();
  const todo = '#tylog.task(id: "t1", text: "Ship it", status: "todo")\n';
  final doing = startTaskClock(
    replaceTaskStatus(todo, 't1', 'doing'),
    't1',
    '2026-10-08T13:00:00.000Z',
  );

  setUpAll(() {
    tmp.createSync(recursive: true);
    expect(
      Process.runSync('which', ['typst']).exitCode,
      0,
      reason: 'These writer tests require real Typst on PATH.',
    );
    for (final fixture in [source, ...headers.values, todo, doing]) {
      expectCompiles(fixture);
    }
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  for (final entry in setters.entries) {
    final (old, next, write) = entry.value;
    test('set ${entry.key} preserves every other byte', () {
      final written = expectCompiles(write(source));
      expect(
        written,
        source.replaceFirst('${entry.key}: $old', '${entry.key}: $next'),
      );
    });
    for (final header in headers.entries) {
      test('append ${entry.key} to ${header.key} task', () {
        final written = expectCompiles(write(header.value));
        expect(
          taskField(written, entry.key),
          next.substring(1, next.length - 1),
        );
        expect(
          written,
          header.value.contains('\n)')
              ? header.value.replaceFirst('\n)', '\n  ${entry.key}: $next,\n)')
              : header.value.replaceFirst(')', ', ${entry.key}: $next,)'),
        );
      });
    }
  }

  final clearers = <String, String Function(String)>{
    'scheduled': (s) => setTaskFields(s, 't1', scheduled: null),
    'due': (s) => setTaskFields(s, 't1', due: null),
    'recurrence': (s) => setTaskFields(s, 't1', recurrence: null),
  };
  for (final entry in clearers.entries) {
    test('clear ${entry.key} to none preserves every other byte', () {
      final written = expectCompiles(entry.value(source));
      expect(
        written,
        source.replaceFirst(
          '${entry.key}: ${setters[entry.key]!.$1}',
          '${entry.key}: none',
        ),
      );
    });
  }
  test('omitting all fields is byte identical', () {
    expect(expectCompiles(setTaskFields(source, 't1')), source);
  });
  test('set multiple fields and clear due in one write', () {
    final written = expectCompiles(
      setTaskFields(
        source,
        't1',
        status: 'cancelled',
        priority: 'low',
        due: null,
      ),
    );
    expect(
      written,
      source
          .replaceFirst('status: "todo"', 'status: "cancelled"')
          .replaceFirst('priority: "normal"', 'priority: "low"')
          .replaceFirst('due: "2026-10-10"', 'due: none'),
    );
  });
  test('string values escape quotes and backslashes', () {
    const value = r'FREQ=DAILY;X="a\b"';
    final written = expectCompiles(
      setTaskFields(source, 't1', recurrence: value),
    );
    final call = locateTypstCalls(
      written,
      names: {'tylog.task'},
    ).singleWhere((c) => taskField(c.source, 'id') == 't1');
    expect(taskField(call.source, 'recurrence'), value);
    expect(
      written,
      source.replaceFirst(
        'recurrence: "FREQ=WEEKLY"',
        r'recurrence: "FREQ=DAILY;X=\"a\\b\""',
      ),
    );
  });

  for (final writer in <String, String Function(String, String)>{
    'setTaskFields': (s, id) => setTaskFields(s, id, status: 'done'),
    'applyTaskStatus': (s, id) => applyTaskStatus(s, id, 'done', now),
  }.entries) {
    test('${writer.key} rejects unknown id like existing writers', () {
      expect(
        () => writer.value(todo, 'missing'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Task missing not found',
          ),
        ),
      );
    });
    test('${writer.key} rejects duplicate id like existing writers', () {
      expect(
        () => writer.value('$todo$todo', 't1'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Duplicate task id "t1" (2 matches)',
          ),
        ),
      );
    });
  }

  test('todo to doing opens a clock', () {
    final written = expectCompiles(applyTaskStatus(todo, 't1', 'doing', now));
    expect(
      written,
      startTaskClock(replaceTaskStatus(todo, 't1', 'doing'), 't1', iso),
    );
    expect(taskClocked(written, 't1').single.start, iso);
    expect(taskClocked(written, 't1').single.end, isNull);
  });
  for (final next in ['todo', 'done', 'cancelled']) {
    test('doing to $next closes the running clock', () {
      final written = expectCompiles(applyTaskStatus(doing, 't1', next, now));
      expect(
        written,
        replaceTaskStatus(stopTaskClock(doing, 't1', iso), 't1', next),
      );
      expect(taskClocked(written, 't1').single.end, iso);
    });
  }
  test(
    'entering doing stops and demotes another running task in this source',
    () {
      const second = '#tylog.task(id: "t2", text: "Next", status: "todo")\n';
      final both = '$doing$second';
      expectCompiles(both);
      final written = expectCompiles(applyTaskStatus(both, 't2', 'doing', now));
      final calls = locateTypstCalls(written, names: {'tylog.task'});
      expect(taskField(calls.first.source, 'status'), 'todo');
      expect(taskClocked(written, 't1').single.end, iso);
      expect(taskField(calls.last.source, 'status'), 'doing');
      expect(taskClocked(written, 't2').single.start, iso);
      expect(taskClocked(written, 't2').single.end, isNull);
    },
  );
  test('cancelled closes a clock even if status was todo', () {
    final running = startTaskClock(todo, 't1', '2026-10-08T13:00:00.000Z');
    expectCompiles(running);
    final written = expectCompiles(
      applyTaskStatus(running, 't1', 'cancelled', now),
    );
    expect(taskField(written, 'status'), 'cancelled');
    expect(taskClocked(written, 't1').single.end, iso);
  });
  for (final status in ['todo', 'doing']) {
    test('repeating $status task done records occurrence and remains todo', () {
      final repeating = status == 'todo'
          ? source
          : startTaskClock(
              replaceTaskStatus(source, 't1', 'doing'),
              't1',
              '2026-10-08T13:00:00.000Z',
            );
      expectCompiles(repeating);
      final written = expectCompiles(
        applyTaskStatus(repeating, 't1', 'done', now),
      );
      expect(
        written,
        completeTaskOccurrence(
          replaceTaskStatus(stopTaskClock(repeating, 't1', iso), 't1', 'todo'),
          't1',
          iso,
        ),
      );
      final call = locateTypstCalls(
        written,
        names: {'tylog.task'},
      ).singleWhere((c) => taskField(c.source, 'id') == 't1');
      expect(taskField(call.source, 'status'), 'todo');
      expect(taskField(call.source, 'due'), '2026-10-10');
      expect(taskField(call.source, 'recurrence'), 'FREQ=WEEKLY');
      expect(taskClocked(written, 't1').every((c) => c.end != null), isTrue);
    });
  }
}
