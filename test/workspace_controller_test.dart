import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met in time');
    }
    await Future.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'controller owns open, source, save, and index with fake boundaries',
    () async {
      final storage = _MemoryStorage();
      final inspector = _FakeInspector();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: inspector,
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      const entry = VaultEntry(
        id: 'fake',
        name: 'Fake vault',
        path: '/not-used',
      );

      await controller.openVault(entry, storage: storage);

      // The fast path is already usable before the background index build
      // finishes.
      expect(controller.vault, isNotNull);
      expect(controller.note, startsWith('daily/'));
      expect(controller.source, contains('#import "/_system/tylog.typ"'));

      await _waitUntil(() => controller.index != null);
      expect(controller.index?.notes, hasLength(1));
      expect(inspector.calls, 1);

      controller.edit('${controller.source}\nController edit.\n');
      expect(controller.dirty, isTrue);
      await controller.save(syncAfter: false);
      expect(controller.dirty, isFalse);
      expect(
        await storage.readText(controller.note!),
        contains('Controller edit.'),
      );

      await controller.refreshIndex(always: true);
      expect(controller.index?.notes.single.metadataSource, 'typst-query');
      expect(inspector.calls, 2);
    },
  );

  test(
    'openVault loads user-vendored packages from _system/packages',
    () async {
      final storage = _MemoryStorage();
      final bytes = Uint8List.fromList(utf8.encode('#let hi() = "hello"\n'));
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      const entry = VaultEntry(
        id: 'vendored',
        name: 'Vendored vault',
        path: '/not-used',
      );

      // Establish the vault first (creates the settings marker + managed
      // files), then drop a user-vendored package in and reopen — this
      // mirrors a user copying a package into an existing vault.
      await controller.openVault(entry, storage: storage);
      await _waitUntil(
        () => controller.index != null && !controller.rebuilding,
      );
      await storage.writeBytes('_system/packages/foo/1.0.0/lib.typ', bytes);
      await controller.openVault(entry, storage: storage);
      await _waitUntil(
        () => controller.index != null && !controller.rebuilding,
      );

      expect(
        controller.typstPackageFiles['_system/packages/foo/1.0.0/lib.typ'],
        bytes,
      );
      expect(
        controller.typstPackageFiles['/_system/packages/foo/1.0.0/lib.typ'],
        bytes,
      );
    },
  );

  test(
    'openVault unblocks the UI before the background index finishes',
    () async {
      final storage = _GatedStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      const entry = VaultEntry(
        id: 'gated',
        name: 'Gated vault',
        path: '/not-used',
      );

      var notifyCount = 0;
      Object? vaultAtFirstNotify;
      Object? indexAtFirstNotify;
      controller.addListener(() {
        notifyCount++;
        if (notifyCount == 1) {
          vaultAtFirstNotify = controller.vault;
          indexAtFirstNotify = controller.index;
        }
      });

      await controller.openVault(entry, storage: storage);

      // openVault returns as soon as the fast reads are done: the
      // recursive scan the background rebuild needs is blocked on the
      // gate, so at the very first notification (and still once
      // openVault's own await completes) vault/note/source are already
      // populated but index is not.
      expect(vaultAtFirstNotify, isNotNull);
      expect(indexAtFirstNotify, isNull);
      expect(controller.vault, isNotNull);
      expect(controller.note, isNotNull);
      expect(controller.source, isNotEmpty);
      expect(controller.index, isNull);

      storage.gate.complete();
      await _waitUntil(() => controller.index != null);
      expect(controller.index?.notes, hasLength(1));
    },
  );

  test(
    'a cold index waits for the first sync, which carries peer donors',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);

      // Stall the sync's remote listing so "sync still running" is a state we
      // can observe rather than a wall-clock race.
      server.armGate();
      await controller.openVault(
        VaultEntry(
          id: 'cold',
          name: 'Cold vault',
          path: '/not-used',
          cloud: server.config,
        ),
        storage: _MemoryStorage(),
        trigger: 'setup',
      );
      await server.gateReached.future;

      // Long enough that a rebuild started in parallel would have finished
      // against this in-memory vault. It has not started: with no usable
      // index on disk, the expensive pass is chained behind the sync that
      // would deliver another device's donor. The UI is already usable.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(controller.vault, isNotNull);
      expect(controller.source, isNotEmpty);
      expect(
        controller.index,
        isNull,
        reason: 'the cold rebuild must not race the donor-carrying sync',
      );

      server.releaseGate.complete();
      await _waitUntil(() => controller.index != null);
    },
  );

  test(
    'a warm index rebuilds without waiting for the sync',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      final storage = _MemoryStorage();

      // First open with no cloud: leaves a current index.json behind.
      final warmup = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      await warmup.openVault(
        const VaultEntry(id: 'warm', name: 'Warm vault', path: '/not-used'),
        storage: storage,
      );
      await _waitUntil(() => warmup.index != null);
      warmup.dispose();

      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);

      server.armGate();
      await controller.openVault(
        VaultEntry(
          id: 'warm',
          name: 'Warm vault',
          path: '/not-used',
          cloud: server.config,
        ),
        storage: storage,
        trigger: 'resume',
      );
      await server.gateReached.future;

      // The cache is current, so there is nothing a donor could add — the
      // rebuild runs concurrently with the sync exactly as it always did.
      await _waitUntil(() => controller.index != null);
      expect(server.releaseGate.isCompleted, isFalse);
      server.releaseGate.complete();
    },
  );

  test('the link resolver exists as soon as the index does, at open', () async {
    // The mention-chip icon path (_resolveKind) resolves links on every span
    // rebuild. It used to build a whole-vault LinkResolver per chip; it now reads
    // the retained one, so that one must exist the moment `index` does — not
    // after the first scan lands. openVault's fast path assigns index from
    // index.json and does not go through _retainIndex, so it is the gap that
    // mattered: the editor renders chips during exactly that window.
    final storage = _MemoryStorage();

    // First open leaves a current index.json behind.
    final warmup = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    await warmup.openVault(
      const VaultEntry(id: 'warm', name: 'Warm vault', path: '/not-used'),
      storage: storage,
    );
    await _waitUntil(() => warmup.index != null);
    warmup.dispose();

    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'warm', name: 'Warm vault', path: '/not-used'),
      storage: storage,
    );

    // Deliberately no _waitUntil on the scan: this asserts the state right after
    // the fast path, which is the whole point.
    expect(controller.index, isNotNull);
    expect(controller.linkResolver, isNotNull);

    controller.close('done');
    expect(
      controller.linkResolver,
      isNull,
      reason: 'a closed vault must not leave a resolver answering for it',
    );
  });

  test('index-derived state is computed once per index, not per build', () async {
    final storage = _MemoryStorage();
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);

    await controller.openVault(
      const VaultEntry(id: 'derived', name: 'Derived', path: '/not-used'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    await _waitUntil(() => controller.communities != null);

    final revisionAfterOpen = controller.indexRevision;
    expect(revisionAfterOpen, greaterThan(0));
    expect(controller.linkResolver, isNotNull);
    final derived = controller.communities;

    // Re-deriving at the same revision is a no-op: the object is reused, not
    // recomputed. This is what stops the shell paying for it on every notify.
    await controller.refreshDerived();
    expect(identical(controller.communities, derived), isTrue);

    // A real rebuild bumps the revision even though _retainIndex hands back
    // the *same* VaultIndex object — the reason the cache cannot key on
    // index identity.
    final indexBefore = controller.index;
    await controller.rebuildIndex();
    await _waitUntil(() => controller.indexRevision > revisionAfterOpen);
    expect(
      identical(controller.index, indexBefore),
      isTrue,
      reason: 'the index is retained in place, so identity never changes',
    );
    await _waitUntil(() => controller.communities != null);
  });

  // `calendar` walks every note twice and sorts; `calendarDayMarks` walks the
  // result again. Both used to run inside the shell's `build()` — guarded only
  // by "a daily note is open", i.e. how the app launches — so they re-ran on
  // every autosave, sync tick and tab tap.
  test('calendar is derived once per index, not per build', () async {
    final storage = _MemoryStorage();
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);

    await controller.openVault(
      const VaultEntry(id: 'cal', name: 'Cal', path: '/not-used'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);

    final calendar = controller.calendar;
    final marks = controller.calendarDayMarks;
    expect(calendar, isNotNull);
    expect(
      identical(controller.calendar, calendar),
      isTrue,
      reason: 'reading it again must not recompute — that was the per-frame bug',
    );
    expect(identical(controller.calendarDayMarks, marks), isTrue);

    // A rebuild republishes it, even though the index object is retained.
    final revision = controller.indexRevision;
    await controller.rebuildIndex();
    await _waitUntil(() => controller.indexRevision > revision);
    expect(
      identical(controller.calendar, calendar),
      isFalse,
      reason: 'a new index revision must republish the derived calendar',
    );

    // Closing a vault must not leave the previous vault's calendar behind.
    controller.close('closed');
    expect(controller.calendar, isEmpty);
    expect(controller.communities, isNull);
  });

  test('a derivation landing after dispose does not throw', () async {
    final storage = _MemoryStorage();
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    await controller.openVault(
      const VaultEntry(id: 'disposed', name: 'Disposed', path: '/not-used'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);

    // Kick off a derivation and tear the controller down underneath it, the
    // way closing a vault or a hot restart does.
    final pending = controller.refreshDerived();
    controller.dispose();
    await expectLater(pending, completes);
  });

  test(
    'registered Android vault is never recreated when access is empty',
    () async {
      final storage = _MemoryStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.openVault(
        const VaultEntry(
          id: 'android',
          name: 'Android vault',
          path: '',
          storageKind: 'android-tree',
          treeUri: 'content://test/tree',
        ),
        storage: storage,
      );

      expect(controller.vault, isNull);
      expect(controller.status, startsWith('Open failed:'));
      expect(storage._directories, {''});
      expect(storage._files, isEmpty);
    },
  );

  test('a resolve announces itself before the reindex it triggers', () async {
    // resolveConflict used to notify exactly once, at the very end, and the
    // end was gated on refreshIndex(always: true) - a full scan plus one
    // queued repeat. Ten minutes of a row that looked untapped. The
    // resolution is complete when the remote write and record cleanup land;
    // reindexing follows from it and must not gate the report.
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);

    // A server that never answers, so the resolve stays in flight.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stalled = Completer<void>();
    server.listen((request) async {
      await stalled.future;
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    addTearDown(() {
      if (!stalled.isCompleted) stalled.complete();
      return server.close(force: true);
    });

    final storage = _MemoryStorage();
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    controller.cloud = NextcloudConfig(
      serverUrl:
          'http://${server.address.address}:${server.port}'
          '/remote.php/dav/files/alice/TyLogVault',
      username: 'alice',
      password: 'secret',
    );

    var notifications = 0;
    controller.addListener(() => notifications++);

    final resolving = controller.resolveConflict(
      SyncConflict(
        id: 'stuck',
        path: 'notes/a.typ',
        recordPath: '.tylog/conflicts/stuck.json',
        createdAt: DateTime.utc(2026),
        localExists: true,
        remoteExists: true,
      ),
      SyncConflictResolution.keepLocal,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      notifications,
      greaterThan(0),
      reason: 'the attempt must be observable while it is still running',
    );
    expect(controller.status, 'Resolving conflict…');

    stalled.complete();
    await resolving;
  });

  test('failed initial sync does not activate draft cloud config', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
      storage: _MemoryStorage(),
    );
    final draft = NextcloudConfig(
      serverUrl:
          'http://${server.address.address}:${server.port}/remote.php/dav/files/alice/TyLogVault',
      username: 'alice',
      password: 'secret',
    );

    expect(
      await controller.syncNow(
        trigger: 'setup',
        configOverride: draft,
        initialMode: InitialSyncMode.safeMerge,
      ),
      isFalse,
    );
    expect(controller.cloud, isNull);
    expect(controller.syncing, isFalse);
  });

  test(
    'autosave landing mid-sync does not spuriously flag a conflict',
    () async {
      // TestWidgetsFlutterBinding installs a global HttpOverrides that fakes
      // every HttpClient with 400 responses (to keep other widget tests off
      // the network); this test needs a real WebDAV round-trip, so lift it
      // for the duration of this test only.
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: _MemoryStorage(),
      );
      await _waitUntil(() => controller.index != null);
      final path = controller.note!;
      final original = controller.source;
      controller.cloud = server.config;

      // Baseline sync uploads the vault's starter content and clears the
      // slate for the sync under test.
      expect(await controller.syncNow(trigger: 'setup'), isTrue);
      expect(controller.syncConflicts, isEmpty);

      // Arm the gate so the *next* sync's remote listing stalls at a known
      // point, giving a deterministic (non-wall-clock) window to land an
      // autosave mid-sync, after sourceBeforeSync has already been captured.
      server.armGate();
      final syncFuture = controller.syncNow(trigger: 'manual');
      await server.gateReached.future;

      // The user typed during the sync; the 400ms autosave timer landed the
      // new content on disk before the sync finished.
      controller.edit('$original\nEdited during sync.\n');
      await controller.save(syncAfter: false);

      server.releaseGate.complete();
      expect(await syncFuture, isTrue);

      // Disk holds exactly what the editor shows (our own autosave) --
      // nothing diverged, so no conflict should have been filed. Checking
      // syncConflicts alone would not distinguish "never created" from
      // "created, then self-healed": either way `status` must never have
      // flashed the alarming "Needs attention" a genuine conflict would
      // cause, since concurrentConflict is set at creation time regardless
      // of any later self-heal.
      expect(controller.syncConflicts, isEmpty);
      expect(controller.status, isNot(contains('attention')));
      expect(
        await controller.vault!.storage.readText(path),
        contains('Edited during sync.'),
      );
    },
  );

  test(
    'typing after a mid-sync autosave does not spuriously flag a conflict',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: _MemoryStorage(),
      );
      await _waitUntil(() => controller.index != null);
      final path = controller.note!;
      final original = controller.source;
      controller.cloud = server.config;

      expect(await controller.syncNow(trigger: 'setup'), isTrue);
      expect(controller.syncConflicts, isEmpty);

      server.armGate();
      final syncFuture = controller.syncNow(trigger: 'manual');
      await server.gateReached.future;

      // The 400ms autosave lands mid-sync, then the user keeps typing: the
      // editor buffer is now *ahead* of its own autosave on disk. Both
      // versions are this session's own writes — pausing to think must not
      // produce a "before the pause vs after the pause" conflict.
      controller.edit('$original\nEdited during sync.\n');
      await controller.save(syncAfter: false);
      controller.edit('$original\nEdited during sync.\nKept typing.\n');

      server.releaseGate.complete();
      expect(await syncFuture, isTrue);

      expect(controller.syncConflicts, isEmpty);
      expect(controller.status, isNot(contains('attention')));
      expect(
        await controller.vault!.storage.readText(path),
        contains('Kept typing.'),
      );
    },
  );

  test(
    'a genuine foreign disk change during sync still files a conflict',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: _MemoryStorage(),
      );
      await _waitUntil(() => controller.index != null);
      final path = controller.note!;
      final original = controller.source;
      controller.cloud = server.config;

      expect(await controller.syncNow(trigger: 'setup'), isTrue);
      expect(controller.syncConflicts, isEmpty);

      server.armGate();
      final syncFuture = controller.syncNow(trigger: 'manual');
      await server.gateReached.future;

      // The editor changes (so editorChanged becomes true) but the disk is
      // written by something other than our own autosave, with content that
      // matches neither the original nor the edited editor text.
      controller.edit('$original\nEdited during sync.\n');
      await controller.vault!.storage.writeText(path, 'foreign disk content');

      server.releaseGate.complete();
      expect(await syncFuture, isTrue);

      expect(controller.syncConflicts, hasLength(1));
      expect(controller.syncConflicts.single.path, path);
    },
  );

  test(
    'edit() drives dirtyNotifier without notifying general listeners',
    () async {
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: _MemoryStorage(),
      );
      await _waitUntil(() => controller.index != null);
      final original = controller.source;

      var notifyCount = 0;
      controller.addListener(() => notifyCount++);
      var dirtyFlips = 0;
      controller.dirtyNotifier.addListener(() => dirtyFlips++);

      controller.edit('$original\nfirst edit\n');
      controller.edit('$original\nsecond edit\n'); // already dirty

      expect(notifyCount, 0, reason: 'keystrokes must not trigger a rebuild');
      expect(
        dirtyFlips,
        1,
        reason: 'only the false->true transition should fire',
      );
    },
  );

  test(
    'sync progress ticks notify syncProgressTick, not the general listener',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: _MemoryStorage(),
      );
      await _waitUntil(() => controller.index != null);
      controller.cloud = server.config;

      var notifyCount = 0;
      controller.addListener(() => notifyCount++);
      var tickCount = 0;
      controller.syncProgressTick.addListener(() => tickCount++);

      expect(await controller.syncNow(trigger: 'setup'), isTrue);

      expect(tickCount, greaterThan(0));
      // Bounded: only the handful of once-per-run transitions should hit the
      // general channel -- not once per file/stage transition. Those are start,
      // index-local-changes stage, the index publish, communities landing,
      // success, and finally. The index publish and communities were added when
      // the post-sync reindex moved onto `_scan`: it now publishes the index as
      // promptly as every other scan path instead of letting the end-of-sync
      // notify cover it. `refreshDerived` is unawaited, so its notify may or may
      // not land before syncNow returns -- hence a bound, not an equality.
      expect(notifyCount, lessThanOrEqualTo(8));
    },
  );

  test('the post-sync reindex goes through the scan driver, not an inline one', () async {
    // The post-sync reindex is the *most frequent* reindex trigger — any sync
    // that changed anything — and it used to call `opened.rebuildIndex` inline,
    // bypassing the worker entirely. Nothing pinned that, so nothing noticed.
    //
    // The donor file is the observable proof: the inline call passed no
    // `deviceId`, so `_writeIndexDonor` never ran on this path. Going through
    // `_scan` supplies it, which both fixes the missing donor (peers were not
    // seeing this device's notes after a sync-triggered reindex) and shows the
    // reindex is on the shared driver rather than a hand-rolled copy.
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await _GatedWebDavServer.start();
    addTearDown(() => server.server.close(force: true));
    final storage = _MemoryStorage();
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    controller.deviceId = 'test-device';
    await controller.openVault(
      const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    controller.cloud = server.config;

    const donor = '_system/index/test-device.json';
    // Whatever the open-time rebuild published, so the assertion below is about
    // the sync path and not about openVault.
    await storage.delete(donor);

    // An unsaved edit guarantees the reindex branch is taken: syncNow flushes it,
    // which lifts savedRevision above indexedRevision.
    controller.edit('#import "/_system/tylog.typ" as tylog\n// synced edit\n');
    expect(await controller.syncNow(trigger: 'setup'), isTrue);

    expect(
      await storage.exists(donor),
      isTrue,
      reason: 'the sync-triggered reindex did not publish the index donor, so it '
          'is not going through _scan',
    );
  });

  test('sync errors explain resumable network and authentication failures', () {
    expect(
      friendlySyncError(const SocketException('offline')),
      contains('Progress was saved'),
    );
    expect(
      friendlySyncError(const HttpException('PROPFIND unexpected status 401')),
      'Nextcloud rejected the login. Re-enter the app password.',
    );
    // resolveConflict's etag-mismatch guard throws a StateError whose own
    // message tells the user what to do; friendlySyncError must not swallow
    // that into a generic message, since the fallback path is the only thing
    // that surfaces it. The guard now refreshes and re-decides first, so this
    // only fires when the remote genuinely became something else — and the
    // message says so rather than "run sync and review".
    expect(
      friendlySyncError(StateError(NextcloudSync.remoteMovedDuringResolve)),
      contains(NextcloudSync.remoteMovedDuringResolve),
    );
  });

  test('stopCloudPolling cancels a running poll timer', () async {
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
      storage: _MemoryStorage(),
    );
    await _waitUntil(() => controller.index != null);
    controller.cloud = NextcloudConfig(
      serverUrl: 'http://127.0.0.1:1/remote.php/dav/files/alice/TyLogVault',
      username: 'alice',
      password: 'secret',
    );

    controller.startCloudPolling();
    expect(controller.hasActiveCloudPoll, isTrue);

    controller.stopCloudPolling();
    expect(controller.hasActiveCloudPoll, isFalse);
  });

  test('poll gate skips only a clean, known, unchanged root etag', () {
    expect(
      canSkipPoll(dirty: false, lastEtag: '"same"', currentEtag: 'same'),
      isTrue,
    );
    expect(
      canSkipPoll(dirty: true, lastEtag: '"same"', currentEtag: '"same"'),
      isFalse,
    );
    expect(
      canSkipPoll(dirty: false, lastEtag: '"before"', currentEtag: '"after"'),
      isFalse,
    );
    expect(
      canSkipPoll(dirty: false, lastEtag: null, currentEtag: '"same"'),
      isFalse,
    );
    expect(
      canSkipPoll(dirty: false, lastEtag: '"same"', currentEtag: null),
      isFalse,
    );
  });

  test(
    'a poll tick clears a phantom conflict instead of staying stuck forever',
    () async {
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: _MemoryStorage(),
      );
      await _waitUntil(() => controller.index != null);
      // Simulate self-heal: the in-memory list still holds a conflict, but
      // its record was already deleted from (or never written to) disk.
      controller.syncConflicts = [
        SyncConflict(
          id: 'phantom',
          path: 'notes/gone.typ',
          recordPath: '.tylog/conflicts/phantom.json',
          createdAt: DateTime.utc(2026),
          localExists: true,
          remoteExists: true,
        ),
      ];
      expect(controller.hasSyncConflicts, isTrue);

      await controller.pollTick();

      expect(controller.hasSyncConflicts, isFalse);
      expect(controller.syncConflicts, isEmpty);
    },
  );

  test(
    'a pending conflict no longer suspends sync for the rest of the vault',
    () async {
      // The A24 sat 695 articles behind for four hours because five junk
      // conflicts - none of them files the user had touched - suspended
      // polling vault-wide. The sync loop already skips conflicted paths one
      // by one, so the rest of the vault was never in danger.
      // TestWidgetsFlutterBinding fakes every HttpClient; this test needs the
      // real one to reach the loopback server.
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);

      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      final storage = _MemoryStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      controller.deviceId = 'test-device';
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: storage,
      );
      await _waitUntil(() => controller.index != null);
      controller.cloud = server.config;

      // A conflict record that is real on disk, so refreshSyncConflicts keeps
      // it rather than clearing it as a phantom.
      await storage.writeText(
        '.tylog/conflicts/stuck.json',
        jsonEncode({
          'id': 'stuck',
          'path': 'articles/junk.typ',
          'createdAt': DateTime.utc(2026).toIso8601String(),
          'localExists': true,
          'remoteExists': true,
        }),
      );
      await controller.refreshSyncConflicts();
      expect(controller.hasSyncConflicts, isTrue);

      // An unrelated local note that has never been uploaded.
      await storage.writeText('notes/unrelated.typ', '#let x = 1\n');

      await controller.pollTick();
      await _waitUntil(() => !controller.syncing);

      expect(
        server.uploaded,
        contains('notes/unrelated.typ'),
        reason: 'the rest of the vault must keep syncing',
      );
      expect(controller.hasSyncConflicts, isTrue,
          reason: 'the conflict itself still waits for review');
    },
  );

  test('reloadReadingState merges device files, newest openedAt wins, '
      'corrupt files are skipped', () async {
    final storage = _MemoryStorage();
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    const entry = VaultEntry(id: 'fake', name: 'Fake', path: '/not-used');
    await controller.openVault(entry, storage: storage);
    await _waitUntil(() => controller.index != null && !controller.rebuilding);

    // Missing directory → empty merged state, no throw.
    await controller.reloadReadingState();
    expect(controller.mergedReading, isEmpty);

    await storage.writeText(
      '_system/reading/aaaa.json',
      jsonEncode({
        'schema': 1,
        'recent': [
          {
            'path': 'articles/a.typ',
            'openedAt': '2026-07-17T10:00:00Z',
            'progress': 0.4,
          },
          {
            'path': 'articles/b.typ',
            'openedAt': '2026-07-18T09:00:00Z',
            'progress': 0.2,
          },
        ],
      }),
    );
    await storage.writeText(
      '_system/reading/bbbb.json',
      jsonEncode({
        'schema': 1,
        'recent': [
          {
            'path': 'articles/a.typ',
            'openedAt': '2026-07-18T08:00:00Z',
            'progress': 0.9,
          },
        ],
      }),
    );
    await storage.writeText('_system/reading/broken.json', 'not json{');

    await controller.reloadReadingState();
    expect(controller.mergedReading, hasLength(2));
    // Sorted newest-first; per-path newest openedAt wins (device bbbb's
    // fresher read of a.typ at 0.9 beats aaaa's 0.4).
    expect(controller.mergedReading.first.path, 'articles/b.typ');
    final a = controller.mergedReading.last;
    expect(a.path, 'articles/a.typ');
    expect(a.progress, 0.9);
  });

  test(
    'refreshIndex during an in-flight scan waits for the queued rescan',
    () async {
      final storage = _GatedScanStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: storage,
      );
      await _waitUntil(() => controller.index != null);
      // Settle any scan the open kicked off, so the gate below catches ours.
      await controller.refreshIndex(always: true);

      // Stall a scan right after it snapshots the file listing.
      storage.armGate();
      final first = controller.refreshIndex(always: true);
      await storage.gateReached.future;

      // A note lands mid-scan — the stalled pass's listing predates it, so
      // only the queued repeat can index it. The second refreshIndex must
      // not return until that repeat ran (the Problems-screen fix buttons
      // read fresh results right after this call).
      await controller.vault!.saveNote(
        'notes/MidScan.typ',
        '#show: tylog.note.with(id: "mid-scan", title: "Mid scan")\nBody',
      );
      final second = controller.refreshIndex(always: true);

      storage.release();
      await first;
      await second;

      expect(
        controller.index!.notesByPath.containsKey('notes/MidScan.typ'),
        isTrue,
      );
    },
  );

  test('shouldRolloverToday detects a calendar day change', () {
    final openedAt = DateTime(2026, 7, 15, 23, 55);
    expect(
      shouldRolloverToday(
        openedAt: openedAt,
        now: DateTime(2026, 7, 15, 23, 59),
      ),
      isFalse,
    );
    expect(
      shouldRolloverToday(openedAt: openedAt, now: DateTime(2026, 7, 16, 0, 1)),
      isTrue,
    );
    expect(
      shouldRolloverToday(
        openedAt: DateTime(2026, 12, 31, 23, 59),
        now: DateTime(2027, 1, 1, 0, 1),
      ),
      isTrue,
    );
  });
}

