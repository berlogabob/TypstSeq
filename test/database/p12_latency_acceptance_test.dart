import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/database/tylog_database.dart';

int p95(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length * 95 + 99) ~/ 100) - 1];
}

void main() {
  test('P12e host acceptance: 30 startup and 100 durable saves', () async {
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

    final startupP95 = p95(startup);
    final saveP95 = p95(saves);
    final startupP50 = startup..sort();
    final saveP50 = saves..sort();
    // These are the plan gates in plan.md; the test is intentionally host-only
    // until a release/profile Android run supplies device evidence.
    expect(startupP95, lessThanOrEqualTo(2000));
    expect(saveP95, lessThanOrEqualTo(150));
    // Keep the measurements visible in CI output without logging vault data.
    // ignore: avoid_print
    print(
      'P12e host startup_ms p50=${startupP50[14]} p95=$startupP95 '
      'max=${startupP50.last}; save_ms p50=${saveP50[49]} '
      'p95=$saveP95 max=${saveP50.last}; samples=30/100',
    );
  });
}
