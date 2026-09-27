import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/tylog_database.dart';
import 'embedding_jobs.dart';
import 'semantic_model.dart';

class SemanticIndexer {
  SemanticIndexer({
    required this.db,
    required this.embed,
    this.model = kSemanticModelId,
    this.batch = 16,
  });

  final TyLogDatabase db;
  final ChunkEmbedder embed;
  final String model;
  final int batch;
  final progress = ValueNotifier<({int done, int pending, bool running})>((
    done: 0,
    pending: 0,
    running: false,
  ));
  Future<void>? _inFlight;

  Future<void> runUntilIdle({bool Function()? cancelled}) {
    final active = _inFlight;
    if (active != null) return active;
    late Future<void> flight;
    flight = _run(cancelled).whenComplete(() {
      if (identical(_inFlight, flight)) _inFlight = null;
    });
    _inFlight = flight;
    return flight;
  }

  Future<void> _run(bool Function()? cancelled) async {
    var done = 0;
    var pending = await _pendingCount();
    progress.value = (done: done, pending: pending, running: true);
    try {
      while (!(cancelled?.call() ?? false)) {
        final result = await runEmbeddingBatch(
          database: db,
          model: model,
          embed: embed,
          limit: batch,
        );
        done += result.completed;
        pending = await _pendingCount();
        progress.value = (done: done, pending: pending, running: true);
        // Failed chunks stay pending for a later run; a batch that completes
        // nothing would otherwise re-claim them forever.
        if (result.claimed == 0 || result.completed == 0) break;
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      progress.value = (done: done, pending: pending, running: false);
    }
  }

  Future<int> _pendingCount() async {
    final count = db.chunks.id.count();
    return (await (db.selectOnly(db.chunks)
          ..addColumns([count])
          ..where(db.chunks.status.equals('pending')))
        .map((row) => row.read(count)!)
        .getSingle());
  }
}
