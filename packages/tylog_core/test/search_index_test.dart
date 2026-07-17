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
