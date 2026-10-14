import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/diagnostics/jank_monitor.dart';

void main() {
  testWidgets('logs isolate stalls and starts only once', (tester) async {
    final lines = <String>[];
    final previousSink = jankSink;
    jankSink = lines.add;
    addTearDown(() => jankSink = previousSink);

    await tester.runAsync(() async {
      startJankMonitor(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      startJankMonitor(force: true);
      expect(lines.where((line) => line == 'TYLOG_JANK start'), hasLength(1));

      final blocking = Stopwatch()..start();
      while (blocking.elapsed < const Duration(milliseconds: 400)) {
        // Deliberately block the isolate between real timer ticks.
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final stalls = lines
          .where((line) => line.startsWith('TYLOG_JANK stall '))
          .toList();
      expect(stalls, hasLength(1));
      expect(
        stalls.single,
        matches(r'^TYLOG_JANK stall isolate=\d+ms t=\d+ms$'),
      );
    });
  });
}
