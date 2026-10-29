import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test(
    'note graph nodes preserve source kinds while hubs and days have none',
    () {
      const sources = [
        'daily',
        'note',
        'screenshot',
        'audio',
        'article',
        'event',
      ];
      final index = VaultIndex(
        notesByPath: {
          for (final source in sources)
            '$source.typ': NoteRef(
              id: source,
              path: '$source.typ',
              title: source,
              kind: source,
              outgoingLinks: const [],
              date: '2026-07-01',
              tags: const ['shared'],
              citations: const ['work'],
              properties: const {'finished': '2026-07-02'},
            ),
        },
        backlinksByTarget: const {},
      );

      final graph = buildNoteGraph(index);
      expect(
        graph.nodes
            .where((n) => n.kind == GraphNodeKind.note)
            .map((n) => n.source),
        unorderedEquals(sources),
      );
      expect(
        graph.nodes
            .where((n) => n.kind != GraphNodeKind.note)
            .map((n) => n.source),
        ['', ''],
      );
      final timeline = buildTimelineGraph(index, const {});
      expect(
        timeline.nodes
            .where((n) => n.kind == GraphNodeKind.note)
            .map((n) => n.source),
        unorderedEquals(sources.where((s) => s != 'daily')),
      );
      expect(
        timeline.nodes
            .where((n) => n.kind == GraphNodeKind.day)
            .map((n) => n.source),
        everyElement(''),
      );
      expect(const GraphNode(path: 'legacy', title: 'Legacy').source, '');
    },
  );
}
