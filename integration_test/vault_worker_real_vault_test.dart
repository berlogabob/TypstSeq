import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/vault_worker.dart';

/// The measurement every other perf test here is a stand-in for.
///
/// All the published numbers — 333→42 ms, 25→6-9 dropped frames, the attribution
/// table — came from 2000 synthetic notes on a `LocalVaultStorage` temp dir, which
/// on Android bypasses SAF entirely. This runs the same A/B against the *real*
/// vault, over `AndroidTreeVaultStorage`, on whatever notes are actually there.
///
/// **Must be run as a profile build**, via
/// `flutter drive --profile --driver=test_driver/integration_test.dart --target=<this>`.
/// `flutter test -d <device>` builds debug, and debug carries
/// `applicationIdSuffix = ".debug"` — a different app, different sandbox, and no
/// persisted SAF grant, so it would measure an empty vault and report a pass. The
/// `hasAccess` check below is what turns that into a loud failure.
///
/// Deliberately does **not**:
///   * pass a `deviceId` — that would write `_system/index/<id>.json`, and
///     `_system/` syncs, so a test-only donor would propagate to the other devices
///     and never be cleaned up;
///   * call `Vault.ensureCreated()` — it rewrites `_system/tylog.typ` and any
///     `_system/packages/*` whose bytes differ from the bundled asset, so a test
///     APK could silently up/downgrade the user's managed Typst files.
///
/// It does rewrite `_index/index.json` and `_index/search-index.json.gz`, which is
/// ordinary app behaviour — `_index/` is local and disposable by design.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const frame = Duration(milliseconds: 16);

  /// Dropped frames and worst gap on the root isolate while [work] runs.
  Future<({int dropped, Duration worst})> stalls(
    Future<void> Function() work,
  ) async {
    var dropped = 0;
    var worst = Duration.zero;
    var last = DateTime.now();
    final ticker = Timer.periodic(frame, (_) {
      final now = DateTime.now();
      final gap = now.difference(last);
      if (gap > worst) worst = gap;
      final late = gap - frame;
      if (late > Duration.zero) {
        dropped += late.inMicroseconds ~/ frame.inMicroseconds;
      }
      last = now;
    });
    try {
      await work();
    } finally {
      ticker.cancel();
    }
    return (dropped: dropped, worst: worst);
  }

  testWidgets('warm rebuild of the real vault, inline vs worker', (_) async {
    final registry = await VaultRegistry.load();
    final entry = registry.active;

    // A local-path vault means this is a desktop run or an unmigrated install;
    // there is no SAF to measure, so say so rather than silently measuring
    // something else.
    if (entry.storageKind != 'android-tree') {
      fail(
        'active vault is "${entry.storageKind}", not android-tree — this test '
        'exists to measure SAF. Run it on the phone, as a profile build.',
      );
    }

    final storage = entry.storage;
    // The guard that makes the whole run meaningful. A ".debug" build reaches
    // this line with no grant and would otherwise sail on and measure nothing.
    expect(
      await (storage as AndroidTreeVaultStorage).hasAccess(),
      isTrue,
      reason:
          'no persisted SAF grant for ${entry.treeUri}. Almost certainly running '
          'as org.tylog.tylog.debug — rebuild with flutter drive --profile.',
    );

    // Baseline: the pre-worker path, on the root isolate, over SAF.
    VaultIndex? built;
    final inline = await stalls(() async {
      final vault = Vault.withStorage(entry.storage);
      FlutterTypstInspector? inspector;
      try {
        inspector = await FlutterTypstInspector.create();
      } catch (_) {
        // Fallback parsing is fine here; a warm scan never calls the inspector.
      }
      try {
        built = await vault.rebuildIndex(inspector: inspector);
      } finally {
        inspector?.dispose();
      }
    });
    final notes = built?.notesByPath.length ?? 0;
    expect(notes, greaterThan(0), reason: 'the real vault indexed to nothing');

    final worker = await VaultWorkerClient.spawn(entry: entry);
    addTearDown(worker.dispose);
    final offloaded = await stalls(() async {
      final events = await worker
          .run(const RebuildIndexCommand(stale: {}))
          .toList();
      final failures = events.whereType<WorkFailedEvent>();
      expect(failures, isEmpty, reason: '${failures.map((e) => e.message)}');
      expect(
        events.whereType<IndexBuiltEvent>().single.index.notesByPath,
        hasLength(notes),
      );
    });

    final problems = <String>[];
    // Surfaces a failed RustLib.init() rather than letting the run look healthy
    // while every note quietly fell back to source parsing.
    for (final note in built!.notesByPath.values) {
      if (note.metadataSource != 'typst-query') problems.add(note.path);
    }

    // ignore: avoid_print
    print(
      'REAL-VAULT notes=$notes storage=SAF\n'
      '  inline: ${inline.dropped} dropped frames, worst ${inline.worst.inMilliseconds}ms\n'
      '  worker: ${offloaded.dropped} dropped frames, worst ${offloaded.worst.inMilliseconds}ms\n'
      '  notes not from typst-query: ${problems.length}/$notes',
    );

    // No ratio assertion. On a *warm* scan the mtime+size gate returns without
    // any I/O, so both paths can legitimately sit at the timer floor and the
    // interesting output is the printed comparison against the synthetic fixture,
    // not a pass/fail. Assert only that the worker is not *worse*.
    expect(
      offloaded.dropped,
      lessThanOrEqualTo(inline.dropped),
      reason: 'the worker path dropped more frames than running inline',
    );
  });
}
