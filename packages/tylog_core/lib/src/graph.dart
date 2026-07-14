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
