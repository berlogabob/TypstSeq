import 'dart:math' as math;
import 'dart:typed_data';

import 'graph.dart';
import 'models.dart';

/// Rounds of (tessellate -> Lloyd re-center -> weight nudge) per hierarchy
/// level. Fixed count, no convergence test — approximate area matching is the
/// requirement ("big tag looks big"), not exact proportions.
const kVoronoiIterations = 40;

/// Signed shoelace area; positive when [poly] winds counter-clockwise in a
/// y-up frame (clockwise on screen). Callers wanting a magnitude use
/// [polygonArea].
double _signedArea(List<(double, double)> poly) {
  var sum = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final (ax, ay) = poly[i];
    final (bx, by) = poly[(i + 1) % poly.length];
    sum += ax * by - bx * ay;
  }
  return sum / 2;
}

double polygonArea(List<(double, double)> poly) =>
    poly.length < 3 ? 0.0 : _signedArea(poly).abs();

(double, double) polygonCentroid(List<(double, double)> poly) {
  final a = _signedArea(poly);
  if (a.abs() < 1e-12) {
    // Degenerate sliver: fall back to the vertex mean.
    var x = 0.0, y = 0.0;
    for (final (px, py) in poly) {
      x += px;
      y += py;
    }
    return (x / poly.length, y / poly.length);
  }
  var cx = 0.0, cy = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final (ax, ay) = poly[i];
    final (bx, by) = poly[(i + 1) % poly.length];
    final cross = ax * by - bx * ay;
    cx += (ax + bx) * cross;
    cy += (ay + by) * cross;
  }
  return (cx / (6 * a), cy / (6 * a));
}

/// True when [p] lies inside convex [poly] (either winding).
bool containsConvex(List<(double, double)> poly, (double, double) p) {
  if (poly.length < 3) return false;
  final orientation = _signedArea(poly).sign;
  for (var i = 0; i < poly.length; i++) {
    final (ax, ay) = poly[i];
    final (bx, by) = poly[(i + 1) % poly.length];
    final cross = (bx - ax) * (p.$2 - ay) - (by - ay) * (p.$1 - ax);
    if (cross * orientation < 0) return false;
  }
  return true;
}

/// Clips convex [poly] to the half-plane of points whose power distance to
/// [site] (weight [wSite]) is <= the power distance to [other] (weight
/// [wOther]). With zero weights this is the plain Voronoi bisector; nonzero
/// weights shift the (still straight) radical axis, so the same clip does
/// power diagrams. Sutherland–Hodgman single-plane pass, O(vertices).
List<(double, double)> clipPowerBisector(
  List<(double, double)> poly,
  (double, double) site,
  double wSite,
  (double, double) other,
  double wOther,
) {
  // Keep p where 2 p·(other - site) <= |other|^2 - |site|^2 + wSite - wOther.
  final nx = other.$1 - site.$1, ny = other.$2 - site.$2;
  final c =
      (other.$1 * other.$1 +
          other.$2 * other.$2 -
          site.$1 * site.$1 -
          site.$2 * site.$2 +
          wSite -
          wOther) /
      2;
  final out = <(double, double)>[];
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    final da = c - (a.$1 * nx + a.$2 * ny);
    final db = c - (b.$1 * nx + b.$2 * ny);
    if (da >= 0) out.add(a);
    if ((da >= 0) != (db >= 0)) {
      final t = da / (da - db);
      out.add((a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t));
    }
  }
  return out;
}

/// One power-diagram tessellation of [sites] inside convex [boundary]. Cells
/// come back in site order; a site whose cell vanishes gets an empty list.
/// ponytail: O(n^2) half-plane clipping with a nearest-first reach test; fine
/// to ~500 siblings per parent, a single tag with thousands of notes would
/// need Fortune's — which we don't have or need yet.
List<List<(double, double)>> powerCells(
  List<(double, double)> sites,
  List<double> weights,
  List<(double, double)> boundary,
) {
  final n = sites.length;
  return [
    for (var i = 0; i < n; i++) _powerCell(i, sites, weights, boundary),
  ];
}

