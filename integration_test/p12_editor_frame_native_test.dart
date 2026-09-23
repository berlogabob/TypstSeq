import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/rich_editor.dart';

import 'support/editor_frame_metrics.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P12 formatted long-note five-minute stage-budget diagnostic', (
    tester,
  ) async {
    var savedSource = _source;
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (value) => savedSource = value,
      onError: (error) => fail('editor error: $error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    expect(shouldUseVirtualPlainEditor(controller), isFalse);
    final initialText = controller.text;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: controller, onInsert: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final timings = <FrameTiming>[];
    final captureStartUs =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
    void onTimings(List<FrameTiming> values) => timings.addAll(
      values.where(
        (t) =>
            t.timestampInMicroseconds(FramePhase.vsyncStart) > captureStartUs,
      ),
    );
    final display = View.of(tester.element(find.byType(TyLogRichEditor)));
    final refreshRates = <double>{display.display.refreshRate};
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    addTearDown(
      () => SchedulerBinding.instance.removeTimingsCallback(onTimings),
    );
    var edits = 0;
    const durationSeconds = int.fromEnvironment(
      'P12_DURATION_SECONDS',
      defaultValue: 300,
    );
    final fullGate = durationSeconds >= 300;
    Future<void> editWorkload() async {
      final deadline = DateTime.now().add(
        const Duration(seconds: durationSeconds),
      );
      while (DateTime.now().isBefore(deadline)) {
        refreshRates.add(display.display.refreshRate);
        final text = '${controller.text}\nframe-$edits';
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        edits++;
        // One rendered response per edit; do not dilute the sample with idle pumps.
        await tester.pump(const Duration(milliseconds: 250));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    if (const bool.fromEnvironment('P12_TRACE')) {
      debugProfileLayoutsEnabled = true;
      debugProfileBuildsEnabled = true;
      try {
        await binding.traceAction(
          editWorkload,
          reportKey: 'p12_formatted_trace',
        );
      } finally {
        debugProfileLayoutsEnabled = false;
        debugProfileBuildsEnabled = false;
      }
    } else {
      await editWorkload();
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    refreshRates.add(display.display.refreshRate);
    expect(
      refreshRates,
      hasLength(1),
      reason: 'Refresh rate changed during capture',
    );
    final metrics = editorFrameMetrics(
      timings,
      refreshRate: refreshRates.single,
    );
    // ignore: avoid_print
    print(
      'P12 formatted-rich edits=$edits '
      '${metrics.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    );
    final addedText = List.generate(edits, (i) => '\nframe-$i').join();
    expect(controller.text == '$initialText$addedText', isTrue);
    expect(TyLogDocument.parse(savedSource).visibleText, controller.text);
    expect(savedSource, contains('#strong[Formatted]'));
    expect(savedSource, startsWith(_header));
    expect(edits, greaterThanOrEqualTo(fullGate ? 1100 : durationSeconds * 3));
    expect(
      timings.length,
      greaterThanOrEqualTo(fullGate ? 1000 : durationSeconds * 3),
    );
    expect(metrics['over_budget_pct'], lessThan(1));
  });
}

const _header = '#show: tylog.note.with(id: "p12-frame", title: "P12 frame")\n';
final _source =
    '''$_header#strong[Formatted] long-note fixture.
${List<String>.filled(899, 'A long active paragraph keeps the editor layout realistic for the frame budget workload.').join('\n')}
''';
