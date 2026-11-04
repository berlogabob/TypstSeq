import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('reports suspicious notes and markers without changing notes', () async {
    final vault = await Directory.systemTemp.createTemp('tylog_health_');
    addTearDown(() => vault.delete(recursive: true));
    final settings = File('${vault.path}/.tylog/settings.json');
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"version":5}');
    final notes = Directory('${vault.path}/notes');
    await notes.create();
    const good =
        '#show: tylog.note.with(id: "a", title: "A")\n= A\n// tylog:auto-entities\n';
    await File('${notes.path}/a.typ').writeAsString(good);
    await File('${notes.path}/bad.typ').writeAsString('{"revision": 1}');
    await File('${notes.path}/empty.typ').writeAsString('');
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/tylog.dart',
      'vault-health',
      vault.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final files = await Directory(
      '${vault.path}/_system/health',
    ).list().toList();
    final reports = files.where(
      (file) => file.path.endsWith('2026-11-04.json'),
    );
    expect(reports, hasLength(1));
    final report =
        jsonDecode(await File(reports.single.path).readAsString()) as Map;
    final issues = (report['issues'] as List).cast<Map>();
    expect(
      issues,
      containsAll([
        {'path': 'notes/a.typ', 'code': 'auto-entities'},
        {'path': 'notes/bad.typ', 'code': 'missing-note-header'},
        {'path': 'notes/empty.typ', 'code': 'missing-note-header'},
      ]),
    );
    expect(await File('${notes.path}/a.typ').readAsString(), good);
    expect(
      await File('${notes.path}/bad.typ').readAsString(),
      '{"revision": 1}',
    );
  });

  test('compiles a bounded batch and resumes at the next note', () async {
    final vault = await Directory.systemTemp.createTemp('tylog_health_batch_');
    addTearDown(() => vault.delete(recursive: true));
    final settings = File('${vault.path}/.tylog/settings.json');
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"version":5}');
    final notes = Directory('${vault.path}/notes');
    await notes.create();
    for (var i = 0; i < 21; i++) {
      final name = 'note_${i.toString().padLeft(2, '0')}.typ';
      await File('${notes.path}/$name').writeAsString(
        '#show: tylog.note.with(id: "$i", title: "$name")\n= $name\n',
      );
    }
    final bin = Directory('${vault.path}/fake-bin');
    await bin.create();
    final typst = File('${bin.path}/typst');
    await typst.writeAsString(r'''#!/bin/sh
for arg in "$@"; do
  case "$arg" in
    */note_20.typ) exit 1 ;;
  esac
done
exit 0
''');
    await Process.run('chmod', ['+x', typst.path]);

    Future<Map> runReport() async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/tylog.dart', 'vault-health', vault.path],
        environment: {
          ...Platform.environment,
          'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final report = File(
        '${vault.path}/_system/health/${DateTime.now().year.toString().padLeft(4, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}.json',
      );
      return jsonDecode(await report.readAsString()) as Map;
    }

    final first = await runReport();
    expect(first['typstCompile']['checked'], 20);
    expect(
      first['issues'],
      isNot(
        contains({'path': 'notes/note_20.typ', 'code': 'typst-compile-error'}),
      ),
    );
    final second = await runReport();
    expect(second['typstCompile']['checked'], 1);
    expect(
      second['issues'],
      contains(
        predicate<Map>(
          (issue) =>
              issue['path'] == 'notes/note_20.typ' &&
              issue['code'] == 'typst-compile-error',
        ),
      ),
    );
  });
}
