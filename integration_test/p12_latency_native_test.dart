import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';

int _p95(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length * 95 + 99) ~/ 100) - 1];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P12e Android database latency acceptance', (_) async {
    final startup = <int>[];
    for (var i = 0; i < 30; i++) {
      final watch = Stopwatch()..start();
      final database = TyLogDatabase(NativeDatabase.memory());
      await database.select(database.nodes).get();
      await database.close();
      startup.add(watch.elapsedMilliseconds);
    }

    final database = TyLogDatabase(NativeDatabase.memory());
    final saves = <int>[];
    final body = 'x' * 50000;
    for (var i = 0; i < 100; i++) {
      final watch = Stopwatch()..start();
      await persistNoteSource(
        database: database,
        path: 'notes/p12-$i.typ',
        source: '#show: tylog.note.with(id: "p12-$i", title: "P12 $i")\n$body',
        updatedAtMs: i + 1,
      );
      saves.add(watch.elapsedMilliseconds);
    }
    await database.close();

    final startupP95 = _p95(startup);
    final saveP95 = _p95(saves);
    expect(startupP95, lessThanOrEqualTo(2000));
    expect(saveP95, lessThanOrEqualTo(150));
    startup.sort();
    saves.sort();
    // ignore: avoid_print
    print(
      'P12e android startup_ms p50=${startup[14]} p95=$startupP95 '
      'max=${startup.last}; save_ms p50=${saves[49]} p95=$saveP95 '
      'max=${saves.last}; samples=30/100',
    );
  });
}
