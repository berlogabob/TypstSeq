/// Portable cluster snapshot format used by the CLI and background worker.
class ClusterSnapshot {
  const ClusterSnapshot({required this.generatedAt, required this.clusters});

  final String generatedAt;
  final Map<String, Set<String>> clusters;

  factory ClusterSnapshot.fromJson(Map value) {
    if (value['schema'] != 1 || value['clusters'] is! Map) {
      throw const FormatException('Unsupported cluster snapshot');
    }
    return ClusterSnapshot(
      generatedAt: value['generated_at']?.toString() ?? '',
      clusters: (value['clusters'] as Map).map(
        (key, tags) => MapEntry(
          key.toString(),
          (tags as List).map((tag) => tag.toString()).toSet(),
        ),
      ),
    );
  }

  Map<String, Object> toJson() => {
    'schema': 1,
    'generated_at': generatedAt,
    'clusters': {
      for (final key in clusters.keys.toList()..sort())
        key: clusters[key]!.toList()..sort(),
    },
  };
}
