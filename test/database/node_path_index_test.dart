import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tylog/database/tylog_database.dart';

const _path = "json_extract(attributes_json, '\$.path')";
const _stamps =
    'SELECT $_path AS path, updated_at_ms FROM nodes '
    'INDEXED BY idx_nodes_path WHERE $_path IS NOT NULL';
String _contents(int count) =>
    'SELECT title, content, $_path AS path '
    'FROM nodes WHERE $_path IN (${List.filled(count, '?').join(',')})';

void main() {
  test('v8 migration preserves notes and indexes path queries', () async {
    final dir = await Directory.systemTemp.createTemp('node-path-migration-');
    final file = File('${dir.path}/db.sqlite');
    var db = TyLogDatabase(NativeDatabase(file));
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    await db
        .into(db.nodes)
        .insert(
          NodesCompanion.insert(
            id: 'kept',
            type: 'note',
            title: 'Kept',
            content: 'body',
            attributesJson: const Value('{"path":"notes/kept.typ"}'),
            createdAtMs: 1,
            updatedAtMs: 2,
          ),
        );
    await db.close();
    final old = sqlite3.open(file.path);
    old.execute('DROP INDEX IF EXISTS idx_nodes_path');
    old.execute('PRAGMA user_version = 8');
    old.close();
    db = TyLogDatabase(NativeDatabase(file));
    expect((await db.select(db.nodes).getSingle()).content, 'body');
    expect(db.schemaVersion, 9);
    for (final query in [
      _stamps,
      _contents(1),
      'SELECT id FROM nodes WHERE $_path = ?',
    ]) {
      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN $query',
            variables: query.contains('?')
                ? [Variable.withString('notes/kept.typ')]
                : [],
          )
          .get();
      expect(
        plan.map((row) => row.read<String>('detail')).join(' '),
        contains('USING INDEX idx_nodes_path'),
      );
    }
    expect(
      (await db.customSelect(_stamps).get()).single.read<String>('path'),
      'notes/kept.typ',
    );
  });

  test('6500-node sync queries: scan versus expression index', () async {
    final db = TyLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.batch((batch) {
      batch.insertAll(db.nodes, [
        for (var i = 0; i < 6500; i++)
          NodesCompanion.insert(
            id: 'n$i',
            type: 'note',
            title: 'Note $i',
            content: List.filled(100, 'note text ').join(),
            attributesJson: Value(
              jsonEncode({
                'path': 'notes/$i.typ',
                'metadata': List.filled(100, 'attribute text').join(),
              }),
            ),
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
      ]);
    });
    Future<double> measure({required bool indexed}) async {
      final watch = Stopwatch()..start();
      final stamps = await db
          .customSelect(
            indexed
                ? _stamps
                : 'SELECT $_path AS path, updated_at_ms FROM nodes '
                      'WHERE $_path IS NOT NULL',
          )
          .get();
      expect(stamps, hasLength(6500));
      var count = 0;
      for (var i = 0; i < 6500; i += 500) {
        final rows = await db
            .customSelect(
              _contents(500),
              variables: [
                for (var j = i; j < i + 500; j++)
                  Variable.withString('notes/$j.typ'),
              ],
            )
            .get();
        count += rows.length;
        expect(rows.first.read<String>('content'), contains('note text'));
      }
      expect(count, 6500);
      return watch.elapsedMicroseconds / 1000;
    }

    await db.customStatement('DROP INDEX IF EXISTS idx_nodes_path');
    final scanPlan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN ${_contents(1)}',
          variables: [Variable.withString('notes/0.typ')],
        )
        .get();
    expect(scanPlan.single.read<String>('detail'), contains('SCAN nodes'));
    await measure(indexed: false); // warm up
    final before = [for (var i = 0; i < 5; i++) await measure(indexed: false)]
      ..sort();
    await db.customStatement('CREATE INDEX idx_nodes_path ON nodes($_path)');
    final indexPlan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN ${_contents(500)}',
          variables: [
            for (var i = 0; i < 500; i++) Variable.withString('notes/$i.typ'),
          ],
        )
        .get();
    expect(
      indexPlan.single.read<String>('detail'),
      contains('SEARCH nodes USING INDEX idx_nodes_path'),
    );
    await measure(indexed: true);
    final after = [for (var i = 0; i < 5; i++) await measure(indexed: true)]
      ..sort();
    // Timing is evidence; the deterministic regression assertion is the plan.
    // ignore: avoid_print
    print(
      '6500-node sync (stamps + 13 x 500 content lookups), warm median/5: '
      'scan=${before[2].toStringAsFixed(3)} ms, '
      'index=${after[2].toStringAsFixed(3)} ms, '
      'speedup=${(before[2] / after[2]).toStringAsFixed(2)}x',
    );
  });
}
