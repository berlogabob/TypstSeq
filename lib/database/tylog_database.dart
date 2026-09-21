import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../pdf/pdf_extraction.dart';
import '../retrieval/chunking.dart';

part 'tylog_database.g.dart';

@DataClassName('DatabaseMetadataData')
class DatabaseMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAtMs => integer().withDefault(Constant(0))();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('NodeData')
class Nodes extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get attributesJson => text().withDefault(Constant('{}'))();
  IntColumn get eventStartMs => integer().nullable()();
  IntColumn get eventEndMs => integer().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (json_valid(attributes_json))',
    'CHECK (event_start_ms IS NULL OR event_end_ms IS NULL OR event_end_ms >= event_start_ms)',
  ];
}

@DataClassName('EdgeData')
class Edges extends Table {
  TextColumn get id => text()();
  @ReferenceName('edgeOutgoing')
  TextColumn get fromNodeId =>
      text().references(Nodes, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('edgeIncoming')
  TextColumn get toNodeId =>
      text().references(Nodes, #id, onDelete: KeyAction.restrict)();
  TextColumn get type => text()();
  TextColumn get attributesJson => text().withDefault(Constant('{}'))();
  IntColumn get validFromMs => integer().nullable()();
  IntColumn get validToMs => integer().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (json_valid(attributes_json))',
    'CHECK (valid_from_ms IS NULL OR valid_to_ms IS NULL OR valid_to_ms >= valid_from_ms)',
  ];
}

@DataClassName('SourceData')
class Sources extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get title => text().nullable()();
  TextColumn get locator => text().nullable()();
  TextColumn get attributesJson => text().withDefault(Constant('{}'))();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (json_valid(attributes_json))'];
}

@DataClassName('SourceVersionData')
class SourceVersions extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId =>
      text().references(Sources, #id, onDelete: KeyAction.cascade)();
  TextColumn get sha256 => text()();
  TextColumn get status => text()();
  TextColumn get pagesJson => text()();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (json_valid(pages_json))',
    "CHECK (status IN ('extracted', 'unsupported', 'invalid'))",
  ];
}

@DataClassName('AnnotationData')
class Annotations extends Table {
  TextColumn get id => text()();
  TextColumn get sourceVersionId =>
      text().references(SourceVersions, #id, onDelete: KeyAction.cascade)();
  IntColumn get page => integer()();
  IntColumn get startOffset => integer()();
  IntColumn get endOffset => integer()();
  TextColumn get quote => text()();
  TextColumn get context => text()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (page >= 0)',
    'CHECK (start_offset >= 0 AND end_offset >= start_offset)',
  ];
}

@DataClassName('ChunkData')
class Chunks extends Table {
  TextColumn get id => text()();
  TextColumn get sourceVersionId =>
      text().references(SourceVersions, #id, onDelete: KeyAction.cascade)();
  IntColumn get startOffset => integer()();
  IntColumn get endOffset => integer()();
  TextColumn get content => text()();
  TextColumn get sha256 => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get embeddingModel => text().nullable()();
  BlobColumn get embedding => blob().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (start_offset >= 0 AND end_offset >= start_offset)',
    "CHECK (status IN ('pending', 'complete', 'failed'))",
  ];
}

