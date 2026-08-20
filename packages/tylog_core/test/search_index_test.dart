import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

Future<PkmsSearchIndex> _buildIndex(
  Directory root,
  Map<String, String> notes,
) async {
  final storage = LocalVaultStorage(root);
  // scanVaultStorage only needs the files to exist on disk, so fixtures
  // write directly instead of through storage.writeText's atomic (fsync'd
  // write + rename) path -- correct for real vault saves, but at 10k+
  // notes the per-file fsync makes fixture setup slow enough to flirt
  // with `dart test`'s 30s default timeout on CI's slower disk.
  final notesDir = await Directory('${root.path}/notes').create();
  for (final entry in notes.entries) {
    await File('${notesDir.path}/${entry.key}.typ').writeAsString(entry.value);
  }
  final vault = await scanVaultStorage(storage);
  return PkmsSearchIndex.buildStorage(storage, vault);
}

String _note({
  required String id,
  required String title,
  List<String> aliases = const [],
}) =>
    '#show: tylog.note.with(id: "$id", title: "$title", aliases: (${aliases.map((value) => '"$value"').join(', ')}))\n'
    'Body of $title.';

void main() {
  // The scanner re-stamps every warm note's fingerprint to the new mtime, so
  // keying this cache on the fingerprint meant a sync that only moved
  // timestamps invalidated the WHOLE corpus: the scanner correctly reused every
  // note via its content hash while this index re-read, re-tokenised and
  // re-posted all of it. Measured on a real device as a "warm" scan that still
  // burned ten minutes at full CPU.
  test('touching mtimes does not invalidate the search index', () async {
    final root = await Directory.systemTemp.createTemp('tylog_search_mtime_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    final notesDir = await Directory('${root.path}/notes').create();
    for (var i = 0; i < 5; i++) {
      await File('${notesDir.path}/n$i.typ').writeAsString(
        _note(id: 'n$i', title: 'Note $i'),
      );
    }

    final first = await PkmsSearchIndex.buildStorage(
      storage,
      await scanVaultStorage(storage),
    );

    // Move every mtime without changing a byte — exactly what a sync does.
    for (final file in notesDir.listSync().whereType<File>()) {
      file.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
    }

    var reread = 0;
    await PkmsSearchIndex.buildStorage(
      storage,
      await scanVaultStorage(storage),
      previous: first,
      onProgress: (done, total) => reread = total,
    );

    expect(
      reread,
      0,
      reason: 'identical bytes must not be re-tokenised because mtime moved',
    );
  });


  // The warm rebuild used to reconstruct (and re-save) 107k posting sets even
  // when every document hit the cache. Returning the previous instance lets
  // the worker skip both the posting rebuild and the multi-megabyte
  // re-encode/re-write.
  test('a fully-cached rebuild returns the previous instance', () async {
    final root = await Directory.systemTemp.createTemp('tylog_search_same_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    final notesDir = await Directory('${root.path}/notes').create();
    for (var i = 0; i < 3; i++) {
      await File(
        '${notesDir.path}/n$i.typ',
      ).writeAsString(_note(id: 'n$i', title: 'Note $i'));
    }

    final vault = await scanVaultStorage(storage);
    final first = await PkmsSearchIndex.buildStorage(storage, vault);
    final second = await PkmsSearchIndex.buildStorage(
      storage,
      await scanVaultStorage(storage, previous: vault),
      previous: first,
    );
    expect(
      identical(second, first),
      isTrue,
      reason: 'no misses and an unchanged document set must reuse previous',
    );

    // Any content change must still produce a fresh index.
    await File('${notesDir.path}/n0.typ').writeAsString(
      _note(id: 'n0', title: 'Renamed'),
    );
    final third = await PkmsSearchIndex.buildStorage(
      storage,
      await scanVaultStorage(storage),
      previous: second,
    );
    expect(identical(third, second), isFalse);
    expect(third.search('Renamed'), isNotEmpty);
  });

  group('searchPrefix', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('tylog_search_prefix_');
    });

    tearDown(() => root.delete(recursive: true));

    test('empty prefix returns no results', () async {
      final index = await _buildIndex(root, {
        'a': _note(id: 'a', title: 'Alpha'),
      });

      expect(index.searchPrefix(''), isEmpty);
      expect(index.searchPrefix('   '), isEmpty);
    });

    test('matches by title prefix, case-insensitively', () async {
      final index = await _buildIndex(root, {
        'fernando': _note(id: 'fernando', title: 'FernandoMarson'),
        'other': _note(id: 'other', title: 'Someone Else'),
      });

      final results = index.searchPrefix('fer');

      expect(results, hasLength(1));
      expect(results.single.title, 'FernandoMarson');
    });

    test('matches by id prefix', () async {
      final index = await _buildIndex(root, {
        'proj-alpha': _note(id: 'proj-alpha', title: 'Alpha Project'),
      });

      final results = index.searchPrefix('proj-a');

      expect(results, hasLength(1));
      expect(results.single.id, 'proj-alpha');
    });

    test('matches by alias prefix', () async {
      final index = await _buildIndex(root, {
        'fernando': _note(
          id: 'fernando',
          title: 'Fernando Marson',
          aliases: ['Nando', 'FM'],
        ),
      });

      final results = index.searchPrefix('nan');

      expect(results, hasLength(1));
      expect(results.single.title, 'Fernando Marson');
    });

    test('respects the limit', () async {
      final index = await _buildIndex(root, {
        for (var i = 0; i < 20; i++) 'n$i': _note(id: 'n$i', title: 'Match $i'),
      });

      final results = index.searchPrefix('match', limit: 5);

      expect(results, hasLength(5));
    });

    test(
      'ranks exact title match above title prefix above alias/id prefix',
      () async {
        final index = await _buildIndex(root, {
          'exact': _note(id: 'exact', title: 'Fer'),
          'title-prefix': _note(id: 'title-prefix', title: 'FernandoMarson'),
          'alias-prefix': _note(
            id: 'alias-prefix',
            title: 'Someone',
            aliases: ['Fer the Great'],
          ),
          'id-prefix': _note(id: 'fer-project', title: 'Unrelated'),
        });

        final results = index.searchPrefix('fer');

        expect(results.map((result) => result.title).toList(), [
          'Fer',
          'FernandoMarson',
          'Someone',
          'Unrelated',
        ]);
      },
    );

    test('does not match a non-prefix substring', () async {
      final index = await _buildIndex(root, {
        'a': _note(id: 'a', title: 'The Great Fernando'),
      });

      expect(index.searchPrefix('fer'), isEmpty);
    });

    test('a prefix query over 10k documents stays fast', () async {
      final notes = <String, String>{
        for (var i = 0; i < 10000; i++) 'n$i': _note(id: 'n$i', title: 'Note $i'),
        'fernando': _note(id: 'fernando', title: 'FernandoMarson'),
      };
      final index = await _buildIndex(root, notes);

      final stopwatch = Stopwatch()..start();
      final results = index.searchPrefix('Fer');
      stopwatch.stop();

      expect(results, hasLength(1));
      expect(results.single.title, 'FernandoMarson');
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 50)));
    });
  });
}
