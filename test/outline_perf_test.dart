import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/widgets/fold_store.dart';

/// Typing rebuilds the editor's span on every keystroke, so outline work for
/// folding must stay cheap on long imported pages.
void main() {
  tearDown(() => FoldStore.instance = null);

  testWidgets('span build on a 2,000-block page with 500 folds stays fast', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('outline-perf-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    FoldStore.instance = (await tester.runAsync(
      () => FoldStore.open(File('${dir.path}/fold_state.json')),
    ))!;
    final source = [
      for (var i = 0; i < 1000; i++) ...[
        '- item $i',
        '  - #tylog.task(id: "t$i", text: "task $i", status: "todo", priority: "normal")',
      ],
    ].join('\n');
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: (_) {},
      onError: (_) {},
      onProtectedTap: (_) {},
      foldScope: 'notes/long.typ',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: controller, onInsert: () async {}),
        ),
      ),
    );
    final lines = outlineOf(controller.document);
    final keys = foldKeysOf('notes/long.typ', lines);
    for (final key in keys.values.take(500)) {
      await tester.runAsync(() => FoldStore.instance!.toggle(key));
    }
    expect(controller.foldedParentLineStarts, hasLength(500));
    final context = tester.element(find.byType(EditableText));
    final watch = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      controller.buildTextSpan(context: context, withComposing: false);
    }
    // ~one keystroke each; debug-mode budget, generous on purpose.
    expect(watch.elapsedMilliseconds / 20, lessThan(40));
  });
}
