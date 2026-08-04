import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'dedupe reports dry-run and safely applies supported duplicate fixes',
    () async {
      final root = await Directory.systemTemp.createTemp('tylog_dedupe_');
      addTearDown(() => root.delete(recursive: true));
      await _write(root, '.tylog/settings.json', '{"version":5}');
      await _write(
        root,
        'articles/Home.typ',
        _note('article-copy', 'Home', 'article', 'same-hash', 'home body'),
      );
      await _write(
        root,
        'articles/A descriptive article.typ',
        _note(
          'article-copy',
          'A descriptive article',
          'article',
          'same-hash',
          'descriptive body',
        ),
      );
      await _write(
        root,
        'daily/2022/01/2022-01-05.typ',
        _note('2022-01-05', '2022-01-05', 'daily', null, 'canonical body'),
      );
      await _write(
        root,
        'daily/2022/01/2022-01-05-01.typ',
        _note('2022-01-05', '2022-01-05 twin', 'daily', null, 'twin body'),
      );
      await _write(
        root,
        'articles/Different one.typ',
        _note(
          'different-hashes',
          'Different one',
          'article',
          'hash-one',
          'one',
        ),
      );
      await _write(
        root,
        'articles/Different two.typ',
        _note(
          'different-hashes',
          'Different two',
          'article',
          'hash-two',
          'two',
        ),
      );
      // Same title + differing content: nothing safe to do automatically.
      await _write(
        root,
        'articles/Twin title.typ',
        _note('same-title', 'Twin title', 'article', 'hash-a', 'alpha'),
      );
      await _write(
        root,
        'articles/Twin title (2).typ',
        _note('same-title', 'Twin title', 'article', 'hash-b', 'beta'),
      );
      final before = await _snapshot(root);

      final dryRun = await _cli(['dedupe', root.path]);

      expect(dryRun.exitCode, 0, reason: dryRun.stderr.toString());
      expect(
        dryRun.stdout,
        contains(
          'article-copy | dry-run: keep articles/A descriptive article.typ, delete articles/Home.typ',
        ),
      );
      expect(
        dryRun.stdout,
        contains(
          '2022-01-05 | dry-run: merge daily/2022/01/2022-01-05-01.typ into daily/2022/01/2022-01-05.typ',
        ),
      );
      expect(
        dryRun.stdout,
        contains('different-hashes | dry-run: reassign'),
      );
      expect(
        dryRun.stdout,
        contains(
          'same-title | skipped: identical titles with differing content — merge by hand',
        ),
      );
      expect(
        dryRun.stdout,
        contains(
          'Summary: groups=4 deletions=2 merges=1 reassigned=1 skipped=1',
        ),
      );
      expect(await _snapshot(root), before);

      final applied = await _cli(['dedupe', root.path, '--apply']);

      expect(applied.exitCode, 0, reason: applied.stderr.toString());
      expect(applied.stdout, contains('article-copy | applied: keep'));
      expect(applied.stdout, contains('2022-01-05 | applied: merge'));
      expect(await File('${root.path}/articles/Home.typ').exists(), isFalse);
      expect(
        await File('${root.path}/articles/A descriptive article.typ').exists(),
        isTrue,
      );
      expect(
        await File('${root.path}/daily/2022/01/2022-01-05-01.typ').exists(),
        isFalse,
      );
      expect(
        await File('${root.path}/daily/2022/01/2022-01-05.typ').readAsString(),
        contains('== Merged from duplicate\n\ntwin body\n'),
      );
      expect(
        await File('${root.path}/articles/Different one.typ').exists(),
        isTrue,
      );
      expect(
        await File('${root.path}/articles/Different two.typ').exists(),
        isTrue,
      );
      // The older owner keeps the colliding id; the newer one was reassigned.
      expect(
        await File('${root.path}/articles/Different one.typ').readAsString(),
        contains('id: "different-hashes",'),
      );
      expect(
        await File('${root.path}/articles/Different two.typ').readAsString(),
        contains('id: "different-hashes-2",'),
      );
      // Same-title pair untouched even with --apply.
      expect(
        await File('${root.path}/articles/Twin title.typ').readAsString(),
        contains('id: "same-title",'),
      );
      expect(
        await File('${root.path}/articles/Twin title (2).typ').readAsString(),
        contains('id: "same-title",'),
      );
    },
  );
}

String _note(String id, String title, String kind, String? hash, String body) =>
    '''#show: tylog.note.with(
  id: "$id",
  title: "$title",
  kind: "$kind",
  properties: ${hash == null ? '(:)' : '("import_sha256": "$hash",)'},
)
= $title

$body
''';

Future<void> _write(Directory root, String path, String source) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(source);
}

Future<Map<String, String>> _snapshot(Directory root) async {
  final files = await root
      .list(recursive: true)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  return {for (final file in files) file.path: await file.readAsString()};
}

Future<ProcessResult> _cli(List<String> arguments) => Process.run(
  Platform.resolvedExecutable,
  ['--suppress-analytics', 'run', 'bin/tylog.dart', ...arguments],
  workingDirectory: Directory.current.path,
);
