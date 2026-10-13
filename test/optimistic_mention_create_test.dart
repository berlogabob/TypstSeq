import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

void main() {
  for (final trigger in ['@', '[[']) {
    testWidgets('$trigger create inserts before storage completes', (
      tester,
    ) async {
      final pending = Completer<void>();
      final controller = TyLogEditingController(
        source: '',
        onSourceChanged: (_) {},
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);
      var started = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TyLogRichEditor(
              controller: controller,
              onInsert: () async {},
              onMentionQuery: (_, _) async => const [
                MentionSuggestion(id: 'New', title: 'New', create: true),
              ],
              onCreateNote: (_) => (
                id: 'allocated-id',
                create: () {
                  // Creation cannot start until the reference is safely inserted.
                  expect(
                    controller.document.toSource(),
                    contains('allocated-id'),
                  );
                  started = true;
                  return pending.future;
                },
              ),
            ),
          ),
        ),
      );
      final editor = find.byKey(const Key('rich-journal-editor'));
      await tester.tap(editor);
      await tester.enterText(
        editor,
        'Keep this $trigger'
        'New',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.byKey(const Key('autocomplete-mention-New')));
      await tester.pump();
      expect(started, isTrue);
      expect(pending.isCompleted, isFalse);
      expect(controller.document.toSource(), contains('Keep this '));
      expect(controller.document.toSource(), contains('allocated-id'));
      pending.complete();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('failed creation keeps the chip and later typed text', (
    tester,
  ) async {
    final pending = Completer<void>();
    final controller = TyLogEditingController(
      source: '',
      onSourceChanged: (_) {},
      onError: (e) => fail('$e'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(
            controller: controller,
            onInsert: () async {},
            onMentionQuery: (_, _) async => const [
              MentionSuggestion(id: 'New', title: 'New', create: true),
            ],
            onCreateNote: (_) =>
                (id: 'unresolved-id', create: () => pending.future),
          ),
        ),
      ),
    );
    final editor = find.byKey(const Key('rich-journal-editor'));
    await tester.tap(editor);
    await tester.enterText(editor, 'Before @New');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.tap(find.byKey(const Key('autocomplete-mention-New')));
    await tester.pump();
    controller.value = controller.value.copyWith(
      text: '${controller.text} after',
      selection: TextSelection.collapsed(offset: controller.text.length + 6),
    );
    final beforeFailure = controller.document.toSource();
    pending.completeError(StateError('storage unavailable'));
    await tester.pump();
    expect(controller.document.toSource(), beforeFailure);
    expect(beforeFailure, contains('unresolved-id'));
    expect(beforeFailure, contains('Before '));
    expect(beforeFailure, contains(' after'));
    expect(find.textContaining('Could not create New'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
