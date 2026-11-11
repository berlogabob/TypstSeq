import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

  Widget host({Map<String, String> clusterNames = const {}}) => MaterialApp(
    home: Scaffold(
      body: VoronoiView(
        index: index,
        communities: communities,
        indexRevision: 1,
        onOpenPath: (_) {},
        clusterNames: clusterNames,
      ),
    ),
  );

  testWidgets('clusterNames replaces the cluster label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(clusterNames: {'a1': 'Tech & AI'}));
    await _waitForLayout(tester);

    // Same finder style as the cluster-label walk in voronoi_view_test: the
    // CustomPainterSemantics nodes aren't Element-backed, so walk the raw tree.
    // ignore: deprecated_member_use
    final owner = tester.binding.pipelineOwner.semanticsOwner!;
    final labels = <String>[];
    void visit(SemanticsNode node) {
      labels.add(node.getSemanticsData().label);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(owner.rootSemanticsNode!);
    expect(labels, anyElement(contains('Tech & AI')));
    expect(labels, isNot(contains('A1')));
    handle.dispose();
  });
}
