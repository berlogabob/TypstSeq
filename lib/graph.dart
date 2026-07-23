import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:tylog_core/graph.dart';

export 'package:tylog_core/graph.dart'
    show
        GraphEdge,
        GraphEdgeKind,
        GraphNode,
        GraphNodeKind,
        GraphStats,
        CommunityMap,
        NoteGraph,
        buildConceptMap,
        buildLocalNoteGraph,
        buildNoteGraph,
        buildTimelineGraph,
        computeCommunities,
        computeGraphStats,
        restrictNoteGraph,
        kConceptMapMinNotes,
        kConceptMinNotes;

/// Above this many nodes, a whole-vault graph reliably turns into an
/// unreadable "hairball" (community consensus from PKM tools like Obsidian).
const _hairballThreshold = 180;

class GraphView extends StatefulWidget {
  const GraphView({
    super.key,
    required this.graph,
    required this.currentPath,
    required this.onOpenPath,
    this.isWholeVault = false,
    this.onSwitchToFocused,
    this.communities,
  });

  final NoteGraph graph;
  final String? currentPath;
  final ValueChanged<String> onOpenPath;
  final bool isWholeVault;
  final VoidCallback? onSwitchToFocused;

  /// Community assignment (from [computeCommunities]) used to seed/pull nodes
  /// into per-cluster agglomerations and color them. Null ⇒ plain force layout.
  final CommunityMap? communities;

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  String? _selectedPath;
  Size? _lastViewport;
  Size? _lastCanvas;

  // LOD (semantic zoom): community aggregates for the collapsed view, cached
  // alongside `_positions`; and whether the view is currently collapsed (below
  // [kLodZoomThreshold]) so chrome and tap semantics can react.
  List<ClusterAgg>? _clusters;
  bool _collapsed = false;

  // Animated zoom-to-cluster (tap a zone → it fills the view and expands).
  late final AnimationController _zoomCtl;
  Animation<Matrix4>? _zoomAnim;
  final Set<GraphEdgeKind> _visibleKinds = {
    GraphEdgeKind.link,
    GraphEdgeKind.citation,
    GraphEdgeKind.tag,
    GraphEdgeKind.read,
  };
  bool _bannerDismissed = false;
  Set<String>? _focusFilter;
  int _hubCycleIndex = 0;

  // Cached force-directed layout — recomputed only when the node set changes,
  // so a tap/chip toggle never re-simulates (and never jitters).
  Map<String, Offset>? _positions;
  Size? _positionsCanvas;
  bool _laying = false;
  int _layoutToken = 0;

  bool get _isConceptGraph =>
      widget.graph.nodes.isNotEmpty &&
      widget.graph.nodes.every((n) => n.kind == GraphNodeKind.concept);

  void _invalidateLayout() {
    _positions = null;
    _positionsCanvas = null;
    _clusters = null;
    _lastCanvas = null;
    _laying = false;
    _layoutToken++;
  }

  /// Recomputes the collapsed-view aggregates for the current positions (null
  /// when there is no community assignment or it's a timeline graph).
  void _refreshClusters(NoteGraph graph) {
    final communities = widget.communities;
    final positions = _positions;
    _clusters = (communities == null || positions == null || isTimelineGraph(graph))
        ? null
        : clusterAggregates(graph, positions, communities);
  }

