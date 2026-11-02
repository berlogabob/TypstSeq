import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/work_surface.dart';

void main() {
  testWidgets(
    'screenshots library: fresh state is newest first with no group headers',
    (tester) async {
      const older = NoteRef(
        id: 'shot-old',
        path: 'screenshots/2026/10/old.typ',
        title: 'Old shot',
        kind: 'screenshot',
        outgoingLinks: [],
        properties: {'source_app': 'Safari'},
        modifiedMillis: 1000,
      );
      const newer = NoteRef(
        id: 'shot-new',
        path: 'screenshots/2026/10/new.typ',
        title: 'New shot',
        kind: 'screenshot',
        outgoingLinks: [],
        properties: {'source_app': 'Photos'},
        modifiedMillis: 2000,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryView(
              initialTab: 2,
              index: VaultIndex(
                notesByPath: {older.path: older, newer.path: newer},
                backlinksByTarget: const {},
              ),
              calendar: const [],
              dayMarks: (daily: <String>{}, refs: <String>{}),
              progressByPath: const {},
              onOpenPath: (_) {},
              onOpenDay: (_) {},
              onSetTaskStatus: (_, _) async {},
              onSetReadStatus: (_, _) async {},
              onSetRelevance: (_, _) async {},
              onCreateNote: (_) {},
              onCreateEntity: () {},
              onImportMarkdownArticles: () async {},
              onReadPath: (_) {},
              onDeleteArticle: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No grouping by default: no "<source> · <count>" section headers.
      expect(find.text('Photos · 1'), findsNothing);
      expect(find.text('Safari · 1'), findsNothing);

      // Newest first in reading order (grid cards can share a row).
      final newPos = tester.getTopLeft(find.text('New shot'));
      final oldPos = tester.getTopLeft(find.text('Old shot'));
      expect(
        newPos.dy < oldPos.dy ||
            (newPos.dy == oldPos.dy && newPos.dx < oldPos.dx),
        isTrue,
        reason: 'newest should come first in reading order',
      );
    },
  );
}
