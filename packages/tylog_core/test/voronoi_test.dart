import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

const unitSquare = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)];

NoteRef _note(String path, List<String> tags) =>
    NoteRef(id: path, path: path, title: path, outgoingLinks: const [], tags: tags);

VaultIndex _index(List<NoteRef> notes) => VaultIndex(
  notesByPath: {for (final n in notes) n.path: n},
  backlinksByTarget: const {},
);

List<List<(double, double)>> _cellsOf(VoronoiResult r) => [
  for (var i = 0; i + 1 < r.cellStart.length; i++)
    [
      for (var v = r.cellStart[i]; v < r.cellStart[i + 1]; v += 2)
        (r.verts[v], r.verts[v + 1]),
    ],
];

void main() {
  test('unweighted bisector splits the unit square into exact halves', () {
    final cell = clipPowerBisector(
      unitSquare,
      (0.25, 0.5),
      0,
      (0.75, 0.5),
      0,
    );
    expect(polygonArea(cell), closeTo(0.5, 1e-9));
    for (final (x, _) in cell) {
      expect(x, lessThanOrEqualTo(0.5 + 1e-9));
    }
  });

  test('powerCells conserves area and keeps each site in its own cell', () {
    final rng = math.Random(3);
    final sites = List.generate(
      30,
      (_) => (rng.nextDouble(), rng.nextDouble()),
    );
    final cells = powerCells(sites, List.filled(30, 0.0), unitSquare);
    final total = cells.fold(0.0, (a, c) => a + polygonArea(c));
    expect(total, closeTo(1.0, 1e-6));
    for (var i = 0; i < sites.length; i++) {
      expect(containsConvex(cells[i], sites[i]), isTrue, reason: 'site $i');
    }
  });

  test('weightedTessellation approximates a 3:1 area split', () {
    final cells = weightedTessellation(unitSquare, [3, 1], 11);
    final a = polygonArea(cells[0]), b = polygonArea(cells[1]);
    expect(a + b, closeTo(1.0, 1e-6));
    expect(a / b, closeTo(3.0, 0.5));
  });

  test('heavier targets get larger cells (monotonic, n=5)', () {
    final targets = [1.0, 2.0, 4.0, 8.0, 16.0];
    final cells = weightedTessellation(unitSquare, targets, 5);
    final areas = cells.map(polygonArea).toList();
    for (var i = 1; i < areas.length; i++) {
      expect(areas[i], greaterThan(areas[i - 1]), reason: 'target $i');
    }
  });

  test('degenerates: single site fills the boundary, duplicates survive', () {
    expect(polygonArea(weightedTessellation(unitSquare, [5], 1).single),
        closeTo(1.0, 1e-9));
    final dup = weightedTessellation(unitSquare, [1, 1, 1], 2);
    expect(dup.length, 3);
    expect(dup.fold(0.0, (a, c) => a + polygonArea(c)), closeTo(1.0, 1e-6));
  });

  group('treemap from a vault fixture', () {
    // Two disjoint communities (a1/a2 over n1-n3, b1/b2 over n4-n6) plus one
    // note whose only tag is below the promotion threshold.
    final index = _index([
      _note('n1', ['a1', 'a2']),
      _note('n2', ['a1', 'a2']),
      _note('n3', ['a1', 'a2']),
      _note('n4', ['b1', 'b2']),
      _note('n5', ['b1', 'b2']),
      _note('n6', ['b1', 'b2']),
      _note('n7', ['solo']),
    ]);
    final communities = computeCommunities(index, minNotes: 2, minCoOccur: 2);
    final req = buildVoronoiRequest(index, communities, 100, 100);

    test('hierarchy: communities, dominant tags, notes, Uncategorized', () {
      final roots = [
        for (var i = 0; i < req.ids.length; i++)
          if (req.parent[i] == -1) req.labels[i],
      ];
      expect(roots, ['a1', 'b1', kUncategorizedLabel]);
      expect(voronoiRootCount(req), 3);

      // Every clustered note sits under its dominant tag (a1/b1: most notes,
      // lexicographic tie-break), two levels below its community.
      final iN1 = req.ids.indexOf('n1');
      expect(req.depth[iN1], 2);
      expect(req.ids[req.parent[iN1]], 'concept:a1');
      expect(req.parent[req.parent[iN1]],
          req.ids.indexOf('cluster:${communities.noteToCluster['n1']}'));

      // The unclustered note is a direct depth-1 child of Uncategorized.
      final iN7 = req.ids.indexOf('n7');
      expect(req.depth[iN7], 1);
      expect(req.ids[req.parent[iN7]], 'cluster:');

      // Community weights are their note counts.
      expect(req.weight[req.ids.indexOf('cluster:a1')], 3);
      expect(req.weight[req.ids.indexOf('cluster:')], 1);
    });

    test('cells nest inside their parent and cover the rectangle', () {
      final result = computeVoronoiTreemap(req);
      final cells = _cellsOf(result);
      expect(cells.length, req.ids.length);

      final rootArea = [
        for (var i = 0; i < cells.length; i++)
          if (req.parent[i] == -1) polygonArea(cells[i]),
      ].fold(0.0, (a, b) => a + b);
      expect(rootArea, closeTo(100 * 100, 1));

      // Every non-root cell's centroid lies inside its parent polygon.
      for (var i = 0; i < cells.length; i++) {
        if (req.parent[i] == -1 || cells[i].length < 3) continue;
        expect(
          containsConvex(cells[req.parent[i]], polygonCentroid(cells[i])),
          isTrue,
          reason: '${req.ids[i]} inside ${req.ids[req.parent[i]]}',
        );
      }
    });

    test('is deterministic for a fixed seed', () {
      final a = computeVoronoiTreemap(req);
      final b = computeVoronoiTreemap(
        buildVoronoiRequest(index, communities, 100, 100),
      );
      expect(a.verts, b.verts);
      expect(a.cellStart, b.cellStart);
    });
  });
}
