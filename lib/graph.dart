import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'models.dart';
import 'scanner.dart';

class GraphNode {
  const GraphNode({required this.path, required this.title});

  final String path;
  final String title;
}

class GraphEdge {
  const GraphEdge({required this.from, required this.to});

  final String from;
  final String to;
}

class NoteGraph {
  const NoteGraph({required this.nodes, required this.edges});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
}

NoteGraph buildNoteGraph(VaultIndex index) {
  final resolver = LinkResolver(index.notes);
  final nodes = index.notes
      .map((note) => GraphNode(path: note.path, title: note.title))
      .toList();
  final edges = <GraphEdge>[];
  for (final source in index.notes) {
    for (final link in source.outgoingLinks) {
      final resolved = resolver.resolve(link);
      final target = resolved.status == LinkResolutionStatus.resolved
          ? resolved.path
          : null;
      if (target != null && index.notesByPath.containsKey(target)) {
        edges.add(GraphEdge(from: source.path, to: target));
      }
    }
  }
  edges.sort((a, b) {
    final byFrom = a.from.compareTo(b.from);
    return byFrom == 0 ? a.to.compareTo(b.to) : byFrom;
  });
  return NoteGraph(nodes: nodes, edges: edges);
}

NoteGraph buildLocalNoteGraph(
  VaultIndex index,
  String? currentPath, {
  int hops = 2,
  int limit = 100,
}) {
  if (currentPath == null || index.notes.length <= limit) {
    return buildNoteGraph(index);
  }
  final full = buildNoteGraph(index);
  final selected = <String>{currentPath};
  var frontier = <String>{currentPath};
  for (var hop = 0; hop < hops && selected.length < limit; hop++) {
    final next = <String>{};
    for (final edge in full.edges) {
      if (frontier.contains(edge.from)) next.add(edge.to);
      if (frontier.contains(edge.to)) next.add(edge.from);
    }
    next.removeAll(selected);
    for (final path in next.toList()..sort()) {
      if (selected.length == limit) break;
      selected.add(path);
    }
    frontier = next;
  }
  return NoteGraph(
    nodes: full.nodes.where((node) => selected.contains(node.path)).toList(),
    edges: full.edges
        .where(
          (edge) => selected.contains(edge.from) && selected.contains(edge.to),
        )
        .toList(),
  );
}

class GraphView extends StatefulWidget {
  const GraphView({
    super.key,
    required this.graph,
    required this.currentPath,
    required this.onOpenPath,
  });

  final NoteGraph graph;
  final String? currentPath;
  final ValueChanged<String> onOpenPath;

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> {
  final _transform = TransformationController();
  String? _selectedPath;
  Size? _lastViewport;
  Size? _lastCanvas;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.currentPath;
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
    final selected = widget.graph.nodes
        .where((node) => node.path == _selectedPath)
        .firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (selected != null)
          Material(
            color: scheme.surfaceContainerLow,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined),
              title: Text(selected.title, maxLines: 1),
              subtitle: Text(selected.path, maxLines: 1),
              trailing: FilledButton.tonalIcon(
                key: const Key('graph-open'),
                onPressed: () => widget.onOpenPath(selected.path),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open'),
              ),
            ),
          ),
        Expanded(child: _canvas(scheme)),
      ],
    );
  }

  Widget _canvas(ColorScheme scheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final canvas = graphCanvasSize(
          widget.graph,
          widget.currentPath,
          viewport,
        );
        final positions = graphPositions(
          widget.graph,
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
                    graph: widget.graph,
                    positions: positions,
                    selectedPath: _selectedPath,
                    colorScheme: scheme,
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
  });

  static const nodeRadius = 22.0;
  static const minimumNodeSpacing = 60.0;

  final NoteGraph graph;
  final Map<String, Offset> positions;
  final String? selectedPath;
  final ColorScheme colorScheme;
  final ValueChanged<String> onSelect;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in graph.edges) {
      final from = positions[edge.from];
      final to = positions[edge.to];
      if (from == null || to == null) continue;
      final connected = edge.from == selectedPath || edge.to == selectedPath;
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = connected
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.45)
          ..strokeWidth = connected ? 2.5 : 1,
      );
    }

    final neighbors = <String>{};
    for (final edge in graph.edges) {
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
                label: node.title,
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
      colorScheme != oldDelegate.colorScheme;

  @override
  bool shouldRebuildSemantics(covariant GraphPainter oldDelegate) =>
      graph != oldDelegate.graph ||
      positions != oldDelegate.positions ||
      selectedPath != oldDelegate.selectedPath;
}
