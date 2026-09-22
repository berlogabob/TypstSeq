import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/widgets/virtual_plain_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P12 actual long-note editor frame workload', (tester) async {
    var source = _source;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualPlainEditor(
            source: source,
            onChanged: (value) => source = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> values) => timings.addAll(values);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    final field = tester.widget<TextField>(find.byType(TextField).first).controller!;
    var edits = 0;
    final editTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
      field.value = field.value.copyWith(
        text: '${field.text} frame-$edits',
        selection: TextSelection.collapsed(
          offset: field.text.length + ' frame-$edits'.length,
        ),
      );
      edits++;
      SchedulerBinding.instance.scheduleFrame();
      },
    );
    if (const bool.fromEnvironment('P12_NO_EDITS')) editTimer.cancel();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    editTimer.cancel();
    SchedulerBinding.instance.removeTimingsCallback(onTimings);

    const budgetUs = 16667;
    final dropped = timings.fold<int>(0, (sum, timing) {
      final spanUs = timing.totalSpan.inMicroseconds;
      return sum + (spanUs <= budgetUs ? 0 : (spanUs / budgetUs).ceil() - 1);
    });
    final worst = timings.isEmpty
        ? Duration.zero
        : timings.map((t) => t.totalSpan).reduce((a, b) => a > b ? a : b);
    final worstBuild = timings.isEmpty
        ? Duration.zero
        : timings.map((t) => t.buildDuration).reduce((a, b) => a > b ? a : b);
    final worstRaster = timings.isEmpty
        ? Duration.zero
        : timings
              .map((t) => t.rasterDuration)
              .reduce((a, b) => a > b ? a : b);
    // ignore: avoid_print
    print(
      'P12 actual-long frames=${timings.length} edits=$edits '
      'dropped=$dropped worst_ms=${worst.inMicroseconds / 1000} '
      'build_ms=${worstBuild.inMicroseconds / 1000} '
      'raster_ms=${worstRaster.inMicroseconds / 1000}',
    );
    expect(edits, greaterThanOrEqualTo(100));
    expect(timings, isNotEmpty);
    expect(dropped, lessThanOrEqualTo(timings.length * 0.01));
  });
}

final _source = List<String>.generate(
  900,
  (i) => 'A long active paragraph keeps the editor layout realistic line $i.',
).join('\n');
