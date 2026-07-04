import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/vault.dart';

void main() {
  test('default vault prefers Nextcloud on desktop', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_nextcloud_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/Nextcloud').create();

    final selected = defaultVaultDirectory(
      Directory('${dir.path}/app_docs'),
      environment: {'HOME': dir.path},
      desktop: true,
    );

    expect(selected.path, '${dir.path}/Nextcloud/TyLogVault');
  });

  test('TYLOG_VAULT_DIR overrides default vault', () {
    final selected = defaultVaultDirectory(
      Directory('/app/docs'),
      environment: {'TYLOG_VAULT_DIR': '/sync/TyLogVault'},
      desktop: false,
    );

    expect(selected.path, '/sync/TyLogVault');
  });

  test('vault creates today note and saves safely', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_vault_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);

    await vault.ensureCreated();
    final note = await vault.todayNote(DateTime(2026, 7, 1));
    await vault.saveNote(note, '#note(title: "2026-07-01")\n#wikilink("PKM")');
    final index = await vault.rebuildIndex();

    expect(await File('${dir.path}/.tylog/tylog.typ').exists(), isTrue);
    expect(vault.relativePath(note), 'journal/2026-07-01.typ');
    expect(await note.readAsString(), contains('#wikilink("PKM")'));
    expect(index.notesByPath['journal/2026-07-01.typ']!.outgoingLinks, ['PKM']);
  });

  test('page creates once and preserves existing content', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_page_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();

    final page = await vault.page('Fast Win');
    await vault.saveNote(page, 'keep me');

    expect((await vault.page('Fast Win')).path, page.path);
    expect(await page.readAsString(), 'keep me');
  });

  test('vault refuses to replace a Typst note with empty content', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_empty_note_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = await vault.todayNote(DateTime(2026, 7, 4));
    final original = await note.readAsString();

    await expectLater(vault.saveNote(note, '  \n'), throwsArgumentError);

    expect(await note.readAsString(), original);
  });

  test(
    'vault upgrades generated helper and creates stable timestamp ids',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_v3_');
      addTearDown(() => dir.delete(recursive: true));
      await Directory('${dir.path}/.tylog').create(recursive: true);
      await File(
        '${dir.path}/.tylog/tylog.typ',
      ).writeAsString(legacyTylogHelperSource);
      final vault = Vault(dir);

      await vault.ensureCreated();
      final page = await vault.page(
        'Readable ID',
        now: DateTime(2026, 7, 3, 18, 42, 15),
      );

      expect(
        await vault.helperFile.readAsString(),
        contains('tylog-helper-version: 4'),
      );
      expect(
        await page.readAsString(),
        contains('id: "20260703-184215-readable-id"'),
      );
    },
  );

  test('vault upgrades the original helper that rejected note id', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_original_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/.tylog').create(recursive: true);
    await File(
      '${dir.path}/.tylog/tylog.typ',
    ).writeAsString(originalTylogHelperSource);

    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = await vault.todayNote(DateTime(2026, 7, 4));

    expect(await vault.helperFile.readAsString(), tylogHelperSource);
    expect(await note.readAsString(), contains('id: "2026-07-04"'));
  });

  test('vault upgrades any older versioned stock helper', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_v2_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/.tylog').create(recursive: true);
    await File('${dir.path}/.tylog/tylog.typ').writeAsString(
      '// tylog-helper-version: 2\n#let note(title: none) = none',
    );

    await Vault(dir).ensureCreated();

    expect(
      await File('${dir.path}/.tylog/tylog.typ').readAsString(),
      tylogHelperSource,
    );
  });

  test('vault leaves the current helper unchanged', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_current_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/.tylog').create(recursive: true);
    await File('${dir.path}/.tylog/tylog.typ').writeAsString(tylogHelperSource);

    await Vault(dir).ensureCreated();

    expect(
      await File('${dir.path}/.tylog/tylog.typ').readAsString(),
      tylogHelperSource,
    );
  });

  test('vault preserves an unrecognized custom helper', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_custom_helper_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/.tylog').create(recursive: true);
    const custom = '#let note(..args) = [custom]';
    await File('${dir.path}/.tylog/tylog.typ').writeAsString(custom);

    await Vault(dir).ensureCreated();

    expect(await File('${dir.path}/.tylog/tylog.typ').readAsString(), custom);
  });

  test(
    'vault handles spaces, non-ascii, external edits, and deterministic rebuild',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_hardening_');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(dir);
      await vault.ensureCreated();

      await vault.saveNote(
        await vault.page('Моя заметка'),
        '#note(title: "Моя заметка")',
      );
      await vault.saveNote(
        await vault.page('page with spaces'),
        '#note(title: "page with spaces")',
      );
      for (var i = 0; i < 160; i++) {
        await vault.saveNote(
          await vault.page('n$i'),
          '#note(id: "n$i", title: "n$i", tags: ("pkms",), links: ("n${(i + 1) % 160}",))\n#wikilink("n${(i + 1) % 160}")',
        );
      }

      await File(
        '${dir.path}/pages/external.typ',
      ).writeAsString('#note(title: "external")\n#wikilink("Моя заметка")');
      final stopwatch = Stopwatch()..start();
      final index = await vault.rebuildIndex();
      final firstJson = vault.indexFile.readAsStringSync();
      await vault.rebuildIndex();
      final secondJson = vault.indexFile.readAsStringSync();
      stopwatch.stop();

      expect(index.notesByPath, contains('pages/Моя заметка.typ'));
      expect(index.notesByPath, contains('pages/page with spaces.typ'));
      expect(index.notesByPath, contains('pages/external.typ'));
      expect(
        index.backlinksByTarget['pages/Моя заметка.typ'],
        contains('pages/external.typ'),
      );
      expect(firstJson, secondJson);
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    },
  );

  test(
    'mvp smoke: create link page, persist, delete index, rebuild backlinks',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_smoke_');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(dir);
      await vault.ensureCreated();

      final today = await vault.todayNote(DateTime(2026, 7, 2));
      await vault.saveNote(
        today,
        '#note(title: "2026-07-02")\nпривет!\n#wikilink("PKM")',
      );
      await vault.saveNote(
        await vault.page('PKM'),
        '#note(title: "PKM")\n= PKM',
      );

      var index = await vault.rebuildIndex();
      expect(
        index.backlinksByTarget['pages/PKM.typ'],
        contains('journal/2026-07-02.typ'),
      );

      await vault.indexFile.delete();
      index = await vault.rebuildIndex();
      expect(await vault.indexFile.exists(), isTrue);
      expect(
        index.backlinksByTarget['pages/PKM.typ'],
        contains('journal/2026-07-02.typ'),
      );
      expect(await today.readAsString(), contains('привет!'));
    },
  );

  test(
    'pkms smoke gate: note->tag->file->backlink flow remains rebuildable',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_pkms_smoke_');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(dir);
      await vault.ensureCreated();
      await Directory('${dir.path}/assets').create();
      await File('${dir.path}/assets/manual.pdf').writeAsString('pdf');
      await File('${dir.path}/.tylog/tags.json').writeAsString('''
{
  "tags": {
    "pkms": {"title": "PKMS", "type": "topic"},
    "manual": {"title": "Manual", "type": "file-kind"}
  }
}
''');
      await File('${dir.path}/.tylog/files.json').writeAsString('''
{
  "files": {
    "manual-doc": {
      "path": "assets/manual.pdf",
      "kind": "pdf",
      "status": "reference",
      "tags": ["pkms", "manual"]
    }
  }
}
''');

      final source =
          '#note(id: "root", title: "Root", tags: ("pkms",), links: ("child",), files: ("manual-doc",))\n#wikilink("child")';
      final child = '#note(id: "child", title: "Child", tags: ("pkms",))';
      await vault.saveNote(await vault.page('Root'), source);
      await vault.saveNote(await vault.page('Child'), child);

      final first = await vault.rebuildIndex();
      final firstJson = await vault.indexFile.readAsString();
      await vault.indexFile.delete();
      final second = await vault.rebuildIndex();
      final secondJson = await vault.indexFile.readAsString();

      expect(first.notesByPath['pages/Root.typ']!.fileRefs, ['manual-doc']);
      expect(second.backlinksByTarget['pages/Child.typ'], ['pages/Root.typ']);
      expect(firstJson, secondJson);
    },
  );
}