@DataClassName('RevisionData')
class Revisions extends Table {
  TextColumn get id => text()();
  TextColumn get entityKind => text()();
  TextColumn get entityId => text()();
  TextColumn get parentRevisionId => text().nullable().references(
    Revisions,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get payloadJson => text()();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (json_valid(payload_json))'];
}

class OutboxEntries extends Table {
  TextColumn get revisionId =>
      text().references(Revisions, #id, onDelete: KeyAction.restrict)();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column> get primaryKey => {revisionId};
}

class DerivedInvalidations extends Table {
  TextColumn get revisionId =>
      text().references(Revisions, #id, onDelete: KeyAction.restrict)();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column> get primaryKey => {revisionId};
}

@DataClassName('ImportJobData')
class ImportJobs extends Table {
  TextColumn get id => text()();
  TextColumn get sourceKind => text()();
  TextColumn get sourceLocator => text().nullable()();
  TextColumn get sourceFingerprint => text()();
  TextColumn get status => text()();
  IntColumn get totalCount => integer()();
  IntColumn get completedCount => integer().withDefault(Constant(0))();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  TextColumn get errorJson => text().withDefault(Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (json_valid(error_json))',
    'CHECK (total_count >= 0)',
    'CHECK (completed_count >= 0 AND completed_count <= total_count)',
    "CHECK (status IN ('running', 'completed', 'failed', 'cancelled'))",
  ];
}

@DataClassName('ImportItemData')
class ImportItems extends Table {
  TextColumn get jobId =>
      text().references(ImportJobs, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourcePath => text()();
  TextColumn get sourceSha256 => text().nullable()();
  TextColumn get state => text()();
  TextColumn get targetNodeId => text().nullable()();
  TextColumn get targetPath => text().nullable()();
  TextColumn get errorJson => text().withDefault(Constant('{}'))();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {jobId, sourcePath};

  @override
  List<String> get customConstraints => [
    'CHECK (json_valid(error_json))',
    "CHECK (state IN ('pending', 'written', 'skipped', 'failed'))",
  ];
}

class NodeSummary {
  const NodeSummary({
    required this.id,
    required this.type,
    required this.title,
    required this.attributesJson,
    required this.updatedAtMs,
  });

  final String id;
  final String type;
  final String title;
  final String attributesJson;
  final int updatedAtMs;
}

class NodeSummaryPage {
  const NodeSummaryPage({
    required this.nodes,
    required this.nextCursor,
    required this.complete,
  });

  final List<NodeSummary> nodes;
  final String? nextCursor;
  final bool complete;
}

class GraphNodeDistance {
  const GraphNodeDistance({required this.id, required this.depth});

  final String id;
  final int depth;
}

typedef PendingRevisionUpload = ({RevisionData revision, NodeData? node});

enum RevisionReceiveResult { applied, duplicate, conflict }

@DriftDatabase(
  tables: [
    DatabaseMetadata,
    Nodes,
    Edges,
    Sources,
    SourceVersions,
    Annotations,
    Chunks,
    Revisions,
    OutboxEntries,
    DerivedInvalidations,
    ImportJobs,
    ImportItems,
  ],
)
class TyLogDatabase extends _$TyLogDatabase {
  static const nodeProjectionKey = 'node_projection_complete_revision';

  TyLogDatabase(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndexes(m);
      await _createQueueIndexes(m);
      await _createRevisionGuards(m);
      await _createImportIndexes(m);
      await _createSourceVersionIndexes(m);
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (to != 8 || from < 1 || from > 7) {
        throw UnsupportedError(
          'Unsupported schema migration from $from to $to',
        );
      }
      if (from == 1) {
        await m.addColumn(databaseMetadata, databaseMetadata.updatedAtMs);
      }
      if (from < 3) {
        await _createGraphSchema(m);
      }
      if (from < 4) {
        await m.create(outboxEntries);
        await m.create(derivedInvalidations);
        await _createQueueIndexes(m);
        await _createRevisionGuards(m);
      }
      if (from < 5) {
        await m.create(importJobs);
        await m.create(importItems);
        await _createImportIndexes(m);
      }
      if (from < 6) {
        await m.create(sourceVersions);
        await _createSourceVersionIndexes(m);
      }
      if (from < 7) await m.create(annotations);
      if (from < 8) await m.create(chunks);
    },
  );

  Future<void> _createGraphSchema(Migrator m) async {
    await m.create(nodes);
    await m.create(edges);
    await m.create(sources);
    await m.create(revisions);
    await _createIndexes(m);
  }

