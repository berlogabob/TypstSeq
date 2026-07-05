import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/search_index.dart';

void main() {
  test(
    '10k note rebuild, warm open, determinism, and search release gate',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_10k_');
      addTearDown(() => dir.delete(recursive: true));
      final pages = await Directory('${dir.path}/notes').create();
      for (var batch = 0; batch < 100; batch++) {
        await Future.wait([
          for (var offset = 0; offset < 100; offset++)
            () {
              final i = batch * 100 + offset;
              return File('${pages.path}/n$i.typ').writeAsString(
                '#show: tylog.note.with(id: "n$i", title: "Note $i", tags: ("pkms",))\n#tylog.ref-note("n${(i + 1) % 10000}")[Next]\nKnowledge body $i',
              );
            }(),
        ]);
      }

      final full = Stopwatch()..start();
      final index = await scanVault(dir, force: true);
      final search = await PkmsSearchIndex.build(dir, index);
      final searchFile = File('${dir.path}/_index/search-index.json.gz');
      await search.save(searchFile);
      final firstSearchBytes = await searchFile.readAsBytes();
      full.stop();

      final warm = Stopwatch()..start();
      final second = await scanVault(dir, previous: index);
      final loadedSearch = await PkmsSearchIndex.load(searchFile);
      final warmSearch = await PkmsSearchIndex.build(
        dir,
        second,
        previous: loadedSearch,
      );
      await warmSearch.save(searchFile);
      warm.stop();

      final queryTimes = <int>[];
      for (var i = 0; i < 20; i++) {
        final watch = Stopwatch()..start();
        expect(search.search('knowledge $i'), isNotEmpty);
        watch.stop();
        queryTimes.add(watch.elapsedMilliseconds);
      }
      queryTimes.sort();

      expect(full.elapsed, lessThan(const Duration(seconds: 120)));
      expect(warm.elapsed, lessThan(const Duration(seconds: 3)));
      expect(queryTimes[(queryTimes.length * .95).floor() - 1], lessThan(200));
      expect(jsonEncode(index.toJson()), jsonEncode(second.toJson()));
      expect(await searchFile.readAsBytes(), firstSearchBytes);
      expect(await searchFile.length(), greaterThan(0));
    },
    skip: Platform.environment['TYLOG_RUN_10K_BENCHMARK'] != '1',
  );
}
