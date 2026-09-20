class SvgGraphNode {
  const SvgGraphNode({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
  });
  final String id;
  final String label;
  final double x;
  final double y;
}

class SvgGraphEdge {
  const SvgGraphEdge({required this.from, required this.to});
  final String from;
  final String to;
}

String graphToSvg({
  required Iterable<SvgGraphNode> nodes,
  required Iterable<SvgGraphEdge> edges,
}) {
  final orderedNodes = nodes.toList()..sort((a, b) => a.id.compareTo(b.id));
  final orderedEdges = edges.toList()
    ..sort(
      (a, b) => '${a.from}\u0000${a.to}'.compareTo('${b.from}\u0000${b.to}'),
    );
  final byId = {for (final node in orderedNodes) node.id: node};
  final out = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">',
  );
  for (final edge in orderedEdges) {
    final from = byId[edge.from], to = byId[edge.to];
    if (from == null || to == null) continue;
    out.write(
      '<line x1="${from.x}" y1="${from.y}" x2="${to.x}" y2="${to.y}" stroke="#888"/>',
    );
  }
  for (final node in orderedNodes) {
    out.write('<circle cx="${node.x}" cy="${node.y}" r="18" fill="#4f46e5"/>');
    out.write(
      '<text x="${node.x + 22}" y="${node.y + 5}">${_escape(node.label)}</text>',
    );
  }
  return '${out.toString()}</svg>';
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
