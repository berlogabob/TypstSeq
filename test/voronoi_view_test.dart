import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/graph.dart' show colorForSlot;
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

  Widget host({
    CommunityMap? c,
    ValueChanged<String>? onOpen,
    ValueChanged<String?>? onSelectionChanged,
    int revision = 1,
    Future<VoronoiResult> Function(VoronoiRequest)? computeLayout,
  }) => MaterialApp(
    home: Scaffold(
      body: VoronoiView(
        index: index,
        communities: c,
        indexRevision: revision,
        onOpenPath: onOpen ?? (_) {},
        onSelectionChanged: onSelectionChanged,
        computeLayout: computeLayout,
      ),
    ),
  );

  // The painter class is private; its fields are read dynamically.
  dynamic painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .firstWhere((p) => p.runtimeType.toString() == '_VoronoiPainter');

  testWidgets('selecting a cell repaints the highlight', (tester) async {
    await tester.pumpWidget(host(c: communities));
    await _waitForLayout(tester);
    final before = painter(tester);
    await tester.tapAt(tester.getCenter(find.byType(VoronoiView)));
    await tester.pump();
    final after = painter(tester);
    expect(after.selectedPath, isNotNull);
    expect(after.shouldRepaint(before), isTrue);
  });

  testWidgets('hues are spread over the communities only', (tester) async {
    await tester.pumpWidget(host(c: communities));
    await _waitForLayout(tester);
    // Two communities plus Uncategorized: the force graph divides by two.
    expect(painter(tester).rootCount, communities.clusterOrder.length);
  });

  test('a cell outside every community is grey', () {
    const scheme = ColorScheme.light();
    final grey = colorForSlot(kVoronoiNoSlot, 2, scheme);
    expect(HSVColor.fromColor(grey).saturation, 0);
    expect(HSVColor.fromColor(colorForSlot(0, 2, scheme)).saturation, isNot(0));
  });

  testWidgets('a failed layout stops and offers Retry', (tester) async {
    var calls = 0;
    var fail = true;
    Future<VoronoiResult> layout(VoronoiRequest req) {
      calls++;
      return fail
          ? Future.error(StateError('boom'))
          : Future.value(computeVoronoiTreemap(req));
    }

    await tester.pumpWidget(host(c: communities, computeLayout: layout));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tester.takeException(), isStateError);
    expect(calls, 1, reason: 'must not respawn the layout on every build');
    expect(find.byKey(const Key('voronoi-retry')), findsOneWidget);

    fail = false;
    await tester.tap(find.byKey(const Key('voronoi-retry')));
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(find.byKey(const Key('voronoi-fit')), findsOneWidget);
  });

  testWidgets('an index refresh keeps the zoom', (tester) async {
    await tester.pumpWidget(host(c: communities));
    await _waitForLayout(tester);
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
    await tester.pumpWidget(host(c: communities, revision: 2));
    await _waitForLayout(tester);
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      2,
    );
  });

  testWidgets('"In cluster" names the cluster, not the tag', (tester) async {
    // x1 leads the community; m6 carries only x2, so its parent cell is the
    // tag x2 while its cluster is x1.
    final mixed = VaultIndex(
      notesByPath: {
        for (final n in [
          _note('m1', ['x1', 'x2']),
          _note('m2', ['x1', 'x2']),
          _note('m3', ['x1', 'x2']),
          _note('m4', ['x1']),
          _note('m5', ['x1']),
          _note('m6', ['x2']),
        ])
          n.path: n,
      },
      backlinksByTarget: const {},
    );
    final c = computeCommunities(mixed, minNotes: 2, minCoOccur: 2);
    final cluster = c.noteToCluster['m6']!;
    expect(cluster, isNot('x2'), reason: 'fixture: tag differs from cluster');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoronoiView(
            index: mixed,
            communities: c,
            indexRevision: 1,
            onOpenPath: (_) {},
            initialSelectedPath: 'm6',
            clusterNames: {cluster: 'Renamed cluster'},
          ),
        ),
      ),
    );
    await _waitForLayout(tester);
    expect(find.text('In cluster Renamed cluster'), findsOneWidget);
  });

  testWidgets('renders and a tap selects before Open opens a note', (
    tester,
  ) async {
    // At the 800x600 test viewport every cell of this tiny fixture is already
    // past the reveal threshold, so a tap lands on a leaf note cell.
    final opened = <String>[];
    await tester.pumpWidget(host(c: communities, onOpen: opened.add));
    await _waitForLayout(tester);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byKey(const Key('voronoi-fit')), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byType(VoronoiView)));
    await tester.pump();
    expect(opened, isEmpty);
    expect(find.byKey(const Key('voronoi-open')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voronoi-open')));
    await tester.pump();
    expect(opened, hasLength(1));
    expect(index.notesByPath.keys, contains(opened.single));
  });

  testWidgets('reports Voronoi selection changes', (tester) async {
    final selected = <String?>[];
    await tester.pumpWidget(
      host(c: communities, onSelectionChanged: selected.add),
    );
    await _waitForLayout(tester);
    await tester.tapAt(tester.getCenter(find.byType(VoronoiView)));
    await tester.pump();
    expect(selected, hasLength(1));
    expect(selected.single, isNotNull);
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
    // Open clusters still name themselves (their names vanished at normal
    // zoom once their tags were shown).
    expect(
      byLabel.keys.where((label) => label.endsWith(' cluster')),
      isNotEmpty,
    );

    // Activating a leaf's semantics node does exactly what tapping it does:
    // select it, then Open in the shared bar opens the note.
    owner.performAction(byLabel['n1']!.id, SemanticsAction.tap);
    await tester.pump();
    expect(opened, isEmpty);
    await tester.tap(find.byKey(const Key('voronoi-open')));
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
