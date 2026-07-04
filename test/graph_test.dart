import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/graph.dart';
import 'package:tylog/models.dart';

void main() {
  test('buildNoteGraph creates deterministic nodes and resolved edges', () {
    final index = VaultIndex(
      notesByPath: {
        'journal/2026-07-01.typ': const NoteRef(
          id: '2026-07-01',
          path: 'journal/2026-07-01.typ',
          title: 'Today',
          outgoingLinks: ['PKM', 'Missing'],
        ),
        'pages/PKM.typ': const NoteRef(
          id: 'pkm',
          path: 'pages/PKM.typ',
          title: 'PKM',
          outgoingLinks: ['Today'],
        ),
      },
      backlinksByTarget: const {},
    );

    final graph = buildNoteGraph(index);

    expect(graph.nodes.map((node) => node.path), [
      'journal/2026-07-01.typ',
      'pages/PKM.typ',
    ]);
    expect(graph.edges.map((edge) => '${edge.from}->${edge.to}'), [
      'journal/2026-07-01.typ->pages/PKM.typ',
      'pages/PKM.typ->journal/2026-07-01.typ',
    ]);
  });

  test('graphPositions uses stable link-distance rings', () {
    const graph = NoteGraph(
      nodes: [
        GraphNode(path: 'a.typ', title: 'A'),
        GraphNode(path: 'b.typ', title: 'B'),
        GraphNode(path: 'c.typ', title: 'C'),
        GraphNode(path: 'd.typ', title: 'D'),
      ],
      edges: [
        GraphEdge(from: 'a.typ', to: 'b.typ'),
        GraphEdge(from: 'b.typ', to: 'c.typ'),
      ],
    );

    final positions = graphPositions(graph, 'a.typ', const Size(800, 800));
    const center = Offset(400, 400);

    expect(positions['a.typ'], center);
    expect((positions['b.typ']! - center).distance, 110);
    expect((positions['c.typ']! - center).distance, 220);
    expect((positions['d.typ']! - center).distance, 330);
    expect(positions.values.toSet(), hasLength(4));
  });

  test('graph canvas grows for crowded and deep rings', () {
    final crowded = NoteGraph(
      nodes: [
        const GraphNode(path: 'root', title: 'Root'),
        for (var i = 0; i < 20; i++) GraphNode(path: '$i', title: '$i'),
      ],
      edges: [for (var i = 0; i < 20; i++) GraphEdge(from: 'root', to: '$i')],
    );
    const deep = NoteGraph(
      nodes: [
        GraphNode(path: 'a', title: 'A'),
        GraphNode(path: 'b', title: 'B'),
        GraphNode(path: 'c', title: 'C'),
        GraphNode(path: 'd', title: 'D'),
      ],
      edges: [
        GraphEdge(from: 'a', to: 'b'),
        GraphEdge(from: 'b', to: 'c'),
        GraphEdge(from: 'c', to: 'd'),
      ],
    );

    expect(
      graphCanvasSize(crowded, 'root', const Size.square(300)).width,
      greaterThan(500),
    );
    expect(
      graphCanvasSize(deep, 'a', const Size.square(300)).width,
      greaterThan(700),
    );
  });

  testWidgets('graph selects before opening and resets its viewport', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const graph = NoteGraph(
      nodes: [
        GraphNode(path: 'a.typ', title: 'Alpha'),
        GraphNode(path: 'b.typ', title: 'Beta'),
      ],
      edges: [GraphEdge(from: 'a.typ', to: 'b.typ')],
    );
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphView(
            graph: graph,
            currentPath: 'a.typ',
            onOpenPath: (path) => opened = path,
          ),
        ),
      ),
    );
    await tester.pump();

    final paintFinder = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is GraphPainter,
    );
    final paintBox = tester.renderObject<RenderBox>(paintFinder);
    final painter =
        tester.widget<CustomPaint>(paintFinder).painter! as GraphPainter;
    await tester.tapAt(paintBox.localToGlobal(painter.positions['b.typ']!));
    await tester.pump();
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('b.typ'), findsOneWidget);
    expect(opened, isNull);

    await tester.tap(find.byKey(const Key('graph-open')));
    expect(opened, 'b.typ');

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final fitted = viewer.transformationController!.value.clone();
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(50, 50, 0, 1);
    await tester.tap(find.byKey(const Key('graph-fit')));
    expect(viewer.transformationController!.value, fitted);
    semantics.dispose();
  });
}