  /// Computes positions once per node-set: synchronously for small graphs
  /// (instant, no spinner), in a background isolate for large ones (`All files`
  /// ~1700+) so the UI thread never blocks.
  void _ensureLayout(NoteGraph graph, Size viewport) {
    if (_positions != null || _laying) return;
    final canvas = graphCanvasSize(graph, widget.currentPath, viewport);
    if (isTimelineGraph(graph)) {
      _positions = timelinePositions(graph, canvas);
      _positionsCanvas = canvas;
      return;
    }
    final n = graph.nodes.length;
    if (n <= 400) {
      final pos = forceLayoutPositions(
        graph,
        canvas,
        communities: widget.communities,
      );
      _positions = pos;
      _positionsCanvas = boundsCanvas(pos);
      _refreshClusters(graph);
      return;
    }
    // Large graph: force-layout all nodes in an isolate. Build edge index pairs
    // and parallel weights in lockstep, dropping edges whose endpoints are gone.
    final nodeIndex = {
      for (var i = 0; i < graph.nodes.length; i++) graph.nodes[i].path: i,
    };
    final edges = <(int, int)>[];
    final weightList = <double>[];
    for (final e in graph.edges) {
      final a = nodeIndex[e.from];
      final b = nodeIndex[e.to];
      if (a == null || b == null) continue;
      edges.add((a, b));
      weightList.add(e.weight.toDouble());
    }
    final clusterId = widget.communities == null
        ? null
        : clusterIdsForNodes(graph.nodes, widget.communities!);
    final edgeWeight = widget.communities == null
        ? null
        : Float64List.fromList(weightList);
    final iters = iterationsFor(n);
    _laying = true;
    final token = _layoutToken;
    final paths = [for (final node in graph.nodes) node.path];
    compute(
      runForceLayout,
      LayoutRequest(
        n,
        edges,
        canvas.width,
        canvas.height,
        iters,
        clusterId: clusterId,
        edgeWeight: edgeWeight,
      ),
    ).then((flat) {
      if (!mounted || token != _layoutToken) return;
      final pos = normalizePositions({
        for (var i = 0; i < n; i++)
          paths[i]: Offset(flat[2 * i], flat[2 * i + 1]),
      });
      setState(() {
        _laying = false;
        _positions = pos;
        _positionsCanvas = boundsCanvas(pos);
        _refreshClusters(graph);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.currentPath;
    _transform.addListener(_onTransform);
    _zoomCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
      if (_zoomAnim case final anim?) _transform.value = anim.value;
    });
  }

  /// Repaints happen per-frame via the painter's `repaint:` listenable; here we
  /// only flip the collapsed bucket (cheap, on threshold-cross) so chrome and
  /// tap semantics track the zoom.
  void _onTransform() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final collapsed =
        widget.communities != null &&
        (_clusters?.length ?? 0) >= 2 &&
        scale < kLodZoomThreshold;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  @override
  void didUpdateWidget(covariant GraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPath != widget.currentPath) {
      _selectedPath = widget.currentPath;
      _invalidateLayout();
    } else if (!_sameNodes(oldWidget.graph.nodes, widget.graph.nodes)) {
      _selectedPath =
          widget.graph.nodes.any((node) => node.path == _selectedPath)
          ? _selectedPath
          : widget.currentPath;
      _focusFilter = null;
      _invalidateLayout();
    }
  }

  @override
  void dispose() {
    _zoomCtl.dispose();
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.graph.nodes.isEmpty) {
      return const Center(child: Text('Graph is empty'));
    }
    final stats = computeGraphStats(widget.graph);
    final displayGraph = _focusFilter == null
        ? widget.graph
        : restrictNoteGraph(widget.graph, _focusFilter!);
    final selected = displayGraph.nodes
        .where((node) => node.path == _selectedPath)
        .firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    final showHairballBanner =
        widget.isWholeVault &&
        widget.graph.nodes.length > _hairballThreshold &&
        !_bannerDismissed;
    return Column(
      children: [
        if (showHairballBanner)
          MaterialBanner(
            content: Text(
              '${widget.graph.nodes.length} notes in view — this can get '
              'hard to read.',
            ),
            actions: [
              if (widget.onSwitchToFocused != null)
                TextButton(
                  onPressed: widget.onSwitchToFocused,
                  child: const Text('Focused view'),
                ),
              TextButton(
                onPressed: () => setState(() => _bannerDismissed = true),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GraphLegend(
                visibleKinds: _visibleKinds,
                onToggle: (kind) => setState(() {
                  if (!_visibleKinds.remove(kind)) _visibleKinds.add(kind);
                }),
              ),
              if (stats.orphanPaths.isNotEmpty)
                ActionChip(
                  // "topics" when the graph is concepts (Concept map), else notes.
                  label: Text(
                    '${stats.orphanPaths.length} '
                    '${_isConceptGraph ? 'isolated topics' : 'orphan notes'}',
                  ),
                  onPressed: () => setState(() {
                    _focusFilter = _focusFilter == null
                        ? stats.orphanPaths.toSet()
                        : null;
                    _invalidateLayout();
                  }),
                ),
              if (stats.hubPaths.isNotEmpty)
                ActionChip(
                  label: const Text('Hubs'),
                  onPressed: () => setState(() {
                    _selectedPath =
                        stats.hubPaths[_hubCycleIndex % stats.hubPaths.length];
                    _hubCycleIndex++;
                  }),
                ),
              if (_focusFilter != null)
                Chip(
                  label: const Text('Filtered'),
                  onDeleted: () => setState(() {
                    _focusFilter = null;
                    _invalidateLayout();
                  }),
                ),
            ],
          ),
        ),
        if (selected != null)
          Material(
            color: scheme.surfaceContainerLow,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined),
              title: Text(selected.title, maxLines: 1),
              trailing: FilledButton.tonalIcon(
                key: const Key('graph-open'),
                onPressed: () => widget.onOpenPath(selected.path),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open'),
              ),
            ),
          ),
        Expanded(child: _canvas(scheme, displayGraph)),
      ],
    );
  }

  Widget _canvas(ColorScheme scheme, NoteGraph displayGraph) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _ensureLayout(displayGraph, viewport);
        final positions = _positions;
        final canvas = _positionsCanvas;
        if (positions == null || canvas == null) {
          return const Center(child: CircularProgressIndicator());
        }
        _fitWhenLayoutChanges(viewport, canvas);
        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: 0.1,
              maxScale: 4,
              boundaryMargin: const EdgeInsets.all(80),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    _onCanvasTap(details.localPosition, viewport),
                child: CustomPaint(
                  size: canvas,
                  painter: GraphPainter(
                    graph: displayGraph,
                    positions: positions,
                    selectedPath: _selectedPath,
                    colorScheme: scheme,
                    visibleEdgeKinds: _visibleKinds,
                    onSelect: (path) => setState(() => _selectedPath = path),
                    communities: widget.communities,
                    clusters: _clusters,
                    viewport: viewport,
                    transform: _transform,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                key: const Key('graph-fit'),
                tooltip: 'Fit graph',
                onPressed: () => _fit(viewport, canvas),
                icon: const Icon(Icons.fit_screen),
              ),
            ),
          ],
        );
      },
    );
  }

  void _fitWhenLayoutChanges(Size viewport, Size canvas) {
    if (_lastViewport == viewport && _lastCanvas == canvas) return;
    _lastViewport = viewport;
    _lastCanvas = canvas;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fit(viewport, canvas);
    });
  }

  void _fit(Size viewport, Size canvas) {
    final scale = math.min(
      1.0,
      math.min(viewport.width / canvas.width, viewport.height / canvas.height),
    );
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (viewport.width - canvas.width * scale) / 2,
        (viewport.height - canvas.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  /// Tap routing: while collapsed, a tap on a cluster zone zooms into it (so it
  /// expands into circles); otherwise it selects the node under the point.
  void _onCanvasTap(Offset point, Size viewport) {
    final positions = _positions;
    if (positions == null) return;
    final clusters = _clusters;
    if (_collapsed && clusters != null) {
      // Nearest zone whose radius contains the tap (canvas coords).
      ClusterAgg? hit;
      var best = double.infinity;
      for (final agg in clusters) {
        final d = (agg.core - point).distance;
        if (d <= agg.radius && d < best) {
          best = d;
          hit = agg;
        }
      }
      if (hit != null) {
        _zoomToRect(
          viewport,
          Rect.fromCircle(center: hit.core, radius: hit.radius),
        );
        return;
      }
    }
    final node = _hitNode(positions, point);
    if (node != null) setState(() => _selectedPath = node);
  }

  /// Animates the view to frame [target] (canvas coords), zooming in past
  /// [kLodZoomThreshold] so a tapped zone expands into its individual circles.
  void _zoomToRect(Size viewport, Rect target) {
    final fit = math.min(
      viewport.width / target.width,
      viewport.height / target.height,
    );
    // Clamp into [threshold+ε, maxScale] so the zone always expands but never
    // over-zooms past the InteractiveViewer's max.
    final scale = fit.clamp(kLodZoomThreshold + 0.1, 4.0);
    final end = Matrix4.identity()
      ..translateByDouble(
        viewport.width / 2 - target.center.dx * scale,
        viewport.height / 2 - target.center.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
    _zoomAnim = Matrix4Tween(begin: _transform.value.clone(), end: end).animate(
      CurvedAnimation(parent: _zoomCtl, curve: Curves.easeInOut),
    );
    _zoomCtl.forward(from: 0);
  }

  String? _hitNode(Map<String, Offset> positions, Offset point) {
    for (final entry in positions.entries) {
      if ((entry.value - point).distance <= GraphPainter.nodeRadius + 8) {
        return entry.key;
      }
    }
    return null;
  }

  bool _sameNodes(List<GraphNode> a, List<GraphNode> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i].path == b[i].path).every((v) => v);
}

/// Positions for a graph via a force-directed layout, keyed by node path.
/// `focalPath` is accepted for API stability but the layout self-centres.
/// True when the graph is a Timeline projection (contains day nodes), which
/// uses a chronological layout instead of the force-directed one.
bool isTimelineGraph(NoteGraph graph) =>
    graph.nodes.any((n) => n.kind == GraphNodeKind.day);

/// Chronological layout: day nodes on the x-axis by date, articles pulled toward
/// the day(s) they connect to and staggered vertically to reduce overlap. O(n),
/// deterministic — no physics needed for a timeline.
Map<String, Offset> timelinePositions(NoteGraph graph, Size size) {
  final w = size.width.isFinite && size.width > 0 ? size.width : 1000.0;
  final h = size.height.isFinite && size.height > 0 ? size.height : 1000.0;
  const margin = 90.0;
  final innerW = math.max(1.0, w - 2 * margin);
  final days = graph.nodes.where((n) => n.kind == GraphNodeKind.day).toList()
    ..sort((a, b) => a.title.compareTo(b.title));
  final dayX = <String, double>{};
  for (var i = 0; i < days.length; i++) {
    dayX[days[i].path] = days.length == 1
        ? w / 2
        : margin + innerW * i / (days.length - 1);
  }
  final neighbourDayX = <String, List<double>>{};
  for (final e in graph.edges) {
    if (dayX[e.from] case final x?) {
      neighbourDayX.putIfAbsent(e.to, () => []).add(x);
    }
    if (dayX[e.to] case final x?) {
      neighbourDayX.putIfAbsent(e.from, () => []).add(x);
    }
  }
  final pos = <String, Offset>{
    for (final day in days) day.path: Offset(dayX[day.path]!, h / 2),
  };
  final laneCount = <int, int>{}; // per x-bucket, for vertical stagger
  for (final node in graph.nodes) {
    if (node.kind == GraphNodeKind.day) continue;
    final xs = neighbourDayX[node.path];
    final x = (xs == null || xs.isEmpty)
        ? w / 2
        : xs.reduce((a, b) => a + b) / xs.length;
    final bucket = (x / 44).round();
    final used = laneCount[bucket] ?? 0;
    laneCount[bucket] = used + 1;
    final ring = (used ~/ 2) + 1;
    final y = h / 2 + (used.isEven ? 1 : -1) * ring * 48.0;
    pos[node.path] = Offset(x, y.clamp(24.0, h - 24));
  }
  return pos;
}

Map<String, Offset> graphPositions(
  NoteGraph graph,
  String? focalPath,
  Size size,
) {
  final nodes = graph.nodes;
  if (nodes.isEmpty) return const {};
  if (isTimelineGraph(graph)) return timelinePositions(graph, size);
  final w = size.width.isFinite && size.width > 0 ? size.width : 1000.0;
  final h = size.height.isFinite && size.height > 0 ? size.height : 1000.0;
  return forceLayoutPositions(graph, Size(w, h));
}

/// The community label a graph node belongs to, or null if unassigned: note
/// nodes resolve by path, concept hubs by their tag (the node title).
String? clusterLabelOf(GraphNode node, CommunityMap communities) {
  switch (node.kind) {
    case GraphNodeKind.concept:
      return communities.tagToCluster[node.title];
    case GraphNodeKind.note:
      return communities.noteToCluster[node.path];
    case GraphNodeKind.work:
    case GraphNodeKind.day:
      return null;
  }
}

/// A per-node cluster index (into [CommunityMap.clusterOrder]) aligned to
/// [nodes]; -1 for unassigned nodes. Isolate-safe primitive for the layout.
Int32List clusterIdsForNodes(List<GraphNode> nodes, CommunityMap communities) {
  final slot = {
    for (var i = 0; i < communities.clusterOrder.length; i++)
      communities.clusterOrder[i]: i,
  };
  final out = Int32List(nodes.length);
  for (var i = 0; i < nodes.length; i++) {
    final label = clusterLabelOf(nodes[i], communities);
    out[i] = label == null ? -1 : (slot[label] ?? -1);
  }
  return out;
}

/// Below this zoom scale the graph collapses each community into a single
/// "zone + core" glyph; at or above it, individual nodes render.
/// ponytail: tuned so the default `_fit` (whole-graph) view starts collapsed.
const kLodZoomThreshold = 0.6;

/// On-screen px for zone labels; divided by the live zoom so they stay a
/// constant readable size however far the view is zoomed out.
const kZoneLabelPx = 13.0;

/// A community collapsed to one glyph for the zoomed-out (LOD) view.
@immutable
class ClusterAgg {
  const ClusterAgg({
    required this.label,
    required this.colorSlot,
    required this.core,
    required this.radius,
    required this.count,
  });

  final String label; // community name (its dominant tag)
  final int colorSlot; // index into CommunityMap.clusterOrder → color hue
  final Offset core; // centroid of member positions
  final double radius; // encloses the members → the zone size
  final int count; // member node count
}

/// One [ClusterAgg] per community that has positioned members — a couple of
/// cheap passes over the nodes. Feeds the collapsed LOD render + its tap targets.
List<ClusterAgg> clusterAggregates(
  NoteGraph graph,
  Map<String, Offset> positions,
  CommunityMap communities,
) {
  final slot = {
    for (var i = 0; i < communities.clusterOrder.length; i++)
      communities.clusterOrder[i]: i,
  };
  final members = <String, List<Offset>>{};
  for (final node in graph.nodes) {
    final label = clusterLabelOf(node, communities);
    if (label == null) continue;
    if (positions[node.path] case final p?) {
      members.putIfAbsent(label, () => []).add(p);
    }
  }
  final out = <ClusterAgg>[];
  for (final label in communities.clusterOrder) {
    final pts = members[label];
    if (pts == null || pts.isEmpty) continue;
    var cx = 0.0, cy = 0.0;
    for (final p in pts) {
      cx += p.dx;
      cy += p.dy;
    }
    final core = Offset(cx / pts.length, cy / pts.length);
    var maxD = 0.0;
    for (final p in pts) {
      maxD = math.max(maxD, (p - core).distance);
    }
    out.add(
      ClusterAgg(
        label: label,
        colorSlot: slot[label] ?? 0,
        core: core,
        radius: maxD + 28, // pad so the zone encloses the outermost node dot
        count: pts.length,
      ),
    );
  }
  return out;
}

/// Force-directs only the *connected* nodes (edge-less "isolated" ones would
/// otherwise be flung to the frame border), and lays the isolated nodes in a
/// tidy grid strip at the bottom — so the view reads as a clustered core plus a
/// labelled shelf of unrelated topics.
Map<String, Offset> forceLayoutPositions(
  NoteGraph graph,
  Size canvas, {
  CommunityMap? communities,
}) {
  final w = canvas.width;
  final h = canvas.height;
  final degree = <String, int>{};
  for (final e in graph.edges) {
    degree[e.from] = (degree[e.from] ?? 0) + 1;
    degree[e.to] = (degree[e.to] ?? 0) + 1;
  }
  final connected = [
    for (final n in graph.nodes)
      if ((degree[n.path] ?? 0) > 0) n,
  ];
  final isolated = [
    for (final n in graph.nodes)
      if ((degree[n.path] ?? 0) == 0) n,
  ]..sort((a, b) => a.path.compareTo(b.path));

  final cols = math.max(1, (w / 96).floor());
  final gridRows = isolated.isEmpty ? 0 : (isolated.length / cols).ceil();
  final gridH = gridRows == 0 ? 0.0 : gridRows * 46.0 + 24;
  final mainH = math.max(240.0, h - gridH);

  final index = {for (var i = 0; i < connected.length; i++) connected[i].path: i};
  // Edges + parallel weights over the connected set, built in lockstep.
  final edges = <(int, int)>[];
  final weightList = <double>[];
  for (final e in graph.edges) {
    final a = index[e.from];
    final b = index[e.to];
    if (a == null || b == null) continue;
    edges.add((a, b));
    weightList.add(e.weight.toDouble());
  }
  final flat = forceDirectedFlat(
    connected.length,
    edges,
    w,
    mainH,
    iterationsFor(connected.length),
    clusterId: communities == null
        ? null
        : clusterIdsForNodes(connected, communities),
    edgeWeight: communities == null ? null : Float64List.fromList(weightList),
  );
  final pos = <String, Offset>{
    for (var i = 0; i < connected.length; i++)
      connected[i].path: Offset(flat[2 * i], flat[2 * i + 1]),
  };
  for (var i = 0; i < isolated.length; i++) {
    final r = i ~/ cols;
    final c = i % cols;
    pos[isolated[i].path] = Offset(48 + c * 96, mainH + 24 + r * 46);
  }
  return normalizePositions(pos);
}

/// Shifts positions so the top-left of the layout sits at a fixed pad — keeps
/// everything positive and lets [boundsCanvas] size the canvas to the content.
Map<String, Offset> normalizePositions(Map<String, Offset> pos) {
  if (pos.isEmpty) return pos;
  var minX = double.infinity, minY = double.infinity;
  for (final o in pos.values) {
    minX = math.min(minX, o.dx);
    minY = math.min(minY, o.dy);
  }
  const pad = 60.0;
  return {
    for (final e in pos.entries)
      e.key: Offset(e.value.dx - minX + pad, e.value.dy - minY + pad),
  };
}

/// A canvas that just encloses normalized [pos] (top-left already padded).
Size boundsCanvas(Map<String, Offset> pos) {
  if (pos.isEmpty) return const Size(1000, 1000);
  var maxX = 0.0, maxY = 0.0;
  for (final o in pos.values) {
    maxX = math.max(maxX, o.dx);
    maxY = math.max(maxY, o.dy);
  }
  return Size(maxX + 60, maxY + 60);
}

/// A square canvas that grows with node count so a force layout has room to
/// spread (no ring radii any more).
Size graphCanvasSize(NoteGraph graph, String? focalPath, Size viewport) {
  final n = graph.nodes.length;
  if (n == 0) return viewport;
  if (isTimelineGraph(graph)) {
    final days = graph.nodes.where((x) => x.kind == GraphNodeKind.day).length;
    return Size(
      math.max(viewport.width, days * 150 + 200),
      math.max(viewport.height, 900),
    );
  }
  final dim = math.max(
    math.max(viewport.width, viewport.height),
    math.sqrt(n) * 160,
  );
  return Size.square(dim);
}

/// Fewer iterations for big graphs so `All files` (~1700+) stays affordable.
int iterationsFor(int n) => n > 600 ? 60 : 120;

/// Fruchterman–Reingold layout. Pure + deterministically seeded, so it can run
/// in a background isolate and never jitters between rebuilds. O(n²·iterations);
/// returns a flat `[x0,y0,x1,y1,…]` (isolate-sendable) for `n` nodes in a
/// `width × height` frame. `edges` are index pairs into the node list.
/// ponytail: O(n²) repulsion; fine to ~2k nodes. For 10k, switch to Barnes–Hut.
Float64List forceDirectedFlat(
  int n,
  List<(int, int)> edges,
  double width,
  double height,
  int iterations, {
  Int32List? clusterId,
  Float64List? edgeWeight,
}) {
  final out = Float64List(2 * n);
  if (n == 0) return out;
  if (n == 1) {
    out[0] = width / 2;
    out[1] = height / 2;
    return out;
  }
  final rng = math.Random(42);
  final k = math.sqrt(width * height / n); // ideal node spacing
  final cx = width / 2;
  final cy = height / 2;
  final px = Float64List(n);
  final py = Float64List(n);

  // Map raw cluster ids (indices into clusterOrder, may be sparse) to dense
  // slots 0..K-1 in first-seen order, and place each slot centroid on a ring so
  // same-cluster nodes seed together instead of on one global index ring.
  final clustered = clusterId != null;
  final slotOf = <int, int>{};
  if (clustered) {
    for (var i = 0; i < n; i++) {
      final c = clusterId[i];
      if (c >= 0) slotOf.putIfAbsent(c, () => slotOf.length);
    }
  }
  final clusterCount = math.max(1, slotOf.length);
  final seedX = Float64List(clusterCount);
  final seedY = Float64List(clusterCount);
  if (clustered) {
    final radius = math.min(width, height) / 3;
    for (var g = 0; g < clusterCount; g++) {
      final a = 2 * math.pi * g / clusterCount;
      seedX[g] = cx + math.cos(a) * radius;
      seedY[g] = cy + math.sin(a) * radius;
    }
  }

  for (var i = 0; i < n; i++) {
    if (clustered && clusterId[i] >= 0) {
      final g = slotOf[clusterId[i]]!;
      px[i] = seedX[g] + (rng.nextDouble() - 0.5) * k;
      py[i] = seedY[g] + (rng.nextDouble() - 0.5) * k;
    } else if (clustered) {
      px[i] = cx + (rng.nextDouble() - 0.5) * width / 3;
      py[i] = cy + (rng.nextDouble() - 0.5) * height / 3;
    } else {
      final a = 2 * math.pi * i / n;
      px[i] = cx + math.cos(a) * width / 3 + rng.nextDouble();
      py[i] = cy + math.sin(a) * height / 3 + rng.nextDouble();
    }
  }
  final dx = Float64List(n);
  final dy = Float64List(n);
  var temp = width / 10;
  for (var iter = 0; iter < iterations; iter++) {
    for (var i = 0; i < n; i++) {
      dx[i] = 0;
      dy[i] = 0;
    }
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var ddx = px[i] - px[j];
        var ddy = py[i] - py[j];
        var dist = math.sqrt(ddx * ddx + ddy * ddy);
        if (dist < 0.01) {
          ddx = rng.nextDouble() - 0.5;
          ddy = rng.nextDouble() - 0.5;
          dist = 0.01;
        }
        final rep = k * k / dist; // repulsion
        final fx = ddx / dist * rep;
        final fy = ddy / dist * rep;
        dx[i] += fx;
        dy[i] += fy;
        dx[j] -= fx;
        dy[j] -= fy;
      }
    }
    for (var ei = 0; ei < edges.length; ei++) {
      final (a, b) = edges[ei];
      var ddx = px[a] - px[b];
      var ddy = py[a] - py[b];
      var dist = math.sqrt(ddx * ddx + ddy * ddy);
      if (dist < 0.01) dist = 0.01;
      var att = dist * dist / k; // attraction along edges
      // Stronger ties (higher co-occurrence weight) pull their endpoints tighter,
      // which packs dense communities into visible blobs. weight>=1 ⇒ factor>=1.
      if (edgeWeight != null) att *= 1 + math.log(math.max(1, edgeWeight[ei]));
      final fx = ddx / dist * att;
      final fy = ddy / dist * att;
      dx[a] -= fx;
      dy[a] -= fy;
      dx[b] += fx;
      dy[b] += fy;
    }
    if (clustered) {
      // Per-cluster gravity: recompute each cluster's centroid, pull its members
      // toward it so communities contract into separated agglomerations. A weak
      // global pull keeps the whole layout bounded on the canvas.
      final gx = Float64List(clusterCount);
      final gy = Float64List(clusterCount);
      final gc = Int32List(clusterCount);
      for (var i = 0; i < n; i++) {
        final c = clusterId[i];
        if (c < 0) continue;
        final g = slotOf[c]!;
        gx[g] += px[i];
        gy[g] += py[i];
        gc[g]++;
      }
      for (var g = 0; g < clusterCount; g++) {
        if (gc[g] > 0) {
          gx[g] /= gc[g];
          gy[g] /= gc[g];
        }
      }
      const clusterGravity = 0.09;
      const globalGravity = 0.01;
      for (var i = 0; i < n; i++) {
        final c = clusterId[i];
        if (c >= 0) {
          final g = slotOf[c]!;
          dx[i] += (gx[g] - px[i]) * clusterGravity;
          dy[i] += (gy[g] - py[i]) * clusterGravity;
        }
        dx[i] += (cx - px[i]) * globalGravity;
        dy[i] += (cy - py[i]) * globalGravity;
      }
    } else {
      // Gentle centre gravity so edge-less nodes settle in a loose cloud around
      // the connected core instead of being flung to the frame border.
      const gravity = 0.04;
      for (var i = 0; i < n; i++) {
        dx[i] += (cx - px[i]) * gravity;
        dy[i] += (cy - py[i]) * gravity;
      }
    }
    for (var i = 0; i < n; i++) {
      final d = math.sqrt(dx[i] * dx[i] + dy[i] * dy[i]);
      if (d > 0) {
        final lim = math.min(d, temp);
        // No clamp: centre gravity keeps the layout bounded, and the caller
        // fits the canvas to the actual result (so nothing piles on a border).
        px[i] += dx[i] / d * lim;
        py[i] += dy[i] / d * lim;
      }
    }
    temp *= 0.95; // cool
  }
  for (var i = 0; i < n; i++) {
    out[2 * i] = px[i];
    out[2 * i + 1] = py[i];
  }
  return out;
}

