import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

const unitSquare = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)];

NoteRef _note(String path, List<String> tags) => NoteRef(
  id: path,
  path: path,
  title: path,
  outgoingLinks: const [],
  tags: tags,
);

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
  test('4000 notes stay lazy and capped with lossless overflow', () {
    final index = _index([
      for (var i = 0; i < 4000; i++) _note('n$i', ['shared']),
    ]);
    final communities = computeCommunities(index, minNotes: 2);
    final watch = Stopwatch()..start();
    final req = buildVoronoiRequest(index, communities, 800, 600);
    final result = computeVoronoiTreemap(req);
    watch.stop();
    expect(watch.elapsedMilliseconds, lessThan(1000));
    for (final p in req.parent.toSet()) {
      expect(
        req.parent.where((value) => value == p).length,
        lessThanOrEqualTo(150),
      );
    }
    final more = req.morePaths.entries.single;
    expect(req.labels[more.key], '+3851 more');
    expect(more.value.toSet().length, 3851);
    final represented = {
      for (var i = 0; i < req.ids.length; i++)
        if (index.notesByPath.containsKey(req.ids[i])) req.ids[i],
      ...more.value,
    };
    expect(represented, index.notesByPath.keys.toSet());
    final cells = _cellsOf(result);
    for (var i = 0; i < cells.length; i++) {
      expect(cells[i].isEmpty, req.parent[i] != -1);
    }
    final root = req.parent.indexOf(-1);
    final children = _cellsOf(
      computeVoronoiTreemap(voronoiChildrenRequest(req, root, cells[root])),
    );
    final tag = req.ids.indexOf('concept:shared');
    expect(children[tag], isNotEmpty);
    final leaves = _cellsOf(
      computeVoronoiTreemap(voronoiChildrenRequest(req, tag, children[tag])),
    );
    expect(leaves.where((cell) => cell.isNotEmpty).length, 150);
  });

  test('caps tags by weight and retains all omitted descendants', () {
    final notes = [
      for (var tag = 0; tag < 151; tag++)
        for (var note = 0; note < (tag == 150 ? 5 : 1); note++)
          _note('$tag/$note', ['tag$tag']),
    ];
    final index = _index(notes);
    final communities = CommunityMap(
      tagToCluster: {for (var tag = 0; tag < 151; tag++) 'tag$tag': 'group'},
      noteToCluster: {for (final note in notes) note.path: 'group'},
      clusterOrder: ['group'],
    );
    final req = buildVoronoiRequest(index, communities, 800, 600);
    final root = req.ids.indexOf('cluster:group');
    final tags = [
      for (var i = 0; i < req.ids.length; i++)
        if (req.parent[i] == root) i,
    ];
    expect(tags.length, 150);
    expect(req.ids, contains('concept:tag150'));
    final overflow = req.morePaths.entries.single;
    expect(req.labels[overflow.key], '+2 more');
    expect(req.weight[overflow.key], 2);
    expect(overflow.value.length, 2);
    expect(req.weight[root], 155);
  });

  test('unweighted bisector splits the unit square into exact halves', () {
    final cell = clipPowerBisector(unitSquare, (0.25, 0.5), 0, (0.75, 0.5), 0);
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

  test('skewed weights: heavy cells out-size the count-1 crowd', () {
    // Shape of real vault data: many 1-note tags next to a few 50-200 ones.
    final targets = [...List.filled(20, 1.0), 50.0, 80.0, 120.0, 150.0, 200.0];
    final cells = weightedTessellation(unitSquare, targets, 7);
    final areas = cells.map(polygonArea).toList();
    expect(areas.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-6));
    for (var i = 0; i < areas.length; i++) {
      expect(areas[i], greaterThan(0), reason: 'cell $i vanished');
    }
    final smallMax = areas.sublist(0, 20).reduce(math.max);
    for (var i = 20; i < areas.length; i++) {
      expect(
        areas[i],
        greaterThan(smallMax),
        reason: 'target ${targets[i]} not bigger than every 1-note cell',
      );
    }
    // A 1-note cell must stay near its fair share, not just below the heavy
    // cells (the relative convergence bound: within 25% of avgArea/4).
    expect(smallMax, lessThan(0.005));
    // Heavy targets sum to 600/620 of the area; the solver should get close.
    final heavySum = areas.sublist(20).fold(0.0, (a, b) => a + b);
    expect(heavySum, greaterThan(0.7));
  });

  test('treemap root areas stay ordered under real-vault skew', () {
    // Shape of the real vault top level: one community with 60% of all
    // notes next to 1-note communities (1147:1 range). Areas are
    // sqrt-compressed, so assert visibility + strict ordering, not
    // proportionality.
    final weights = [
      1147.0, 156.0, 139.0, 79.0, 68.0, 35.0, 28.0, 17.0, 11.0, 9.0,
      6.0, 5.0, 3.0, 3.0, 3.0, 2.0, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0, //
    ];
    final n = weights.length;
    final req = VoronoiRequest(
      ids: [for (var i = 0; i < n; i++) 'cluster:$i'],
      labels: [for (var i = 0; i < n; i++) 'c$i'],
      parent: Int32List.fromList(List.filled(n, -1)),
      depth: Int32List(n),
      colorSlot: Int32List.fromList([for (var i = 0; i < n; i++) i]),
      weight: Float64List.fromList(weights),
      width: 1450,
      height: 1470,
      seed: 7,
    );
    final areas = _cellsOf(
      computeVoronoiTreemap(req),
    ).map(polygonArea).toList();
    final total = areas.fold(0.0, (a, b) => a + b);
    expect(total, closeTo(1450 * 1470, 1450 * 1470 * 1e-6));
    // Every community visible and big enough to at least register (>0.1%).
    for (var i = 0; i < n; i++) {
      expect(areas[i], greaterThan(1450 * 1470 * 0.001), reason: 'cell $i');
    }
    // Areas follow counts wherever the sqrt-targets differ beyond the
    // solver's 25% relative tolerance (near-equal counts may tie).
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (math.sqrt(weights[i]) > math.sqrt(weights[j]) * 1.3) {
          expect(areas[i], greaterThan(areas[j]), reason: '$i vs $j');
        }
      }
    }
  });

  test('degenerates: single site fills the boundary, duplicates survive', () {
    expect(
      polygonArea(weightedTessellation(unitSquare, [5], 1).single),
      closeTo(1.0, 1e-9),
    );
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
      expect(
        req.parent[req.parent[iN1]],
        req.ids.indexOf('cluster:${communities.noteToCluster['n1']}'),
      );

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
      for (var i = 0; i < cells.length; i++) {
        if (cells[i].length < 3) continue;
        final level = _cellsOf(
          computeVoronoiTreemap(voronoiChildrenRequest(req, i, cells[i])),
        );
        for (var j = 0; j < cells.length; j++) {
          if (req.parent[j] == i) cells[j] = level[j];
        }
      }
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
