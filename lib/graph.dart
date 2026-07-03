import 'dart:math' as math;

import 'package:flutter/material.dart';

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

class GraphView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (graph.nodes.isEmpty) {
      return const Center(child: Text('Graph is empty'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final positions = graphPositions(graph.nodes, size);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final hit = _hitNode(positions, details.localPosition);
            if (hit != null) onOpenPath(hit);
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: GraphPainter(
              graph: graph,
              positions: positions,
              currentPath: currentPath,
              colorScheme: Theme.of(context).colorScheme,
            ),
          ),
        );
      },
    );
  }

  String? _hitNode(Map<String, Offset> positions, Offset point) {
    for (final entry in positions.entries) {
      if ((entry.value - point).distance <= GraphPainter.nodeRadius + 8) {
        return entry.key;
      }
    }
    return null;
  }
}

Map<String, Offset> graphPositions(List<GraphNode> nodes, Size size) {
  final usableWidth = size.width.isFinite ? size.width : 0.0;
  final usableHeight = size.height.isFinite ? size.height : 0.0;
  final center = Offset(usableWidth / 2, usableHeight / 2);
  if (nodes.isEmpty) return const {};
  if (nodes.length == 1) return {nodes.first.path: center};

  final radius = math.max(
    56.0,
    math.min(usableWidth, usableHeight) / 2 - GraphPainter.nodeRadius - 24,
  );
  final positions = <String, Offset>{};
  for (var i = 0; i < nodes.length; i++) {
    final angle = -math.pi / 2 + 2 * math.pi * i / nodes.length;
    positions[nodes[i].path] = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
  }
  return positions;
}

class GraphPainter extends CustomPainter {
  const GraphPainter({
    required this.graph,
    required this.positions,
    required this.currentPath,
    required this.colorScheme,
  });

  static const nodeRadius = 22.0;

  final NoteGraph graph;
  final Map<String, Offset> positions;
  final String? currentPath;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1.5;
    for (final edge in graph.edges) {
      final from = positions[edge.from];
      final to = positions[edge.to];
      if (from == null || to == null) continue;
      canvas.drawLine(from, to, edgePaint);
    }

    for (final node in graph.nodes) {
      final center = positions[node.path];
      if (center == null) continue;
      final selected = node.path == currentPath;
      final fill = Paint()
        ..color = selected
            ? colorScheme.primary
            : colorScheme.secondaryContainer;
      final stroke = Paint()
        ..color = selected ? colorScheme.primary : colorScheme.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 1;
      canvas.drawCircle(center, nodeRadius, fill);
      canvas.drawCircle(center, nodeRadius, stroke);

      final label = node.title.length > 18
          ? '${node.title.substring(0, 17)}…'
          : node.title;
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
            fontSize: 11,
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
  bool shouldRepaint(covariant GraphPainter oldDelegate) =>
      graph != oldDelegate.graph ||
      positions != oldDelegate.positions ||
      currentPath != oldDelegate.currentPath ||
      colorScheme != oldDelegate.colorScheme;
}
