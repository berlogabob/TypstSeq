import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/tylog_database.dart';
import 'cosine_search.dart';
import 'embedding_jobs.dart';
import 'hybrid_search.dart';
import 'native_embedding.dart';
import 'note_chunk_sync.dart';
import 'semantic_indexer.dart';
import 'semantic_model.dart';
import 'vector_index.dart';

typedef SemanticEmbedderFactory =
    ChunkEmbedder Function(String model, String tokenizer);

sealed class SemanticSearchState {
  const SemanticSearchState();
}

class SemanticNotInstalled extends SemanticSearchState {
  const SemanticNotInstalled();
}

class SemanticDownloading extends SemanticSearchState {
  const SemanticDownloading(this.progress);
  final double progress;
}

class SemanticIndexing extends SemanticSearchState {
  const SemanticIndexing(this.done, this.pending);
  final int done;
  final int pending;
}

class SemanticReady extends SemanticSearchState {
  const SemanticReady();
}

class SemanticError extends SemanticSearchState {
  const SemanticError(this.message);
  final String message;
}

class SemanticSearchController extends ChangeNotifier {
  SemanticSearchController({
    required this.db,
    required this.modelRoot,
    SemanticEmbedderFactory? passageEmbedderFactory,
    SemanticEmbedderFactory? queryEmbedderFactory,
    SemanticModelStore? modelStore,
  }) : _passageFactory = passageEmbedderFactory,
       _queryFactory = queryEmbedderFactory,
       _providedStore = modelStore;

  final TyLogDatabase db;
  final Directory modelRoot;
  final SemanticEmbedderFactory? _passageFactory;
  final SemanticEmbedderFactory? _queryFactory;
  final SemanticModelStore? _providedStore;
  SemanticSearchState state = const SemanticNotInstalled();
  SemanticModelStore? _store;
  Future<void>? _refreshInFlight;
  bool _cancelled = false;

  bool get ready => state is SemanticReady;

  /// Search works on whatever is embedded so far, including during indexing.
  bool get searchable => state is SemanticReady || state is SemanticIndexing;

  /// note path -> nodes.updated_at_ms at the last sync; null until the first
  /// full sync of this session.
  Map<String, int>? _synced;
  ({String query, Future<List<VectorHit>> hits})? _lastQuery;

