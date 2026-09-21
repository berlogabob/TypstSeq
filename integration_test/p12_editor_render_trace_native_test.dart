import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/rich_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P12 editor rendering trace', (tester) async {
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (_) {},
      onError: (error) => fail('editor error: $error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: controller, onInsert: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> values) => timings.addAll(values);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    var edits = 0;
    final editTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final text = '${controller.text}\ntrace-$edits';
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      edits++;
    });
    await Future<void>.delayed(const Duration(seconds: 30));
    editTimer.cancel();
    SchedulerBinding.instance.removeTimingsCallback(onTimings);

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
    expect(timings, isNotEmpty);
  });
}

final _source =
    '''#show: tylog.note.with(id: "p12-trace", title: "P12 trace")
${List<String>.filled(900, 'A long active paragraph keeps the rendering workload realistic for the frame budget.').join('\n')}
''';
