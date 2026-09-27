import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show FlutterTimeline;
import 'package:flutter/rendering.dart'
    show debugProfileLayoutsEnabled, debugProfilePaintsEnabled;
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/widgets/virtual_plain_editor.dart';

import 'support/editor_frame_metrics.dart';

// Device acceptance/diagnostic runs, not host regression checks: opt in with
// --dart-define=P12_FRAME_GATE=true (see plan P12).
const _p12Gate = bool.fromEnvironment('P12_FRAME_GATE');

/// P12k: run the same plain workload through the windowed rich editor
/// instead of `VirtualPlainEditor`.
const _window = bool.fromEnvironment('P12_WINDOW');

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
    debugEnableEditorWindow = _window;
    addTearDown(() => debugEnableEditorWindow = false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _window
              ? TyLogRichEditor(controller: controller, onInsert: () async {})
              : VirtualPlainEditor(
                  source: controller.text,
                  onChanged: (visibleText) {
                    controller.value = TextEditingValue(
                      text: visibleText,
                      selection: TextSelection.collapsed(
                        offset: visibleText.length,
                      ),
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
    late final Finder lastField;
    late final TextEditingController field;
    if (_window) {
      // Caret at the end of the last paragraph; the window follows it.
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await tester.pumpAndSettle();
      lastField = find.byKey(const Key('rich-journal-editor'));
      await tester.ensureVisible(lastField);
      await tester.pumpAndSettle();
      field = tester.widget<TextField>(lastField).controller!;
      expect(field.text.endsWith(_body.split('\n').last), isTrue);
    } else {
      final list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -100000));
      await tester.pumpAndSettle();
      lastField = find.byType(TextField).last;
      await tester.ensureVisible(lastField);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(lastField).controller!.text,
        _body.split('\n').last,
      );
      field = tester.widget<TextField>(lastField).controller!;
      await tester.tap(lastField);
      field.selection = TextSelection.collapsed(offset: field.text.length);
    }
    await tester.pump();
    final display = View.of(tester.element(lastField));
    final refreshRates = <double>{display.display.refreshRate};
    captureStartUs =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    var listening = true;
    addTearDown(() {
      if (listening) SchedulerBinding.instance.removeTimingsCallback(onTimings);
    });
    var edits = 0;
    const durationSeconds = int.fromEnvironment(
      'P12_DURATION_SECONDS',
      defaultValue: 300,
    );
    final fullGate = durationSeconds >= 300;
    final startedAt = DateTime.now();
    final deadline = startedAt.add(Duration(seconds: durationSeconds));
    var editUs = 0, pumpUs = 0, delayUs = 0;
    Future<void> editWorkload() async {
      while (DateTime.now().isBefore(deadline)) {
        refreshRates.add(display.display.refreshRate);
        // Drive the mounted row controller and its production callback.
        // Platform text-input injection is ignored for this many-row fixture
        // by some Android keyboards, producing a false idle-frame pass.
        final editWatch = Stopwatch()..start();
        final character = edits % 5 == 4 ? ' ' : 'x';
        final text = '${field.text}$character';
        field.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        // The windowed field forwards edits itself (value setter); the
        // row editor needs its production onChanged callback.
        if (!_window) tester.widget<TextField>(lastField).onChanged!(text);
        edits++;
        editUs += editWatch.elapsedMicroseconds;
        final pumpWatch = Stopwatch()..start();
        await tester.pump(const Duration(milliseconds: 250));
        pumpUs += pumpWatch.elapsedMicroseconds;
        final delayWatch = Stopwatch()..start();
        await Future<void>.delayed(const Duration(milliseconds: 1));
        delayUs += delayWatch.elapsedMicroseconds;
      }
    }

    if (const bool.fromEnvironment('P12_TRACE')) {
      debugProfileLayoutsEnabled = true;
      debugProfileBuildsEnabled = true;
      // In-process collection: traceAction needs the VM service, which a
      // profile build on the device cannot reach.
      debugProfilePaintsEnabled = true;
      FlutterTimeline.debugCollectionEnabled = true;
      try {
        await editWorkload();
        final timings = FlutterTimeline.debugCollect();
        final top = [...timings.aggregatedBlocks]
          ..sort((a, b) => b.duration.compareTo(a.duration));
        for (final block in top.take(30)) {
          // ignore: avoid_print
          print(
            'P12 trace ${block.name} total_ms=${block.duration.toStringAsFixed(1)} '
            'count=${block.count}',
          );
        }
      } finally {
        FlutterTimeline.debugCollectionEnabled = false;
        debugProfilePaintsEnabled = false;
        debugProfileLayoutsEnabled = false;
        debugProfileBuildsEnabled = false;
      }
    } else {
      await editWorkload();
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    listening = false;
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
      'edit_ms=${(editUs / edits / 1000).toStringAsFixed(1)} '
      'pump_ms=${(pumpUs / edits / 1000).toStringAsFixed(1)} '
      'delay_ms=${(delayUs / edits / 1000).toStringAsFixed(1)} '
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
  }, skip: !_p12Gate);
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
