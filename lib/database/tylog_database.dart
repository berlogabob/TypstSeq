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

@DriftDatabase(tables: [DatabaseMetadata])
class TyLogDatabase extends _$TyLogDatabase {
  TyLogDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from == 1 && to == 2) {
        await m.addColumn(databaseMetadata, databaseMetadata.updatedAtMs);
      } else {
        throw UnsupportedError(
          'Unsupported schema migration from $from to $to',
        );
      }
    },
  );
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
