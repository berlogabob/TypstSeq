import 'models.dart';

class TreePosition {
  const TreePosition(this.x, this.y);
  final double x, y;
}

class TreeEdge {
  const TreeEdge(this.from, this.to);
  final String from, to;
}

class TreeLayout {
  const TreeLayout(this.positions, this.edges);
  final Map<String, TreePosition> positions;
  final List<TreeEdge> edges;
}

/// Lays out a spanning tree and retains every reachable relationship as an edge.
TreeLayout layoutTree(
  String root,
  Map<String, List<NoteRef>> childrenByParent,
) {
  final discovered = <String>{root};
  final queue = <String>[root];
  final tree = <String, List<String>>{};
  final depths = <String, int>{root: 0};
  final edges = <TreeEdge>[];
  final edgeKeys = <(String, String)>{};
  for (var i = 0; i < queue.length; i++) {
    final parent = queue[i];
    for (final child in childrenByParent[parent] ?? <NoteRef>[]) {
      if (edgeKeys.add((parent, child.id))) {
        edges.add(TreeEdge(parent, child.id));
      }
      if (discovered.add(child.id)) {
        (tree[parent] ??= []).add(child.id);
        depths[child.id] = depths[parent]! + 1;
        queue.add(child.id);
      }
    }
  }
  final positions = <String, TreePosition>{};
  var nextLeaf = 0;
  double place(String id) {
    final children = tree[id] ?? <String>[];
    final double x;
    if (children.isEmpty) {
      x = 32.0 + nextLeaf++ * 280;
    } else {
      final first = place(children.first);
      var last = first;
      for (final child in children.skip(1)) {
        last = place(child);
      }
      x = (first + last) / 2;
    }
    positions[id] = TreePosition(x, 32.0 + depths[id]! * 180);
    return x;
  }

  place(root);
  return TreeLayout(positions, edges);
}
