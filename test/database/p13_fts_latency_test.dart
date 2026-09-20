import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';

int _p95(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length * 95 + 99) ~/ 100) - 1];
}

void main() {
  test('10k multilingual FTS queries stay under the keyword gate', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.batch((batch) {
      batch.insertAll(database.nodes, [
        for (var i = 0; i < 10000; i++)
          NodeData(
            id: 'n$i',
            type: 'note',
            title: switch (i % 3) {
              0 => 'Ação research $i',
              1 => 'árvore pesquisa $i',
              _ => 'исследование заметка $i',
            },
            content: 'body $i',
            attributesJson: jsonEncode({'path': 'notes/n$i.typ'}),
            eventStartMs: null,
            eventEndMs: null,
            createdAtMs: now,
            updatedAtMs: now,
          ),
      ]);
    });
    await database.rebuildNodeSearch();
    final timings = <int>[];
    for (var i = 0; i < 100; i++) {
      final watch = Stopwatch()..start();
      final result = await database.searchNodeIds(
        i.isEven ? 'acao' : 'исследование',
      );
      timings.add(watch.elapsedMilliseconds);
      expect(result, isNotEmpty);
    }
    final p95 = _p95(timings);
    // P13's keyword-search gate is <=200 ms p95 at full scale.
    expect(p95, lessThanOrEqualTo(200));
    // ignore: avoid_print
    print(
      'P13 FTS 10k query_ms p95=$p95 max=${([...timings]..sort()).last} samples=100',
    );
  });
}
