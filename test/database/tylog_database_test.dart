import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  group('TyLogDatabase', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('tylog_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fresh creation has schema version 2', () async {
      final file = File('${tempDir.path}/fresh.db');
      final db = await openDatabaseWithFile(file);
      expect(db.schemaVersion, equals(2));
      await db.close();
    });

    test('fresh creation has DatabaseMetadata table', () async {
      final file = File('${tempDir.path}/fresh_table.db');
      final db = await openDatabaseWithFile(file);

      // Insert a test row to verify table exists and works
      await db
          .into(db.databaseMetadata)
          .insert(
            DatabaseMetadataData(
              key: 'test_key',
              value: 'test_value',
              updatedAtMs: 12345,
            ),
          );

      final rows = await db.select(db.databaseMetadata).get();
      expect(rows.length, equals(1));
      expect(rows[0].key, equals('test_key'));
      expect(rows[0].value, equals('test_value'));
      expect(rows[0].updatedAtMs, equals(12345));

      await db.close();
    });

    test('WAL pragma enabled on fresh creation', () async {
      final file = File('${tempDir.path}/wal.db');
      final db = await openDatabaseWithFile(file);

      final result = await db
          .customSelect('PRAGMA journal_mode')
          .getSingle()
          .then((row) => row.data['journal_mode']);
      expect(result, equals('wal'));

      await db.close();
    });

    test('foreign_keys pragma enabled', () async {
      final file = File('${tempDir.path}/fk.db');
      final db = await openDatabaseWithFile(file);

      final result = await db
          .customSelect('PRAGMA foreign_keys')
          .getSingle()
          .then((row) => row.data['foreign_keys']);
      expect(result, equals(1));

      await db.close();
    });

    test('busy_timeout pragma set to 5000', () async {
      final file = File('${tempDir.path}/timeout.db');
      final db = await openDatabaseWithFile(file);

      // PRAGMA busy_timeout returns a single value (timeout in ms)
      final result = await db
          .customSelect('PRAGMA busy_timeout')
          .getSingle()
          .then((row) => row.data.values.first);
      expect(result, equals(5000));

      await db.close();
    });

    test('v1 database migrates to v2, preserving rows', () async {
      final file = File('${tempDir.path}/v1_migration.db');

      // Create a v1 database file using sqlite3
      final sqlite = sqlite3.open(file.path);
      sqlite.execute('''
        PRAGMA user_version = 1;
      ''');
      sqlite.execute('''
        CREATE TABLE database_metadata (
          key TEXT NOT NULL PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      sqlite.execute('''
        INSERT INTO database_metadata (key, value)
        VALUES ('existing_key', 'existing_value')
      ''');
      sqlite.close();

      // Now open with Drift, which should migrate
      final db = await openDatabaseWithFile(file);
      expect(db.schemaVersion, equals(2));

      // Verify the row was preserved
      final rows = await db.select(db.databaseMetadata).get();
      expect(rows.length, equals(1));
      expect(rows[0].key, equals('existing_key'));
      expect(rows[0].value, equals('existing_value'));
      // The migrated row should have the default updatedAtMs value of 0
      expect(rows[0].updatedAtMs, equals(0));

      await db.close();
    });

    test('reopen is idempotent', () async {
      final file = File('${tempDir.path}/reopen.db');

      // First open and insert data
      var db = await openDatabaseWithFile(file);
      await db
          .into(db.databaseMetadata)
          .insert(
            DatabaseMetadataData(
              key: 'persistent_key',
              value: 'persistent_value',
              updatedAtMs: 999,
            ),
          );
      await db.close();

      // Reopen and verify data
      db = await openDatabaseWithFile(file);
      final rows = await db.select(db.databaseMetadata).get();
      expect(rows.length, equals(1));
      expect(rows[0].key, equals('persistent_key'));
      expect(rows[0].value, equals('persistent_value'));
      expect(rows[0].updatedAtMs, equals(999));

      // Verify pragmas are still set
      final walMode = await db
          .customSelect('PRAGMA journal_mode')
          .getSingle()
          .then((row) => row.data['journal_mode']);
      expect(walMode, equals('wal'));

      final fkEnabled = await db
          .customSelect('PRAGMA foreign_keys')
          .getSingle()
          .then((row) => row.data['foreign_keys']);
      expect(fkEnabled, equals(1));

      await db.close();
    });

    test('unsupported migration version is rejected', () async {
      final file = File('${tempDir.path}/unsupported_migration.db');

      // Create a v3 database file (unsupported)
      final sqlite = sqlite3.open(file.path);
      sqlite.execute('''
        PRAGMA user_version = 3;
      ''');
      sqlite.execute('''
        CREATE TABLE database_metadata (
          key TEXT NOT NULL PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at_ms INTEGER NOT NULL DEFAULT 0
        )
      ''');
      sqlite.close();

      // Attempting to open should fail (throws DriftRemoteException wrapping UnsupportedError)
      expect(() => openDatabaseWithFile(file), throwsException);
    });
  });
}
