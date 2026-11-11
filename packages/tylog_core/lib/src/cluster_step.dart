import 'dart:convert';

import 'clusters.dart';
import 'cluster_snapshot.dart';
import 'graph.dart';
import 'models.dart';
import 'storage.dart';

class ClusterStepResult {
  const ClusterStepResult({
    required this.clusterCount,
    required this.proposalCount,
  });

  final int clusterCount;
  final int proposalCount;
}

Future<ClusterStepResult> runClusterStep(
  VaultStorage storage,
  VaultIndex index, {
  required DateTime now,
}) async {
  final next = <String, Set<String>>{};
  for (final entry in computeCommunities(index).tagToCluster.entries) {
    next.putIfAbsent(entry.value, () => <String>{}).add(entry.key);
  }
  Map<String, Set<String>> previous = {};
  // Storages differ in how a missing file fails (FileSystemException, SAF
  // PlatformException, ...), so test for it instead of catching one type.
  try {
    if (await storage.exists('_system/clusters/snapshot.json')) {
      previous = ClusterSnapshot.fromJson(
        jsonDecode(await storage.readText('_system/clusters/snapshot.json'))
            as Map,
      ).clusters;
    }
  } on FormatException {
    // Rebuild malformed snapshots.
  }
  final match = matchClusters(previous, next);
  final decisions = await _clusterChangeDecisions(storage);
  final liveTags = {for (final s in next.values) ...s};
  final clusters = <String, Set<String>>{};
  for (final entry in next.entries) {
    final label = match.stableLabel[entry.key] ?? entry.key;
    clusters[(liveTags.contains(label) ? label : entry.key)] = entry.value;
  }
  for (final change in match.changes) {
    if (!const {'rename', 'merge', 'split'}.contains(change.kind)) continue;
    final id = _clusterChangeId(change);
    if (decisions.accepted.contains(id)) {
      for (final label in change.from) {
        clusters.remove(label);
      }
      for (final label in change.to) {
        clusters.remove(match.stableLabel[label] ?? label);
        if (next.containsKey(label)) clusters[label] = next[label]!;
      }
    } else {
      for (final label in change.to) {
        final stable = match.stableLabel[label] ?? label;
        // A stable label whose tag no longer exists in any cluster (e.g. it was
        // dropped from clustering) must not resurrect, and its live cluster
        // must be kept rather than reverted away.
        if (!liveTags.contains(stable)) continue;
        clusters.remove(stable);
        clusters.remove(label);
      }
      for (final label in change.from) {
        if (previous.containsKey(label) && liveTags.contains(label)) {
          clusters[label] = previous[label]!;
        }
      }
    }
  }
  final generatedAt = now.toUtc().toIso8601String();
  await storage.writeText(
    '_system/clusters/snapshot.json',
    '${const JsonEncoder.withIndent('  ').convert(ClusterSnapshot(generatedAt: generatedAt, clusters: clusters).toJson())}\n',
  );
  final proposals = [
    for (final change in match.changes)
      if (!decisions.rejected.contains(_clusterChangeId(change)) &&
          !decisions.accepted.contains(_clusterChangeId(change)))
        {
          'id': _clusterChangeId(change),
          'kind': change.kind,
          'from': change.from,
          'to': change.to,
        },
  ];
  await storage.writeText(
    '_system/clusters/proposals.json',
    '${const JsonEncoder.withIndent('  ').convert({'schema': 1, 'generated_at': generatedAt, 'changes': proposals})}\n',
  );
  return ClusterStepResult(
    clusterCount: clusters.length,
    proposalCount: proposals.length,
  );
}

String _clusterChangeId(ClusterChange change) =>
    '${change.kind}:${change.from.join('+')}->${change.to.join('+')}';

class _ClusterChangeDecisions {
  const _ClusterChangeDecisions(this.accepted, this.rejected);
  final Set<String> accepted;
  final Set<String> rejected;
}

Future<_ClusterChangeDecisions> _clusterChangeDecisions(
  VaultStorage storage,
) async {
  final accepted = <String>{};
  final rejected = <String>{};
  if (!await storage.exists('_system/decisions')) {
    return _ClusterChangeDecisions(accepted, rejected);
  }
  for (final entry in await storage.list(path: '_system/decisions')) {
    if (entry.isDirectory || !entry.path.endsWith('.jsonl')) continue;
    for (final line in (await storage.readText(entry.path)).split('\n')) {
      try {
        final row = jsonDecode(line);
        if (row is Map &&
            row['source'] == 'clusters' &&
            row['target'] is String) {
          if (row['action'] == 'accepted') {
            accepted.add(row['target'] as String);
          }
          if (row['action'] == 'rejected') {
            rejected.add(row['target'] as String);
          }
        }
      } on FormatException {
        // Ignore a partial ledger line.
      }
    }
  }
  return _ClusterChangeDecisions(accepted, rejected);
}