  Future<void> _createIndexes(Migrator m) async {
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(type)',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_nodes_updated_at_ms ON nodes(updated_at_ms)',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_edges_from_node_type ON edges(from_node_id, type)',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_edges_to_node_type ON edges(to_node_id, type)',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_edges_updated_at_ms ON edges(updated_at_ms)',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sources_kind ON sources(kind)',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_revisions_entity_time ON revisions(entity_kind, entity_id, created_at_ms)',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_revisions_parent ON revisions(parent_revision_id)',
    );
  }

  Future<void> _createSourceVersionIndexes(Migrator m) async {
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_source_versions_source_created '
      'ON source_versions(source_id, created_at_ms DESC)',
    );
  }

  Future<void> savePdfExtraction({
    required String sourceId,
    required PdfExtraction extraction,
    required int createdAtMs,
  }) async {
    await into(sourceVersions).insertOnConflictUpdate(
      SourceVersionsCompanion.insert(
        id: extraction.sourceVersionId,
        sourceId: sourceId,
        sha256: extraction.sha256,
        status: extraction.status.name,
        pagesJson: jsonEncode([
          for (final page in extraction.pages)
            {
              'page': page.page,
              'text': page.text,
              'start': page.start,
              'end': page.end,
            },
        ]),
        createdAtMs: createdAtMs,
      ),
    );
  }

  Future<List<SourceVersionData>> sourceVersionsFor(String sourceId) async =>
      (select(sourceVersions)
            ..where((row) => row.sourceId.equals(sourceId))
            ..orderBy([(row) => OrderingTerm.desc(row.createdAtMs)]))
          .get();

  Future<void> saveAnnotation({
    required String id,
    required String sourceVersionId,
    required int page,
    required int startOffset,
    required int endOffset,
    required String quote,
    required String context,
    required int createdAtMs,
    required int updatedAtMs,
  }) async {
    await into(annotations).insertOnConflictUpdate(
      AnnotationsCompanion.insert(
        id: id,
        sourceVersionId: sourceVersionId,
        page: page,
        startOffset: startOffset,
        endOffset: endOffset,
        quote: quote,
        context: context,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs,
      ),
    );
  }

  Future<List<AnnotationData>> annotationsFor(String sourceVersionId) async =>
      (select(annotations)
            ..where((row) => row.sourceVersionId.equals(sourceVersionId))
            ..orderBy([(row) => OrderingTerm.asc(row.startOffset)]))
          .get();

