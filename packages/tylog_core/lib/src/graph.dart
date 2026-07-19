import 'models.dart';

enum GraphEdgeKind { link, citation, tag, read }

/// A tag on fewer notes than this is a pure leaf (a hub node wired to a single
/// note connects nothing), so it is not promoted to a concept node in the note
/// graph. Real vaults carry thousands of one-off tags; dropping the leaves keeps
/// the graph about connections without losing any actual connectivity.
const kConceptMinNotes = 2;

/// Threshold for the aggregated concept-map overview — higher than
/// [kConceptMinNotes] so the map shows only substantial topics, not every pair.
const kConceptMapMinNotes = 5;

/// What a node represents. Notes are documents; concepts are tags promoted to
/// hubs; works are cited bibliographic entries. Concept/work nodes turn a tag
/// or citekey shared by k notes into a single k-spoke star instead of a
/// k*(k-1)/2 note-to-note edge cloud.
enum GraphNodeKind { note, concept, work, day }

class GraphNode {
  const GraphNode({
    required this.path,
    required this.title,
    this.kind = GraphNodeKind.note,
    this.problemCount = 0,
    this.count = 0,
  });

  final String path;
  final String title;
  final GraphNodeKind kind;
  final int problemCount;

  /// For concept/work hubs: how many notes carry this tag/citekey (drives the
  /// count badge and the concept-map overview). 0 for note nodes.
  final int count;
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
  final nodes = <GraphNode>[
    for (final note in index.notes)
      GraphNode(
        path: note.path,
        title: note.title,
        problemCount: problemCounts[note.path] ?? 0,
      ),
  ];

  final edges = <GraphEdge>[
    for (final entry in index.backlinksByTarget.entries)
      for (final source in entry.value)
        GraphEdge(from: source, to: entry.key),
  ];
  // Tags and citations become their own hub nodes with note->entity spokes,
  // rather than fanning every co-occurring pair of notes into a clique. Single-
  // note tags are dropped (leaf hubs that connect nothing).
  _addEntityNodes(
    index.notes,
    (note) => note.tags,
    GraphNodeKind.concept,
    'concept',
    GraphEdgeKind.tag,
    nodes,
    edges,
    minNotes: kConceptMinNotes,
  );
  _addEntityNodes(
    index.notes,
    (note) => note.citations,
    GraphNodeKind.work,
    'cite',
    GraphEdgeKind.citation,
    nodes,
    edges,
  );
  edges.sort((a, b) {
    final byFrom = a.from.compareTo(b.from);
    if (byFrom != 0) return byFrom;
    final byTo = a.to.compareTo(b.to);
    if (byTo != 0) return byTo;
    return a.kind.index.compareTo(b.kind.index);
  });
  return NoteGraph(nodes: nodes, edges: edges);
}

/// Adds one hub node per distinct key returned by [keyOf] (a tag or citekey)
/// plus a note->hub edge per note carrying it. A key on k notes yields k edges,
/// not k*(k-1)/2. Hub node path is `<idPrefix>:<key>`; appended deterministically
/// (keys sorted) after the note nodes so ordering stays stable.
void _addEntityNodes(
  Iterable<NoteRef> notes,
  Iterable<String> Function(NoteRef note) keyOf,
  GraphNodeKind nodeKind,
  String idPrefix,
  GraphEdgeKind edgeKind,
  List<GraphNode> nodes,
  List<GraphEdge> edges, {
  int minNotes = 1,
}) {
  final notesByKey = <String, Set<String>>{};
  for (final note in notes) {
    for (final key in keyOf(note)) {
      notesByKey.putIfAbsent(key, () => {}).add(note.path);
    }
  }
  for (final key in notesByKey.keys.toList()..sort()) {
    final notePaths = notesByKey[key]!;
    if (notePaths.length < minNotes) continue;
    nodes.add(
      GraphNode(
        path: '$idPrefix:$key',
        title: key,
        kind: nodeKind,
        count: notePaths.length,
      ),
    );
    for (final notePath in notePaths.toList()..sort()) {
      edges.add(GraphEdge(from: notePath, to: '$idPrefix:$key', kind: edgeKind));
    }
  }
}

