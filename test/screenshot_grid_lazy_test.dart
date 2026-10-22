import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/work_surface.dart';

void main() {
  // Each group used to be its own SliverGrid, which builds its first card even
  // off-screen: hundreds of groups loaded hundreds of thumbnails on a phone.
  testWidgets('screenshot tab with many groups reads only visible thumbnails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    var reads = 0;
    final notes = [
      for (var i = 0; i < 600; i++)
        NoteRef(
          id: 'shot-${i.toRadixString(16).padLeft(16, '0')}',
          path: 'screenshots/2026/10/shot-$i.typ',
          title: 'Shot $i',
          kind: 'screenshot',
          date: '2026-10-21',
          outgoingLinks: const [],
          properties: {
            'source_app': 'App ${i ~/ 2}',
            'captured_at': '2026-10-21T09:07:00',
          },
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryView(
            initialTab: 2,
            imageResolver: (_) async {
              reads++;
              return Uint8List(0);
            },
            index: VaultIndex(
              notesByPath: {for (final n in notes) n.path: n},
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
    expect(find.text('App 0 · 2'), findsOneWidget);
    expect(reads, inInclusiveRange(1, 60));
  });
}