/// Isolate-sendable layout request (primitives only).
@immutable
class LayoutRequest {
  const LayoutRequest(
    this.nodeCount,
    this.edges,
    this.width,
    this.height,
    this.iterations, {
    this.clusterId,
    this.edgeWeight,
  });
  final int nodeCount;
  final List<(int, int)> edges;
  final double width;
  final double height;
  final int iterations;
  final Int32List? clusterId;
  final Float64List? edgeWeight;
}

/// Top-level entry for `compute()` — runs the layout off the UI thread.
Float64List runForceLayout(LayoutRequest r) => forceDirectedFlat(
  r.nodeCount,
  r.edges,
  r.width,
  r.height,
  r.iterations,
  clusterId: r.clusterId,
  edgeWeight: r.edgeWeight,
);

class GraphPainter extends CustomPainter {
  GraphPainter({
    required this.graph,
    required this.positions,
    required this.selectedPath,
    required this.colorScheme,
    required this.onSelect,
    required this.transform,
    required this.viewport,
    this.visibleEdgeKinds = const {
      GraphEdgeKind.link,
      GraphEdgeKind.citation,
      GraphEdgeKind.tag,
      GraphEdgeKind.read,
    },
    this.communities,
    this.clusters,
  }) : super(repaint: transform);

  static const nodeRadius = 22.0;
  static const minimumNodeSpacing = 60.0;

