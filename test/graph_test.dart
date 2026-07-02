import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/graph.dart';
import 'package:tylog/models.dart';

void main() {
  test('buildNoteGraph creates deterministic nodes and resolved edges', () {
    final index = VaultIndex(
      notesByPath: {
        'journal/2026-07-01.typ': const NoteRef(
          path: 'journal/2026-07-01.typ',
          title: 'Today',
          outgoingLinks: ['PKM', 'Missing'],
        ),
        'pages/PKM.typ': const NoteRef(
          path: 'pages/PKM.typ',
          title: 'PKM',
          outgoingLinks: ['Today'],
        ),
      },
      backlinksByTarget: const {},
    );

    final graph = buildNoteGraph(index);

    expect(graph.nodes.map((node) => node.path), [
      'journal/2026-07-01.typ',
      'pages/PKM.typ',
    ]);
    expect(graph.edges.map((edge) => '${edge.from}->${edge.to}'), [
      'journal/2026-07-01.typ->pages/PKM.typ',
      'pages/PKM.typ->journal/2026-07-01.typ',
    ]);
  });

  test('graphPositions gives one stable point per node', () {
    const nodes = [
      GraphNode(path: 'a.typ', title: 'A'),
      GraphNode(path: 'b.typ', title: 'B'),
      GraphNode(path: 'c.typ', title: 'C'),
    ];

    final positions = graphPositions(nodes, const Size(300, 300));

    expect(positions.keys, ['a.typ', 'b.typ', 'c.typ']);
    expect(positions.values.toSet(), hasLength(3));
  });
}