List<(double, double)> _powerCell(
  int i,
  List<(double, double)> sites,
  List<double> weights,
  List<(double, double)> boundary,
) {
  final (sx, sy) = sites[i];
  var cell = List.of(boundary);
  // Nearest sites first: they carve the cell small early, so the "bisector
  // can't reach the cell" test below skips almost all the far sites.
  final others = [
    for (var j = 0; j < sites.length; j++)
      if (j != i) j,
  ];
  double d2(int j) {
    final (ox, oy) = sites[j];
    return (ox - sx) * (ox - sx) + (oy - sy) * (oy - sy);
  }

  others.sort((a, b) => d2(a).compareTo(d2(b)));

  var reach2 = double.infinity; // max squared vertex distance from the site
  void updateReach() {
    reach2 = 0;
    for (final (vx, vy) in cell) {
      final r = (vx - sx) * (vx - sx) + (vy - sy) * (vy - sy);
      if (r > reach2) reach2 = r;
    }
  }

  updateReach();
  for (final j in others) {
    final dd = d2(j);
    if (dd < 1e-12) continue; // coincident site: leave to seeding jitter
    // Distance from the site to the radical axis along the inter-site line.
    final offset = (dd + weights[i] - weights[j]) / (2 * math.sqrt(dd));
    if (offset > 0 && offset * offset >= reach2) continue; // can't cut
    cell = clipPowerBisector(cell, (sx, sy), weights[i], sites[j], weights[j]);
    if (cell.length < 3) return const [];
    updateReach();
  }
  return cell;
}

(double, double) _randomPointIn(
  List<(double, double)> boundary,
  math.Random rng,
) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final (x, y) in boundary) {
    minX = math.min(minX, x);
    minY = math.min(minY, y);
    maxX = math.max(maxX, x);
    maxY = math.max(maxY, y);
  }
  for (var attempt = 0; attempt < 100; attempt++) {
    final p = (
      minX + rng.nextDouble() * (maxX - minX),
      minY + rng.nextDouble() * (maxY - minY),
    );
    if (containsConvex(boundary, p)) return p;
  }
  return polygonCentroid(boundary);
}

/// Weighted treemap of one level: seeds sites with Random([seed]) inside
/// convex [boundary], then runs [kVoronoiIterations] rounds of Lloyd
/// re-centering plus a clamped area-deficit weight nudge (simplified
/// Balzer–Deussen). Cells return in input order; [targetWeights] need not be
/// normalized. Deterministic for a given seed.
List<List<(double, double)>> weightedTessellation(
  List<(double, double)> boundary,
  List<double> targetWeights,
  int seed,
) {
  final n = targetWeights.length;
  if (n == 0) return const [];
  if (n == 1) return [List.of(boundary)];
  final totalArea = polygonArea(boundary);
  if (totalArea <= 1e-9) {
    return [for (var i = 0; i < n; i++) const <(double, double)>[]];
  }
  final totalW = targetWeights.fold(0.0, (a, b) => a + math.max(b, 0.0));
  final target = [
    for (final w in targetWeights)
      totalW > 0 ? totalArea * math.max(w, 0.0) / totalW : totalArea / n,
  ];
  final rng = math.Random(seed);
  final sites = List.generate(n, (_) => _randomPointIn(boundary, rng));
  final weights = List.filled(n, 0.0);
  var cells = powerCells(sites, weights, boundary);
  final avgArea = totalArea / n;
  for (var iter = 0; iter < kVoronoiIterations; iter++) {
    for (var i = 0; i < n; i++) {
      final cell = cells[i];
      if (cell.length < 3) {
        // Vanished: its weight fell too far behind the neighbors' — pull it
        // toward the current max so it wins ground back next round.
        final wMax = weights.reduce(math.max);
        weights[i] = (weights[i] + wMax) / 2 + avgArea * 0.05;
        continue;
      }
      sites[i] = polygonCentroid(cell);
      final deficit = target[i] - polygonArea(cell);
      // Clamped nudge keeps a huge target from shoving the radical axis past
      // a neighbor site in one step (the oscillation/vanishing failure mode).
      weights[i] += deficit.clamp(-avgArea, avgArea) * 0.6;
    }
    cells = powerCells(sites, weights, boundary);
  }
  return cells;
}