  final NoteGraph graph;
  final Map<String, Offset> positions;
  final String? selectedPath;
  final ColorScheme colorScheme;
  final ValueChanged<String> onSelect;
  final Set<GraphEdgeKind> visibleEdgeKinds;

  /// When set, nodes are tinted by their community so agglomerations read as
  /// distinct color groups (null ⇒ the kind-based coloring).
  final CommunityMap? communities;

  /// Collapsed-view aggregates. When non-null and the view is zoomed out past
  /// [kLodZoomThreshold], each community draws as one zone glyph instead of its
  /// nodes. Null ⇒ always draw individual nodes.
  final List<ClusterAgg>? clusters;

  /// Live view transform (also the repaint signal) — lets `paint` read the
  /// current zoom to pick the LOD and to keep zone labels a constant size.
  final TransformationController transform;

  /// Viewport size, for culling off-screen nodes when zoomed in.
  final Size viewport;

  /// Concept/work hubs render larger than note dots so they read as hubs.
  static double _radiusFor(GraphNode node) =>
      node.kind == GraphNodeKind.note ? 12.0 : nodeRadius;

  /// A stable, evenly-spread hue for community [slot] of [total]. Saturation/
  /// value are tuned per theme so tints stay legible on light and dark.
  Color _colorForSlot(int slot, int total) {
    final hue = (slot * 360.0 / math.max(1, total)) % 360;
    final dark = colorScheme.brightness == Brightness.dark;
    return HSVColor.fromAHSV(1, hue, dark ? 0.42 : 0.40, dark ? 0.55 : 0.82)
        .toColor();
  }

