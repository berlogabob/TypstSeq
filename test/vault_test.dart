import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/tylog_assets.dart';
import 'package:tylog/vault.dart';

void main() {
  test('default vault prefers Nextcloud on desktop', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_nextcloud_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/Nextcloud').create();
    expect(
      defaultVaultDirectory(
        Directory('${dir.path}/app_docs'),
        environment: {'HOME': dir.path},
        desktop: true,
      ).path,
      '${dir.path}/Nextcloud/TyLogVault',
    );
  });

  test('TYLOG_VAULT_DIR overrides default vault', () {
    expect(
      defaultVaultDirectory(
        Directory('/app/docs'),
        environment: {'TYLOG_VAULT_DIR': '/sync/TyLogVault'},
        desktop: false,
      ).path,
      '/sync/TyLogVault',
    );
  });

  test('empty folder becomes a complete v5 vault', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_v5_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();

    for (final path in const [
      'daily',
      'notes',
      'projects',
      'articles',
      'assets',
      'outputs',
      '_system',
      '_index',
      '.tylog',
    ]) {
      expect(await Directory('${dir.path}/$path').exists(), isTrue);
    }
    expect(
      await vault.helperFile.readAsString(),
      (await TylogAssets.load()).text('typst/vault/tylog.typ'),
    );
    expect(await vault.themeFile.exists(), isTrue);
    expect(await vault.exportFile.exists(), isTrue);
    expect(await vault.bibliographyFile.exists(), isTrue);
    final settings = jsonDecode(await vault.settingsFile.readAsString()) as Map;
    expect(settings['version'], 5);
  });

  test('exact legacy helper upgrades without rewriting notes', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_upgrade_');
    addTearDown(() => dir.delete(recursive: true));
    final assets = await TylogAssets.load();
    await Directory('${dir.path}/.tylog').create(recursive: true);
    await Directory('${dir.path}/_system').create(recursive: true);
    await Directory('${dir.path}/notes').create(recursive: true);
    await File(
      '${dir.path}/.tylog/settings.json',
    ).writeAsString(jsonEncode({'name': 'TyLogVault', 'version': 5}));
    await File(
      '${dir.path}/_system/tylog.typ',
    ).writeAsString(assets.text('typst/vault/legacy-v5-tylog.typ'));
    const source = '#import "/_system/tylog.typ" as tylog\n= Existing\n';
    await File('${dir.path}/notes/existing.typ').writeAsString(source);

    await Vault(dir).ensureCreated();

    expect(
      await File('${dir.path}/_system/tylog.typ').readAsString(),
      assets.text('typst/vault/tylog.typ'),
    );
    expect(await File('${dir.path}/notes/existing.typ').readAsString(), source);
  });

  test('custom helper is preserved and vendored package is repaired', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_custom_package_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();
    const custom = '#let note(..args) = [custom]';
    await vault.storage.writeText(Vault.helperPath, custom);
    const packagePath = '_system/packages/tylog/0.1.0/lib.typ';
    await vault.storage.writeText(packagePath, 'broken');

    await vault.ensureCreated();

    expect(await vault.storage.readText(Vault.helperPath), custom);
    expect(
      await vault.storage.readText(packagePath),
      (await TylogAssets.load()).text('typst/tylog/lib.typ'),
    );
  });

  test('missing vault marker is rejected without mutation', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_missing_marker_');
    addTearDown(() => dir.delete(recursive: true));

    await expectLater(
      Vault(dir).ensureCreated(createIfMissing: false),
      throwsStateError,
    );

    expect(await Directory('${dir.path}/daily').exists(), isFalse);
    expect(await File('${dir.path}/.tylog/settings.json').exists(), isFalse);
  });

  test('old vault is rejected without mutation', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_old_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/journal').create();
    await File('${dir.path}/journal/old.typ').writeAsString('old');

    await expectLater(Vault(dir).ensureCreated(), throwsStateError);
    expect(await Directory('${dir.path}/daily').exists(), isFalse);
    expect(await File('${dir.path}/journal/old.typ').readAsString(), 'old');
  });

  test('vault creates nested daily note and named content kinds', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_notes_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();

    final daily = await vault.todayNote(DateTime(2026, 7, 1));
    final note = await vault.page('Моя заметка');
    final project = await vault.project('PhD Thesis');
    final article = await vault.article('Smith 2026');

    expect(vault.relativePath(daily), 'daily/2026/07/2026-07-01.typ');
    expect(vault.relativePath(note), 'notes/Моя заметка.typ');
    expect(vault.relativePath(project), 'projects/PhD Thesis.typ');
    expect(vault.relativePath(article), 'articles/Smith 2026.typ');
    expect(await vault.readText(daily), contains('kind: "daily"'));
    expect(await vault.readText(project), contains('kind: "project"'));
    expect(await vault.readText(article), contains('kind: "article"'));
  });

  test('dailyNote opens or creates the journal file for any date', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_daily_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();

    final past = await vault.dailyNote(DateTime(2025, 1, 9));
    final future = await vault.dailyNote(DateTime(2027, 12, 31));

    expect(vault.relativePath(past), 'daily/2025/01/2025-01-09.typ');
    expect(vault.relativePath(future), 'daily/2027/12/2027-12-31.typ');
    expect(await vault.readText(past), contains('kind: "daily"'));
    // Reopening returns the existing file untouched.
    await vault.saveNote(past, 'existing content');
    expect(await vault.dailyNote(DateTime(2025, 1, 9)), past);
    expect(await vault.readText(past), 'existing content');
  });

  test(
    'page creates once and atomic save preserves existing content',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_page_');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(dir);
      await vault.ensureCreated();
      final page = await vault.page('Fast Win');
      await vault.saveNote(page, 'keep me');
      expect(await vault.page('Fast Win'), page);
      expect(await vault.readText(page), 'keep me');
      expect(await File('${dir.path}/$page.tmp').exists(), isFalse);
    },
  );

  test('vault refuses to replace a Typst note with empty content', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_empty_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = await vault.todayNote(DateTime(2026, 7, 4));
    final original = await vault.readText(note);
    await expectLater(vault.saveNote(note, '  \n'), throwsArgumentError);
    expect(await vault.readText(note), original);
  });

  test('index is deterministic and rebuilds v5 backlinks', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_index_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();
    final root = await vault.page('Root');
    final child = await vault.page('Child');
    await vault.saveNote(root, '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "root", title: "Root", kind: "note")
#tylog.ref-note("child")[Child]
''');
    await vault.saveNote(child, '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "child", title: "Child", kind: "note")
= Child
''');

    final first = await vault.rebuildIndex();
    final firstJson = await vault.indexFile.readAsString();
    await vault.cache.delete(recursive: true);
    final second = await vault.rebuildIndex();
    final secondJson = await vault.indexFile.readAsString();

    expect(first.version, 5);
    expect(first.backlinksByTarget['notes/Child.typ'], ['notes/Root.typ']);
    expect(second.backlinksByTarget, first.backlinksByTarget);
    expect(secondJson, firstJson);
  });
}
