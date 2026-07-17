import 'models.dart';

enum GraphEdgeKind { link, citation, tag }

/// Co-occurrence keys shared by more than this many notes are skipped —
/// a generic tag shouldn't fan out into an O(n^2) edge cloud.
const _coOccurrenceCap = 30;

class GraphNode {
  const GraphNode({
    required this.path,
    required this.title,
    this.problemCount = 0,
  });

  final String path;
  final String title;
  final int problemCount;
}

class GraphEdge {
  const GraphEdge({
    required this.from,
    required this.to,
    this.kind = GraphEdgeKind.link,
    this.weight = 1,
  });

  final String from;
  final String to;
  final GraphEdgeKind kind;
  final int weight;
}

class NoteGraph {
  const NoteGraph({required this.nodes, required this.edges});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
}

NoteGraph buildNoteGraph(VaultIndex index) {
  final problemCounts = <String, int>{};
  for (final problem in index.problems) {
    problemCounts.update(
      problem.subject,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  final nodes = index.notes
      .map(
        (note) => GraphNode(
          path: note.path,
          title: note.title,
          problemCount: problemCounts[note.path] ?? 0,
        ),
      )
      .toList();

  final edges = <GraphEdge>[
    for (final entry in index.backlinksByTarget.entries)
      for (final source in entry.value)
        GraphEdge(from: source, to: entry.key),
    ..._coOccurrenceEdges(
      index.notes,
      (note) => note.citations,
      GraphEdgeKind.citation,
    ),
    ..._coOccurrenceEdges(index.notes, (note) => note.tags, GraphEdgeKind.tag),
  ];
  edges.sort((a, b) {
    final byFrom = a.from.compareTo(b.from);
    if (byFrom != 0) return byFrom;
    final byTo = a.to.compareTo(b.to);
    if (byTo != 0) return byTo;
    return a.kind.index.compareTo(b.kind.index);
  });
  return NoteGraph(nodes: nodes, edges: edges);
}

/// Emits one edge per pair of notes that share a key returned by
/// [keyOf] (e.g. a tag or citation), weighted by how many keys they share.
List<GraphEdge> _coOccurrenceEdges(
  Iterable<NoteRef> notes,
  Iterable<String> Function(NoteRef note) keyOf,
  GraphEdgeKind kind,
) {
  final pathsByKey = <String, Set<String>>{};
  for (final note in notes) {
    for (final key in keyOf(note)) {
      pathsByKey.putIfAbsent(key, () => {}).add(note.path);
    }
  }
  final weightByPair = <(String, String), int>{};
  for (final paths in pathsByKey.values) {
    if (paths.length < 2 || paths.length > _coOccurrenceCap) continue;
    final sorted = paths.toList()..sort();
    for (var i = 0; i < sorted.length; i++) {
      for (var j = i + 1; j < sorted.length; j++) {
        final pairKey = (sorted[i], sorted[j]);
        weightByPair.update(
          pairKey,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }
  return [
    for (final entry in weightByPair.entries)
      GraphEdge(
        from: entry.key.$1,
        to: entry.key.$2,
        kind: kind,
        weight: entry.value,
      ),
  ];
}

NoteGraph buildLocalNoteGraph(
  VaultIndex index,
  String? currentPath, {
  int hops = 2,
  int limit = 100,
}) {
  if (currentPath == null) {
    return const NoteGraph(nodes: [], edges: []);
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
  return restrictNoteGraph(full, selected);
}

/// Restricts [graph] to just the nodes in [paths] (and edges between them).
NoteGraph restrictNoteGraph(NoteGraph graph, Set<String> paths) => NoteGraph(
  nodes: graph.nodes.where((node) => paths.contains(node.path)).toList(),
  edges: graph.edges
      .where((edge) => paths.contains(edge.from) && paths.contains(edge.to))
      .toList(),
);

class GraphStats {
  const GraphStats({required this.orphanPaths, required this.hubPaths});

  final List<String> orphanPaths;
  final List<String> hubPaths;
}

/// Cheap degree-count diagnostics: notes with no edges at all ([orphanPaths],
/// sorted), and the top [hubLimit] most-connected notes ([hubPaths], ranked
/// by degree desc then path). No graph-theory beyond counting edges.
GraphStats computeGraphStats(NoteGraph graph, {int hubLimit = 5}) {
  final degree = {for (final node in graph.nodes) node.path: 0};
  for (final edge in graph.edges) {
    degree[edge.from] = (degree[edge.from] ?? 0) + 1;
    degree[edge.to] = (degree[edge.to] ?? 0) + 1;
  }
  final orphans = degree.entries
      .where((entry) => entry.value == 0)
      .map((entry) => entry.key)
      .toList()
    ..sort();
  final ranked = degree.entries.where((entry) => entry.value > 0).toList()
    ..sort((a, b) {
      final byDegree = b.value.compareTo(a.value);
      return byDegree != 0 ? byDegree : a.key.compareTo(b.key);
    });
  return GraphStats(
    orphanPaths: orphans,
    hubPaths: ranked.take(hubLimit).map((entry) => entry.key).toList(),
  );
}