  Color? _clusterColor(GraphNode node) {
    final c = communities;
    if (c == null || c.clusterOrder.isEmpty) return null;
    final label = clusterLabelOf(node, c);
    if (label == null) return null;
    final slot = c.clusterOrder.indexOf(label);
    if (slot < 0) return null;
    return _colorForSlot(slot, c.clusterOrder.length);
  }

  /// Visible region in canvas coords, from the translate+scale view transform
  /// (no rotation), padded so nodes near the edge aren't popped.
  Rect _cullRect() {
    final m = transform.value;
    final s = m.getMaxScaleOnAxis();
    if (s <= 0) return Rect.largest;
    final tx = m.storage[12];
    final ty = m.storage[13];
    return Rect.fromLTRB(
      (0 - tx) / s,
      (0 - ty) / s,
      (viewport.width - tx) / s,
      (viewport.height - ty) / s,
    ).inflate(160);
  }

  /// Collapsed LOD: one translucent zone + solid core + `name · N` label per
  /// community, plus unclustered nodes as faint dots. [scale] keeps labels a
  /// constant on-screen size.
  void _paintZones(Canvas canvas, double scale) {
    final aggs = clusters!;
    final total = communities!.clusterOrder.length;

    // Unclustered ("isolated topics") nodes first, as faint dots under the zones
    // — they're already summarised by the "N isolated topics" chip, so keep them
    // quiet. Drawn before zones so a zone's tint sits on top of any overlap.
    final c = communities!;
    for (final node in graph.nodes) {
      if (clusterLabelOf(node, c) != null) continue;
      if (positions[node.path] case final center?) {
        canvas.drawCircle(
          center,
          4,
          Paint()..color = colorScheme.outline.withValues(alpha: 0.28),
        );
      }
    }

    // Zones + cores (translucent areas may overlap harmlessly).
    for (final agg in aggs) {
      final color = _colorForSlot(agg.colorSlot, total);
      canvas.drawCircle(
        agg.core,
        agg.radius,
        Paint()..color = color.withValues(alpha: 0.16),
      );
      canvas.drawCircle(
        agg.core,
        agg.radius,
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale,
      );
      canvas.drawCircle(agg.core, nodeRadius, Paint()..color = color);
    }

    // Labels last, biggest community first (aggs are ordered largest→smallest),
    // greedily skipping any that would collide with one already placed. Rects are
    // constant on-screen size, so zooming in naturally reveals more labels.
    // ponytail: greedy O(kept²) placement; fine for dozens of clusters.
    final placed = <Rect>[];
    for (final agg in aggs) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${agg.label} · ${agg.count}',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: kZoneLabelPx / scale,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(agg.radius * 2, 120 / scale));
      final topLeft = agg.core + Offset(-tp.width / 2, agg.radius + 4 / scale);
      final rect = (topLeft & Size(tp.width, tp.height)).inflate(4 / scale);
      if (placed.any(rect.overlaps)) continue;
      placed.add(rect);
      // Faint backing plate so a label stays readable over a zone tint.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(4 / scale)),
        Paint()..color = colorScheme.surface.withValues(alpha: 0.72),
      );
      tp.paint(canvas, topLeft);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = transform.value.getMaxScaleOnAxis();
    final aggs = clusters;
    if (communities != null &&
        aggs != null &&
        aggs.length >= 2 &&
        scale < kLodZoomThreshold) {
      _paintZones(canvas, scale);
      return;
    }
    final cull = _cullRect();
    for (final edge in graph.edges) {
      if (!visibleEdgeKinds.contains(edge.kind)) continue;
      final from = positions[edge.from];
      final to = positions[edge.to];
      if (from == null || to == null) continue;
      if (!cull.contains(from) && !cull.contains(to)) continue;
      final connected = edge.from == selectedPath || edge.to == selectedPath;
      final paint = Paint()
        ..color = connected
            ? colorScheme.primary
            : _edgeColor(
                edge.kind,
                colorScheme.brightness,
              ).withValues(alpha: connected ? 1 : 0.45)
        ..strokeWidth = connected ? 2.5 : 1;
      if (edge.kind == GraphEdgeKind.citation) {
        _drawDashedLine(canvas, from, to, paint);
      } else {
        canvas.drawLine(from, to, paint);
      }
    }

