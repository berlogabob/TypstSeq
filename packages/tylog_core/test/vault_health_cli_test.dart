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
    expect(files, hasLength(1));
    final report =
        jsonDecode(await File(files.single.path).readAsString()) as Map;
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
}
