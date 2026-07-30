import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_worker.dart';

/// The regression test for the reason the worker exists.
///
/// "The app stutters while reindexing" is really "the root isolate is busy, so no
/// frame can render". That is measurable without a UI: run a rebuild, tick a
/// timer at frame cadence on the root isolate, and record the worst gap between
/// ticks. A gap is a dropped frame — 16 ms is one at 60 Hz.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const notes = 2000;

  Future<VaultEntry> seed() async {
    final root = await Directory.systemTemp.createTemp('tylog_jank_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();
    // Rich on purpose. A vault of one-line notes is not the thing that stutters:
    // the stalls that no `await` can break up are proportional to the *index*, not
    // the note count — the multi-MB `jsonEncode`, the donor encode, the search
    // index gzip. Tags, links and tasks per note are what make the index big
    // enough to reproduce that, matching the ~2.2 MB index.json a real vault has.
    for (var i = 0; i < notes; i++) {
      final tags = [for (var t = 0; t < 12; t++) 'tag-${(i + t) % 40}'];
      await vault.saveNote(
        'notes/Note$i.typ',
        '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "note-$i", title: "Note number $i", tags: (${tags.map((t) => '"$t"').join(', ')},))
${[for (final t in tags) '#tylog.tag("$t")'].join('\n')}
${[for (var l = 1; l <= 8; l++) '#tylog.ref-note("note-${(i + l) % notes}")[Note ${(i + l) % notes}]'].join('\n')}
${[for (var k = 0; k < 4; k++) '#tylog.task(id: "task-$i-$k", text: "Task $k of note $i", due: "2026-08-0${(k % 9) + 1}")'].join('\n')}
''',
      );
    }
    return VaultEntry(id: 'jank', name: 'Jank', path: root.path);
  }

  const frame = Duration(milliseconds: 16);

  /// Ticks a timer at frame cadence on the root isolate while [work] runs and
  /// reports how badly the loop was blocked.
  ///
  /// `dropped` is the metric that matters: every 16 ms a tick was late by is one
  /// frame the UI could not render. It is a sum over the whole run, so unlike the
  /// single worst gap it does not hinge on one unlucky sample — and "stuttering"
  /// is many dropped frames, not one long pause.
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
      // Only lateness counts. A tick that lands early (timers coalesce, so a
      // 16 ms period routinely fires at 15.9) dropped nothing, and must not
      // subtract from the total.
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

  testWidgets('a worker rebuild leaves the root isolate free to render', (
    _,
  ) async {
    final entry = await seed();

    // Baseline: the pre-worker path — scan, hash, jsonEncode, gzip, all inline.
    final inline = await stalls(() async {
      final vault = Vault.withStorage(entry.storage);
      final index = await vault.rebuildIndex(
        inspector: await FlutterTypstInspector.create(),
        force: true,
      );
      expect(index.notesByPath, hasLength(notes));
    });

    final worker = await VaultWorkerClient.spawn(entry: entry);
    addTearDown(worker.dispose);
    final offloaded = await stalls(() async {
      final events = await worker
          .run(const RebuildIndexCommand(force: true, stale: {}))
          .toList();
      expect(events.whereType<WorkFailedEvent>(), isEmpty);
      expect(
        events.whereType<IndexBuiltEvent>().single.index.notesByPath,
        hasLength(notes),
      );
    });

    final summary =
        'notes=$notes '
        'inline=${inline.dropped} frames (worst ${inline.worst.inMilliseconds}ms) '
        'worker=${offloaded.dropped} frames (worst '
        '${offloaded.worst.inMilliseconds}ms)';
    // ignore: avoid_print
    print('JANK $summary');

    // Guard the guard: if the baseline never blocked, this fixture proves nothing
    // and a pass would be meaningless rather than reassuring.
    expect(
      inline.dropped,
      greaterThan(0),
      reason: 'baseline dropped no frames — fixture too small to discriminate, '
          'raise `notes`: $summary',
    );

    // A ratio, not a wall-clock budget: absolute timings vary across machines and
    // CI, but the shape is the invariant — inline blocks in proportion to the
    // vault, the worker stays near the 16 ms timer floor no matter how big the
    // vault gets. Should indexing leak back onto the root isolate the two
    // converge and this fails. Measured inline 50–60 ms vs worker 18–21 ms
    // (0 dropped frames) over repeat runs on an M-series laptop, so 2x holds
    // with margin.
    expect(
      offloaded.worst.inMicroseconds * 2,
      lessThan(inline.worst.inMicroseconds),
      reason: 'indexing work has leaked back onto the UI isolate: $summary',
    );
  });
}
