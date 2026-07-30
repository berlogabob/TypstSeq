import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/search_index.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_worker.dart';

/// The worker's only automated coverage that CI actually runs.
///
/// `ci.yml` runs `flutter analyze` + `flutter test`, and until this file existed
/// neither reached `lib/vault_worker.dart` at all: `WorkspaceController._useWorker`
/// is `inspector == null`, every controller test supplies a fake inspector, and the
/// four `integration_test/vault_worker_*.dart` files are invoked by nothing — not
/// CI, not `make test`, not `make verify`. So the whole worker protocol shipped
/// with a hand-run test as its only guard.
///
/// This needs no native Typst: `_createInspector` fails here and the scan falls
/// back to source parsing, which is exactly what makes it runnable on a bare CI
/// box. The native path stays covered by the integration tests.
void main() {
  Future<({Directory root, VaultEntry entry})> seed(int notes) async {
    final root = await Directory.systemTemp.createTemp('tylog_worker_unit_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();
    for (var i = 0; i < notes; i++) {
      await vault.saveNote(
        'notes/Note$i.typ',
        '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "note-$i", title: "Note $i", tags: ("unit",))
#tylog.tag("unit")
#tylog.task(id: "task-$i", text: "Do $i")
''',
      );
    }
    return (
      root: root,
      entry: VaultEntry(id: 'unit', name: 'Unit', path: root.path),
    );
  }

  test('a rebuild round-trips through the worker isolate', () async {
    final vault = await seed(4);
    final worker = await VaultWorkerClient.spawn(entry: vault.entry);
    addTearDown(worker.dispose);

    final events = await worker
        .run(const RebuildIndexCommand(force: true, stale: {}))
        .toList();

    final failures = events.whereType<WorkFailedEvent>();
    expect(failures, isEmpty, reason: '${failures.map((e) => e.message)}');
    expect(events.last, isA<WorkDoneEvent>());

    final built = events.whereType<IndexBuiltEvent>().single.index;
    expect(built.notesByPath, hasLength(4));
    expect(built.tasks, hasLength(4));
    // No native Typst on a CI box, so the scanner's source-parsing fallback is
    // what ran — and the worker must now say so rather than degrade in silence.
    expect(built.notesByPath['notes/Note0.typ']?.metadataSource, 'fallback');

    expect(events.whereType<CommunitiesBuiltEvent>(), hasLength(1));
    final report = events.whereType<PkmsBuiltEvent>().single.report;
    expect(
      report.problems.map((p) => p.code),
      contains('typst-engine-unavailable'),
      reason: 'a failed native init must be reported, not swallowed',
    );
  });

  test('the worker answers a search without shipping the index', () async {
    final vault = await seed(4);
    final worker = await VaultWorkerClient.spawn(entry: vault.entry);
    addTearDown(worker.dispose);

    await worker.run(const RebuildIndexCommand(force: true, stale: {})).toList();

    final hits = await worker.search('unit');
    expect(hits, isNotEmpty);
    expect(hits.map((r) => r.path), contains('notes/Note0.typ'));
    expect(await worker.search('nothingmatchesthisquery'), isEmpty);
  });

  test('run is single-flight and says so instead of cross-talking', () async {
    final vault = await seed(4);
    final worker = await VaultWorkerClient.spawn(entry: vault.entry);
    addTearDown(worker.dispose);

    // Every run subscribes to the same relay, so two overlapping runs would each
    // receive the other's events. Throwing is the contract.
    final first = worker.run(const RebuildIndexCommand(stale: {}));
    expect(
      () => worker.run(const RebuildIndexCommand(stale: {})),
      throwsStateError,
    );
    await first.toList();

    // ...and the guard clears, so the next command still works.
    final again = await worker.run(const RebuildIndexCommand(stale: {})).toList();
    expect(again.whereType<WorkFailedEvent>(), isEmpty);
  });

  test('a cancelled rebuild publishes no index and leaves the worker usable', () async {
    final vault = await seed(400);
    final worker = await VaultWorkerClient.spawn(entry: vault.entry);
    addTearDown(worker.dispose);

    final collected = <VaultWorkerEvent>[];
    await for (final event in worker.run(
      const RebuildIndexCommand(force: true, stale: {}),
    )) {
      collected.add(event);
      if (event is IndexProgressEvent &&
          event.complete >= 100 &&
          event.complete < event.total) {
        worker.cancel();
      }
    }

    final failure = collected.whereType<WorkFailedEvent>().single;
    expect(failure.cancelled, isTrue);
    expect(collected.whereType<IndexBuiltEvent>(), isEmpty);

    final after = await worker
        .run(const RebuildIndexCommand(stale: {}))
        .toList();
    expect(after.whereType<WorkFailedEvent>(), isEmpty);
    expect(
      after.whereType<IndexBuiltEvent>().single.index.notesByPath,
      hasLength(400),
    );
  });

  test('search results survive a query issued during a rebuild', () async {
    final vault = await seed(400);
    final worker = await VaultWorkerClient.spawn(entry: vault.entry);
    addTearDown(worker.dispose);

    await worker.run(const RebuildIndexCommand(force: true, stale: {})).toList();

    List<PkmsSearchResult>? midScan;
    await for (final event in worker.run(
      const RebuildIndexCommand(force: true, stale: {}),
    )) {
      if (event is IndexProgressEvent &&
          event.complete >= 100 &&
          event.complete < event.total &&
          midScan == null) {
        midScan = await worker.search('unit');
      }
    }

    expect(midScan, isNotNull, reason: 'nothing was queried mid-scan');
    expect(midScan, isNotEmpty);
  });
}
