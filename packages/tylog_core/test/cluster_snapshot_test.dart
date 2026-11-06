import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('cluster snapshot round trips schema and tag membership', () {
    final snapshot = ClusterSnapshot(
      generatedAt: '2026-11-06T00:00:00Z',
      clusters: {
        'label': {'one', 'two'},
      },
    );
    final decoded = ClusterSnapshot.fromJson(snapshot.toJson());
    expect(decoded.generatedAt, snapshot.generatedAt);
    expect(decoded.clusters, snapshot.clusters);
  });

  test('cluster snapshot rejects unknown schema', () {
    expect(
      () => ClusterSnapshot.fromJson({'schema': 2, 'clusters': {}}),
      throwsFormatException,
    );
  });
}
