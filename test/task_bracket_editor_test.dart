import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tylog/rich_editor.dart';

/// W35.1: on the P30 the loan task "... QUEST 3 [2] домой до пятницы" showed a
/// blank gap between its first and second visual line. Not the bracket: the
/// task before it has a strip that no longer fits beside its text, so the
/// editor reserves that strip's height by inflating the first character of
/// the next block, and half of that leading lands below line 1 of a wrapped
/// paragraph. Source below is the exact device note.
void main() {
  for (final width in [300.0, 320.0, 340.0, 360.0]) {
    testWidgets('wrapped task after a strip task has even line pitch @$width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(1080, 2340);
      addTearDown(tester.view.reset);
      final source = File(
        'test/fixtures/daily_2026_11_12_loan_brackets.typ',
      ).readAsStringSync();
      final controller = TyLogEditingController(
        source: source,
        onSourceChanged: (_) {},
        onError: (e) => fail('$e'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: TyLogRichEditor(
                  controller: controller,
                  onInsert: () async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      RenderEditable? found;
      void visit(RenderObject o) {
        if (o is RenderEditable) found ??= o;
        o.visitChildren(visit);
      }

      visit(tester.binding.renderViews.first);
      final field = found!;
      final text = field.plainText;
      final start = text.indexOf('◐ Студент');
      final end = text.indexOf('пятницы') + 'пятницы'.length;
      final tops = <double>[];
      for (var i = start; i < end; i++) {
        final top = field.getLocalRectForCaret(TextPosition(offset: i)).top;
        if (tops.isEmpty || (top - tops.last).abs() > 1) tops.add(top);
      }
      expect(tops.length, greaterThan(1), reason: 'the task must wrap');
      final pitches = [
        for (var i = 1; i < tops.length; i++) tops[i] - tops[i - 1],
      ];
      // Normal pitch is the last one; the first may carry at most a sliver
      // (was +18 dp: the whole strip height).
      final normal = pitches.last;
      for (final p in pitches) {
        expect(p, lessThanOrEqualTo(normal + 6), reason: 'pitches $pitches');
        expect(p, greaterThanOrEqualTo(normal - 1.5), reason: '$pitches');
      }
    });
  }
}
