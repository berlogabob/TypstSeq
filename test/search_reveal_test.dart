import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

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
    await tester.pump(const Duration(seconds: 3));
    expect(controller.selection.isCollapsed, isTrue);
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
}
