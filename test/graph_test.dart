import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/graph.dart';
import 'package:tylog/models.dart';

void main() {
  test('buildNoteGraph creates deterministic nodes and resolved edges', () {
    final index = VaultIndex(
      notesByPath: {
        'daily/2026/07/2026-07-01.typ': const NoteRef(
          id: '2026-07-01',
          path: 'daily/2026/07/2026-07-01.typ',
          title: 'Today',
          outgoingLinks: ['PKM', 'Missing'],
        ),
        'notes/PKM.typ': const NoteRef(
          id: 'pkm',
          path: 'notes/PKM.typ',
          title: 'PKM',
          outgoingLinks: ['Today'],
        ),
      },
      backlinksByTarget: const {
        'notes/PKM.typ': ['daily/2026/07/2026-07-01.typ'],
        'daily/2026/07/2026-07-01.typ': ['notes/PKM.typ'],
      },
    );

    final graph = buildNoteGraph(index);

    expect(graph.nodes.map((node) => node.path), [
      'daily/2026/07/2026-07-01.typ',
      'notes/PKM.typ',
    ]);
    expect(graph.edges.map((edge) => '${edge.from}->${edge.to}'), [
      'daily/2026/07/2026-07-01.typ->notes/PKM.typ',
      'notes/PKM.typ->daily/2026/07/2026-07-01.typ',
    ]);
  });

  test('buildNoteGraph links notes to concept and work hubs, not each other', () {
    final index = VaultIndex(
      notesByPath: {
        'articles/a.typ': const NoteRef(
          id: 'a',
          path: 'articles/a.typ',
          title: 'A',
          outgoingLinks: [],
          citations: ['smith-2026'],
          tags: ['ml'],
        ),
        'articles/b.typ': const NoteRef(
          id: 'b',
          path: 'articles/b.typ',
          title: 'B',
          outgoingLinks: [],
          citations: ['smith-2026'],
          tags: ['ml'],
        ),
      },
      backlinksByTarget: const {},
    );

    final graph = buildNoteGraph(index);

    // A concept hub for the shared tag and a work hub for the shared citekey.
    final concept = graph.nodes.singleWhere(
      (node) => node.kind == GraphNodeKind.concept,
    );
    expect(concept.path, 'concept:ml');
    expect(concept.title, 'ml');
    final work = graph.nodes.singleWhere(
      (node) => node.kind == GraphNodeKind.work,
    );
    expect(work.path, 'cite:smith-2026');

    // Both notes spoke into each hub; no direct note<->note edges.
    final tagEdges = graph.edges.where((e) => e.kind == GraphEdgeKind.tag);
    expect(
      tagEdges.map((e) => '${e.from}->${e.to}'),
      containsAll([
        'articles/a.typ->concept:ml',
        'articles/b.typ->concept:ml',
      ]),
    );
    final citationEdges = graph.edges.where(
      (e) => e.kind == GraphEdgeKind.citation,
    );
    expect(
      citationEdges.map((e) => '${e.from}->${e.to}'),
      containsAll([
        'articles/a.typ->cite:smith-2026',
        'articles/b.typ->cite:smith-2026',
      ]),
    );
    expect(
      graph.edges.any(
        (e) => e.from == 'articles/a.typ' && e.to == 'articles/b.typ',
      ),
      isFalse,
    );
  });

  test('a tag on k notes yields one concept hub and k spokes, not k*(k-1)/2', () {
    const k = 5;
    final index = VaultIndex(
      notesByPath: {
        for (var i = 0; i < k; i++)
          'articles/n$i.typ': NoteRef(
            id: 'n$i',
            path: 'articles/n$i.typ',
            title: 'N$i',
            outgoingLinks: const [],
            tags: const ['esp32'],
          ),
      },
      backlinksByTarget: const {},
    );

    final graph = buildNoteGraph(index);

    expect(
      graph.nodes.where((n) => n.kind == GraphNodeKind.concept),
      hasLength(1),
    );
    expect(
      graph.edges.where((e) => e.kind == GraphEdgeKind.tag),
      hasLength(k),
    );
  });

  test('a single-note (leaf) tag is not promoted to a concept node', () {
    final index = VaultIndex(
      notesByPath: {
        'articles/a.typ': const NoteRef(
          id: 'a',
          path: 'articles/a.typ',
          title: 'A',
          outgoingLinks: [],
          tags: ['shared', 'unique-to-a'],
        ),
        'articles/b.typ': const NoteRef(
          id: 'b',
          path: 'articles/b.typ',
          title: 'B',
          outgoingLinks: [],
          tags: ['shared'],
        ),
      },
      backlinksByTarget: const {},
    );

    final concepts = buildNoteGraph(index).nodes
        .where((n) => n.kind == GraphNodeKind.concept)
        .toList();

    // 'shared' (2 notes) promoted; 'unique-to-a' (1 note) dropped.
    expect(concepts.map((n) => n.path), ['concept:shared']);
    expect(concepts.single.count, 2);
  });

  test('buildConceptMap yields badged concept hubs and co-occurrence edges', () {
    NoteRef article(String id, List<String> tags) => NoteRef(
      id: id,
      path: 'articles/$id.typ',
      title: id.toUpperCase(),
      outgoingLinks: const [],
      tags: tags,
    );
    // esp32 on 5 notes, home-assistant on 5 notes (co-occur on 5), rare on 1.
    final notes = <String, NoteRef>{};
    for (var i = 0; i < 5; i++) {
      notes['articles/n$i.typ'] = article('n$i', ['esp32', 'home-assistant']);
    }
    notes['articles/z.typ'] = article('z', ['rare']);
    final index = VaultIndex(notesByPath: notes, backlinksByTarget: const {});

    final map = buildConceptMap(index, minNotes: 5, minCoOccur: 3);

    // Only the two substantial concepts appear; 'rare' (1 note) is excluded.
    expect(
      map.nodes.map((n) => n.path).toSet(),
      {'concept:esp32', 'concept:home-assistant'},
    );
    expect(map.nodes.every((n) => n.count == 5), isTrue);
    // Concept-to-concept co-occurrence edge (shared on 5 notes >= 3).
    expect(map.edges, hasLength(1));
    expect(map.edges.single.weight, 5);
    expect(map.nodes.any((n) => n.path.startsWith('articles/')), isFalse);
  });

  test('buildLocalNoteGraph reaches a co-tagged note through its concept', () {
    final index = VaultIndex(
      notesByPath: {
        'daily/today.typ': const NoteRef(
          id: 'today',
          path: 'daily/today.typ',
          title: 'Today',
          outgoingLinks: [],
          tags: ['esp32'],
        ),
        'articles/panel.typ': const NoteRef(
          id: 'panel',
          path: 'articles/panel.typ',
          title: 'ESP32 panel',
          outgoingLinks: [],
          tags: ['esp32'],
        ),
      },
      backlinksByTarget: const {},
    );

    final local = buildLocalNoteGraph(index, 'daily/today.typ');

    // daily -> concept:esp32 (hop 1) -> articles/panel.typ (hop 2)
    expect(local.nodes.map((n) => n.path), contains('concept:esp32'));
    expect(local.nodes.map((n) => n.path), contains('articles/panel.typ'));
  });

  test('buildNoteGraph flags nodes with problems', () {
    final index = VaultIndex(
      notesByPath: {
        'notes/broken.typ': const NoteRef(
          id: 'broken',
          path: 'notes/broken.typ',
          title: 'Broken',
          outgoingLinks: ['missing'],
        ),
      },
      backlinksByTarget: const {},
      problems: const [
        PkmsProblem(
          code: 'broken-link',
          severity: PkmsSeverity.warning,
          subject: 'notes/broken.typ',
          message: 'broken link: missing',
        ),
      ],
    );

    final graph = buildNoteGraph(index);

    expect(graph.nodes.single.problemCount, 1);
  });

  test(
    'buildLocalNoteGraph returns only the current note when it has no edges',
    () {
      final index = VaultIndex(
        notesByPath: {
          'daily/today.typ': const NoteRef(
            id: 'today',
            path: 'daily/today.typ',
            title: 'Today',
            outgoingLinks: [],
          ),
          'notes/other.typ': const NoteRef(
            id: 'other',
            path: 'notes/other.typ',
            title: 'Other',
            outgoingLinks: [],
          ),
        },
        backlinksByTarget: const {},
      );

      final local = buildLocalNoteGraph(index, 'daily/today.typ');
      expect(local.nodes.map((n) => n.path), ['daily/today.typ']);

      final whole = buildNoteGraph(index);
      expect(whole.nodes, hasLength(2));
    },
  );

  test('buildLocalNoteGraph truncates at the given limit', () {
    final notes = <String, NoteRef>{
      for (var i = 0; i < 150; i++)
        'n$i.typ': NoteRef(
          id: 'n$i',
          path: 'n$i.typ',
          title: 'N$i',
          outgoingLinks: i == 0 ? const [] : ['n${i - 1}.typ'],
        ),
    };
    final backlinks = <String, List<String>>{
      for (var i = 1; i < 150; i++) 'n${i - 1}.typ': ['n$i.typ'],
    };
    final index = VaultIndex(
      notesByPath: notes,
      backlinksByTarget: backlinks,
    );

    expect(buildNoteGraph(index).nodes, hasLength(150));
    expect(
      buildLocalNoteGraph(index, 'n0.typ', hops: 200, limit: 50).nodes,
      hasLength(50),
    );
  });

  test('buildLocalNoteGraph with no current path returns an empty graph', () {
    final index = VaultIndex(notesByPath: const {}, backlinksByTarget: const {});
    final local = buildLocalNoteGraph(index, null);
    expect(local.nodes, isEmpty);
    expect(local.edges, isEmpty);
  });

  test('restrictNoteGraph keeps only nodes/edges within the given paths', () {
    const graph = NoteGraph(
      nodes: [
        GraphNode(path: 'a', title: 'A'),
        GraphNode(path: 'b', title: 'B'),
        GraphNode(path: 'c', title: 'C'),
      ],
      edges: [
        GraphEdge(from: 'a', to: 'b'),
        GraphEdge(from: 'b', to: 'c'),
      ],
    );

    final restricted = restrictNoteGraph(graph, {'a', 'b'});

    expect(restricted.nodes.map((n) => n.path), ['a', 'b']);
    expect(restricted.edges, [const GraphEdge(from: 'a', to: 'b')]);
  });

  test('computeGraphStats finds orphans and ranks hubs by degree', () {
    const graph = NoteGraph(
      nodes: [
        GraphNode(path: 'hub', title: 'Hub'),
        GraphNode(path: 'a', title: 'A'),
        GraphNode(path: 'b', title: 'B'),
        GraphNode(path: 'c', title: 'C'),
        GraphNode(path: 'orphan1', title: 'Orphan1'),
        GraphNode(path: 'orphan2', title: 'Orphan2'),
      ],
      edges: [
        GraphEdge(from: 'hub', to: 'a'),
        GraphEdge(from: 'hub', to: 'b'),
        GraphEdge(from: 'hub', to: 'c'),
      ],
    );

    final stats = computeGraphStats(graph, hubLimit: 2);

    expect(stats.orphanPaths, ['orphan1', 'orphan2']);
    expect(stats.hubPaths, ['hub', 'a']);
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
