import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:tylog/calendar_feeds.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/workspace_controller.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/editor_autocomplete.dart';

void main() {
  testWidgets('rendered popup stays clear of a multiline query caret', (
    tester,
  ) async {
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
              MentionSuggestion(id: 'near', title: 'Near match'),
              MentionSuggestion(id: 'new', title: 'Query', create: true),
            ],
          ),
        ),
      ),
    );
    final field = find.byKey(const Key('rich-journal-editor'));
    await tester.tap(field);
    await tester.enterText(field, 'First line\nSecond line\n@Query');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final local = editable.getLocalRectForCaret(
      TextPosition(offset: editable.selection!.extentOffset),
    );
    final caret = local.shift(editable.localToGlobal(Offset.zero));
    final popup = tester.getRect(find.byKey(const Key('autocomplete-popup')));
    expect(popup.overlaps(caret), isFalse);
    expect(popup.top, greaterThan(caret.bottom));
    expect(
      tester.getTopLeft(find.byKey(const Key('autocomplete-mention-new'))).dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const Key('autocomplete-mention-near')))
            .dy,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.document.toSource(), contains('#tylog.ref-note("near")'));
  });
  testWidgets('selecting a future class twice creates one note and links it', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('tylog_future_mention_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    final workspace = WorkspaceController(taskScheduler: TaskScheduler());
    addTearDown(workspace.dispose);
    workspace.vault = vault;
    final date = DateTime.now()
        .add(const Duration(days: 2))
        .toIso8601String()
        .substring(0, 10);
    final event = FeedEvent('future-class', 'Ética', date, {
      'course': 'Ética',
      'start': '19:00',
      'end': '21:00',
      'rooms': '020',
    });
    workspace.feedEvents = [event];
    final controller = TyLogEditingController(
      source: '',
      onSourceChanged: (_) {},
      onError: (e) => fail('$e'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    Future<String>? flight;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(
            controller: controller,
            onInsert: () async {},
            onMentionQuery: (query, _) async => [
              for (final e in searchFeedEvents(
                workspace.feedEvents,
                query,
                today: DateTime.now(),
              ))
                MentionSuggestion(id: e.id, title: e.title, noteKind: 'event'),
            ],
            onSelectMention: (item) async {
              flight = workspace.materializeEvent(event.path);
              await flight;
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 2; i++) {
      final field = find.byKey(const Key('rich-journal-editor'));
      await tester.tap(field);
      await tester.enterText(field, '@Éti');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(Key('autocomplete-mention-${event.id}')));
        await flight;
      });
      await tester.pumpAndSettle();
      expect(
        controller.document.toSource(),
        contains('#tylog.ref-note("future-class")'),
      );
      if (i == 0) {
        await tester.runAsync(
          () async => vault.storage.writeText(
            event.path,
            '${await vault.storage.readText(event.path)}\nWritten once',
          ),
        );
      }
    }
    await tester.runAsync(() async {
      expect(
        await vault.storage.readText(event.path),
        contains('Written once'),
      );
      final files = await vault.storage.list(recursive: true);
      expect(
        files.where((e) => e.path.startsWith('events/') && !e.isDirectory),
        hasLength(1),
      );
    });
  });
  test('create page follows real matches', () {
    final rows = orderMentionSuggestions(const [
      MentionSuggestion(id: 'near', title: 'Near'),
      MentionSuggestion(id: 'new', title: 'New', create: true),
    ]);
    expect(rows.first.create, isFalse);
    expect(rows.last.create, isTrue);
  });
  test('popup stays below caret or above when space is limited', () {
    const size = Size(400, 600);
    const popup = Size(320, 288);
    for (final caret in [
      const Rect.fromLTWH(30, 100, 2, 24),
      const Rect.fromLTWH(390, 550, 2, 24),
      const Rect.fromLTWH(30, 280, 2, 24),
    ]) {
      final rect = autocompletePopupRect(caret, size, popup);
      expect(rect.overlaps(caret), isFalse);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
    }
    expect(
      autocompletePopupRect(
        const Rect.fromLTWH(30, 100, 2, 24),
        size,
        popup,
      ).top,
      128,
    );
    expect(
      autocompletePopupRect(
        const Rect.fromLTWH(30, 550, 2, 24),
        size,
        popup,
      ).bottom,
      546,
    );
  });
}
