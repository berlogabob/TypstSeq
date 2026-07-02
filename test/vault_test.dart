import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault.dart';

void main() {
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

  test(
    'vault handles spaces, non-ascii, external edits, and 100 notes',
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
      for (var i = 0; i < 100; i++) {
        await vault.saveNote(
          await vault.page('n$i'),
          '#note(title: "n$i")\n#wikilink("n${(i + 1) % 100}")',
        );
      }

      await File(
        '${dir.path}/pages/external.typ',
      ).writeAsString('#note(title: "external")\n#wikilink("Моя заметка")');
      final stopwatch = Stopwatch()..start();
      final index = await vault.rebuildIndex();
      stopwatch.stop();

      expect(index.notesByPath, contains('pages/Моя заметка.typ'));
      expect(index.notesByPath, contains('pages/page with spaces.typ'));
      expect(index.notesByPath, contains('pages/external.typ'));
      expect(
        index.backlinksByTarget['pages/Моя заметка.typ'],
        contains('pages/external.typ'),
      );
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
}