/// Flat cell tree for the treemap, primitives-only so it crosses the isolate
/// boundary cheaply. Parallel lists: cell i has parent index `parent[i]`
/// (-1 for a root community), hierarchy `depth[i]` (0 community, 1 tag,
/// 2 note — uncategorized notes sit at depth 1 directly under their
/// community), community color slot `colorSlot[i]`, and area weight
/// `weight[i]`. `ids` are `cluster:<label>`, `concept:<tag>`, or a note path;
/// a leaf cell (no children) is always a note.
class VoronoiRequest {
  const VoronoiRequest({
    required this.ids,
    required this.labels,
    required this.parent,
    required this.depth,
    required this.colorSlot,
    required this.weight,
    required this.width,
    required this.height,
    required this.seed,
  });

  final List<String> ids;
  final List<String> labels;
  final Int32List parent;
  final Int32List depth;
  final Int32List colorSlot;
  final Float64List weight;
  final double width;
  final double height;
  final int seed;
}

/// Tessellated cell polygons, flat: cell i's vertices are
/// `verts[cellStart[i] .. cellStart[i+1])` as x,y pairs. `cellStart` carries
/// an end sentinel, so its length is cell count + 1. An empty range means the
/// cell vanished (or its parent did).
class VoronoiResult {
  const VoronoiResult({required this.verts, required this.cellStart});

  final Float64List verts;
  final Int32List cellStart;
}

/// Number of communities (root cells) in [req] — the `total` a caller passes
/// to a per-slot color function.
int voronoiRootCount(VoronoiRequest req) {
  var count = 0;
  for (var i = 0; i < req.parent.length; i++) {
    if (req.parent[i] == -1) count++;
  }
  return count;
}

const kUncategorizedLabel = 'Uncategorized';