  /// Resolves a retrieved chunk to a stable source and character range.
  Future<
    ({
      String chunkId,
      String sourceId,
      String sourceVersionId,
      int startOffset,
      int endOffset,
    })?
  >
  navigationForChunk(String chunkId) async {
    final rows = await customSelect(
      '''
      SELECT c.id AS chunk_id, v.source_id, c.source_version_id,
             c.start_offset, c.end_offset
      FROM chunks c
      JOIN source_versions v ON v.id = c.source_version_id
      WHERE c.id = ?
      LIMIT 1
      ''',
      variables: [Variable.withString(chunkId)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    return (
      chunkId: row.read<String>('chunk_id'),
      sourceId: row.read<String>('source_id'),
      sourceVersionId: row.read<String>('source_version_id'),
      startOffset: row.read<int>('start_offset'),
      endOffset: row.read<int>('end_offset'),
    );
  }

  Future<List<GraphNodeDistance>> boundedNeighborhood(
    String nodeId, {
    int maxDepth = 3,
    int maxNodes = 200,
    int maxEdges = 500,
  }) async {
    if (maxDepth < 0 || maxDepth > 10) {
      throw ArgumentError.value(
        maxDepth,
        'maxDepth',
        'must be between 0 and 10',
      );
    }
    if (maxNodes < 1 || maxNodes > 200) {
      throw ArgumentError.value(
        maxNodes,
        'maxNodes',
        'must be between 1 and 200',
      );
    }
    if (maxEdges < 0 || maxEdges > 500) {
      throw ArgumentError.value(
        maxEdges,
        'maxEdges',
        'must be between 0 and 500',
      );
    }

    final seed = await customSelect(
      'SELECT id FROM nodes WHERE id = ? LIMIT 1',
      variables: [Variable.withString(nodeId)],
      readsFrom: {nodes},
    ).get();
    if (seed.isEmpty) return const [];

    final distances = <String, int>{nodeId: 0};
    var frontier = <String>[nodeId];
    var examinedEdges = 0;
    for (
      var depth = 0;
      depth < maxDepth &&
          frontier.isNotEmpty &&
          distances.length < maxNodes &&
          examinedEdges < maxEdges;
      depth++
    ) {
      final placeholders = List.filled(frontier.length, '?').join(', ');
      final rows = await customSelect(
        'SELECT DISTINCT id, from_node_id, to_node_id FROM edges '
        'WHERE from_node_id IN ($placeholders) OR to_node_id IN ($placeholders) '
        'ORDER BY id LIMIT ?',
        variables: [
          ...frontier.map(Variable.withString),
          ...frontier.map(Variable.withString),
          Variable.withInt(maxEdges - examinedEdges),
        ],
        readsFrom: {edges},
      ).get();
      examinedEdges += rows.length;

      final next = <String>{};
      for (final row in rows) {
        final from = row.read<String>('from_node_id');
        final to = row.read<String>('to_node_id');
        if (frontier.contains(from)) {
          next.add(to);
        }
        if (frontier.contains(to)) {
          next.add(from);
        }
      }
      final candidates = next.where((id) => !distances.containsKey(id)).toList()
        ..sort();
      final room = maxNodes - distances.length;
      final accepted = candidates.take(room).toList(growable: false);
      for (final id in accepted) {
        distances[id] = depth + 1;
      }
      frontier = accepted;
    }

    return [
      for (final entry in distances.entries)
        GraphNodeDistance(id: entry.key, depth: entry.value),
    ]..sort((a, b) {
      final depth = a.depth.compareTo(b.depth);
      return depth == 0 ? a.id.compareTo(b.id) : depth;
    });
  }

  Future<void> saveEdge(EdgeData edge) async {
    await into(edges).insertOnConflictUpdate(
      EdgesCompanion.insert(
        id: edge.id,
        fromNodeId: edge.fromNodeId,
        toNodeId: edge.toNodeId,
        type: edge.type,
        attributesJson: Value(edge.attributesJson),
        validFromMs: Value(edge.validFromMs),
        validToMs: Value(edge.validToMs),
        createdAtMs: edge.createdAtMs,
        updatedAtMs: edge.updatedAtMs,
      ),
    );
  }

  Future<void> deleteEdge(String edgeId) async {
    await (delete(edges)..where((row) => row.id.equals(edgeId))).go();
  }

  Future<void> saveChunks(Iterable<TextChunk> values) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(
        chunks,
        values
            .map(
              (chunk) => ChunksCompanion.insert(
                id: chunk.id,
                sourceVersionId: chunk.sourceVersionId,
                startOffset: chunk.start,
                endOffset: chunk.end,
                content: chunk.text,
                sha256: chunk.sha256,
              ),
            )
            .toList(),
      );
    });
  }

  Future<List<ChunkData>> pendingChunks({int limit = 100}) =>
      (select(chunks)
            ..where((row) => row.status.equals('pending'))
            ..orderBy([(row) => OrderingTerm.asc(row.id)])
            ..limit(limit))
          .get();

  Future<void> completeChunk(
    String id, {
    required String model,
    required List<int> embedding,
  }) async {
    await (update(chunks)..where((row) => row.id.equals(id))).write(
      ChunksCompanion(
        status: const Value('complete'),
        embeddingModel: Value(model),
        embedding: Value(Uint8List.fromList(embedding)),
      ),
    );
  }

