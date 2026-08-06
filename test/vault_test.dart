import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/tylog_assets.dart';
import 'package:tylog/vault.dart';
import 'package:tylog_core/models.dart';

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
      await vault.storage.readText(Vault.helperPath),
      (await TylogAssets.load()).text('typst/vault/tylog.typ'),
    );
    expect(await vault.storage.exists(Vault.themePath), isTrue);
    expect(await vault.storage.exists(Vault.exportPath), isTrue);
    expect(await vault.storage.exists(Vault.bibliographyPath), isTrue);
    final settings =
        jsonDecode(await vault.storage.readText(Vault.settingsPath)) as Map;
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

  test('custom helper and theme are preserved; package is repaired', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_custom_package_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();
    const custom = '#let note(..args) = [custom]';
    await vault.storage.writeText(Vault.helperPath, custom);
    const customTheme = '#let document(body) = body';
    await vault.storage.writeText(Vault.themePath, customTheme);
    const packagePath = '_system/packages/tylog/0.1.0/lib.typ';
    await vault.storage.writeText(packagePath, 'broken');

    await vault.ensureCreated();

    expect(await vault.storage.readText(Vault.helperPath), custom);
    expect(await vault.storage.readText(Vault.themePath), customTheme);
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

    expect(daily, 'daily/2026/07/2026-07-01.typ');
    expect(note, 'notes/Моя заметка.typ');
    expect(project, 'projects/PhD Thesis.typ');
    expect(article, 'articles/Smith 2026.typ');
    expect(await vault.readText(daily), contains('kind: "daily"'));
    expect(await vault.readText(project), contains('kind: "project"'));
    expect(await vault.readText(article), contains('kind: "article"'));
  });

  // The missing-page triage creates hundreds of notes in one pass, most of
  // them Cyrillic. nextNoteId slugs with [^a-z0-9]+, so those titles slug to
  // nothing and the id collapses to a bare second-resolution timestamp; left
  // deduping against the on-disk index (which cannot see a note written a
  // millisecond ago) every one of them would be minted identical, and the
  // triage would manufacture duplicate-note-id errors instead of fixing links.
  test('a batch of Cyrillic pages shares one id namespace', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_triage_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();

    final ids = <String>{};
    final now = DateTime(2026, 8, 6, 12, 0, 0);
    final paths = [
      for (final title in ['Илья Бирман', 'Дубай', 'Купить'])
        await vault.page(
          title,
          kind: title == 'Илья Бирман' ? 'person' : 'note',
          now: now,
          knownIds: ids,
        ),
    ];

    expect(paths, [
      'notes/Илья Бирман.typ',
      'notes/Дубай.typ',
      'notes/Купить.typ',
    ]);
    expect(ids, hasLength(3), reason: 'ids must not collide within a batch');
    expect(await vault.readText(paths.first), contains('kind: "person"'));
  });

  test('dailyNote opens or creates the journal file for any date', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_daily_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();

    final past = await vault.dailyNote(DateTime(2025, 1, 9));
    final future = await vault.dailyNote(DateTime(2027, 12, 31));

    expect(past, 'daily/2025/01/2025-01-09.typ');
    expect(future, 'daily/2027/12/2027-12-31.typ');
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

  test(
    'nextTaskId avoids collisions with existing task ids so two inserted '
    'tasks never share an id',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_task_id_');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(dir);
      await vault.ensureCreated();
      final now = DateTime(2026, 7, 15, 9, 30, 0);

      final firstId = await vault.nextTaskId('Buy milk', now: now);
      expect(firstId, '20260715-093000-buy-milk');

      final note = await vault.todayNote(now);
      await vault.saveNote(note, '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "day", title: "Day", kind: "daily")
#tylog.task(id: "$firstId", text: "Buy milk", status: "todo")
''');
      await vault.rebuildIndex();

      final secondId = await vault.nextTaskId('Buy milk', now: now);

      expect(secondId, isNot(firstId));
      expect(secondId, '$firstId-2');
    },
  );

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
    final firstJson = await vault.storage.readText(Vault.indexPath);
    await vault.storage.delete('_index');
    final second = await vault.rebuildIndex();
    final secondJson = await vault.storage.readText(Vault.indexPath);

    expect(first.version, kVaultIndexVersion);
    expect(first.backlinksByTarget['notes/Child.typ'], ['notes/Root.typ']);
    expect(second.backlinksByTarget, first.backlinksByTarget);
    expect(secondJson, firstJson);
  });

  group('index donors', () {
    const source = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "root", title: "Root", kind: "note")
= Root
''';

    Future<Vault> newVault(String prefix) async {
      final dir = await Directory.systemTemp.createTemp(prefix);
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(dir);
      await vault.ensureCreated();
      return vault;
    }

    test('a rebuild publishes this device, and only this device', () async {
      final vault = await newVault('tylog_donor_write_');
      await vault.storage.writeText('notes/Root.typ', source);

      final index = await vault.rebuildIndex(deviceId: 'laptop');
      final donor =
          jsonDecode(await vault.storage.readText('_system/index/laptop.json'))
              as Map<String, Object?>;

      expect(donor['indexVersion'], kVaultIndexVersion);
      expect((donor['notes'] as List), hasLength(index.notes.length));
      expect(
        (donor['notes'] as List).first,
        containsPair('contentHash', isNotNull),
        reason: 'a donor without hashes is useless to the other device',
      );
      // An unchanged vault must not touch the donor at all. Identical bytes
      // are not enough: on desktop the Nextcloud client owns this folder and
      // detects changes by mtime+size, and an atomic write renames a fresh
      // temp file into place — so a redundant rewrite re-uploads megabytes.
      const donorPath = '_system/index/laptop.json';
      final beforeBytes = await vault.storage.readText(donorPath);
      final beforeStamp = (await vault.storage.stat(donorPath))?.modified;
      expect(beforeStamp, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      await vault.rebuildIndex(deviceId: 'laptop');

      expect(await vault.storage.readText(donorPath), beforeBytes);
      expect(
        (await vault.storage.stat(donorPath))?.modified,
        beforeStamp,
        reason: 'an unchanged donor must not be rewritten',
      );

      // No deviceId (CLI, tests, pre-registry startup) publishes nothing.
      final anonymous = await newVault('tylog_donor_none_');
      await anonymous.storage.writeText('notes/Root.typ', source);
      await anonymous.rebuildIndex();
      expect(await anonymous.storage.exists('_system/index'), isFalse);
    });

    test("a peer's donor is reused rather than re-parsed", () async {
      final laptop = await newVault('tylog_donor_laptop_');
      await laptop.storage.writeText('notes/Root.typ', source);
      await laptop.rebuildIndex(deviceId: 'laptop');

      // Mark the donor's cached entry so a reuse is distinguishable from a
      // re-parse: the content hash still matches the bytes, only the derived
      // title differs from what parsing would produce.
      final donor =
          jsonDecode(await laptop.storage.readText('_system/index/laptop.json'))
              as Map<String, Object?>;
      for (final note in (donor['notes'] as List).cast<Map>()) {
        note['title'] = 'FROM DONOR';
      }

      // The phone receives the same bytes through sync — storage writes, not
      // saveNote, so nothing is marked stale — plus the laptop's donor.
      final phone = await newVault('tylog_donor_phone_');
      await phone.storage.writeText('notes/Root.typ', source);
      await phone.storage.writeText(
        '_system/index/laptop.json',
        jsonEncode(donor),
      );

      final index = await phone.rebuildIndex(deviceId: 'phone');

      expect(
        index.notesByPath['notes/Root.typ']?.title,
        'FROM DONOR',
        reason: 'the phone reused the laptop entry instead of re-parsing',
      );
      expect(
        await phone.storage.exists('_system/index/phone.json'),
        isTrue,
        reason: 'the phone publishes its own donor too',
      );
    });

    test('a donor is ignored when it no longer matches the bytes', () async {
      final laptop = await newVault('tylog_donor_stale_');
      await laptop.storage.writeText('notes/Root.typ', source);
      await laptop.rebuildIndex(deviceId: 'laptop');
      final donor =
          jsonDecode(await laptop.storage.readText('_system/index/laptop.json'))
              as Map<String, Object?>;
      for (final note in (donor['notes'] as List).cast<Map>()) {
        note['title'] = 'FROM DONOR';
      }

      final phone = await newVault('tylog_donor_stale_phone_');
      // Same path, different content from the one the donor describes.
      await phone.storage.writeText(
        'notes/Root.typ',
        source.replaceFirst('title: "Root"', 'title: "Edited"'),
      );
      await phone.storage.writeText(
        '_system/index/laptop.json',
        jsonEncode(donor),
      );

      final index = await phone.rebuildIndex(deviceId: 'phone');

      expect(index.notesByPath['notes/Root.typ']?.title, 'Edited');
    });

    test('a donor built with a different synonym map is ignored', () async {
      // The donor carries *derived* tags. If the map changed, its NoteRefs are
      // as stale as an old-schema entry — and because the content hashes still
      // match, the change would otherwise be silently invisible.
      final laptop = await newVault('tylog_donor_syn_');
      await laptop.storage.writeText('notes/Root.typ', source);
      await laptop.storage.writeText(
        '_system/tag-synonyms.json',
        '{"synonyms":{"a":"b"}}',
      );
      await laptop.rebuildIndex(deviceId: 'laptop');
      final donor = await laptop.storage.readText(
        '_system/index/laptop.json',
      );

      final phone = await newVault('tylog_donor_syn_phone_');
      await phone.storage.writeText('notes/Root.typ', source);
      await phone.storage.writeText('_system/index/laptop.json', donor);
      // A different map: this device folds tags by other rules.
      await phone.storage.writeText(
        '_system/tag-synonyms.json',
        '{"synonyms":{"a":"c"}}',
      );

      final seeded = await phone.rebuildIndex(deviceId: 'phone');

      expect(seeded.notesByPath['notes/Root.typ'], isNotNull);
      final own = jsonDecode(
        await phone.storage.readText('_system/index/phone.json'),
      ) as Map<String, Object?>;
      final theirs = jsonDecode(donor) as Map<String, Object?>;
      expect(
        own['synonymsHash'],
        isNot(theirs['synonymsHash']),
        reason: 'each device stamps the map it actually used',
      );
    });

    test('a corrupt or wrong-version donor never fails the rebuild', () async {
      final phone = await newVault('tylog_donor_corrupt_');
      await phone.storage.writeText('notes/Root.typ', source);
      await phone.storage.writeText('_system/index/bad.json', 'not json {');
      await phone.storage.writeText(
        '_system/index/old.json',
        jsonEncode({'schema': 1, 'indexVersion': 1, 'notes': []}),
      );

      final index = await phone.rebuildIndex(deviceId: 'phone');

      expect(index.notesByPath['notes/Root.typ']?.title, 'Root');
    });
  });

  test('nextTaskId avoids reserved ids', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_reserved_id_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();
    final now = DateTime(2026, 8, 3, 14, 22, 0);

    final id1 = await vault.nextTaskId('milk', now: now);
    expect(id1, '20260803-142200-milk');

    final id2 = await vault.nextTaskId(
      'milk',
      now: now,
      reserved: {id1},
    );
    expect(id2, '$id1-2');
  });
}
