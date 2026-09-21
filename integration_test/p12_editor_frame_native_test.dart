import 'dart:async';

import 'package:flutter/material.dart';
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

    const frame = Duration(milliseconds: 16);
    final lateFrames = <int>[];
    var ticks = 0;
    var lastTick = Stopwatch()..start();
    final frameTimer = Timer.periodic(frame, (_) {
      final elapsed = lastTick.elapsed;
      lastTick = Stopwatch()..start();
      ticks++;
      final late = elapsed - frame;
      if (late > Duration.zero) {
        lateFrames.add(late.inMicroseconds ~/ frame.inMicroseconds);
      }
    });
    var edits = 0;
    final editTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final text = '${controller.text}\nframe-$edits';
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      edits++;
    });
    await Future<void>.delayed(const Duration(minutes: 5));
    editTimer.cancel();
    frameTimer.cancel();
    final dropped = lateFrames.fold<int>(0, (sum, value) => sum + value);
    final worst = lateFrames.isEmpty
        ? 0
        : lateFrames.reduce((a, b) => a > b ? a : b);
    // ignore: avoid_print
    print(
      'P12e editor frames ticks=$ticks edits=$edits dropped=$dropped '
      'late_samples=${lateFrames.length} worst_gap_ms=${worst * 16}',
    );
    expect(edits, greaterThanOrEqualTo(1100));
    expect(ticks, greaterThan(1000));
  });
}

final _source =
    '''#show: tylog.note.with(id: "p12-frame", title: "P12 frame")
${List<String>.filled(900, 'A long active paragraph keeps the editor layout realistic for the frame budget workload.').join('\n')}
''';