    final neighbors = <String>{};
    for (final edge in graph.edges) {
      if (!visibleEdgeKinds.contains(edge.kind)) continue;
      if (edge.from == selectedPath) neighbors.add(edge.to);
      if (edge.to == selectedPath) neighbors.add(edge.from);
    }
    for (final node in graph.nodes) {
      final center = positions[node.path];
      if (center == null) continue;
      if (!cull.contains(center)) continue;
      final selected = node.path == selectedPath;
      final related = selected || neighbors.contains(node.path);
      final isEntity = node.kind != GraphNodeKind.note;
      final radius = _radiusFor(node);
      final baseColor =
          _clusterColor(node) ??
          (isEntity
              ? colorScheme.tertiaryContainer
              : colorScheme.secondaryContainer);
      final fill = Paint()
        ..color = selected
            ? colorScheme.primary
            : baseColor.withValues(
                alpha: selectedPath == null || related ? 1 : 0.35,
              );
      final stroke = Paint()
        ..color = selected
            ? colorScheme.primary
            : (isEntity ? colorScheme.tertiary : colorScheme.outline)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 1;
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, stroke);
      if (node.problemCount > 0) {
        canvas.drawCircle(
          center,
          radius + 3,
          Paint()
            ..color = colorScheme.error
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      // Note labels appear only near the selection to cut clutter; concept/work
      // hubs are always labelled so the map reads as a set of named topics.
      if (!related && !isEntity) continue;
      final title = node.title.length > 18
          ? '${node.title.substring(0, 17)}…'
          : node.title;
      // Concept/work hubs carry an article-count badge (e.g. "esp32 · 31").
      final label = isEntity && node.count > 0 ? '$title · ${node.count}' : title;
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 96);
      textPainter.paint(
        canvas,
        center + Offset(-textPainter.width / 2, radius + 4),
      );
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final node in graph.nodes)
          if (positions[node.path] case final center?)
            CustomPainterSemantics(
              rect: Rect.fromCircle(center: center, radius: nodeRadius + 8),
              properties: SemanticsProperties(
                label: node.problemCount > 0
                    ? '${node.title} (${node.problemCount} problems)'
                    : node.title,
                textDirection: TextDirection.ltr,
                button: true,
                selected: node.path == selectedPath,
                onTap: () => onSelect(node.path),
              ),
            ),
      ];

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) =>
      graph != oldDelegate.graph ||
      positions != oldDelegate.positions ||
      selectedPath != oldDelegate.selectedPath ||
      colorScheme != oldDelegate.colorScheme ||
      clusters != oldDelegate.clusters ||
      viewport != oldDelegate.viewport ||
      !setEquals(visibleEdgeKinds, oldDelegate.visibleEdgeKinds);

  @override
  bool shouldRebuildSemantics(covariant GraphPainter oldDelegate) =>
      graph != oldDelegate.graph ||
      positions != oldDelegate.positions ||
      selectedPath != oldDelegate.selectedPath;
}

