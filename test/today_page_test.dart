import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog_core/models.dart';

NoteRef _article(String id) => NoteRef(
  id: id,
  path: 'articles/$id.typ',
  title: 'Article $id',
  kind: 'article',
  outgoingLinks: const [],
  tags: const [],
);

void main() {
  testWidgets('continue reading renders each entry as a card with progress', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPage(
            tasks: const [],
            recent: [(_article('a'), 0.4), (_article('b'), 0.0)],
            editor: const SizedBox(),
            onOpenPath: (_) {},
            onSetStatus: (task, status) async {},
            onReadPath: opened.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNWidgets(2));
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Card),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNWidgets(2),
    );

    await tester.tap(find.text('Article a'));
    expect(opened, ['articles/a.typ']);
  });
}
