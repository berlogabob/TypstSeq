import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';

// Exercise the production opener, including Drift's nested database isolate.
// Report success only after close, then let the owning isolate exit naturally.
Future<void> _openUseAndClose((String, SendPort) boot) async {
  final (path, results) = boot;
  try {
    final db = await openDatabaseWithFile(File(path));
    try {
      await db.customStatement(
        'CREATE TABLE IF NOT EXISTS shutdown_probe (value INTEGER)',
      );
      await db.transaction(() async {
        await db.customStatement('DELETE FROM shutdown_probe');
        await db.customStatement('INSERT INTO shutdown_probe VALUES (?)', [42]);
      });
      // Exceed Drift's statement cache capacity to cover eviction and shutdown.
      for (var i = 0; i < 100; i++) {
        final row = await db
            .customSelect(
              'SELECT value + $i AS result FROM shutdown_probe WHERE value = ?',
              variables: [const Variable<int>(42)],
            )
            .getSingle();
        if (row.read<int>('result') != 42 + i) {
          throw StateError('Unexpected query result');
        }
      }
    } finally {
      await db.close();
    }
    results.send('closed');
  } catch (error, stack) {
    results.send('$error\n$stack');
  }
}

void main() {
  test(
    'file database closes before its owning isolate exits, 50 times',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tylog_shutdown_',
      );
      try {
        for (var i = 0; i < 50; i++) {
          final messages = ReceivePort();
          try {
            await Isolate.spawn(
              _openUseAndClose,
              ('${directory.path}/probe.db', messages.sendPort),
              onError: messages.sendPort,
              onExit: messages.sendPort,
            );
            // Waiting for onExit ensures shutdown finalizers actually run.
            final received = await messages
                .take(2)
                .toList()
                .timeout(const Duration(seconds: 15));
            expect(received, ['closed', null], reason: 'iteration $i');
          } finally {
            messages.close();
          }
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
