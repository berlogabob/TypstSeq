import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

/// Every writer's *actual output* has to compile.
///
/// `scanNote` is deliberately lenient — it read `kind: "note"  properties: (…)`
/// back as a perfectly good note, so a parse-based test passes on output Typst
/// rejects. That leniency is why 167 real notes stopped compiling with nothing
/// failing in CI. The fixture in `typst/tylog/tests/app_written.typ` proves a
/// hand-written shape compiles; this proves the shape the writer *produces*
/// does, which is the half that was missing.
///
/// Skipped when `typst` isn't on PATH (`make test-typst` is the gate that
/// always has it).
void main() {
  final repoRoot = Directory.current.path.endsWith('packages/tylog_core')
      ? Directory.current.parent.parent.path
      : Directory.current.path;

  // Typst refuses a source file outside `--root`, so the scratch files have to
  // live inside the repo. `.dart_tool` is already ignored.
  final tmp = Directory('$repoRoot/.dart_tool/tylog_writer_test');
  setUpAll(() => tmp.createSync(recursive: true));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  final hasTypst = Process.runSync('which', ['typst']).exitCode == 0;

  void expectCompiles(String label, String body) {
    if (!hasTypst) {
      markTestSkipped('typst not on PATH');
      return;
    }
    final file = File('${tmp.path}/${label.replaceAll(' ', '-')}.typ')
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
      reason: 'writer output does not compile ($label):\n'
          '${result.stderr}\n--- source ---\n${file.readAsStringSync()}',
    );
  }

  // Both header forms, because they take different branches: a single-line
  // header has no trailing comma, so the field append has to supply one.
  const headers = {
    'single-line header':
        '#show: tylog.note.with(id: "a", title: "A", kind: "note")\n',
    'multi-line header':
        '#show: tylog.note.with(\n  id: "a",\n  title: "A",\n  kind: "note",\n)\n',
  };

  headers.forEach((label, source) {
    test('replaceNoteProperty output compiles ($label)', () {
      expectCompiles('$label-prop', replaceNoteProperty(source, 'status', 'read'));
    });
  });

  const tasks = {
    'single-line task':
        '#tylog.task(id: "t1", text: "Ship it", due: none, project: none)\n',
    'multi-line task':
        '#tylog.task(\n  id: "t1",\n  text: "Ship it",\n  status: "todo",\n)\n',
  };

  tasks.forEach((label, source) {
    test('replaceTaskStatus output compiles ($label)', () {
      expectCompiles('$label-status', replaceTaskStatus(source, 't1', 'done'));
    });

    test('startTaskClock output compiles ($label)', () {
      expectCompiles(
        '$label-clock',
        startTaskClock(source, 't1', '2025-12-25T12:33:43'),
      );
    });

    test('start+stop clock output compiles ($label)', () {
      final started =
          startTaskClock(source, 't1', '2025-12-25T12:33:43');
      expectCompiles(
        '$label-clock-stop',
        stopTaskClock(started, 't1', '2025-12-25T13:45:02'),
      );
    });
  });
}
