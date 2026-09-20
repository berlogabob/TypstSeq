import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/retrieval/graph_svg.dart';

void main() {
  test('SVG graph export is deterministic and escapes labels', () {
    final svg = graphToSvg(
      nodes: const [
        SvgGraphNode(id: 'b', label: 'B & <x>', x: 100, y: 100),
        SvgGraphNode(id: 'a', label: 'A', x: 10, y: 10),
      ],
      edges: const [SvgGraphEdge(from: 'a', to: 'b')],
    );
    expect(svg, startsWith('<svg'));
    expect(svg, contains('B &amp; &lt;x&gt;'));
    expect(svg, contains('<line'));
  });
}
