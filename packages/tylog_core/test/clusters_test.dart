import 'package:tylog_core/tylog_core.dart';
import 'package:test/test.dart';

void main() {
  group('jaccard', () {
    test('both empty -> 0', () {
      expect(jaccard(const {}, const {}), 0);
    });

    test('identical non-empty -> 1', () {
      expect(jaccard(const {'a', 'b'}, const {'a', 'b'}), 1);
    });

    test('disjoint -> 0', () {
      expect(jaccard(const {'a'}, const {'b'}), 0);
    });

    test('partial overlap', () {
      expect(jaccard(const {'a', 'b'}, const {'a', 'c'}), closeTo(1 / 3, 1e-9));
    });
  });

  group('matchClusters', () {
    test('identical maps -> stableLabel identity, no changes', () {
      final previous = {
        'A': {'1', '2'},
        'B': {'3'},
      };
      final next = {
        'A': {'1', '2'},
        'B': {'3'},
      };
      final match = matchClusters(previous, next);
      expect(match.stableLabel, {'A': 'A', 'B': 'B'});
      expect(match.changes, isEmpty);
    });

    test('same members under a new label -> rename', () {
      final previous = {
        'A': {'1', '2'},
      };
      final next = {
        'B': {'1', '2'},
      };
      final match = matchClusters(previous, next);
      expect(match.stableLabel['B'], 'A');
      expect(
        match.changes.map((c) => c.toJson()),
        anyElement(
          equals({
            'kind': 'rename',
            'from': ['A'],
            'to': ['B'],
          }),
        ),
      );
    });

    test('one previous split into two halves -> one split', () {
      final previous = {
        'A': {'1', '2', '3', '4'},
      };
      final next = {
        'B': {'1', '2'},
        'C': {'3', '4'},
      };
      final match = matchClusters(previous, next);
      // B and C both best-match A; keeper keeps A, the other is dropped label.
      expect(match.stableLabel['B'], 'A');
      final splits = match.changes.where((c) => c.kind == 'split').toList();
      expect(splits, hasLength(1));
      expect(splits.single.from, ['A']);
      expect(splits.single.to, ['B', 'C']);
    });

    test('two previous fully inside one next -> merge', () {
      final previous = {
        'A': {'1'},
        'B': {'2'},
      };
      final next = {
        'C': {'1', '2'},
      };
      final match = matchClusters(previous, next);
      final merges = match.changes.where((c) => c.kind == 'merge').toList();
      expect(merges, hasLength(1));
      expect(merges.single.from, ['A', 'B']);
      expect(merges.single.to, ['C']);
    });

    test('a previous with no counterpart -> gone', () {
      final previous = {
        'A': {'1'},
        'X': {'9'},
      };
      final next = {
        'A': {'1'},
      };
      final match = matchClusters(previous, next);
      expect(match.stableLabel['A'], 'A');
      final gone = match.changes.where((c) => c.kind == 'gone').toList();
      expect(
        gone.map((c) => c.toJson()),
        anyElement(
          equals({
            'kind': 'gone',
            'from': ['X'],
            'to': [],
          }),
        ),
      );
    });

    test('a brand new cluster -> new', () {
      final previous = {
        'A': {'1'},
      };
      final next = {
        'A': {'1'},
        'Z': {'7'},
      };
      final match = matchClusters(previous, next);
      expect(match.stableLabel['Z'], 'Z');
      final news = match.changes.where((c) => c.kind == 'new').toList();
      expect(
        news.map((c) => c.toJson()),
        anyElement(
          equals({
            'kind': 'new',
            'from': [],
            'to': ['Z'],
          }),
        ),
      );
    });
  });
}
