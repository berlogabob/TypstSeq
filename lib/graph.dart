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
        GraphStats,
        NoteGraph,
        buildLocalNoteGraph,
        buildNoteGraph,
        computeGraphStats,
        restrictNoteGraph;

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
  });

  final NoteGraph graph;
  final String? currentPath;
  final ValueChanged<String> onOpenPath;
  final bool isWholeVault;
  final VoidCallback? onSwitchToFocused;

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> {
  final _transform = TransformationController();
  String? _selectedPath;
  Size? _lastViewport;
  Size? _lastCanvas;
  final Set<GraphEdgeKind> _visibleKinds = {
    GraphEdgeKind.link,
    GraphEdgeKind.citation,
    GraphEdgeKind.tag,
  };
  bool _dimWeakTagEdges = false;
  bool _bannerDismissed = false;
  Set<String>? _focusFilter;
  int _hubCycleIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.currentPath;
    _dimWeakTagEdges = widget.graph.nodes.length > _hairballThreshold;
  }

  @override
  void didUpdateWidget(covariant GraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPath != widget.currentPath) {
      _selectedPath = widget.currentPath;
      _lastCanvas = null;
    } else if (!_sameNodes(oldWidget.graph.nodes, widget.graph.nodes)) {
      _selectedPath =
          widget.graph.nodes.any((node) => node.path == _selectedPath)
          ? _selectedPath
          : widget.currentPath;
      _lastCanvas = null;
      _dimWeakTagEdges = widget.graph.nodes.length > _hairballThreshold;
      _focusFilter = null;
    }
  }

  @override
  void dispose() {
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
                  label: Text('${stats.orphanPaths.length} orphan notes'),
                  onPressed: () => setState(() {
                    _focusFilter = _focusFilter == null
                        ? stats.orphanPaths.toSet()
                        : null;
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
                  onDeleted: () => setState(() => _focusFilter = null),
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
        final canvas = graphCanvasSize(
          displayGraph,
          widget.currentPath,
          viewport,
        );
        final positions = graphPositions(
          displayGraph,
          widget.currentPath,
          canvas,
        );
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
                onTapUp: (details) {
                  final hit = _hitNode(positions, details.localPosition);
                  if (hit != null) setState(() => _selectedPath = hit);
                },
                child: CustomPaint(
                  size: canvas,
                  painter: GraphPainter(
                    graph: displayGraph,
                    positions: positions,
                    selectedPath: _selectedPath,
                    colorScheme: scheme,
                    visibleEdgeKinds: _visibleKinds,
                    minTagWeight: _dimWeakTagEdges ? 2 : 1,
                    onSelect: (path) => setState(() => _selectedPath = path),
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

Map<String, Offset> graphPositions(
  NoteGraph graph,
  String? focalPath,
  Size size,
) {
  final nodes = graph.nodes;
  final usableWidth = size.width.isFinite ? size.width : 0.0;
  final usableHeight = size.height.isFinite ? size.height : 0.0;
  final center = Offset(usableWidth / 2, usableHeight / 2);
  if (nodes.isEmpty) return const {};

  final rings = _graphRings(graph, focalPath);
  final root = rings[0]!.single;
  final positions = <String, Offset>{root: center};
  for (final entry in rings.entries.where((entry) => entry.key > 0)) {
    final ring = entry.value;
    final radius = _ringRadius(entry.key, ring.length);
    for (var i = 0; i < ring.length; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / ring.length;
      positions[ring[i]] = center + Offset.fromDirection(angle, radius);
    }
  }
  return positions;
}

Size graphCanvasSize(NoteGraph graph, String? focalPath, Size viewport) {
  if (graph.nodes.isEmpty) return viewport;
  final rings = _graphRings(graph, focalPath);
  final radius = rings.entries.fold(
    0.0,
    (largest, entry) =>
        math.max(largest, _ringRadius(entry.key, entry.value.length)),
  );
  final dimension = math.max(
    math.max(viewport.width, viewport.height),
    2 * (radius + GraphPainter.nodeRadius + 60),
  );
  return Size.square(dimension);
}

Map<int, List<String>> _graphRings(NoteGraph graph, String? focalPath) {
  final paths = graph.nodes.map((node) => node.path).toSet();
  final root = paths.contains(focalPath)
      ? focalPath!
      : (paths.toList()..sort()).first;
  final neighbors = {for (final path in paths) path: <String>{}};
  for (final edge in graph.edges) {
    if (paths.contains(edge.from) && paths.contains(edge.to)) {
      neighbors[edge.from]!.add(edge.to);
      neighbors[edge.to]!.add(edge.from);
    }
  }

  final distances = <String, int>{root: 0};
  var frontier = <String>{root};
  while (frontier.isNotEmpty) {
    final next = <String>{};
    for (final path in frontier) {
      for (final neighbor in neighbors[path]!) {
        if (!distances.containsKey(neighbor)) {
          distances[neighbor] = distances[path]! + 1;
          next.add(neighbor);
        }
      }
    }
    frontier = next;
  }
  final disconnectedRing = (distances.values.fold(0, math.max)) + 1;
  for (final path in paths) {
    distances.putIfAbsent(path, () => disconnectedRing);
  }

  final rings = <int, List<String>>{};
  for (final entry in distances.entries) {
    rings.putIfAbsent(entry.value, () => []).add(entry.key);
  }
  for (final ring in rings.values) {
    ring.sort();
  }
  return rings;
}

double _ringRadius(int depth, int nodes) => math.max(
  110.0 * depth,
  nodes * GraphPainter.minimumNodeSpacing / (2 * math.pi),
);

class GraphPainter extends CustomPainter {
  const GraphPainter({
    required this.graph,
    required this.positions,
    required this.selectedPath,
    required this.colorScheme,
    required this.onSelect,
    this.visibleEdgeKinds = const {
      GraphEdgeKind.link,
      GraphEdgeKind.citation,
      GraphEdgeKind.tag,
    },
    this.minTagWeight = 1,
  });

  static const nodeRadius = 22.0;
  static const minimumNodeSpacing = 60.0;

  final NoteGraph graph;
  final Map<String, Offset> positions;
  final String? selectedPath;
  final ColorScheme colorScheme;
  final ValueChanged<String> onSelect;
  final Set<GraphEdgeKind> visibleEdgeKinds;
  final int minTagWeight;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in graph.edges) {
      if (!visibleEdgeKinds.contains(edge.kind)) continue;
      if (edge.kind == GraphEdgeKind.tag && edge.weight < minTagWeight) {
        continue;
      }
      final from = positions[edge.from];
      final to = positions[edge.to];
      if (from == null || to == null) continue;
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
      if (edge.kind == GraphEdgeKind.tag && edge.weight < minTagWeight) {
        continue;
      }
      if (edge.from == selectedPath) neighbors.add(edge.to);
      if (edge.to == selectedPath) neighbors.add(edge.from);
    }
    for (final node in graph.nodes) {
      final center = positions[node.path];
      if (center == null) continue;
      final selected = node.path == selectedPath;
      final related = selected || neighbors.contains(node.path);
      final fill = Paint()
        ..color = selected
            ? colorScheme.primary
            : colorScheme.secondaryContainer.withValues(
                alpha: selectedPath == null || related ? 1 : 0.35,
              );
      final stroke = Paint()
        ..color = selected ? colorScheme.primary : colorScheme.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 1;
      canvas.drawCircle(center, nodeRadius, fill);
      canvas.drawCircle(center, nodeRadius, stroke);
      if (node.problemCount > 0) {
        canvas.drawCircle(
          center,
          nodeRadius + 3,
          Paint()
            ..color = colorScheme.error
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      if (!related) continue;
      final label = node.title.length > 18
          ? '${node.title.substring(0, 17)}…'
          : node.title;
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
        center + Offset(-textPainter.width / 2, nodeRadius + 4),
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
      !setEquals(visibleEdgeKinds, oldDelegate.visibleEdgeKinds) ||
      minTagWeight != oldDelegate.minTagWeight;

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
      }
    : switch (kind) {
        GraphEdgeKind.link => const Color(0xFF9E9E9E),
        GraphEdgeKind.citation => const Color(0xFF7986CB),
        GraphEdgeKind.tag => const Color(0xFF4DB6AC),
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
        label: 'Shared tag',
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
