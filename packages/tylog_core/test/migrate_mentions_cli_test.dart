import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('migrates marked notes outside daily folders', () async {
    final vault = await Directory.systemTemp.createTemp('tylog_mentions_');
    addTearDown(() => vault.delete(recursive: true));
    final settings = File('${vault.path}/.tylog/settings.json');
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"version":5}');
    const source =
        '''#show: tylog.note.with(id: "shot", title: "Shot", kind: "screenshot")
= Shot
Alice met #tylog.ref-note("bob")[Bob].

// tylog:auto-entities
== Mentions
- #tylog.ref-note("alice")[Alice]
''';
    final paths = ['screenshots/shot.typ', 'archive/other.typ'];
    for (final path in paths) {
      final note = File('${vault.path}/$path');
      await note.parent.create(recursive: true);
      await note.writeAsString(source);
    }
    Future<ProcessResult> run(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/tylog.dart', 'migrate-mentions', vault.path, ...args],
    );

    final preview = await run([]);
    expect(preview.exitCode, 0, reason: '${preview.stderr}');
    for (final path in paths) {
      expect(preview.stdout, contains(path));
      expect(await File('${vault.path}/$path').readAsString(), source);
    }
    expect(await Directory('${vault.path}/_system/backups').exists(), isFalse);

    final applied = await run(['--apply']);
    expect(applied.exitCode, 0, reason: '${applied.stderr}');
    for (final path in paths) {
      final migrated = await File('${vault.path}/$path').readAsString();
      expect(migrated, contains('#tylog.ref-note("alice")[Alice]'));
      expect(migrated, isNot(contains('// tylog:auto-entities')));
    }
    expect(
      await Directory(
        '${vault.path}/_system/backups',
      ).list(recursive: true).where((entry) => entry is File).length,
      2,
    );
  });

  test('previews and backs up a migrated daily note', () async {
    final vault = await Directory.systemTemp.createTemp('tylog_mentions_');
    addTearDown(() => vault.delete(recursive: true));
    final settings = File('${vault.path}/.tylog/settings.json');
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"version":5}');
    const path = 'daily/2026/11/2026-11-04.typ';
    const source = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "2026-11-04", title: "Day", kind: "daily", tags: ("old",))
= Day
Alice met #tylog.ref-note("bob")[Bob].

// tylog:auto-entities
== Mentions
- #tylog.ref-note("alice")[Alice]
- #tylog.ref-note("bob")[Bob]
#tylog.tag("design")
''';
    final note = File('${vault.path}/$path');
    await note.parent.create(recursive: true);
    await note.writeAsString(source);
    Future<ProcessResult> run(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/tylog.dart', 'migrate-mentions', vault.path, ...args],
    );

    final preview = await run([]);
    expect(preview.exitCode, 0, reason: '${preview.stderr}');
    expect(
      preview.stdout,
      allOf(
        contains(path),
        contains('alice'),
        contains('bob'),
        contains('design'),
      ),
    );
    expect(await note.readAsString(), source);
    expect(await Directory('${vault.path}/_system/backups').exists(), isFalse);

    final applied = await run(['--apply']);
    expect(applied.exitCode, 0, reason: '${applied.stderr}');
    final migrated = await note.readAsString();
    expect(migrated, contains('#tylog.ref-note("alice")[Alice]'));
    expect(migrated, contains('#tylog.ref-note("bob")[Bob]'));
    expect(migrated, contains('"design"'));
    expect(migrated, isNot(contains('// tylog:auto-entities')));
    final backups = Directory('${vault.path}/_system/backups').listSync();
    expect(backups, hasLength(1));
    expect(await File('${backups.single.path}/$path').readAsString(), source);
    final root = Directory.current.parent.parent.path;
    final compiled = File('${vault.path}/compile.typ');
    await compiled.writeAsString(
      migrated.replaceFirst('/_system/tylog.typ', '$root/typst/tylog/lib.typ'),
    );
    final result = await Process.run('typst', [
      'compile',
      '--root',
      '/',
      compiled.path,
      '${vault.path}/out.pdf',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('retains unplaceable links and computed tags', () async {
    final vault = await Directory.systemTemp.createTemp('tylog_mentions_');
    addTearDown(() => vault.delete(recursive: true));
    final settings = File('${vault.path}/.tylog/settings.json');
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"version":5}');
    final note = File('${vault.path}/daily/day.typ');
    await note.parent.create(recursive: true);
    const source =
        '#show: tylog.note.with(id: "day", tags: custom)\n= Day\n// Alice\n\n// tylog:auto-entities\n== Mentions\n- #tylog.ref-note("alice")[Alice]\n#tylog.tag("design")\n';
    await note.writeAsString(source);
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/tylog.dart',
      'migrate-mentions',
      vault.path,
      '--apply',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      await note.readAsString(),
      contains('- #tylog.ref-note("alice")[Alice]'),
    );
    expect(await note.readAsString(), contains('#tylog.tag("design")'));
    expect(await note.readAsString(), contains('tags: custom'));
  });
}
