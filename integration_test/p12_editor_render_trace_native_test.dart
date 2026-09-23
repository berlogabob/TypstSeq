import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/widgets/virtual_plain_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P12 editor rendering trace', (tester) async {
    final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
    final field = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    await tester.tap(find.byType(TextField).first);
    field.selection = TextSelection.collapsed(offset: field.text.length);
    await tester.pump();

    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> values) => timings.addAll(values);
    var edits = 0;
    await binding.traceAction(() async {
      SchedulerBinding.instance.addTimingsCallback(onTimings);
      final editTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final character = edits % 5 == 4 ? ' ' : 'x';
        final text = '${field.text}$character';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        SchedulerBinding.instance.scheduleFrame();
        edits++;
      });
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      editTimer.cancel();
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
    }, reportKey: 'p12_editor_trace');

    final build = timings.map((t) => t.buildDuration.inMicroseconds).toList()
      ..sort();
    final raster = timings.map((t) => t.rasterDuration.inMicroseconds).toList()
      ..sort();
    int p95(List<int> values) => values.isEmpty
        ? 0
        : values[(values.length * 0.95).floor().clamp(0, values.length - 1)];
    // ignore: avoid_print
    print(
      'P12 trace frames=${timings.length} edits=$edits '
      'build_p95_us=${p95(build)} build_max_us=${build.isEmpty ? 0 : build.last} '
      'raster_p95_us=${p95(raster)} raster_max_us=${raster.isEmpty ? 0 : raster.last}',
    );
    expect(edits, greaterThanOrEqualTo(100));
    expect(timings.length, greaterThanOrEqualTo(100));
  });
}

final _source = [
  List<String>.filled(240, 'word').join(' '),
  ...List<String>.generate(
    899,
    (i) =>
        'A long active paragraph keeps the rendering workload realistic line $i.',
  ),
].join('\n');
