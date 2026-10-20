import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/search_index.dart';
import 'package:tylog_core/storage.dart';

void main() {
  test(
    '10k mixed corpus reports compact index load and query measurements',
    () async {
      final root = await Directory.systemTemp.createTemp('tylog_search_10k_');
      addTearDown(() => root.delete(recursive: true));
      final notes = await Directory('${root.path}/notes').create();
      for (var i = 0; i < 10000; i++) {
        final targetBytes = 2000 + (i * 18000 ~/ 9999);
        final seed = 'article corpus topic${i % 23} shared-search-term ';
        final body = seed * ((targetBytes ~/ seed.length) + 1);
        await File('${notes.path}/n$i.typ').writeAsString(
          '#show: tylog.note.with(id: "n$i", title: "Article $i", tags: ("bench",))\n$body',
        );
      }
      final storage = LocalVaultStorage(root);
      final vault = await scanVaultStorage(storage, force: true);
      final buildWatch = Stopwatch()..start();
      final built = await PkmsSearchIndex.buildStorage(storage, vault);
      buildWatch.stop();
      await built.saveStorage(storage, '_index/search-index.json.gz');

      final loadWatch = Stopwatch()..start();
      final loaded = await PkmsSearchIndex.loadStorage(
        storage,
        '_index/search-index.json.gz',
      );
      loadWatch.stop();
      final queryWatch = Stopwatch()..start();
      final loadedResults = loaded.search('shared-search-term');
      queryWatch.stop();

      for (final query in ['shared-search-term', 'topic7', 'article 42']) {
        expect(
          loaded.search(query).map((result) => result.id).toList(),
          built.search(query).map((result) => result.id).toList(),
          reason: 'serialized index changed top results for "$query"',
        );
      }
      final stats = loaded.debugStats;
      print({
        'buildMs': buildWatch.elapsedMilliseconds,
        'loadMs': loadWatch.elapsedMilliseconds,
        'firstQueryMs': queryWatch.elapsedMilliseconds,
        'compressedBytes': await File(
          '${root.path}/_index/search-index.json.gz',
        ).length(),
        ...stats,
      });
      expect(loadedResults, isNotEmpty);
      expect(
        stats['estimatedCompactBytes']!,
        lessThan(stats['estimatedLegacyBytes']! ~/ 2),
      );
    },
    skip: Platform.environment['TYLOG_RUN_10K_BENCHMARK'] != '1',
  );
}
