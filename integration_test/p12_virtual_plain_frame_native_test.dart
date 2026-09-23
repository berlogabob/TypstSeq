import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/widgets/virtual_plain_editor.dart';

import 'support/editor_frame_metrics.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P12 production long-note editor five-minute frame gate', (
    tester,
  ) async {
    var savedSource = _source;
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (value) => savedSource = value,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    expect(shouldUseVirtualPlainEditor(controller), isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VirtualPlainEditor(
            source: controller.text,
            onChanged: (visibleText) {
              controller.value = TextEditingValue(
                text: visibleText,
                selection: TextSelection.collapsed(offset: visibleText.length),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final timings = <FrameTiming>[];
    var captureStartUs = 0;
    void onTimings(List<FrameTiming> values) => timings.addAll(
      values.where(
        (t) =>
            t.timestampInMicroseconds(FramePhase.vsyncStart) > captureStartUs,
      ),
    );
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -100000));
    await tester.pumpAndSettle();
    final lastField = find.byType(TextField).last;
    await tester.ensureVisible(lastField);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(lastField).controller!.text,
      _body.split('\n').last,
    );
    final field = tester.widget<TextField>(lastField).controller!;
    await tester.tap(lastField);
    field.selection = TextSelection.collapsed(offset: field.text.length);
    await tester.pump();
    final display = View.of(tester.element(lastField));
    final refreshRates = <double>{display.display.refreshRate};
    captureStartUs =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
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
    final startedAt = DateTime.now();
    final deadline = startedAt.add(Duration(seconds: durationSeconds));
    while (DateTime.now().isBefore(deadline)) {
      refreshRates.add(display.display.refreshRate);
      // Drive the mounted row controller and its production callback.
      // Platform text-input injection is ignored for this many-row fixture
      // by some Android keyboards, producing a false idle-frame pass.
      final character = edits % 5 == 4 ? ' ' : 'x';
      final text = '${field.text}$character';
      field.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      tester.widget<TextField>(lastField).onChanged!(text);
      edits++;
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    await tester.pump();

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
      'P12 actual-long active_chars=$_activeParagraphChars edits=$edits '
      '${metrics.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    );
    final addedText = List<String>.generate(
      edits,
      (i) => i % 5 == 4 ? ' ' : 'x',
    ).join();
    final expectedText = '$_body$addedText';
    expect(
      controller.text == expectedText,
      isTrue,
      reason:
          'controller chars=${controller.text.length}, expected=${expectedText.length}, '
          'startsWithBody=${controller.text.startsWith(_body)}, '
          'endsWithEdits=${controller.text.endsWith(addedText)}, '
          'fieldChars=${field.text.length}, fieldTail=${field.text.substring(field.text.length > 20 ? field.text.length - 20 : 0)}, '
          'tail=${controller.text.substring(controller.text.length > 20 ? controller.text.length - 20 : 0)}',
    );
    expect(TyLogDocument.parse(savedSource).visibleText, controller.text);
    expect(savedSource, startsWith(_header));
    expect(edits, greaterThanOrEqualTo(fullGate ? 1100 : durationSeconds * 3));
    expect(
      timings.length,
      greaterThanOrEqualTo(fullGate ? 1000 : durationSeconds * 3),
    );
    expect(metrics['over_budget_pct'], lessThan(1));
  });
}

const _header = '#show: tylog.note.with(id: "p12", title: "P12")\n';
const _activeParagraphChars = int.fromEnvironment(
  'P12_ACTIVE_PARAGRAPH_CHARS',
  defaultValue: 68,
);
final _body = [
  ...List<String>.generate(
    899,
    (i) => 'A long active paragraph keeps the editor layout realistic line $i.',
  ),
  (List<String>.filled(
    (_activeParagraphChars + 4) ~/ 5,
    'word ',
  ).join()).substring(0, _activeParagraphChars),
].join('\n');
final _source = '$_header$_body';
