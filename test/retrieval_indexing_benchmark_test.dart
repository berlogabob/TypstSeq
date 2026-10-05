import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// The optional host benchmark loads typst_flutter's existing FRB dependency.
// ignore: depend_on_referenced_packages
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:typst_flutter/src/rust/frb_generated.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/retrieval/native_embedding.dart';
import 'package:tylog/retrieval/semantic_indexer.dart';

// Synthetic English research prose, ~1.5 KB; never reads a vault.
final benchmarkText = List.filled(
  8,
  'The research journal records observations, methods and supporting evidence. '
  'Each experiment compares measured results with earlier notes and documents '
  'the assumptions needed to reproduce the analysis. ',
).join();

class _SqlTimings extends QueryInterceptor {
  final count = Stopwatch();
  bool enabled = false;
  int countQueries = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final timed = enabled && statement.contains('COUNT(');
    if (timed) {
      countQueries++;
      count.start();
    }
    try {
      return await executor.runSelect(statement, args);
    } finally {
      if (timed) count.stop();
    }
  }
}

class _TimedDatabase extends TyLogDatabase {
  _TimedDatabase(super.executor);
  final pending = Stopwatch();
  final complete = Stopwatch();

  @override
  Future<List<ChunkData>> pendingChunks({int limit = 100}) async {
    pending.start();
    try {
      return await super.pendingChunks(limit: limit);
    } finally {
      pending.stop();
    }
  }

  @override
  Future<void> completeChunk(
    String id, {
    required String model,
    required List<int> embedding,
  }) async {
    complete.start();
    try {
      await super.completeChunk(id, model: model, embedding: embedding);
    } finally {
      complete.stop();
    }
  }
}

/// Also callable by a socket-free flutter_tester host runner.
Future<void> runIndexingBenchmark() async {
  final dir = await Directory.systemTemp.createTemp('tylog-index-bench-');
  final sql = _SqlTimings();
  final db = _TimedDatabase(
    NativeDatabase(File('${dir.path}/index.sqlite')).interceptWith(sql),
  );
  final indexer = SemanticIndexer(
    db: db,
    embed: (_) async {
      embedTime.start();
      await Future<void>.delayed(const Duration(milliseconds: 29));
      embedTime.stop();
      return Uint8List(1536);
    },
  );
  embedTime.reset();
  try {
    await db.customStatement(
      "INSERT INTO sources(id, kind, created_at_ms, updated_at_ms) "
      "VALUES ('source', 'note', 0, 0)",
    );
    await db.customStatement(
      "INSERT INTO source_versions(id, source_id, sha256, status, pages_json, created_at_ms) "
      "VALUES ('version', 'source', 'hash', 'extracted', '[]', 0)",
    );
    await db.customStatement(
      'WITH RECURSIVE n(i) AS (VALUES(0) UNION ALL SELECT i+1 FROM n WHERE i<99999) '
      'INSERT INTO chunks(id, source_version_id, start_offset, end_offset, content, '
      'sha256, status, embedding_model, embedding) '
      "SELECT printf('%06d',i), 'version', 0, ?, ?, printf('hash-%d',i), "
      "CASE WHEN i%2=0 THEN 'complete' ELSE 'pending' END, "
      "CASE WHEN i%2=0 THEN 'fake' ELSE NULL END, "
      'CASE WHEN i%2=0 THEN zeroblob(1536) ELSE NULL END FROM n',
      [benchmarkText.length, benchmarkText],
    );
    sql.enabled = true;
    final wall = Stopwatch()..start();
    await indexer.runUntilIdle(
      cancelled: () => indexer.progress.value.done >= 320,
    );
    wall.stop();
    final p = indexer.progress.value;
    if (p.done != 320 || p.pending != 49680 || p.running) {
      throw StateError('Unexpected indexing progress: $p');
    }
    if (sql.countQueries != 3) {
      throw StateError('Expected 3 pending counts, got ${sql.countQueries}');
    }
    final ms = wall.elapsedMicroseconds / 1000;
    // ignore: avoid_print
    print(
      'INDEX_BENCH rows=100000 text_bytes=${benchmarkText.length} '
      'done=${p.done} chunks_s=${(320000 / ms).toStringAsFixed(2)} '
      'ms_chunk=${(ms / 320).toStringAsFixed(2)} '
      'pendingChunks_ms=${db.pending.elapsedMicroseconds / 1000} '
      'embed_ms=${embedTime.elapsedMicroseconds / 1000} '
      'completeChunk_ms=${db.complete.elapsedMicroseconds / 1000} '
      '_pendingCount_sql_ms=${sql.count.elapsedMicroseconds / 1000} '
      'other_ms=${ms - (db.pending.elapsedMicroseconds + embedTime.elapsedMicroseconds + db.complete.elapsedMicroseconds + sql.count.elapsedMicroseconds) / 1000}',
    );
  } finally {
    indexer.progress.dispose();
    await db.close();
    await dir.delete(recursive: true);
  }
}

final embedTime = Stopwatch();

Future<void> runNativeBenchmark() async {
  final library = Platform.environment['TYLOG_BENCH_DYLIB'];
  final modelDir = Platform.environment['TYLOG_BENCH_MODEL_DIR'];
  if (library == null || modelDir == null) return;
  await RustLib.init(externalLibrary: ExternalLibrary.open(library));
  final embed = nativeEmbedder(
    modelPath: '$modelDir/model_O4.onnx',
    tokenizerPath: '$modelDir/tokenizer.json',
  );
  final first = Stopwatch()..start();
  if ((await embed(benchmarkText)).length != 1536) {
    throw StateError('Invalid embedding byte length');
  }
  first.stop();
  final warm = Stopwatch()..start();
  for (var i = 0; i < 50; i++) {
    if ((await embed(benchmarkText)).length != 1536) {
      throw StateError('Invalid embedding byte length');
    }
  }
  warm.stop();
  // ignore: avoid_print
  print(
    'NATIVE_BENCH chunks=50 cold_ms=${first.elapsedMicroseconds / 1000} '
    'warm_ms_chunk=${warm.elapsedMicroseconds / 50000} '
    'chunks_s=${50000000 / warm.elapsedMicroseconds}',
  );
}

void main() {
  test(
    'file-backed 100k chunk indexing stage benchmark',
    runIndexingBenchmark,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'optional production native host benchmark',
    runNativeBenchmark,
    skip: Platform.environment['TYLOG_BENCH_DYLIB'] == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
