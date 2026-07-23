import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/graph.dart';

double _dist(Float64List p, int i, int j) {
  final dx = p[2 * i] - p[2 * j];
  final dy = p[2 * i + 1] - p[2 * j + 1];
  return math.sqrt(dx * dx + dy * dy);
}

void main() {
  test('cluster-seeded layout packs communities tighter than it separates them',
      () {
    // Two triangles: nodes 0,1,2 (cluster 0) and 3,4,5 (cluster 1). Edges only
    // within each triangle — no cross-cluster edge.
    const edges = <(int, int)>[(0, 1), (1, 2), (0, 2), (3, 4), (4, 5), (3, 5)];
    final clusterId = Int32List.fromList([0, 0, 0, 1, 1, 1]);

    final pos = forceDirectedFlat(6, edges, 1000, 1000, 120,
        clusterId: clusterId);

    double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
    final intra = <double>[
      for (final (a, b) in [(0, 1), (0, 2), (1, 2), (3, 4), (3, 5), (4, 5)])
        _dist(pos, a, b),
    ];
    final inter = <double>[
      for (var i = 0; i < 3; i++)
        for (var j = 3; j < 6; j++) _dist(pos, i, j),
    ];

    expect(mean(intra), lessThan(mean(inter)),
        reason: 'same-cluster nodes should end up closer than cross-cluster');
  });

  test('no clusterId reproduces the original ring layout deterministically', () {
    const edges = <(int, int)>[(0, 1), (1, 2)];
    final a = forceDirectedFlat(3, edges, 800, 800, 60);
    final b = forceDirectedFlat(3, edges, 800, 800, 60);
    expect(a, b);
  });

  test('clusterAggregates collapses each community to one zone glyph', () {
    // Two note communities: A = {n1,n2,n3} near (100,100); B = {n4,n5} near (500,500).
    final graph = NoteGraph(
      nodes: const [
        GraphNode(path: 'n1', title: 'n1'),
        GraphNode(path: 'n2', title: 'n2'),
        GraphNode(path: 'n3', title: 'n3'),
        GraphNode(path: 'n4', title: 'n4'),
        GraphNode(path: 'n5', title: 'n5'),
      ],
      edges: const [],
    );
    final positions = {
      'n1': const Offset(90, 90),
      'n2': const Offset(110, 90),
      'n3': const Offset(100, 120),
      'n4': const Offset(490, 500),
      'n5': const Offset(510, 500),
    };
    const communities = CommunityMap(
      tagToCluster: {},
      noteToCluster: {'n1': 'A', 'n2': 'A', 'n3': 'A', 'n4': 'B', 'n5': 'B'},
      clusterOrder: ['A', 'B'],
    );

    final aggs = clusterAggregates(graph, positions, communities);

    expect(aggs.map((a) => a.label), ['A', 'B']);
    expect(aggs[0].count, 3);
    expect(aggs[1].count, 2);
    // Core sits at the members' centroid.
    expect((aggs[0].core - const Offset(100, 100)).distance, lessThan(1));
    expect((aggs[1].core - const Offset(500, 500)).distance, lessThan(1));
    // Radius encloses every member of its community.
    for (final path in ['n1', 'n2', 'n3']) {
      expect((positions[path]! - aggs[0].core).distance, lessThan(aggs[0].radius));
    }
  });
}