/// Aggregated concept-map overview: nodes are substantial concepts (tags on
/// >= [minNotes] notes) badged by article count; edges connect concepts that
/// co-occur on >= [minCoOccur] notes. Articles are not shown — the UI expands a
/// concept into its notes via [buildLocalNoteGraph] rooted at `concept:<tag>`.
/// At ~hundreds of concepts the O(concepts^2) co-occurrence pass is cheap.
/// ponytail: O(concepts^2); revisit only if the promoted-concept count explodes.
NoteGraph buildConceptMap(
  VaultIndex index, {
  int minNotes = kConceptMapMinNotes,
  int minCoOccur = 3,
}) {
  final notesByTag = <String, Set<String>>{};
  for (final note in index.notes) {
    for (final tag in note.tags) {
      notesByTag.putIfAbsent(tag, () => {}).add(note.path);
    }
  }
  final promoted = {
    for (final entry in notesByTag.entries)
      if (entry.value.length >= minNotes) entry.key: entry.value,
  };
  final keys = promoted.keys.toList()..sort();
  final nodes = [
    for (final key in keys)
      GraphNode(
        path: 'concept:$key',
        title: key,
        kind: GraphNodeKind.concept,
        count: promoted[key]!.length,
      ),
  ];
  final edges = <GraphEdge>[];
  for (var i = 0; i < keys.length; i++) {
    for (var j = i + 1; j < keys.length; j++) {
      final shared = promoted[keys[i]]!.intersection(promoted[keys[j]]!).length;
      if (shared >= minCoOccur) {
        edges.add(
          GraphEdge(
            from: 'concept:${keys[i]}',
            to: 'concept:${keys[j]}',
            kind: GraphEdgeKind.tag,
            weight: shared,
          ),
        );
      }
    }
  }
  return NoteGraph(nodes: nodes, edges: edges);
}

String _isoDay(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';

final _isoDayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}');

/// A time-perspective projection: day nodes linked to the articles *added* on
/// that day (`link` edge, from `note.date` or file mtime) and *read* on that day
/// (`read` edge, from [readDayByPath] — a path→`YYYY-MM-DD` map the app derives
/// from reading state). Bounded to the most recent [windowDays] active days so
/// it never becomes the whole corpus.
NoteGraph buildTimelineGraph(
  VaultIndex index,
  Map<String, String> readDayByPath, {
  int windowDays = 45,
}) {
  String? addedDay(NoteRef note) {
    final date = note.date;
    if (date != null && _isoDayPattern.hasMatch(date)) return date.substring(0, 10);
    final millis = note.modifiedMillis;
    if (millis != null) {
      return _isoDay(DateTime.fromMillisecondsSinceEpoch(millis));
    }
    return null;
  }

  final articles = index.notes.where((note) => note.kind == 'article');
  final addedByPath = <String, String>{};
  final activity = <String, int>{};
  for (final note in articles) {
    final added = addedDay(note);
    if (added != null) {
      addedByPath[note.path] = added;
      activity[added] = (activity[added] ?? 0) + 1;
    }
    final read = readDayByPath[note.path];
    if (read != null) activity[read] = (activity[read] ?? 0) + 1;
  }
  final allDays = activity.keys.toList()..sort();
  final window = allDays.length <= windowDays
      ? allDays.toSet()
      : allDays.sublist(allDays.length - windowDays).toSet();

  final edges = <GraphEdge>[];
  final usedDays = <String>{};
  final usedArticles = <String, NoteRef>{};
  for (final note in index.notes.where((n) => n.kind == 'article')) {
    final added = addedByPath[note.path];
    final read = readDayByPath[note.path];
    final inAdded = added != null && window.contains(added);
    final inRead = read != null && window.contains(read);
    if (!inAdded && !inRead) continue;
    usedArticles[note.path] = note;
    if (inAdded) {
      usedDays.add(added);
      edges.add(GraphEdge(from: 'day:$added', to: note.path));
    }
    if (inRead) {
      usedDays.add(read);
      edges.add(
        GraphEdge(from: 'day:$read', to: note.path, kind: GraphEdgeKind.read),
      );
    }
  }
  final nodes = <GraphNode>[
    for (final day in usedDays.toList()..sort())
      GraphNode(
        path: 'day:$day',
        title: day,
        kind: GraphNodeKind.day,
        count: activity[day] ?? 0,
      ),
    for (final note in usedArticles.values)
      GraphNode(path: note.path, title: note.title),
  ];
  edges.sort((a, b) {
    final byFrom = a.from.compareTo(b.from);
    return byFrom != 0 ? byFrom : a.to.compareTo(b.to);
  });
  return NoteGraph(nodes: nodes, edges: edges);
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
