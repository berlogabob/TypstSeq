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
    await _waitForLayout(tester);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byKey(const Key('voronoi-fit')), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byType(VoronoiView)));
    await tester.pump();
    expect(opened, hasLength(1));
    expect(index.notesByPath.keys, contains(opened.single));
  });

  testWidgets('exposes visible cells as semantics nodes', (tester) async {
    // The CustomPainterSemantics nodes _VoronoiPainter emits are synthetic
    // children of the CustomPaint's own SemanticsNode — they aren't backed
    // by their own Element/RenderObject, so `find.bySemanticsLabel` (which
    // matches on an Element's own attached SemanticsNode) can't see them.
    // Walk the raw semantics tree instead, which is the same thing a screen
    // reader would traverse.
    final handle = tester.ensureSemantics();
    final opened = <String>[];
    await tester.pumpWidget(host(c: communities, onOpen: opened.add));
    await _waitForLayout(tester);

    // ignore: deprecated_member_use — rootPipelineOwner has no semanticsOwner
    final owner = tester.binding.pipelineOwner.semanticsOwner!;
    final byLabel = <String, SemanticsNode>{};
    void visit(SemanticsNode node) {
      final label = node.getSemanticsData().label;
      if (label.isNotEmpty) byLabel[label] = node;
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(owner.rootSemanticsNode!);

    // At the 800x600 test viewport every cell of this fixture is already
    // past the reveal threshold (see the tap test above), so the visible
    // cells are leaf note cells labeled with their paths.
    for (final path in index.notesByPath.keys) {
      expect(byLabel, contains(path));
    }

    // Activating a leaf's semantics node should do exactly what tapping it
    // does: open the note.
    owner.performAction(byLabel['n1']!.id, SemanticsAction.tap);
    await tester.pump();
    expect(opened, ['n1']);

    handle.dispose();
  });

  testWidgets(
    'overflow activation opens omitted notes and cached levels survive zoom',
    (tester) async {
      final handle = tester.ensureSemantics();
      final large = VaultIndex(
        notesByPath: {
          for (var i = 0; i < 151; i++) 'note$i': _note('note$i', []),
        },
        backlinksByTarget: const {},
      );
      final groups = computeCommunities(large);
      final opened = <List<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoronoiView(
              index: large,
              communities: groups,
              indexRevision: 1,
              onOpenPath: (_) {},
              onOpenNotes: opened.add,
            ),
          ),
        ),
      );
      await _waitForLayout(tester);
      // The initial community is revealed at this viewport, so its overflow
      // becomes an accessible leaf after the child isolate completes.
      // ignore: deprecated_member_use
      final owner = tester.binding.pipelineOwner.semanticsOwner!;
      SemanticsNode? overflow;
      void visit(SemanticsNode node) {
        if (node.getSemanticsData().label == '+2 more') overflow = node;
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(owner.rootSemanticsNode!);
      expect(overflow, isNotNull);
      owner.performAction(overflow!.id, SemanticsAction.tap);
      expect(opened.single.length, 2);
      expect(opened.single.toSet().length, 2);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final controller = viewer.transformationController!;
      controller.value = Matrix4.identity()..scaleByDouble(0.5, 0.5, 0.5, 1);
      await tester.pump();
      controller.value = Matrix4.identity();
      await tester.pump();
      overflow = null;
      visit(owner.rootSemanticsNode!);
      expect(overflow, isNotNull);
      handle.dispose();
    },
  );

  testWidgets('unrevealed group loads only after crossing the zoom threshold', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final small = VaultIndex(
      notesByPath: {'leaf': _note('leaf', [])},
      backlinksByTarget: const {},
    );
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: VoronoiView(
              index: small,
              communities: computeCommunities(small),
              indexRevision: 1,
              onOpenPath: opened.add,
            ),
          ),
        ),
      ),
    );
    await _waitForLayout(tester);
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
    expect(labels, contains('Uncategorized, 1 notes'));
    expect(labels, isNot(contains('leaf')));
    await tester.tapAt(tester.getCenter(find.byType(VoronoiView)));
    expect(opened, isEmpty);
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.identity()
      ..scaleByDouble(2, 2, 2, 1);
    await _waitForLayout(tester);
    labels.clear();
    visit(owner.rootSemanticsNode!);
    expect(labels, contains('leaf'));
    handle.dispose();
  });

  testWidgets('shows a placeholder while communities are missing', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(find.text('Analyzing communities…'), findsOneWidget);
  });
}