/// Extracts the community -> tag -> note hierarchy from the index. Cheap and
/// sync — run it on the main thread so [VaultIndex] never crosses an isolate.
/// Each clustered note goes under its dominant promoted tag (same dominance
/// rule as [computeCommunities]); notes with no promoted tag land directly
/// under a trailing grey [kUncategorizedLabel] community.
VoronoiRequest buildVoronoiRequest(
  VaultIndex index,
  CommunityMap communities,
  double width,
  double height, {
  int seed = 7,
}) {
  final byTag = tagToNotes(index);

  // Note -> dominant promoted tag (most notes; tie -> smallest tag). Mirrors
  // the assignment inside computeCommunities, which only keeps the cluster.
  final tagOfNote = <String, String>{};
  for (final note in index.notesByPath.values) {
    String? bestTag;
    var bestCount = -1;
    for (final tag in note.tags) {
      if (!communities.tagToCluster.containsKey(tag)) continue;
      final count = byTag[tag]!.length;
      if (count > bestCount ||
          (count == bestCount && tag.compareTo(bestTag!) < 0)) {
        bestTag = tag;
        bestCount = count;
      }
    }
    if (bestTag != null) tagOfNote[note.path] = bestTag;
  }

  // cluster -> tag -> sorted note paths, plus the leftover unclustered notes.
  final notesByClusterTag = <String, Map<String, List<String>>>{};
  final unclustered = <String>[];
  final paths = index.notesByPath.keys.toList()..sort();
  for (final path in paths) {
    final tag = tagOfNote[path];
    if (tag == null) {
      unclustered.add(path);
      continue;
    }
    final cluster = communities.tagToCluster[tag]!;
    notesByClusterTag
        .putIfAbsent(cluster, () => {})
        .putIfAbsent(tag, () => [])
        .add(path);
  }

  final ids = <String>[];
  final labels = <String>[];
  final parent = <int>[];
  final depth = <int>[];
  final colorSlot = <int>[];
  final weight = <double>[];

  void add(String id, String label, int p, int d, int slot, double w) {
    ids.add(id);
    labels.add(label);
    parent.add(p);
    depth.add(d);
    colorSlot.add(slot);
    weight.add(w);
  }

  String titleOf(String path) => index.notesByPath[path]?.title ?? path;

  var slot = 0;
  for (final cluster in communities.clusterOrder) {
    final tags = notesByClusterTag[cluster];
    if (tags == null) continue;
    final noteCount = tags.values.fold(0, (a, b) => a + b.length);
    final clusterIndex = ids.length;
    add('cluster:$cluster', cluster, -1, 0, slot, noteCount.toDouble());
    final tagNames = tags.keys.toList()
      ..sort((a, b) {
        final byCount = tags[b]!.length.compareTo(tags[a]!.length);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    for (final tag in tagNames) {
      final notes = tags[tag]!;
      final tagIndex = ids.length;
      add('concept:$tag', tag, clusterIndex, 1, slot, notes.length.toDouble());
      for (final path in notes) {
        add(path, titleOf(path), tagIndex, 2, slot, 1);
      }
    }
    slot++;
  }
  if (unclustered.isNotEmpty) {
    final clusterIndex = ids.length;
    add(
      'cluster:',
      kUncategorizedLabel,
      -1,
      0,
      slot,
      unclustered.length.toDouble(),
    );
    for (final path in unclustered) {
      add(path, titleOf(path), clusterIndex, 1, slot, 1);
    }
  }

  return VoronoiRequest(
    ids: ids,
    labels: labels,
    parent: Int32List.fromList(parent),
    depth: Int32List.fromList(depth),
    colorSlot: Int32List.fromList(colorSlot),
    weight: Float64List.fromList(weight),
    width: width,
    height: height,
    seed: seed,
  );
}

/// Top-level `compute()` entry: tessellates the communities inside the
/// [VoronoiRequest.width] x [VoronoiRequest.height] rectangle, then each
/// parent's children inside the parent polygon, recursively (depth <= 3).
VoronoiResult computeVoronoiTreemap(VoronoiRequest req) {
  final n = req.ids.length;
  final childrenOf = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    childrenOf.putIfAbsent(req.parent[i], () => []).add(i);
  }
  final polys = List<List<(double, double)>>.filled(n, const []);

  void tessellate(int parentIndex, List<(double, double)> boundary) {
    final kids = childrenOf[parentIndex];
    if (kids == null || kids.isEmpty || boundary.length < 3) return;
    final cells = weightedTessellation(
      boundary,
      [for (final k in kids) req.weight[k]],
      req.seed + (parentIndex + 2) * 1000003,
    );
    for (var j = 0; j < kids.length; j++) {
      polys[kids[j]] = cells[j];
      tessellate(kids[j], cells[j]);
    }
  }

  tessellate(-1, [
    (0.0, 0.0),
    (req.width, 0.0),
    (req.width, req.height),
    (0.0, req.height),
  ]);

  final cellStart = Int32List(n + 1);
  var total = 0;
  for (var i = 0; i < n; i++) {
    cellStart[i] = total * 2;
    total += polys[i].length;
  }
  cellStart[n] = total * 2;
  final verts = Float64List(total * 2);
  var v = 0;
  for (final poly in polys) {
    for (final (x, y) in poly) {
      verts[v++] = x;
      verts[v++] = y;
    }
  }
  return VoronoiResult(verts: verts, cellStart: cellStart);
}
