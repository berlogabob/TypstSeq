import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/tylog_assets.dart';
import 'package:tylog/vault.dart';
import 'package:tylog_core/models.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/values.dart';
import 'package:tylog_core/vault.dart' show decodeVaultIndexBytes;

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

  // `page()` sanitises `\` and `/` — but only for the *filename*. The title
  // went into the header raw, so a quote produced a header Typst rejects, and
  // into the `= ` heading raw, so a `#` or `[` broke that instead. Neither
  // failed loudly: the fallback parser reads a broken header back as a valid
  // note, so the note simply never regained real metadata.
  test('a page title with Typst syntax in it produces valid source', () async {
    final hasTypst = Process.runSync('which', ['typst']).exitCode == 0;
    final dir = await Directory.systemTemp.createTemp('tylog_title_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();

    for (final title in const [
      r'He said "hi"',
      r'C:\path\thing',
      'Cost #5 [draft]',
      r'a_b *c* $d$ @e',
    ]) {
      final path = await vault.page(title);
      final source = await vault.readText(path);

      // The header must round-trip through the same escaping the scanner uses.
      expect(
        source,
        contains('title: ${typstString(title)}'),
        reason: 'header literal for: $title',
      );
      expect(
        source,
        contains('= ${escapeMarkup(title)}'),
        reason: 'heading markup for: $title',
      );
      // And the header must still parse back to the original title.
      expect(scanNote(path, source).title, title, reason: 'round-trip: $title');

      // The check that actually matters. `scanNote` is lenient enough to read a
      // broken header back as a valid note, and it never looks at the heading
      // at all — so only the compiler can fail the markup half of this.
      if (hasTypst) {
        final result = Process.runSync('typst', [
          'compile',
          '--root',
          dir.path,
          '${dir.path}/$path',
          '${dir.path}/out.pdf',
        ]);
        expect(
          result.exitCode,
          0,
          reason: 'new note does not compile for title "$title":\n'
              '${result.stderr}\n--- source ---\n$source',
        );
      }
    }
  });

  // The safety net under the bulk maintenance passes. There is no vault-level
  // undo, so if this does not run before a rewrite, a mis-tap over 3,351 notes
  // is recoverable only from the server's versioning.
  test('snapshotNotes copies notes as they are, under a stamped folder', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_snapshot_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();
    final a = await vault.page('Alpha');
    final b = await vault.page('Beta');
    await vault.saveNote(a, 'original alpha');
    await vault.saveNote(b, 'original beta');

    final undo = await vault.snapshotNotes([a, b], now: DateTime.utc(2026, 8, 7, 9, 30));

    expect(undo, '.tylog/undo/2026-08-07T09-30-00.000Z');
    expect(await vault.readText('$undo/$a'), 'original alpha');
    expect(await vault.readText('$undo/$b'), 'original beta');

    // Overwriting afterwards must leave the copies alone — that is the point.
    await vault.saveNote(a, 'rewritten alpha');
    expect(await vault.readText('$undo/$a'), 'original alpha');
    expect(await vault.readText(a), 'rewritten alpha');
  });

  test('snapshotNotes throws rather than half-copying', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_snapshot_fail_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();
    final a = await vault.page('Alpha');

    // A caller that cannot snapshot must not go on to rewrite.
    await expectLater(
      vault.snapshotNotes([a, 'notes/does-not-exist.typ']),
      throwsA(anything),
    );
  });

  // `_index/` is device-local derived data that TyLog never syncs — but the
  // vault usually sits inside ~/Nextcloud, and the desktop client uploads what
  // it finds. The search index tokenises whole note bodies, so that upload
  // carries note text.
  test('ensureCreated keeps device-local caches out of a desktop sync', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_exclude_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);

    await vault.ensureCreated();
    final excludes = await vault.readText('.sync-exclude.lst');

    expect(excludes, contains('_index'));
    expect(excludes, contains('.tylog'));

    // A user's own edits to the file survive re-opening the vault.
    await vault.storage.writeText('.sync-exclude.lst', '_index\nmy-own-rule\n');
    await vault.ensureCreated();
    expect(await vault.readText('.sync-exclude.lst'), contains('my-own-rule'));
  });

  test('vault refuses to replace a Typst note with empty content', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_empty_');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(dir);
    await vault.ensureCreated();
    final note = await vault.todayNote(DateTime(2026, 7, 4));
    // Written into, so it is real content rather than the untouched starter —
    // emptying a starter daily now removes it instead, which is the point of
    // test/empty_note_cleanup_test.dart.
    await vault.saveNote(
      note,
      '${await vault.readText(note)}\nSomething the user wrote.\n',
    );
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
    final firstBytes = await vault.storage.readBytes(Vault.indexPath);
    await vault.storage.delete('_index');
    final second = await vault.rebuildIndex();
    final secondBytes = await vault.storage.readBytes(Vault.indexPath);

    expect(first.version, kVaultIndexVersion);
    expect(first.backlinksByTarget['notes/Child.typ'], ['notes/Root.typ']);
    expect(second.backlinksByTarget, first.backlinksByTarget);
    expect(secondBytes, firstBytes);
    expect(
      decodeVaultIndexBytes(secondBytes).backlinksByTarget,
      first.backlinksByTarget,
      reason: 'the on-disk cache must decode back to the same index',
    );
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

    // The donor is the whole index a fresh device starts from, and the
    // scanner's cached branch reuses `previous.tasks` for any note whose bytes
    // still match. A donor carrying notes but no tasks therefore matches every
    // note, re-derives nothing, and leaves the Tasks view empty.
    test("a peer's donor carries its tasks, not just its notes", () async {
      const withTask = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "root", title: "Root", kind: "note")
= Root
#tylog.task(id: "t1", text: "Ship it", status: "todo")
''';
      final laptop = await newVault('tylog_donor_tasks_');
      await laptop.storage.writeText('notes/Root.typ', withTask);
      final laptopIndex = await laptop.rebuildIndex(deviceId: 'laptop');
      expect(
        laptopIndex.tasks,
        isNotEmpty,
        reason: 'precondition: the laptop found the task by scanning',
      );

      final phone = await newVault('tylog_donor_tasks_phone_');
      await phone.storage.writeText('notes/Root.typ', withTask);
      await phone.storage.writeText(
        '_system/index/laptop.json',
        await laptop.storage.readText('_system/index/laptop.json'),
      );

      final index = await phone.rebuildIndex(deviceId: 'phone');

      expect(index.tasks.map((task) => task.id), contains('t1'));
    });

    // The donor is uploaded to `_system/index/`, which is inside the sync
    // allowlist, so every byte of it reaches the server and every peer device.
    // `NoteRef.toJson` serialises `properties` verbatim, so a note's
    // hand-written `pswrd:` travelled with it — confirmed on the real vault,
    // where two donors carried five each.
    test('a donor never publishes properties we did not write', () async {
      const secret = 'S3cretValue123';
      const withSecret = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(
  id: "creds",
  title: "Creds",
  kind: "note",
  properties: ("login": "bob", "pswrd": "$secret",),
)

= Creds
#tylog.task(id: "t9", text: "Rotate it", status: "todo")
''';
      final vault = await newVault('tylog_donor_secret_');
      await vault.storage.writeText('notes/Root.typ', source);
      await vault.storage.writeText('notes/Creds.typ', withSecret);

      await vault.rebuildIndex(deviceId: 'laptop');
      final donor = await vault.storage.readText('_system/index/laptop.json');

      expect(donor, isNot(contains(secret)));
      expect(donor, isNot(contains('pswrd')));
      expect(
        donor,
        isNot(contains('t9')),
        reason: 'a held-back note must not leak its tasks either',
      );
      // The other 99% still ship — this must not become "publish nothing".
      expect(donor, contains('notes/Root.typ'));
    });

    // A note held back from the donor has to be re-parsed by the peer, not
    // silently dropped from its index.
    test('a peer re-parses the notes a donor held back', () async {
      const withSecret = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(
  id: "creds",
  title: "Creds",
  kind: "note",
  properties: ("pswrd": "hunter2",),
)

= Creds
''';
      final laptop = await newVault('tylog_donor_holdback_');
      await laptop.storage.writeText('notes/Root.typ', source);
      await laptop.storage.writeText('notes/Creds.typ', withSecret);
      await laptop.rebuildIndex(deviceId: 'laptop');

      final phone = await newVault('tylog_donor_holdback_phone_');
      await phone.storage.writeText('notes/Root.typ', source);
      await phone.storage.writeText('notes/Creds.typ', withSecret);
      await phone.storage.writeText(
        '_system/index/laptop.json',
        await laptop.storage.readText('_system/index/laptop.json'),
      );

      final index = await phone.rebuildIndex(deviceId: 'phone');

      expect(index.notesByPath['notes/Creds.typ'], isNotNull);
      expect(
        index.notesByPath['notes/Creds.typ']?.properties['pswrd'],
        'hunter2',
        reason: 'held back from the donor, but still read from local disk',
      );
    });

    test('a schema-1 donor is skipped rather than trusted', () async {
      final laptop = await newVault('tylog_donor_v1_');
      await laptop.storage.writeText('notes/Root.typ', source);
      await laptop.rebuildIndex(deviceId: 'laptop');
      final donor =
          jsonDecode(await laptop.storage.readText('_system/index/laptop.json'))
              as Map<String, Object?>;
      // What the previous release wrote: notes, no tasks.
      donor['schema'] = 1;
      donor.remove('tasks');
      for (final note in (donor['notes'] as List).cast<Map>()) {
        note['title'] = 'FROM DONOR';
      }

      final phone = await newVault('tylog_donor_v1_phone_');
      await phone.storage.writeText('notes/Root.typ', source);
      await phone.storage.writeText(
        '_system/index/laptop.json',
        jsonEncode(donor),
      );

      final index = await phone.rebuildIndex(deviceId: 'phone');

      expect(
        index.notesByPath['notes/Root.typ']?.title,
        'Root',
        reason: 'a task-less donor must be re-parsed, not reused',
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
