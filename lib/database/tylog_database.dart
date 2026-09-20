import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

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

@DriftDatabase(
  tables: [
    DatabaseMetadata,
    Nodes,
    Edges,
    Sources,
    Revisions,
    OutboxEntries,
    DerivedInvalidations,
    ImportJobs,
    ImportItems,
  ],
)
class TyLogDatabase extends _$TyLogDatabase {
  TyLogDatabase(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndexes(m);
      await _createQueueIndexes(m);
      await _createRevisionGuards(m);
      await _createImportIndexes(m);
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (to != 5 || from < 1 || from > 4) {
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

  Future<void> markImportItem({
    required ImportItemData item,
    required int completedCount,
    required String status,
  }) async {
    await transaction(() async {
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
  }) async {
    await into(nodes).insertOnConflictUpdate(node);
    await into(revisions).insert(revision);
    await into(outboxEntries).insert(
      OutboxEntry(revisionId: revision.id, createdAtMs: revision.createdAtMs),
    );
    await into(derivedInvalidations).insert(
      DerivedInvalidation(
        revisionId: revision.id,
        createdAtMs: revision.createdAtMs,
      ),
    );
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
