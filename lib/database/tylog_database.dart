import 'dart:io';

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

@DriftDatabase(tables: [DatabaseMetadata, Nodes, Edges, Sources, Revisions])
class TyLogDatabase extends _$TyLogDatabase {
  TyLogDatabase(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndexes(m);
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (to != 3 || (from != 1 && from != 2)) {
        throw UnsupportedError(
          'Unsupported schema migration from $from to $to',
        );
      }
      if (from == 1) {
        await m.addColumn(databaseMetadata, databaseMetadata.updatedAtMs);
      }
      await m.create(nodes);
      await m.create(edges);
      await m.create(sources);
      await m.create(revisions);
      await _createIndexes(m);
    },
  );

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
}

Future<TyLogDatabase> openDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/tylog.db');
  return openDatabaseWithFile(file);
}

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
