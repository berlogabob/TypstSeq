import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/voronoi_view.dart';
import 'package:tylog_core/tylog_core.dart';

NoteRef _note(String path, List<String> tags) => NoteRef(
  id: path,
  path: path,
  title: path,
  outgoingLinks: const [],
  tags: tags,
);

void main() {
  final index = VaultIndex(
    notesByPath: {
      for (final n in [
        _note('n1', ['a1', 'a2']),
        _note('n2', ['a1', 'a2']),
        _note('n3', ['a1', 'a2']),
        _note('n4', ['b1', 'b2']),
        _note('n5', ['b1', 'b2']),
        _note('n6', ['b1', 'b2']),
        _note('n7', ['solo']),
      ])
        n.path: n,
    },
    backlinksByTarget: const {},
  );
  final communities = computeCommunities(index, minNotes: 2, minCoOccur: 2);

  Widget host({CommunityMap? c, ValueChanged<String>? onOpen}) => MaterialApp(
    home: Scaffold(
      body: VoronoiView(
        index: index,
        communities: c,
        indexRevision: 1,
        onOpenPath: onOpen ?? (_) {},
      ),
    ),
  );

  testWidgets('renders and a tap drills down to open a note', (tester) async {
    // At the 800x600 test viewport every cell of this tiny fixture is already
    // past the reveal threshold, so a tap lands on a leaf note cell.
    final opened = <String>[];
    await tester.pumpWidget(host(c: communities, onOpen: opened.add));
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byKey(const Key('voronoi-fit')), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byType(VoronoiView)));
    await tester.pump();
    expect(opened, hasLength(1));
    expect(index.notesByPath.keys, contains(opened.single));
  });

  testWidgets('shows a placeholder while communities are missing', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(find.text('Analyzing communities…'), findsOneWidget);
  });
}