  Future<List<({String id, List<int> embedding})>> embeddedChunkCandidates({
    required String model,
    int limit = 10000,
  }) async {
    if (model.isEmpty) throw ArgumentError.value(model, 'model');
    if (limit < 1 || limit > 100000) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100000');
    }
    final rows =
        await (select(chunks)
              ..where(
                (row) =>
                    row.status.equals('complete') &
                    row.embeddingModel.equals(model) &
                    row.embedding.isNotNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.id)])
              ..limit(limit))
            .get();
    return [
      for (final row in rows)
        if (row.embedding case final embedding?)
          (id: row.id, embedding: embedding),
    ];
  }

  Future<void> _createQueueIndexes(Migrator m) async {
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_outbox_created_at_ms ON outbox_entries(created_at_ms)',
    );
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_invalidations_created_at_ms ON derived_invalidations(created_at_ms)',
    );
  }

  Future<void> _createRevisionGuards(Migrator m) async {
    await m.database.customStatement('''
      CREATE TRIGGER IF NOT EXISTS revisions_no_update
      BEFORE UPDATE ON revisions
      BEGIN SELECT RAISE(ABORT, 'revisions are immutable'); END
    ''');
    await m.database.customStatement('''
      CREATE TRIGGER IF NOT EXISTS revisions_no_delete
      BEFORE DELETE ON revisions
      BEGIN SELECT RAISE(ABORT, 'revisions are immutable'); END
    ''');
  }

  Future<void> _createImportIndexes(Migrator m) async {
    await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_import_items_job_state ON import_items(job_id, state)',
    );
  }

  Future<List<ImportItemData>> pendingImportItems(
    String jobId, {
    int limit = 100,
  }) =>
      (select(importItems)
            ..where((t) => t.jobId.equals(jobId) & t.state.equals('pending'))
            ..orderBy([(t) => OrderingTerm.asc(t.sourcePath)])
            ..limit(limit))
          .get();

  Future<NodeSummaryPage> pageNodeSummaries({
    String? afterId,
    String? type,
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100');
    }
    final conditions = <String>[];
    final variables = <Variable<Object>>[];
    if (afterId != null) {
      conditions.add('id > ?');
      variables.add(Variable.withString(afterId));
    }
    if (type != null) {
      conditions.add('type = ?');
      variables.add(Variable.withString(type));
    }
    variables.add(Variable.withInt(limit));
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = await customSelect('''
      SELECT id, type, title, attributes_json, updated_at_ms
      FROM nodes
      $where
      ORDER BY id ASC
      LIMIT ?
      ''', variables: variables).get();
    final nodes = [
      for (final row in rows)
        NodeSummary(
          id: row.read<String>('id'),
          type: row.read<String>('type'),
          title: row.read<String>('title'),
          attributesJson: row.read<String>('attributes_json'),
          updatedAtMs: row.read<int>('updated_at_ms'),
        ),
    ];
    return NodeSummaryPage(
      nodes: nodes,
      nextCursor: nodes.length == limit ? nodes.last.id : null,
      complete: await nodeProjectionComplete(),
    );
  }

  Future<bool> nodeProjectionComplete() async {
    final row = await (select(
      databaseMetadata,
    )..where((table) => table.key.equals(nodeProjectionKey))).getSingleOrNull();
    final revision = row == null ? null : int.tryParse(row.value);
    return revision != null && revision >= 0;
  }

  Future<void> markNodeProjectionComplete(int revision) async {
    if (revision < 0) throw ArgumentError.value(revision, 'revision');
    await into(databaseMetadata).insertOnConflictUpdate(
      DatabaseMetadataData(
        key: nodeProjectionKey,
        value: '$revision',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> markImportItem({
    required ImportItemData item,
    required int completedCount,
    required String status,
  }) async {
    await transaction(() async {
      final job = await (select(
        importJobs,
      )..where((table) => table.id.equals(item.jobId))).getSingleOrNull();
      if (job == null) throw StateError('Import job does not exist');
      if (job.status == 'cancelled') {
        throw StateError('Import job is cancelled');
      }
      await into(importItems).insertOnConflictUpdate(item);
      await (update(importJobs)..where((t) => t.id.equals(item.jobId))).write(
        ImportJobsCompanion(
          completedCount: Value(completedCount),
          status: Value(status),
          updatedAtMs: Value(item.updatedAtMs),
        ),
      );
    });
  }

  /// Reopens a resumable job and returns its next pending batch.
  Future<List<ImportItemData>> resumeImportJob(
    String jobId, {
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 1000');
    }
    await transaction(() async {
      final job = await (select(
        importJobs,
      )..where((table) => table.id.equals(jobId))).getSingleOrNull();
      if (job == null) throw StateError('Import job does not exist');
      if (job.status == 'completed') return;
      await (update(
        importJobs,
      )..where((table) => table.id.equals(jobId))).write(
        ImportJobsCompanion(
          status: const Value('running'),
          updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    });
    return pendingImportItems(jobId, limit: limit);
  }

  Future<void> cancelImportJob(String jobId, {int? nowMs}) async {
    final changed =
        await (update(importJobs)..where(
              (table) =>
                  table.id.equals(jobId) & table.status.isNotIn(['completed']),
            ))
            .write(
              ImportJobsCompanion(
                status: const Value('cancelled'),
                updatedAtMs: Value(
                  nowMs ?? DateTime.now().millisecondsSinceEpoch,
                ),
              ),
            );
    if (changed == 0) {
      final exists = await (select(
        importJobs,
      )..where((table) => table.id.equals(jobId))).getSingleOrNull();
      if (exists == null) throw StateError('Import job does not exist');
    }
  }

  Future<void> checkpointImportItem({required ImportItemData item}) async {
    await (update(importItems)..where(
          (t) =>
              t.jobId.equals(item.jobId) & t.sourcePath.equals(item.sourcePath),
        ))
        .write(
          ImportItemsCompanion(
            sourceSha256: Value(item.sourceSha256),
            targetPath: Value(item.targetPath),
            updatedAtMs: Value(item.updatedAtMs),
          ),
        );
  }

  Future<List<PendingRevisionUpload>> pendingRevisionUploads({
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 1000');
    }
    final entries =
        await (select(outboxEntries)
              ..orderBy([(table) => OrderingTerm.asc(table.createdAtMs)])
              ..limit(limit))
            .get();
    final uploads = <PendingRevisionUpload>[];
    for (final entry in entries) {
      final revision = await (select(
        revisions,
      )..where((table) => table.id.equals(entry.revisionId))).getSingleOrNull();
      if (revision == null) continue;
      final node =
          await (select(nodes)
                ..where((table) => table.id.equals(revision.entityId)))
              .getSingleOrNull();
      uploads.add((revision: revision, node: node));
    }
    return uploads;
  }

  Future<void> acknowledgeRevisionUpload(String revisionId) async {
    final removed = await (delete(
      outboxEntries,
    )..where((table) => table.revisionId.equals(revisionId))).go();
    if (removed == 0) return;
  }

  Future<RevisionReceiveResult> receiveRevision({
    required NodeData node,
    required RevisionData revision,
  }) async {
    if (revision.entityKind != 'node' || revision.entityId != node.id) {
      throw ArgumentError('Revision must describe the edited node');
    }
    return transaction(() async {
      final duplicate = await (select(
        revisions,
      )..where((table) => table.id.equals(revision.id))).getSingleOrNull();
      if (duplicate != null) return RevisionReceiveResult.duplicate;
      final head =
          await (select(revisions)
                ..where(
                  (table) =>
                      table.entityKind.equals('node') &
                      table.entityId.equals(node.id),
                )
                ..orderBy([
                  (table) => OrderingTerm.desc(table.createdAtMs),
                  (table) => OrderingTerm.desc(table.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (head?.id != revision.parentRevisionId) {
        return RevisionReceiveResult.conflict;
      }
      await _commitNodeRows(
        node: node,
        revision: revision,
        queuePublication: false,
      );
      return RevisionReceiveResult.applied;
    });
  }

  Future<void> createOrResumeImportJob(
    ImportJobData job,
    List<ImportItemData> items,
  ) async {
    final paths = <String>{};
    for (final item in items) {
      if (item.jobId != job.id || !paths.add(item.sourcePath)) {
        throw ArgumentError(
          'Import items must belong to the job and be unique',
        );
      }
      if (item.state != 'pending') {
        throw ArgumentError('New import items must be pending');
      }
    }
    if (job.status != 'running' ||
        job.completedCount != 0 ||
        items.length != job.totalCount) {
      throw ArgumentError(
        'Import job must start running with all pending items',
      );
    }
    await transaction(() async {
      final existing = await (select(
        importJobs,
      )..where((table) => table.id.equals(job.id))).getSingleOrNull();
      if (existing != null) {
        if (existing.sourceKind != job.sourceKind ||
            existing.sourceFingerprint != job.sourceFingerprint ||
            existing.totalCount != job.totalCount) {
          throw ArgumentError('Import job identity cannot change');
        }
        await batch((batch) {
          batch.insertAll(importItems, items, mode: InsertMode.insertOrIgnore);
        });
        return;
      }
      await into(importJobs).insert(job);
      await batch((batch) {
        batch.insertAll(importItems, items);
      });
    });
  }

  Future<void> commitNodeEdit({
    required NodeData node,
    required RevisionData revision,
  }) async {
    if (revision.entityKind != 'node' || revision.entityId != node.id) {
      throw ArgumentError('Revision must describe the edited node');
    }
    await transaction(() async {
      await _commitNodeRows(node: node, revision: revision);
    });
  }

  Future<void> _commitNodeRows({
    required NodeData node,
    required RevisionData revision,
    bool queuePublication = true,
  }) async {
    await _ensureNodeSearch();
    await into(nodes).insertOnConflictUpdate(node);
    await _upsertNodeSearch(node);
    await into(revisions).insert(revision);
    if (queuePublication) {
      await into(outboxEntries).insert(
        OutboxEntry(revisionId: revision.id, createdAtMs: revision.createdAtMs),
      );
    }
    await into(derivedInvalidations).insert(
      DerivedInvalidation(
        revisionId: revision.id,
        createdAtMs: revision.createdAtMs,
      ),
    );
  }

  Future<void> _ensureNodeSearch() => customStatement('''
    CREATE VIRTUAL TABLE IF NOT EXISTS node_search_fts USING fts5(
      node_id UNINDEXED,
      title,
      content,
      attributes,
      tokenize = 'unicode61 remove_diacritics 2'
    )
  ''');

  Future<void> rebuildNodeSearch() async {
    await transaction(() async {
      await _ensureNodeSearch();
      await customStatement('DELETE FROM node_search_fts');
      await customStatement('''
        INSERT INTO node_search_fts(node_id, title, content, attributes)
        SELECT id, title, content, attributes_json FROM nodes
      ''');
    });
  }

  Future<void> _upsertNodeSearch(NodeData node) async {
    await customStatement('DELETE FROM node_search_fts WHERE node_id = ?', [
      node.id,
    ]);
    await customStatement(
      'INSERT INTO node_search_fts(node_id, title, content, attributes) '
      'VALUES (?, ?, ?, ?)',
      [node.id, node.title, node.content, node.attributesJson],
    );
  }

  /// Reindexes only the supplied IDs and returns the number inspected.
  Future<int> refreshNodeSearch(Iterable<String> nodeIds) async {
    final ids = nodeIds.toSet();
    if (ids.isEmpty) return 0;
    await transaction(() async {
      await _ensureNodeSearch();
      for (final id in ids) {
        final node = await (select(
          nodes,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        await customStatement('DELETE FROM node_search_fts WHERE node_id = ?', [
          id,
        ]);
        if (node != null) await _upsertNodeSearch(node);
      }
    });
    return ids.length;
  }

  Future<List<String>> searchNodeIds(String query, {int limit = 50}) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100');
    }
    final terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .map((term) => '"${term.replaceAll('"', '""')}"*')
        .join(' AND ');
    if (terms.isEmpty) return const [];
    await _ensureNodeSearch();
    final rows = await customSelect(
      '''
      SELECT node_id FROM node_search_fts
      JOIN nodes ON nodes.id = node_search_fts.node_id
      WHERE node_search_fts MATCH ?
        AND json_extract(nodes.attributes_json, '\$.deletedAtMs') IS NULL
      ORDER BY rank
      LIMIT ?
      ''',
      variables: [Variable.withString(terms), Variable.withInt(limit)],
    ).get();
    return [for (final row in rows) row.read<String>('node_id')];
  }

  Future<void> commitImportedNode({
    required NodeData node,
    required RevisionData revision,
    required ImportItemData item,
    required int completedCount,
    required String status,
  }) async {
    if (revision.entityKind != 'node' || revision.entityId != node.id) {
      throw ArgumentError('Revision must describe the edited node');
    }
    if (item.jobId.isEmpty ||
        item.targetNodeId != node.id ||
        item.state != 'written') {
      throw ArgumentError('Import item must target the imported node');
    }
    await transaction(() async {
      final job = await (select(
        importJobs,
      )..where((table) => table.id.equals(item.jobId))).getSingleOrNull();
      if (job == null) throw ArgumentError('Import job does not exist');
      await _commitNodeRows(node: node, revision: revision);
      await into(importItems).insertOnConflictUpdate(item);
      await (update(
        importJobs,
      )..where((table) => table.id.equals(item.jobId))).write(
        ImportJobsCompanion(
          completedCount: Value(completedCount),
          status: Value(status),
          updatedAtMs: Value(item.updatedAtMs),
        ),
      );
    });
  }

  Future<bool> claimVault(String stableVaultId) async {
    if (stableVaultId.isEmpty) {
      throw ArgumentError.value(stableVaultId, 'stableVaultId');
    }
    return transaction(() async {
      await into(databaseMetadata).insert(
        DatabaseMetadataCompanion.insert(
          key: _vaultOwnerMetadataKey,
          value: stableVaultId,
          updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
        ),
        mode: InsertMode.insertOrIgnore,
      );
      final owner =
          await (select(databaseMetadata)
                ..where((table) => table.key.equals(_vaultOwnerMetadataKey)))
              .getSingleOrNull();
      return owner?.value == stableVaultId;
    });
  }
}

const _vaultOwnerMetadataKey = 'database_owner_vault_id';

Future<TyLogDatabase> openDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/tylog.db');
  return openDatabaseWithFile(file);
}

Future<TyLogDatabase> openDatabaseForVault(String stableVaultId) async {
  if (stableVaultId.isEmpty) {
    throw ArgumentError.value(stableVaultId, 'stableVaultId');
  }
  final dir = await getApplicationSupportDirectory();
  final legacy = await openDatabaseWithFile(File('${dir.path}/tylog.db'));
  if (await legacy.claimVault(stableVaultId)) return legacy;
  await legacy.close();
  return openDatabaseWithFile(
    File('${dir.path}/${_vaultDatabaseName(stableVaultId)}'),
  );
}

String _vaultDatabaseName(String stableVaultId) =>
    'tylog-${sha256.convert(utf8.encode(stableVaultId))}.db';

Future<TyLogDatabase> openDatabaseWithFile(File file) async {
  final db = TyLogDatabase(
    NativeDatabase.createInBackground(
      file,
      setup: (database) {
        database.execute('PRAGMA journal_mode = WAL');
        database.execute('PRAGMA foreign_keys = ON');
        database.execute('PRAGMA busy_timeout = 5000');
      },
    ),
  );
  try {
    await db.customSelect('SELECT 1').getSingle();
    return db;
  } catch (_) {
    await db.close();
    rethrow;
  }
}