  /// fp16 scan copy of the embedded chunks; rebuilt when [_indexDirty].
  CompactVectorIndex? _index;
  bool _indexDirty = true;
  DateTime _indexBuiltAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    _store = _providedStore ?? SemanticModelStore(modelRoot);
    try {
      if (await _store!.installed() == null) {
        _set(const SemanticNotInstalled());
      } else {
        _set(const SemanticReady());
      }
    } catch (error) {
      _set(SemanticError('$error'));
    }
  }

  Future<void> download() async {
    final store = _store ??= _providedStore ?? SemanticModelStore(modelRoot);
    _cancelled = false;
    try {
      await store.download(
        cancelled: () => _cancelled,
        onProgress: (received, total) =>
            _set(SemanticDownloading(received / total)),
      );
      _set(const SemanticReady());
      unawaited(refreshNotes());
    } catch (error) {
      _set(_cancelled ? const SemanticNotInstalled() : SemanticError('$error'));
    }
  }

  void cancel() => _cancelled = true;

  Future<void> refreshNotes() {
    final active = _refreshInFlight;
    if (active != null) return active;
    late Future<void> flight;
    flight = _refresh().whenComplete(() {
      if (identical(_refreshInFlight, flight)) _refreshInFlight = null;
    });
    _refreshInFlight = flight;
    return flight;
  }

  Future<void> _refresh() async {
    final store = _store ??= _providedStore ?? SemanticModelStore(modelRoot);
    final files = await store.installed();
    if (files == null) return;
    _cancelled = false;
    try {
      // Paths and change stamps are cheap; only changed notes' text is read,
      // so a save does not rehash the whole vault.
      final stamps = <String, int>{};
      for (final row
          in await db
              .customSelect(
                "SELECT json_extract(attributes_json, '\$.path') AS path, "
                "updated_at_ms FROM nodes "
                "WHERE json_extract(attributes_json, '\$.path') IS NOT NULL",
              )
              .get()) {
        stamps[row.read<String>('path')] = row.read<int>('updated_at_ms');
      }
      final previous = _synced;
      final changed = [
        for (final entry in stamps.entries)
          if (previous == null || previous[entry.key] != entry.value) entry.key,
      ];
      final notes = <String, ({String title, String text})>{};
      for (var i = 0; i < changed.length; i += 500) {
        final batch = changed.sublist(i, (i + 500).clamp(0, changed.length));
        final rows = await db
            .customSelect(
              "SELECT title, content, json_extract(attributes_json, '\$.path') AS path "
              "FROM nodes WHERE json_extract(attributes_json, '\$.path') "
              "IN (${List.filled(batch.length, '?').join(',')})",
              variables: [for (final path in batch) Variable.withString(path)],
            )
            .get();
        for (final row in rows) {
          notes[row.read<String>('path')] = (
            title: row.read<String>('title'),
            text: row.read<String>('content'),
          );
        }
      }
      await syncNoteChunks(db, notes, allPaths: stamps.keys.toSet());
      _synced = stamps;
      _lastQuery = null;
      _indexDirty = true;
      final embed =
          _passageFactory?.call(files.model, files.tokenizer) ??
          nativePassageEmbedder(
            modelPath: files.model,
            tokenizerPath: files.tokenizer,
          );
      final indexer = SemanticIndexer(db: db, embed: embed);
      void listen() {
        _lastQuery = null; // new vectors: a repeated query must rescan
        _indexDirty = true;
        _set(
          SemanticIndexing(
            indexer.progress.value.done,
            indexer.progress.value.pending,
          ),
        );
      }

      indexer.progress.addListener(listen);
      try {
        await indexer.runUntilIdle(cancelled: () => _cancelled);
      } finally {
        indexer.progress.removeListener(listen);
      }
      if (!_cancelled) _set(const SemanticReady());
    } catch (error) {
      if (!_cancelled) _set(SemanticError('$error'));
    }
  }

  void pause() => _cancelled = true;

  Future<List<VectorHit>> searchNotes(String query, {int limit = 20}) async {
    if (!searchable) return const [];
    final chunks = await _chunkHits(query);
    final navigation =
        (await db.navigationForChunks(chunks.map((hit) => hit.id)))
            .whereType<
              ({
                String chunkId,
                String sourceId,
                String sourceVersionId,
                int startOffset,
                int endOffset,
              })
            >();
    final sourceIds = {for (final row in navigation) row.sourceId};
    if (sourceIds.isEmpty) return const [];
    final placeholders = List.filled(sourceIds.length, '?').join(',');
    final sources = await db
        .customSelect(
          'SELECT id, locator FROM sources WHERE kind = \'note\' AND id IN ($placeholders)',
          variables: [for (final id in sourceIds) Variable.withString(id)],
        )
        .get();
    final locators = {
      for (final row in sources)
        row.read<String>('id'): row.readNullable<String>('locator'),
    };
    final scores = {for (final hit in chunks) hit.id: hit.score};
    final best = <String, double>{};
    for (final row in navigation) {
      final path = locators[row.sourceId];
      final score = scores[row.chunkId];
      if (path != null &&
          score != null &&
          (best[path] ?? double.negativeInfinity) < score) {
        best[path] = score;
      }
    }
    final result = [
      for (final entry in best.entries)
        VectorHit(id: entry.key, score: entry.value),
    ];
    result.sort((a, b) => b.score.compareTo(a.score));
    return result.take(limit).toList(growable: false);
  }

  /// Results and citations for the same query share one embedding and scan.
  Future<List<VectorHit>> _chunkHits(String query) {
    final last = _lastQuery;
    if (last != null && last.query == query) return last.hits;
    final hits = _searchChunkHits(query, limit: 100);
    _lastQuery = (query: query, hits: hits);
    return hits;
  }

  Future<List<VectorHit>> _searchChunkHits(
    String query, {
    required int limit,
  }) async {
    final files =
        await (_store ??= _providedStore ?? SemanticModelStore(modelRoot))
            .installed();
    if (files == null) return const [];
    final embed =
        _queryFactory?.call(files.model, files.tokenizer) ??
        nativeQueryEmbedder(
          modelPath: files.model,
          tokenizerPath: files.tokenizer,
        );
    final bytes = await embed(query);
    if (bytes.length % 4 != 0 || bytes.isEmpty) {
      throw StateError('invalid query embedding');
    }
    final vector = Uint8List.fromList(bytes).buffer.asFloat32List().toList();
    final index = await _currentIndex(vector.length);
    // fp16 ranks candidates; the exact Float32 rerank decides the scores.
    final candidates = index.top(vector, 200);
    return topCosineHits(
      query: vector,
      candidates: await db.embeddingsForChunks(
        candidates.map((hit) => hit.id),
        model: kSemanticModelId,
      ),
      limit: limit,
    );
  }

  Future<CompactVectorIndex> _currentIndex(int dimension) async {
    final existing = _index;
    // ponytail: rebuild the whole index when dirty, at most once a minute
    // while indexing adds vectors; append-only updates if rebuilds get hot.
    final throttled =
        state is SemanticIndexing &&
        DateTime.now().difference(_indexBuiltAt) < const Duration(minutes: 1);
    if (existing != null &&
        existing.dimension == dimension &&
        (!_indexDirty || throttled)) {
      return existing;
    }
    final count = await db.embeddedChunkCount(model: kSemanticModelId);
    final builder = CompactVectorIndexBuilder(count + 1024, dimension);
    String? after;
    while (!builder.isFull) {
      final page = await db.embeddedChunkPage(
        model: kSemanticModelId,
        afterId: after,
      );
      if (page.isEmpty) break;
      for (final row in page) {
        if (builder.isFull) break;
        builder.addBytes(row.id, row.embedding);
      }
      after = page.last.id;
    }
    _indexDirty = false;
    _indexBuiltAt = DateTime.now();
    return _index = builder.build();
  }

  Future<List<ChunkCitation>> citations(String query) async {
    if (!searchable) return const [];
    final hits = await _chunkHits(query);
    if (hits.isEmpty) return const [];
    final rows = await db
        .customSelect(
          '''
      SELECT c.id chunk_id, s.id source_id, s.kind source_kind, s.locator source_locator,
             s.title source_title, v.id source_version_id, c.start_offset, c.end_offset, c.content
      FROM chunks c JOIN source_versions v ON v.id = c.source_version_id
      JOIN sources s ON s.id = v.source_id
      WHERE c.id IN (${List.filled(hits.length, '?').join(',')}) AND s.kind = 'note'
      ''',
          variables: [for (final hit in hits) Variable.withString(hit.id)],
        )
        .get();
    return [
      for (final row in rows)
        ChunkCitation(
          chunkId: row.read<String>('chunk_id'),
          sourceId: row.read<String>('source_id'),
          sourceKind: row.read<String>('source_kind'),
          sourceLocator: row.read<String>('source_locator'),
          sourceTitle: row.readNullable<String>('source_title'),
          sourceVersionId: row.read<String>('source_version_id'),
          startOffset: row.read<int>('start_offset'),
          endOffset: row.read<int>('end_offset'),
          content: row.read<String>('content'),
        ),
    ];
  }

  void _set(SemanticSearchState next) {
    state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }
}