Color _edgeColor(GraphEdgeKind kind, Brightness brightness) =>
    brightness == Brightness.dark
    ? switch (kind) {
        GraphEdgeKind.link => const Color(0xFFE0E0E0),
        GraphEdgeKind.citation => const Color(0xFFC5CAE9),
        GraphEdgeKind.tag => const Color(0xFFB2DFDB),
        GraphEdgeKind.read => const Color(0xFF80CBC4), // read-on-day = teal
      }
    : switch (kind) {
        GraphEdgeKind.link => const Color(0xFF9E9E9E),
        GraphEdgeKind.citation => const Color(0xFF7986CB),
        GraphEdgeKind.tag => const Color(0xFF4DB6AC),
        GraphEdgeKind.read => const Color(0xFF00897B),
      };

void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
  const dashLength = 6.0;
  const gapLength = 4.0;
  final total = (to - from).distance;
  if (total == 0) return;
  final direction = (to - from) / total;
  var drawn = 0.0;
  while (drawn < total) {
    final segmentEnd = math.min(drawn + dashLength, total);
    canvas.drawLine(
      from + direction * drawn,
      from + direction * segmentEnd,
      paint,
    );
    drawn = segmentEnd + gapLength;
  }
}

/// Tappable legend that doubles as an edge-kind visibility filter.
class GraphLegend extends StatelessWidget {
  const GraphLegend({
    super.key,
    required this.visibleKinds,
    required this.onToggle,
  });

