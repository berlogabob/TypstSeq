import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/widgets/constants.dart';
import 'package:tylog/widgets/reading_mode.dart';

bool _hasRevealHighlight(InlineSpan span, String text) {
  if (span is TextSpan) {
    if (span.text == text && span.style?.backgroundColor == kSearchRevealFill) {
      return true;
    }
    return (span.children ?? const <InlineSpan>[]).any(
      (child) => _hasRevealHighlight(child, text),
    );
  }
  return false;
}

void main() {
  testWidgets('search-result reveal scrolls and fades its selection', (
    tester,
  ) async {
    final controller = TyLogEditingController(
      source: '${List.filled(180, 'padding').join('\n')}\nNeedle here',
      onSourceChanged: (_) {},
      onError: (_) {},
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(
            controller: controller,
            revealQuery: 'needle',
            onInsert: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.selectedPlainText, 'Needle');
    expect(controller.selection.isCollapsed, isFalse);
    // An unfocused TextField paints no selection, so the match must also be
    // painted as a span background (the phone showed nothing otherwise).
    TextSpan painted() => controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      withComposing: false,
    );
    expect(_hasRevealHighlight(painted(), 'Needle'), isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(controller.selection.isCollapsed, isTrue);
    expect(_hasRevealHighlight(painted(), 'Needle'), isFalse);
  });

  testWidgets('ordinary editor opens do not reveal a match', (tester) async {
    final controller = TyLogEditingController(
      source: '${List.filled(180, 'padding').join('\n')}\nNeedle here',
      onSourceChanged: (_) {},
      onError: (_) {},
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
    expect(controller.selection.isCollapsed, isTrue);
  });

  testWidgets(
    'search-result reveal highlights the first visible body occurrence',
    (tester) async {
      final source = File(
        'test/fixtures/shot_cervejaria.typ',
      ).readAsStringSync();
      final controller = TyLogEditingController(
        source: source,
        onSourceChanged: (_) {},
        onError: (_) {},
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);

      Widget app(String? query) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: TyLogRichEditor(
                  controller: controller,
                  revealQuery: query,
                  onInsert: () async {},
                ),
              ),
              Expanded(
                child: ReadingMode(
                  source: source,
                  path: null,
                  fontScale: 1,
                  nightMode: false,
                  revealQuery: query,
                  onExit: () {},
                  onPreferencesChanged: (_, _) async {},
                  onProgress: (_, _) async {},
                ),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(app(null));
      await tester.pump();
      await tester.pumpWidget(app('cervejaria'));
      await tester.pump();

      final readingTexts = tester.widgetList<RichText>(
        find.descendant(
          of: find.byKey(const Key('reading-document')),
          matching: find.byType(RichText),
        ),
      );
      expect(
        readingTexts.any((t) => _hasRevealHighlight(t.text, 'Cervejaria')),
        isTrue,
      );
      expect(controller.selectedPlainText, 'Cervejaria');
    },
  );
}
