import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/graph.dart';

int _p95(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length * 95 + 99) ~/ 100) - 1];
}

NoteGraph _representativeBoundedGraph() {
  const nodeCount = 300;
  const edgeCount = 800;
  final graph = NoteGraph(
    nodes: [
      for (var i = 0; i < nodeCount; i++)
        GraphNode(path: 'notes/$i.typ', title: 'Synthetic note $i'),
    ],
    edges: [
      for (var i = 0; i < edgeCount; i++)
        GraphEdge(
          from: 'notes/0.typ',
          to: 'notes/${i % (nodeCount - 1) + 1}.typ',
        ),
    ],
  );
  final bounded = boundGraphForLayout(graph, currentPath: 'notes/0.typ');
  if (bounded.nodes.length != 200 || bounded.edges.length != 500) {
    throw StateError('Synthetic graph did not reach the production bounds');
  }
  return bounded;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final binding = IntegrationTestWidgetsFlutterBinding.instance;

  testWidgets('P22 GraphView mount and node selection latency', (tester) async {
    const sampleCount = 100;
    final graph = _representativeBoundedGraph();
    final openSamples = <int>[];
    final selectionSamples = <int>[];
    String? openedPath;

    for (var i = 0; i < sampleCount; i++) {
      final watch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphView(
              key: ValueKey(i),
              graph: graph,
              currentPath: 'notes/0.typ',
              onOpenPath: (path) => openedPath = path,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      watch.stop();
      final painterFinder = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is GraphPainter,
      );
      final painter =
          tester.widget<CustomPaint>(painterFinder).painter! as GraphPainter;
      expect(painter.positions, hasLength(200));
      openSamples.add(watch.elapsedMicroseconds);

      final path = painter.positions.keys
          .where((path) => path != 'notes/0.typ')
          .reduce((best, candidate) {
            double nearestDistance(String path) {
              final point = painter.positions[path]!;
              return painter.positions.entries
                  .where((entry) => entry.key != path)
                  .map((entry) => (entry.value - point).distance)
                  .reduce((a, b) => a < b ? a : b);
            }

            return nearestDistance(candidate) > nearestDistance(best)
                ? candidate
                : best;
          });
      final paintBox = tester.renderObject<RenderBox>(painterFinder);
      final point = paintBox.localToGlobal(painter.positions[path]!);
      final selectionWatch = Stopwatch()..start();
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      selectionWatch.stop();
      expect(
        find.text(graph.nodes.singleWhere((node) => node.path == path).title),
        findsOneWidget,
      );
      selectionSamples.add(selectionWatch.elapsedMicroseconds);
    }

    int p50(List<int> values) {
      final sorted = [...values]..sort();
      return sorted[(sorted.length * 50 + 99) ~/ 100 - 1];
    }

    final openP95 = _p95(openSamples);
    final selectionP95 = _p95(selectionSamples);
    // ignore: avoid_print
    print(
      'P22 GraphView profile samples=$sampleCount '
      'nodes=${graph.nodes.length} edges=${graph.edges.length}; '
      'open_rebuild_ms p50=${(p50(openSamples) / 1000).toStringAsFixed(3)} '
      'p95=${(openP95 / 1000).toStringAsFixed(3)} '
      'max=${(openSamples.reduce((a, b) => a > b ? a : b) / 1000).toStringAsFixed(3)}; '
      'selection_ms p50=${(p50(selectionSamples) / 1000).toStringAsFixed(3)} '
      'p95=${(selectionP95 / 1000).toStringAsFixed(3)} '
      'max=${(selectionSamples.reduce((a, b) => a > b ? a : b) / 1000).toStringAsFixed(3)}',
    );
    binding.reportData = {
      'sample_count': sampleCount,
      'node_count': graph.nodes.length,
      'edge_count': graph.edges.length,
      'mount_us': openSamples,
      'selection_us': selectionSamples,
    };
    expect(openSamples, hasLength(sampleCount));
    expect(selectionSamples, hasLength(sampleCount));
    expect(openP95, lessThanOrEqualTo(500000));
    expect(selectionP95, lessThanOrEqualTo(500000));
    expect(openedPath, isNull);
  });
}
