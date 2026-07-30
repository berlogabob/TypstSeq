import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/search_index.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_worker.dart';

/// Covers the worker isolate against real native Typst.
///
/// The whole "move indexing off the UI isolate" change rests on one assumption
/// that only a real engine can settle: that `RustLib.init()` and a Typst compile
/// work in a *spawned* isolate, not just the root one. `RustLib.instance` is a
/// `static final` and Dart statics are isolate-local, so each isolate should get
/// its own entrypoint over the process-wide FRB handler — but if that were
/// wrong, the worker would have to proxy every `inspect` back to root and the
/// design would change shape. `metadataSource == 'typst-query'` below is the
/// proof: the source-parsing fallback reports `'fallback'` instead.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<({Directory root, VaultEntry entry})> seed(int notes) async {
    final root = await Directory.systemTemp.createTemp('tylog_worker_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();
    for (var i = 0; i < notes; i++) {
      await vault.saveNote(
        'notes/Note$i.typ',
        '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "note-$i", title: "Note $i", tags: ("spike",))
#tylog.tag("spike")
#tylog.task(id: "task-$i", text: "Do $i")
''',
      );
    }
    return (
      root: root,
      entry: VaultEntry(id: 'worker', name: 'Worker', path: root.path),
    );
  }

  testWidgets('rebuild runs natively inside the worker isolate', (_) async {
    final vault = await seed(3);
    final worker = await VaultWorkerClient.spawn(entry: vault.entry);
    addTearDown(worker.dispose);

    final events = await worker
        .run(const RebuildIndexCommand(force: true, stale: {}))
        .toList();

    final failures = events.whereType<WorkFailedEvent>();
    expect(failures, isEmpty, reason: '${failures.map((e) => e.message)}');
    expect(events.last, isA<WorkDoneEvent>());

    final built = events.whereType<IndexBuiltEvent>().single.index;
    expect(built.notesByPath, hasLength(3));
    // The point of the whole exercise: native Typst compiled off the root
    // isolate. Source-parsing fallback would say 'fallback' here.
    expect(
      built.notesByPath['notes/Note0.typ']?.metadataSource,
      'typst-query',
    );
    expect(built.tasks, hasLength(3));

    // Both derived passes crossed the port as finished data, so the root
    // isolate never copies the index to compute them.
    expect(events.whereType<CommunitiesBuiltEvent>(), hasLength(1));
    final pkms = events.whereType<PkmsBuiltEvent>().single;
    expect(pkms.report.summary(), contains('errors='));

    // The search index deliberately never crosses the port; it is queried in
    // place. This is the pin that the worker answers a search at all.
    expect(await worker.search('spike'), isNotEmpty);
    expect(
      (await worker.search('spike')).map((r) => r.path),
      contains('notes/Note0.typ'),
    );
    expect(await worker.search('nothingmatchesthis'), isEmpty);
  });

  testWidgets('search is answered while a rebuild is running', (_) async {
    // The risky half of keeping the index in the worker. `run` is single-flight,
    // so a query cannot go through it during a rebuild; SearchCommand takes its
    // own reply port and is handled without awaiting, like Cancel. If either of
    // those were wrong this would hang or throw rather than answer.
    final vault = await seed(400);
    final worker = await VaultWorkerClient.spawn(entry: vault.entry);
    addTearDown(worker.dispose);

    // Populate the worker's index first, so there is something to find.
    await worker.run(const RebuildIndexCommand(force: true, stale: {})).toList();

    List<PkmsSearchResult>? midScan;
    // `await for`, not `forEach`: forEach does not await an async callback, so the
    // reply could have landed after the rebuild finished and the test would have
    // proved nothing. Awaiting inside the loop means the reply demonstrably
    // arrives while the worker is still scanning.
    await for (final event in worker.run(
      const RebuildIndexCommand(force: true, stale: {}),
    )) {
      if (event is IndexProgressEvent &&
          event.complete >= 100 &&
          event.complete < event.total &&
          midScan == null) {
        midScan = await worker.search('spike');
      }
    }

    expect(
      midScan,
      isNotNull,
      reason: 'no progress tick arrived, so nothing was queried mid-scan',
    );
    expect(midScan, isNotEmpty);
  });

  testWidgets('cancel is observed mid-scan and reported as cancelled', (
    _,
  ) async {
    // Progress ticks every 100 notes, so waiting for the tick at 100 proves the
    // scan loop is genuinely mid-flight with ~1900 notes still to go — no sleep,
    // nothing to tune per machine. A forced scan re-compiles every note, so this
    // exercises the scanner's per-32-note yield delivering the cancel rather
    // than a no-op cancel arriving after the work already finished.
    final vault = await seed(2000);
    final worker = await VaultWorkerClient.spawn(entry: vault.entry);
    addTearDown(worker.dispose);

    final collected = <VaultWorkerEvent>[];
    final done = worker
        .run(const RebuildIndexCommand(force: true, stale: {}))
        .forEach((event) {
          collected.add(event);
          if (event is IndexProgressEvent && event.complete >= 100) {
            worker.cancel();
          }
        });
    await done;

    final failure = collected.whereType<WorkFailedEvent>().single;
    expect(failure.cancelled, isTrue);
    // Cancelled means cancelled: no index published, and nothing downstream ran.
    expect(collected.whereType<IndexBuiltEvent>(), isEmpty);
    expect(collected.whereType<PkmsBuiltEvent>(), isEmpty);

    // ...and the worker is still usable afterwards — a cancel must not wedge the
    // engine it shares with the next command.
    final after = await worker
        .run(const RebuildIndexCommand(stale: {}))
        .toList();
    expect(after.whereType<WorkFailedEvent>(), isEmpty);
    expect(
      after.whereType<IndexBuiltEvent>().single.index.notesByPath,
      hasLength(2000),
    );
  });
}
