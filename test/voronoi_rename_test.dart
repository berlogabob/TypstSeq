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

Future<void> _waitForLayout(WidgetTester tester) async {
  // compute uses real isolates; let their completion return to the test zone.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
}

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

  // The {a1,a2} community is a top-level cluster whose _Cell id is
  // `cluster:a1` (not in notesByPath), so selecting it shows the rename
  // button; the dialog persists the raw label `a1`, not its display name.
  const clusterId = 'cluster:a1';
  const clusterLabel = 'a1';

  Widget host({
    Map<String, String> clusterNames = const {},
    String? initialSelectedPath,
    Future<void> Function(String, String)? onRenameCluster,
  }) => MaterialApp(
    home: Scaffold(
      body: VoronoiView(
        index: index,
        communities: communities,
        indexRevision: 1,
        onOpenPath: (_) {},
        clusterNames: clusterNames,
        initialSelectedPath: initialSelectedPath,
        onRenameCluster: onRenameCluster,
      ),
    ),
  );

  testWidgets(
    'Save in the rename dialog calls onRenameCluster with label and text',
    (tester) async {
      final recorded = <(String, String)>[];
      await tester.pumpWidget(
        host(
          initialSelectedPath: clusterId,
          onRenameCluster: (label, name) async => recorded.add((label, name)),
        ),
      );
      await _waitForLayout(tester);

      expect(find.byKey(const Key('voronoi-rename')), findsOneWidget);
      await tester.tap(find.byKey(const Key('voronoi-rename')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('voronoi-rename-field')),
        'Tech & AI',
      );
      await tester.tap(find.byKey(const Key('voronoi-rename-save')));
      await tester.pumpAndSettle();

      expect(recorded, hasLength(1));
      expect(recorded.single.$2, 'Tech & AI');
      expect(recorded.single.$1, clusterLabel);
    },
  );
}
