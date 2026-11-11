import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

/// The kind→tag alias would otherwise make `article` (thousands of notes) the
/// highest-degree concept hub and let it dominate community detection; kind
/// tags are excluded from the tag→notes aggregation the graph builders share.
void main() {
  VaultIndex index() => VaultIndex(
    notesByPath: {
      for (var i = 0; i < 4; i++)
        'articles/a$i.typ': NoteRef(
          id: 'a$i',
          path: 'articles/a$i.typ',
          title: 'A$i',
          kind: 'article',
          tags: const ['article', 'rust'],
          outgoingLinks: const [],
        ),
    },
    backlinksByTarget: const {},
    tasks: const [],
  );

  test('kind-alias tags do not become concept nodes', () {
    final map = buildConceptMap(index(), minNotes: 2, minCoOccur: 2);
    final titles = map.nodes.map((n) => n.title).toList();
    expect(titles, contains('rust'));
    expect(
      titles,
      isNot(contains('article')),
      reason: 'a kind alias on every article is not a concept',
    );
  });

  test('kind-alias tags do not feed tagToNotes', () {
    expect(tagToNotes(index()).keys, isNot(contains('article')));
  });

  test('structural tags are excluded from communities', () {
    // Default `computeCommunities` requires a tag on >= kConceptMapMinNotes (5)
    // notes to promote; five notes each carrying the structural tags 'journal'
    // and '2026' plus the topic tags 'ai' and 'llm'.
    VaultIndex structuralIndex() => VaultIndex(
      notesByPath: {
        for (var i = 0; i < 5; i++)
          'notes/n$i.typ': NoteRef(
            id: 'n$i',
            path: 'notes/n$i.typ',
            title: 'N$i',
            kind: 'note',
            tags: const ['journal', '2026', 'ai', 'llm'],
            outgoingLinks: const [],
          ),
      },
      backlinksByTarget: const {},
      tasks: const [],
    );

    final communities = computeCommunities(structuralIndex());
    expect(
      communities.tagToCluster.keys,
      isNot(contains('journal')),
      reason: 'a structural tag on every note is not a community',
    );
    expect(
      communities.tagToCluster.keys,
      isNot(contains('2026')),
      reason: 'a digit-only tag on every note is not a community',
    );
    expect(communities.tagToCluster.keys, contains('ai'));
    expect(communities.tagToCluster.keys, contains('llm'));
  });
}
