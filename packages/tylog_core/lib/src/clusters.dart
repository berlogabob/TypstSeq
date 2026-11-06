/// A single change observed between two cluster snapshots.
///
/// `kind` is one of `'merge' | 'split' | 'rename' | 'new' | 'gone'`.
/// `from` lists the previous cluster labels involved, `to` lists the
/// resulting cluster labels.
class ClusterChange {
  const ClusterChange(this.kind, this.from, this.to);

  final String kind;
  final List<String> from;
  final List<String> to;

  Map<String, Object?> toJson() => {'kind': kind, 'from': from, 'to': to};
}

/// The result of matching two cluster snapshots: a stable label per next
/// cluster plus the list of changes that explain the difference.
class ClusterMatch {
  const ClusterMatch(this.stableLabel, this.changes);

  /// Maps each next-cluster label to the previous-cluster label it should be
  /// considered identical to (itself when there is no previous counterpart).
  final Map<String, String> stableLabel;

  /// The changes that explain how `previous` became `next`.
  final List<ClusterChange> changes;
}

/// Jaccard similarity between two sets. Two empty sets are considered
/// dissimilar (0) by convention.
double jaccard(Set<String> a, Set<String> b) =>
    a.isEmpty && b.isEmpty ? 0 : a.intersection(b).length / a.union(b).length;

/// Match a previous set of clusters against a next set.
///
/// Keys are cluster labels, values are member ids (tags). The algorithm is
/// deterministic: cluster keys are always iterated in sorted order.
ClusterMatch matchClusters(
  Map<String, Set<String>> previous,
  Map<String, Set<String>> next, {
  double minOverlap = 0.3,
}) {
  final sortedPrevious = previous.keys.toList()..sort();
  final sortedNext = next.keys.toList()..sort();

  final stableLabel = <String, String>{};
  final changes = <ClusterChange>[];

  // 1 & 2: for every next cluster find its best previous match, then group.
  final bestFor = <String, String>{}; // next label -> best previous label
  final bestScore = <String, double>{};

  for (final n in sortedNext) {
    String? bestP;
    double bestSoFar = 0;
    for (final p in sortedPrevious) {
      final score = jaccard(previous[p]!, next[n]!);
      if (score >= minOverlap &&
          (bestP == null ||
              score > bestSoFar ||
              (score == bestSoFar && p.compareTo(bestP) < 0))) {
        bestP = p;
        bestSoFar = score;
      }
    }
    if (bestP != null) {
      bestFor[n] = bestP;
      bestScore[n] = bestSoFar;
    }
  }

  // Group next clusters by their best previous match.
  final groups = <String, List<String>>{}; // previous label -> next labels
  for (final entry in bestFor.entries) {
    groups.putIfAbsent(entry.value, () => <String>[]).add(entry.key);
  }

  final keptPrevious = <String>{}; // previous labels that were "kept"
  for (final MapEntry(key: previousLabel, value: group) in groups.entries) {
    // The next cluster with the highest jaccard keeps p.
    String? keeper;
    double keeperScore = -1;
    for (final n in group) {
      final score = bestScore[n]!;
      if (score > keeperScore ||
          (score == keeperScore &&
              (keeper == null || n.compareTo(keeper) < 0))) {
        keeper = n;
        keeperScore = score;
      }
    }
    for (final n in group) {
      final bestP = bestFor[n]!;
      if (n == keeper) {
        stableLabel[n] = bestP;
        if (n != bestP) {
          changes.add(ClusterChange('rename', [bestP], [n]));
        }
        keptPrevious.add(bestP);
      } else {
        stableLabel[n] = n;
      }
    }
    if (group.length > 1) {
      changes.add(ClusterChange('split', [previousLabel], [...group]..sort()));
    }
  }

  // 3: next clusters with no best previous match.
  for (final n in sortedNext) {
    if (!bestFor.containsKey(n)) {
      stableLabel[n] = n;
      // Only report 'new' when it overlaps nothing previous enough to be a
      // match; here it has no best p at all, so it is genuinely new.
      changes.add(ClusterChange('new', [], [n]));
    }
  }

  // 4: merges.
  for (final n in sortedNext) {
    final membersN = next[n]!;
    final p = <String>{};
    for (final kp in sortedPrevious) {
      final membersP = previous[kp]!;
      final score = jaccard(membersP, membersN);
      final contained = membersP.where(membersN.contains).length;
      if (score >= minOverlap || contained * 1.0 >= membersP.length * 0.5) {
        p.add(kp);
      }
    }
    if (p.length >= 2) {
      changes.add(ClusterChange('merge', [...p]..sort(), [n]));
    }
  }

  // 5: previous clusters that are nobody's best and not part of a merge.
  final mergedPrevious = <String>{};
  for (final change in changes) {
    if (change.kind == 'merge') {
      mergedPrevious.addAll(change.from);
    }
  }
  for (final p in sortedPrevious) {
    if (!keptPrevious.contains(p) && !mergedPrevious.contains(p)) {
      changes.add(ClusterChange('gone', [p], []));
    }
  }

  // Order changes by kind then from.
  changes.sort((a, b) {
    final kc = a.kind.compareTo(b.kind);
    if (kc != 0) return kc;
    return a.from.join(',').compareTo(b.from.join(','));
  });

  return ClusterMatch(stableLabel, changes);
}