class _FakeInspector implements TypstInspector {
  int calls = 0;

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    calls++;
    final note = scanNote(input.path, input.source);
    return [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {
          'schema': 1,
          'entity': 'note',
          'id': note.id,
          'title': note.title,
          'kind': note.kind,
          'date': note.date,
          'tags': note.tags,
          'aliases': note.aliases,
          'properties': note.properties,
        },
      ),
    ];
  }
}

/// Stalls every armed `list()` call *after* it has captured its snapshot, so
/// a test can land a write that the in-flight scan's listing predates —
/// exactly the "file saved while a scan runs" race the coalesced-rescan
/// logic exists for.
class _GatedScanStorage extends _MemoryStorage {
  Completer<void>? _armed;
  Completer<void> gateReached = Completer<void>();

  void armGate() {
    gateReached = Completer<void>();
    _armed = Completer<void>();
  }

  void release() {
    final gate = _armed;
    _armed = null;
    gate?.complete();
  }

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final result = await super.list(path: path, recursive: recursive);
    final gate = _armed;
    if (gate != null) {
      if (!gateReached.isCompleted) gateReached.complete();
      await gate.future;
    }
    return result;
  }
}

class _MemoryStorage extends VaultStorage {
  final Map<String, Uint8List> _files = {};
  final Set<String> _directories = {''};

