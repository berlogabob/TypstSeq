import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';

const runScaleBenchmarks = bool.fromEnvironment('TYLOG_RUN_SCALE_BENCHMARKS');

void main() {
  test('measures bounded traversal at a synthetic high-degree hub', () async {
    const nodeCount = 100000;
    const edgeCount = 1000000;
    const insertBatchSize = 5000;
    const warmupRuns = 5;
    const measuredRuns = 40;
    final db = TyLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.transaction(() async {
      for (var start = 0; start < nodeCount; start += insertBatchSize) {
        final end = (start + insertBatchSize).clamp(0, nodeCount);
        await db.batch((batch) {
          batch.insertAll(
            db.nodes,
            List.generate(end - start, (offset) {
              final i = start + offset;
              return NodesCompanion.insert(
                id: 'n${i.toString().padLeft(6, '0')}',
                type: 'note',
                title: 'synthetic $i',
                content: '',
                createdAtMs: 1,
                updatedAtMs: 1,
              );
            }),
          );
        });
      }
      for (var start = 0; start < edgeCount; start += insertBatchSize) {
        final end = (start + insertBatchSize).clamp(0, edgeCount);
        await db.batch((batch) {
          batch.insertAll(
            db.edges,
            List.generate(end - start, (offset) {
              final i = start + offset;
              return EdgesCompanion.insert(
                id: 'e${i.toString().padLeft(7, '0')}',
                fromNodeId: 'n000000',
                toNodeId:
                    'n${(i % (nodeCount - 1) + 1).toString().padLeft(6, '0')}',
                type: 'links',
                createdAtMs: 1,
                updatedAtMs: 1,
              );
            }),
          );
        });
      }
    });

    final samples = <int>[];
    for (var i = 0; i < warmupRuns + measuredRuns; i++) {
      final watch = Stopwatch()..start();
      final result = await db.boundedNeighborhood('n000000');
      watch.stop();
      expect(result.length, lessThanOrEqualTo(200));
      expect(result.first.id, 'n000000');
      if (i >= warmupRuns) samples.add(watch.elapsedMicroseconds);
    }

    samples.sort();
    int percentile(double p) => samples[(samples.length * p).ceil() - 1];
    stdout.writeln('Synthetic SQLite high-degree traversal (in-memory)');
    stdout.writeln('nodes=$nodeCount edges=$edgeCount hub_degree=$edgeCount');
    stdout.writeln(
      'runs=$measuredRuns warmup=$warmupRuns configured_limits=200 nodes/500 edges',
    );
    stdout.writeln(
      'latency_ms p50=${(percentile(.50) / 1000).toStringAsFixed(3)} '
      'p95=${(percentile(.95) / 1000).toStringAsFixed(3)} '
      'max=${(samples.last / 1000).toStringAsFixed(3)}',
    );
    expect(samples, hasLength(measuredRuns));
  }, skip: !runScaleBenchmarks);
}
