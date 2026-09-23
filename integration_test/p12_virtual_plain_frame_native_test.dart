import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/widgets/virtual_plain_editor.dart';

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
    void onTimings(List<FrameTiming> values) => timings.addAll(values);
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
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    var edits = 0;
    const durationSeconds = int.fromEnvironment(
      'P12_DURATION_SECONDS',
      defaultValue: 300,
    );
    final fullGate = durationSeconds >= 300;
    const budgetUs = 16667; // P12 targets a sustained 60 FPS on Android.
    final startedAt = DateTime.now();
    final deadline = startedAt.add(Duration(seconds: durationSeconds));
    while (DateTime.now().isBefore(deadline)) {
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

    final refreshRate =
        WidgetsBinding.instance.platformDispatcher.displays.first.refreshRate;
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
        : timings.map((t) => t.rasterDuration).reduce((a, b) => a > b ? a : b);
    final spans = timings.map((t) => t.totalSpan.inMicroseconds).toList()
      ..sort();
    final spanP95 = spans.isEmpty
        ? 0
        : spans[(spans.length * 0.95).floor().clamp(0, spans.length - 1)];
    // ignore: avoid_print
    print(
      'P12 actual-long refresh_hz=$refreshRate budget_ms=${budgetUs / 1000} '
      'frames=${timings.length} edits=$edits '
      'dropped=$dropped worst_ms=${worst.inMicroseconds / 1000} '
      'span_p95_ms=${spanP95 / 1000} '
      'build_ms=${worstBuild.inMicroseconds / 1000} '
      'raster_ms=${worstRaster.inMicroseconds / 1000}',
    );
    expect(edits, greaterThanOrEqualTo(fullGate ? 1100 : durationSeconds * 3));
    expect(
      timings.length,
      greaterThanOrEqualTo(fullGate ? 1000 : durationSeconds * 3),
    );
    expect(dropped, lessThanOrEqualTo(timings.length * 0.01));
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
  });
}

const _header = '#show: tylog.note.with(id: "p12", title: "P12")\n';
final _body = List<String>.generate(
  900,
  (i) => 'A long active paragraph keeps the editor layout realistic line $i.',
).join('\n');
final _source = '$_header$_body';
