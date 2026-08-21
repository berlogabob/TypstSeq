import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';

/// Interrupted atomic writes leave their temp file behind. Three were sitting
/// in the live vault on the P30 — `_index/.index.json.tylog-451878162009693.tmp`
/// from July 30, plus two whole articles that never landed.
void main() {
  test('recognises both writers\' temp names', () {
    expect(
      isOrphanedTempPath('_index/.index.json.tylog-451878162009693.tmp'),
      isTrue,
    );
    expect(
      isOrphanedTempPath('articles/.A Note - Blog.typ.tylog-449257966368947.tmp'),
      isTrue,
    );
    // LocalVaultStorage's form: `${path}.${micros}.tmp`, no `tylog-` marker.
    expect(isOrphanedTempPath('notes/a.typ.1755772800000000.tmp'), isTrue);
  });

  test('leaves anything that is not a temp orphan alone', () {
    expect(isOrphanedTempPath('notes/a.typ'), isFalse);
    // A note a user genuinely named "…tmp" must survive.
    expect(isOrphanedTempPath('notes/scratch.tmp'), isFalse);
    expect(isOrphanedTempPath('notes/draft-v2.tmp'), isFalse);
    // The backup orphan has its own predicate and is swept unconditionally.
    expect(isOrphanedTempPath('.tylog/.sync_state.json.tylog-12345.backup'),
        isFalse);
  });

  test('the grace period is long enough to outlast an in-flight write', () {
    // The background service writes the same vault from another process, so a
    // fresh temp file may still be in use. An hour is far past any real write.
    expect(orphanTempGrace, greaterThanOrEqualTo(const Duration(minutes: 30)));
  });
}