  final Set<GraphEdgeKind> visibleKinds;
  final ValueChanged<GraphEdgeKind> onToggle;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      _LegendEntry(
        kind: GraphEdgeKind.link,
        color: _edgeColor(GraphEdgeKind.link, Theme.of(context).brightness),
        label: 'Link',
        selected: visibleKinds.contains(GraphEdgeKind.link),
        onToggle: onToggle,
      ),
      _LegendEntry(
        kind: GraphEdgeKind.citation,
        color: _edgeColor(GraphEdgeKind.citation, Theme.of(context).brightness),
        label: 'Citation',
        dashed: true,
        selected: visibleKinds.contains(GraphEdgeKind.citation),
        onToggle: onToggle,
      ),
      _LegendEntry(
        kind: GraphEdgeKind.tag,
        color: _edgeColor(GraphEdgeKind.tag, Theme.of(context).brightness),
        label: 'Tag',
        selected: visibleKinds.contains(GraphEdgeKind.tag),
        onToggle: onToggle,
      ),
    ],
  );
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.kind,
    required this.color,
    required this.label,
    required this.selected,
    required this.onToggle,
    this.dashed = false,
  });

  final GraphEdgeKind kind;
  final Color color;
  final String label;
  final bool selected;
  final bool dashed;
  final ValueChanged<GraphEdgeKind> onToggle;

  @override
  Widget build(BuildContext context) => FilterChip(
    avatar: SizedBox(
      width: 16,
      height: 10,
      child: CustomPaint(
        painter: _SwatchPainter(color: color, dashed: dashed),
      ),
    ),
    label: Text(label),
    labelStyle: Theme.of(context).textTheme.labelSmall,
    visualDensity: VisualDensity.compact,
    selected: selected,
    onSelected: (_) => onToggle(kind),
  );
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final y = size.height / 2;
    final from = Offset(0, y);
    final to = Offset(size.width, y);
    if (dashed) {
      _drawDashedLine(canvas, from, to, paint);
    } else {
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter oldDelegate) =>
      color != oldDelegate.color || dashed != oldDelegate.dashed;
}
