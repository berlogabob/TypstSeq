import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_worker.dart';

/// Diagnostic: where does the *residual* root-isolate stall actually go?
///
/// The worker removed the bulk of it (333 ms → 42 ms on a P30) but not all, and
/// the remainder was only ever guessed at. This prices each suspect separately
/// so the next optimization targets the real winner:
///
///   - port transfers, attributed by which event the root isolate was waiting on
///     when the tick was late (the deserialization happens inside the port
///     receive, before any handler of ours runs, so it cannot be Stopwatch'd —
///     but it can be bracketed)
///   - the synchronous work the controller does per event, which can
///
/// Prints a breakdown; run it, don't assert on it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const notes = 2000;
  const frame = Duration(milliseconds: 16);

  testWidgets('breakdown of the residual root-isolate stall', (_) async {
    final root = await Directory.systemTemp.createTemp('tylog_attr_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();
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
    final entry = VaultEntry(id: 'attr', name: 'Attr', path: root.path);

    // Warm the caches on disk so this measures the steady-state incremental
    // rebuild — the one that fires constantly — not a one-off cold scan.
    final warm = await VaultWorkerClient.spawn(entry: entry);
    await warm.run(const RebuildIndexCommand(force: true, stale: {})).toList();
    await warm.dispose();

    final worker = await VaultWorkerClient.spawn(entry: entry);
    addTearDown(worker.dispose);

    // Stand-in for the controller's retained index.
    VaultIndex? retained;

    final phases = <String, Duration>{};
    var phase = 'run->IndexBuilt';
    var worst = Duration.zero;
    var last = DateTime.now();
    final ticker = Timer.periodic(frame, (_) {
      final now = DateTime.now();
      final gap = now.difference(last);
      if (gap > worst) worst = gap;
      last = now;
    });
    void closePhase(String next) {
      phases[phase] = worst;
      worst = Duration.zero;
      phase = next;
    }

    final retain = Stopwatch();
    final resolver = Stopwatch();
    final replace = Stopwatch();

    await for (final event in worker.run(
      const RebuildIndexCommand(stale: {}),
    )) {
      switch (event) {
        case IndexBuiltEvent(:final index):
          closePhase('IndexBuilt->Communities');
          // What WorkspaceController._retainIndex does: copy every collection
          // into the instance the UI already holds.
          retain.start();
          final prior = retained;
          if (prior != null) {
            prior.notesByPath
              ..clear()
              ..addAll(index.notesByPath);
            prior.backlinksByTarget
              ..clear()
              ..addAll(index.backlinksByTarget);
            prior.problems
              ..clear()
              ..addAll(index.problems);
            prior.tasks
              ..clear()
              ..addAll(index.tasks);
          }
          retained = prior ?? index;
          retain.stop();
          resolver.start();
          LinkResolver(index.notes);
          resolver.stop();
        case CommunitiesBuiltEvent():
          closePhase('Communities->PkmsBuilt');
        case PkmsBuiltEvent():
          // PkmsBuiltEvent no longer carries the search index — that is the point
          // of the change this test measures. What used to happen here was a
          // ~40 ms deserialization of 14.9 MB followed by a ~31 ms replaceWith
          // rebuilding 107k posting Sets. Now it carries a validation report and
          // the query is a message round-trip, priced separately below.
          closePhase('PkmsBuilt->done');
        case WorkFailedEvent(:final message):
          fail('worker failed: $message');
        default:
          break;
      }
    }
    // The ticker only records a gap when it next fires, so cancelling straight
    // after the last handler would score the trailing phase as 0 ms — the
    // synchronous work in it would simply never be observed.
    await Future<void>.delayed(frame * 3);
    closePhase('search');

    // What replaced the transfer, measured the same way — as a *tick gap*, not a
    // stopwatch. That distinction is the whole point: the old cost was ~71 ms of
    // blocked root isolate (deserialize + replaceWith), whereas a query is an
    // await, so its wall-clock latency costs no frames. Comparing a stopwatch
    // around an await against blocking work would flatter or damn it at random.
    replace.start();
    final hits = await worker.search('tag-3');
    replace.stop();
    await Future<void>.delayed(frame * 3);
    closePhase('done');
    ticker.cancel();

    // Sanity: a silent no-op measurement is worse than none.
    expect(hits, isNotEmpty);
    expect(resolver.elapsedMicroseconds, greaterThan(0));

    // ignore: avoid_print
    print('ATTRIBUTION notes=$notes');
    for (final entry in phases.entries) {
      // ignore: avoid_print
      print('  waiting ${entry.key}: worst tick gap ${entry.value.inMilliseconds}ms');
    }
    // ignore: avoid_print
    print('  sync _retainIndex copy:      ${retain.elapsedMilliseconds}ms');
    // ignore: avoid_print
    print('  sync LinkResolver(notes):    ${resolver.elapsedMilliseconds}ms');
    // ignore: avoid_print
    print(
      '  search latency (not a stall): ${replace.elapsedMilliseconds}ms '
      '— see the "waiting search" gap above for what it cost in frames; '
      'it replaced ~40ms transfer + ~31ms replaceWith of blocked root isolate',
    );
  });
}