  @override
  Future<void> createDirectory(String path) async {
    if (path.isEmpty) return;
    final parts = path.split('/');
    for (var i = 1; i <= parts.length; i++) {
      _directories.add(parts.take(i).join('/'));
    }
  }

  @override
  Future<void> delete(String path) async {
    _files.removeWhere((key, _) => key == path || key.startsWith('$path/'));
    _directories.removeWhere((key) => key == path || key.startsWith('$path/'));
  }

  @override
  Future<bool> exists(String path) async =>
      _files.containsKey(path) || _directories.contains(path);

  @override
  Future<String> hash(String path) async => base64.encode(_files[path]!);

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final prefix = path.isEmpty ? '' : '$path/';
    bool included(String candidate) {
      if (!candidate.startsWith(prefix) || candidate == path) return false;
      return recursive || !candidate.substring(prefix.length).contains('/');
    }

    return [
      for (final directory in _directories)
        if (included(directory))
          VaultStorageEntry(path: directory, isDirectory: true),
      for (final entry in _files.entries)
        if (included(entry.key))
          VaultStorageEntry(
            path: entry.key,
            isDirectory: false,
            size: entry.value.length,
            modified: DateTime.utc(2026, 7, 14),
          ),
    ];
  }

  @override
  Future<Uint8List> readBytes(String path) async => _files[path]!;

  @override
  Future<VaultStorageEntry?> stat(String path) async {
    final bytes = _files[path];
    if (bytes != null) {
      return VaultStorageEntry(
        path: path,
        isDirectory: false,
        size: bytes.length,
        modified: DateTime.utc(2026, 7, 14),
      );
    }
    return _directories.contains(path)
        ? VaultStorageEntry(path: path, isDirectory: true)
        : null;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final slash = path.lastIndexOf('/');
    if (slash > 0) await createDirectory(path.substring(0, slash));
    _files[path] = Uint8List.fromList(bytes);
  }
}

