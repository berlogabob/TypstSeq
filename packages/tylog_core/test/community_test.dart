import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

NoteRef _note(String path, List<String> tags) =>
    NoteRef(id: path, path: path, title: path, outgoingLinks: const [], tags: tags);

VaultIndex _index(List<NoteRef> notes) => VaultIndex(
  notesByPath: {for (final n in notes) n.path: n},
  backlinksByTarget: const {},
);

void main() {
  // Two tag groups that never co-occur -> two disjoint communities.
  // Group A: a1,a2 on notes n1..n3. Group B: b1,b2 on notes n4..n6.
  // `solo` appears once (< minNotes) so it is never promoted.
  final index = _index([
    _note('n1', ['a1', 'a2']),
    _note('n2', ['a1', 'a2']),
    _note('n3', ['a1', 'a2']),
    _note('n4', ['b1', 'b2']),
    _note('n5', ['b1', 'b2']),
    _note('n6', ['b1', 'b2']),
    _note('n7', ['solo']),
  ]);

  test('splits disjoint tag groups into two named communities', () {
    final c = computeCommunities(index, minNotes: 2, minCoOccur: 2);

    expect(c.clusterOrder.length, 2, reason: 'two disjoint groups');
    // Names are the highest-count member; ties break to the smallest tag.
    expect(c.tagToCluster['a1'], 'a1');
    expect(c.tagToCluster['a2'], 'a1');
    expect(c.tagToCluster['b1'], 'b1');
    expect(c.tagToCluster['b2'], 'b1');

    // Notes land in their group's community; cross-group notes differ.
    expect(c.noteToCluster['n1'], c.noteToCluster['n2']);
    expect(c.noteToCluster['n1'], isNot(c.noteToCluster['n4']));
    expect(c.noteToCluster['n4'], c.noteToCluster['n6']);

    // A note whose only tag is below the promotion threshold is unassigned.
    expect(c.noteToCluster.containsKey('n7'), isFalse);
  });

  test('is deterministic across runs', () {
    final a = computeCommunities(index, minNotes: 2, minCoOccur: 2);
    final b = computeCommunities(index, minNotes: 2, minCoOccur: 2);
    expect(a.noteToCluster, b.noteToCluster);
    expect(a.tagToCluster, b.tagToCluster);
    expect(a.clusterOrder, b.clusterOrder);
  });
}
