import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/pkms_registry.dart';
import 'package:tylog/scanner.dart';

void main() {
  test(
    'pkms validator reports unknown tags, duplicate aliases, and missing files',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_pkms_invalid_');
      addTearDown(() => dir.delete(recursive: true));
      await Directory('${dir.path}/.tylog').create();
      await Directory('${dir.path}/pages').create();
      await File('${dir.path}/pages/n1.typ').writeAsString('''#note(
  id: "n1",
  title: "N1",
  tags: ("known", "note-unknown"),
  aliases: ("shared",),
)''');
      await File('${dir.path}/.tylog/tags.json').writeAsString('''
{
  "tags": {
    "known": {"title": "Known", "type": "topic", "aliases": ["shared"]}
  }
}
''');
      await File('${dir.path}/.tylog/files.json').writeAsString('''
{
  "files": {
    "missing-doc": {
      "path": "assets/missing.pdf",
      "kind": "pdf",
      "status": "reference",
      "tags": ["known", "file-unknown"]
    }
  }
}
''');

      final index = await scanVault(dir);
      final report = await validatePkms(dir, index);

      expect(report.unknownTags, 2);
      expect(report.duplicateAliases, 1);
      expect(report.missingFiles, 1);
    },
  );

  test('pkms validator returns zeroes for valid registries', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_pkms_valid_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/.tylog').create();
    await Directory('${dir.path}/pages').create(recursive: true);
    await Directory('${dir.path}/assets').create();
    await File('${dir.path}/assets/reference.pdf').writeAsString('pdf');
    await File('${dir.path}/pages/n1.typ').writeAsString('''#note(
  id: "n1",
  title: "N1",
  tags: ("known",),
  aliases: ("n1-alias",),
)''');
    await File('${dir.path}/.tylog/tags.json').writeAsString('''
{
  "tags": {
    "known": {"title": "Known", "type": "topic", "aliases": ["known-alias"]}
  }
}
''');
    await File('${dir.path}/.tylog/files.json').writeAsString('''
{
  "files": {
    "ref-doc": {
      "path": "assets/reference.pdf",
      "kind": "pdf",
      "status": "reference",
      "tags": ["known"]
    }
  }
}
''');

    final index = await scanVault(dir);
    final report = await validatePkms(dir, index);

    expect(report.unknownTags, 0);
    expect(report.duplicateAliases, 0);
    expect(report.missingFiles, 0);
  });

  test('conflicts are discovered outside the metadata directory', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_conflicts_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/journal').create(recursive: true);
    await File(
      '${dir.path}/journal/2026-07-03.typ.remote-conflict-1',
    ).writeAsString('remote');

    final data = await loadPkmsData(dir);
    final conflict = data.problems.singleWhere(
      (problem) => problem.code == 'sync-conflict',
    );

    expect(conflict.subject, 'journal/2026-07-03.typ.remote-conflict-1');
  });

  test('disposable cache conflicts are grouped as one cleanup item', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_cache_conflicts_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/.tylog').create(recursive: true);
    for (var i = 0; i < 3; i++) {
      await File(
        '${dir.path}/.tylog/index.json.remote-conflict-$i',
      ).writeAsString('{}');
    }

    final data = await loadPkmsData(dir);

    expect(data.problems.where((p) => p.code == 'sync-conflict'), isEmpty);
    final cleanup = data.problems.singleWhere(
      (problem) => problem.code == 'sync-cache-conflicts',
    );
    expect(cleanup.subject, '3 disposable cache copies');
  });

  test(
    'malformed registry and unsafe path are reported without throwing',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_pkms_safe_');
      addTearDown(() => dir.delete(recursive: true));
      await Directory('${dir.path}/.tylog').create();
      await File('${dir.path}/.tylog/tags.json').writeAsString('{bad');
      await File('${dir.path}/.tylog/files.json').writeAsString('''
{"files":{"escape":{"path":"../secret","kind":"file","status":"reference"}}}
''');
      final data = await loadPkmsData(dir);
      final report = await validatePkms(
        dir,
        const VaultIndex(notesByPath: {}, backlinksByTarget: {}),
        data: data,
      );

      expect(
        report.problems.map((problem) => problem.code),
        contains('tags-registry-invalid'),
      );
      expect(
        report.problems.map((problem) => problem.code),
        contains('unsafe-file-path'),
      );
      expect(isSafeVaultPath('../secret'), isFalse);
    },
  );
}