/// A storage double whose recursive listing blocks until [gate] completes,
/// simulating a slow full-vault scan (e.g. Android SAF) so tests can observe
/// state while the background index rebuild is still in flight. Non-recursive
/// listing (used by the fast open path, e.g. sync-conflict lookup) is left
/// unblocked so `openVault` itself does not hang.
class _GatedStorage extends _MemoryStorage {
  final gate = Completer<void>();

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    if (recursive) await gate.future;
    return super.list(path: path, recursive: recursive);
  }
}

/// A minimal WebDAV double whose remote listing (PROPFIND) can be paused
/// mid-request via [armGate], then resumed via [releaseGate]. This gives a
/// deterministic window to observe/mutate state while a real `syncNow()` is
/// in flight, without relying on wall-clock timing races.
class _GatedWebDavServer {
  _GatedWebDavServer._(this.server);

  static const _root = '/remote.php/dav/files/alice/TyLogVault/';

  final HttpServer server;
  final Map<String, List<int>> _files = {};
  /// Paths the client PUT, so a test can assert what actually synced.
  final uploaded = <String>[];
  final Map<String, String> _etags = {};
  var _gateArmed = false;
  var gateReached = Completer<void>();
  var releaseGate = Completer<void>();

  static Future<_GatedWebDavServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final instance = _GatedWebDavServer._(server);
    instance._listen();
    return instance;
  }

  NextcloudConfig get config => NextcloudConfig(
    serverUrl:
        'http://${server.address.address}:${server.port}'
        '/remote.php/dav/files/alice/TyLogVault',
    username: 'alice',
    password: 'secret',
  );

  /// Arms the gate for the next PROPFIND only.
  void armGate() {
    _gateArmed = true;
    gateReached = Completer<void>();
    releaseGate = Completer<void>();
  }

  void _listen() {
    server.listen((request) async {
      final path = request.uri.path.startsWith(_root)
          ? request.uri.path.substring(_root.length)
          : '';
      switch (request.method) {
        case 'MKCOL':
          request.response.statusCode = HttpStatus.methodNotAllowed;
        case 'PROPFIND':
          if (_gateArmed) {
            _gateArmed = false;
            gateReached.complete();
            await releaseGate.future;
          }
          request.response.statusCode = 207;
          request.response.write('<d:multistatus xmlns:d="DAV:">');
          for (final entry in _files.entries) {
            request.response.write(
              '<d:response><d:href>$_root${entry.key}</d:href>'
              '<d:propstat><d:prop>'
              '<d:getlastmodified>'
              '${HttpDate.format(DateTime.now().toUtc())}'
              '</d:getlastmodified>'
              '<d:getetag>${_etags[entry.key]}</d:getetag>'
              '<d:getcontentlength>${entry.value.length}</d:getcontentlength>'
              '</d:prop></d:propstat></d:response>',
            );
          }
          request.response.write('</d:multistatus>');
        case 'GET':
          final bytes = _files[path];
          if (bytes == null) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.headers.set(HttpHeaders.etagHeader, _etags[path]!);
            request.response.add(bytes);
          }
        case 'PUT':
          final bytes = await request.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          _files[path] = bytes;
          uploaded.add(path);
          _etags[path] = '"etag-${DateTime.now().microsecondsSinceEpoch}"';
          request.response.statusCode = HttpStatus.created;
          request.response.headers.set('OC-Etag', _etags[path]!);
        default:
          request.response.statusCode = HttpStatus.methodNotAllowed;
      }
      await request.response.close();
    });
  }
}
