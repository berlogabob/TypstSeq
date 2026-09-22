import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/rich_editor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P12e rich editor five-minute frame workload', (tester) async {
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
      final text = '${controller.text}\nframe-$edits';
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      // Controller mutations from a timer do not always request a platform
      // frame in the profile driver. Schedule one explicitly so FrameTiming
      // measures the rendered workload rather than the timer alone.
      SchedulerBinding.instance.scheduleFrame();
      edits++;
    });
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      // Keep the integration binding attached to a live frame stream. A plain
      // Future.delayed lets Android stop scheduling frames while the app is
      // idle, which makes the timing sample count meaningless.
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    editTimer.cancel();
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    const budgetUs = 16667;
    final dropped = timings.fold<int>(0, (sum, timing) {
      final spanUs = timing.totalSpan.inMicroseconds;
      return sum + (spanUs <= budgetUs ? 0 : (spanUs / budgetUs).ceil() - 1);
    });
    final overBudget = timings.where(
      (timing) => timing.totalSpan.inMicroseconds > budgetUs,
    );
    final worst = timings.isEmpty
        ? Duration.zero
        : timings
              .map((timing) => timing.totalSpan)
              .reduce((a, b) => a > b ? a : b);
    // ignore: avoid_print
    print(
      'P12e editor frames=${timings.length} edits=$edits dropped=$dropped '
      'over_budget=${overBudget.length} worst_ms=${worst.inMicroseconds / 1000}',
    );
    expect(edits, greaterThanOrEqualTo(1100));
    expect(timings.length, greaterThanOrEqualTo(1000));
    expect(dropped, lessThanOrEqualTo(timings.length * 0.01));
  });
}

final _source =
    '''#show: tylog.note.with(id: "p12-frame", title: "P12 frame")
${List<String>.filled(900, 'A long active paragraph keeps the editor layout realistic for the frame budget workload.').join('\n')}
''';
