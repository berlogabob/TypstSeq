import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:tylog_core/storage.dart';
import 'package:tylog_core/vault.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault_lock.dart';
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
  final defaultRetryDelays = NextcloudSync.connectionRetryDelays;
  setUp(() => NextcloudSync.connectionRetryDelays = const [Duration.zero]);
  tearDown(() => NextcloudSync.connectionRetryDelays = defaultRetryDelays);

  test(
    'late open success and failure cannot replace the newer vault',
    () async {
      final oldStorage = _GatedOpenStorage();
      final newStorage = _MemoryStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);

      oldStorage.arm();
      final oldOpen = controller.openVault(
        const VaultEntry(id: 'old', name: 'Old', path: '/old'),
        storage: oldStorage,
      );
      await oldStorage.reached.future;
      await controller.openVault(
        const VaultEntry(id: 'new', name: 'New', path: '/new'),
        storage: newStorage,
      );
      oldStorage.release();
      await oldOpen;
      expect(controller.entry?.id, 'new');

      final failingStorage = _GatedOpenStorage()..failAfterGate = true;
      failingStorage.arm();
      final failedOpen = controller.openVault(
        const VaultEntry(id: 'failed', name: 'Failed', path: '/failed'),
        storage: failingStorage,
      );
      await failingStorage.reached.future;
      await controller.openVault(
        const VaultEntry(id: 'newer', name: 'Newer', path: '/newer'),
        storage: _MemoryStorage(),
      );
      failingStorage.release();
      await failedOpen;
      expect(controller.entry?.id, 'newer');
    },
  );

  test(
    'late sync success and failure cannot clear newer vault state',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      Future<void> run({required bool fail}) async {
        final server = await _GatedWebDavServer.start();
        addTearDown(() => server.server.close(force: true));
        server.propfindStatus = 207;
        final controller = WorkspaceController(
          taskScheduler: TaskScheduler(),
          inspector: _FakeInspector(),
          reconcileTasks: (_) async {},
        );
        addTearDown(controller.dispose);
        await controller.openVault(
          const VaultEntry(id: 'old-sync', name: 'Old', path: '/old'),
          storage: _MemoryStorage(),
        );
        await _waitUntil(
          () => controller.index != null && !controller.rebuilding,
        );
        controller.cloud = server.config;
        expect(await controller.syncNow(trigger: 'setup'), isTrue);
        server.propfindStatus = fail ? HttpStatus.internalServerError : 207;
        server.armGate();
        final oldSync = controller.syncNow(trigger: 'manual');
        await server.gateReached.future;
        await controller.openVault(
          const VaultEntry(id: 'new-sync', name: 'New', path: '/new'),
          storage: _MemoryStorage(),
        );
        server.releaseGate.complete();
        await oldSync.timeout(const Duration(seconds: 1));
        expect(controller.entry?.id, 'new-sync');
        expect(controller.syncing, isFalse);
        expect(controller.syncError, isNull);
      }

      await run(fail: false);
      await run(fail: true);
    },
  );

  test(
    'late scan settles after close without publishing old index state',
    () async {
      final storage = _GatedScanStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'scan', name: 'Scan', path: '/scan'),
        storage: storage,
      );
      await _waitUntil(
        () => controller.index != null && !controller.rebuilding,
      );
      storage.armGate();
      final oldScan = controller.refreshIndex(always: true);
      await storage.gateReached.future;
      controller.close('closed');
      storage.release();
      await oldScan.timeout(const Duration(seconds: 1));
      expect(controller.vault, isNull);
      expect(controller.index, isNull);
      expect(controller.searchReady, isFalse);
      expect(controller.searchRevision, 0);
      expect(controller.status, 'closed');
    },
  );

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
      expect(controller.searchReady, isTrue);
      expect(controller.searchRevision, greaterThan(0));

      controller.edit('${controller.source}\nController edit.\n');
      expect(controller.dirty, isTrue);
      expect(await controller.save(syncAfter: false), isTrue);
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
    'mutateNote preserves a newer open edit during its gated save',
    () async {
      final storage = _GatedWriteStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'mutate-open', name: 'Mutate', path: '/mutate'),
        storage: storage,
      );
      await _waitUntil(() => controller.index != null);
      final path = controller.note!;
      storage.armWrite();
      final mutation = controller.mutateNote(
        path,
        (value) => '$value\nmutated',
      );
      await storage.gateReached.future;
      controller.edit('${controller.source}\nnewer');
      storage.releaseWrite();
      expect(await mutation, isFalse);
      expect(controller.dirty, isTrue);
      expect(controller.source, endsWith('newer'));
      await controller.save(syncAfter: false);
      expect(await storage.readText(path), endsWith('newer'));
    },
  );

  test('mutateNote serializes delayed closed-note read-modify-write', () async {
    final storage = _MemoryStorage();
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'mutate-closed', name: 'Mutate', path: '/mutate'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    final path = 'notes/closed.typ';
    await storage.writeText(path, 'base');
    final first = controller.mutateNote(path, (value) => '$value\nfirst');
    final second = controller.mutateNote(path, (value) => '$value\nsecond');
    expect(await Future.wait([first, second]), [true, true]);
    expect(await storage.readText(path), 'base\nfirst\nsecond');
  });

  test(
    'queued old-vault mutation cannot write the replacement vault',
    () async {
      final oldStorage = _GatedWriteStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'mutation-old', name: 'Old', path: '/old'),
        storage: oldStorage,
      );
      await _waitUntil(() => controller.index != null);
      final path = controller.note!;
      oldStorage.armWrite();
      final first = controller.mutateNote(path, (value) => '$value\nfirst');
      await oldStorage.gateReached.future;
      final queued = controller.mutateNote(path, (value) => '$value\nqueued');
      final newStorage = _MemoryStorage();
      final replacement = controller.openVault(
        const VaultEntry(id: 'mutation-new', name: 'New', path: '/new'),
        storage: newStorage,
      );
      oldStorage.releaseWrite();
      await Future.wait([first, queued, replacement]);
      expect(controller.entry?.id, 'mutation-new');
      expect(await newStorage.readText(path), isNot(contains('queued')));
    },
  );

  test(
    'task mutations preserve recurring behavior and surface bad IDs',
    () async {
      final storage = _MemoryStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'task-mutate', name: 'Tasks', path: '/tasks'),
        storage: storage,
      );
      await _waitUntil(() => controller.index != null);
      const path = 'notes/tasks.typ';
      await storage.writeText(
        path,
        '#tylog.task(id: "once", text: "One", status: "todo")\n'
        '#tylog.task(id: "repeat", text: "Repeat", recurrence: "weekly", '
        'status: "todo")\n',
      );
      expect(
        await controller.mutateNote(
          path,
          (source) => replaceTaskStatus(source, 'once', 'done'),
        ),
        isTrue,
      );
      expect(
        await controller.mutateNote(
          path,
          (source) =>
              completeTaskOccurrence(source, 'repeat', '2026-09-09T00:00:00Z'),
        ),
        isTrue,
      );
      final updated = await storage.readText(path);
      expect(updated, contains('status: "done"'));
      expect(updated, contains('2026-09-09T00:00:00Z'));
      expect(
        () => controller.mutateNote(
          path,
          (source) => replaceTaskStatus(source, 'missing', 'done'),
        ),
        throwsStateError,
      );
      await controller.mutateNote(
        path,
        (source) =>
            '$source'
            '#tylog.task(id: "duplicate", text: "Two", status: "todo")\n'
            '#tylog.task(id: "duplicate", text: "Three", status: "todo")\n',
      );
      expect(
        () => controller.mutateNote(
          path,
          (source) => replaceTaskStatus(source, 'duplicate', 'done'),
        ),
        throwsStateError,
      );
    },
  );

  test('mutateNote propagates a storage write failure', () async {
    final storage = _FailingWriteStorage();
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'task-failure', name: 'Tasks', path: '/tasks'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    const path = 'notes/fail.typ';
    await storage.writeText(path, 'base');
    storage.failWrites = true;
    expect(
      () => controller.mutateNote(path, (source) => '$source\nchanged'),
      throwsA(isA<FileSystemException>()),
    );
  });

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
    'worker startup does not decode the cached index on the root isolate',
    () async {
      final storage = _IndexReadGatedStorage();
      await storage.writeText(
        TylogVaultPaths.settings,
        '{"version":5}',
      );
      await storage.writeText(TylogVaultPaths.index, '{}');
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.openVault(
        const VaultEntry(id: 'worker-cache', name: 'Worker cache', path: '/db'),
        storage: storage,
      );

      expect(storage.indexReadStarted, isFalse);
      expect(controller.vault, isNotNull);
      expect(controller.note, isNotNull);
      expect(controller.index, isNull);

      storage.gate.complete();
      await _waitUntil(() => controller.index != null);
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

  test('a warm index rebuilds without waiting for the sync', () async {
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
  });

  test(
    'startup foreground service has one owner and stops on success/failure',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      const channel = MethodChannel('org.tylog.tylog/saf');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      server.armGate();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
        useForegroundService: true,
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        VaultEntry(
          id: 'foreground-success',
          name: 'Foreground success',
          path: '/not-used',
          cloud: server.config,
        ),
        storage: _MemoryStorage(),
        trigger: 'startup',
      );
      await server.gateReached.future;
      expect(
        calls.where((method) => method == 'startSyncForeground'),
        hasLength(1),
      );
      expect(await controller.syncNow(trigger: 'resume'), isFalse);
      expect(
        calls.where((method) => method == 'startSyncForeground'),
        hasLength(1),
      );
      server.releaseGate.complete();
      await _waitUntil(() => !controller.syncing && !controller.rebuilding);
      expect(
        calls.where((method) => method == 'stopSyncForeground'),
        hasLength(1),
      );

      final failedServer = await _GatedWebDavServer.start();
      addTearDown(() => failedServer.server.close(force: true));
      failedServer.propfindStatus = HttpStatus.internalServerError;
      final failed = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
        useForegroundService: true,
      );
      addTearDown(failed.dispose);
      await failed.openVault(
        VaultEntry(
          id: 'foreground-failure',
          name: 'Foreground failure',
          path: '/not-used',
          cloud: failedServer.config,
        ),
        storage: _MemoryStorage(),
        trigger: 'startup',
      );
      await _waitUntil(() => failed.index != null && !failed.syncing);
      expect(
        calls.where((method) => method == 'startSyncForeground'),
        hasLength(2),
      );
      expect(
        calls.where((method) => method == 'stopSyncForeground'),
        hasLength(2),
      );
    },
  );

  test(
    'cold startup publishes one index for transfer, unchanged, or failure',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);

      Future<int> openAndCount({
        required int status,
        Map<String, List<int>> files = const {},
      }) async {
        final server = await _GatedWebDavServer.start();
        addTearDown(() => server.server.close(force: true));
        server.propfindStatus = status;
        for (final entry in files.entries) {
          server._files[entry.key] = entry.value;
          server._etags[entry.key] = '"${entry.key}-etag"';
        }
        final inspector = _FakeInspector();
        var publications = 0;
        final controller = WorkspaceController(
          taskScheduler: TaskScheduler(),
          inspector: inspector,
          reconcileTasks: (_) async {
            publications++;
          },
        );
        addTearDown(controller.dispose);
        await controller.openVault(
          VaultEntry(
            id: 'cold-$status-${files.length}',
            name: 'Cold vault',
            path: '/not-used',
            cloud: server.config,
          ),
          storage: _MemoryStorage(),
          trigger: 'startup',
        );
        await _waitUntil(
          () =>
              controller.index != null &&
              !controller.syncing &&
              !controller.rebuilding,
        );
        return publications;
      }

      expect(
        await openAndCount(
          status: 207,
          files: {'notes/remote.typ': utf8.encode('#let remote = true\n')},
        ),
        1,
        reason: 'transferred content is indexed by sync exactly once',
      );
      expect(
        await openAndCount(status: 207),
        1,
        reason: 'unchanged remote still gets one usable startup index',
      );
      expect(
        await openAndCount(status: HttpStatus.internalServerError),
        1,
        reason: 'pre-transfer failure still gets one usable startup index',
      );
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

  test(
    'index-derived state is computed once per index, not per build',
    () async {
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
    },
  );

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
    // Non-empty first: `calendar` is non-nullable and defaults to `const []`,
    // so `isNotNull` was dead and identity between two `const []`s is trivially
    // true — the assertions below only mean something once there is something
    // to reuse.
    expect(calendar, isNotEmpty);
    expect(marks.daily, isNotEmpty);
    expect(
      identical(controller.calendar, calendar),
      isTrue,
      reason:
          'reading it again must not recompute — that was the per-frame bug',
    );
    expect(identical(controller.calendarDayMarks, marks), isTrue);
    // This identity is the whole contract. VaultIndex.calendar walks every
    // note twice, allocates per daily, per date ref and per due task, and
    // sorts the result — 20-40 ms on a 6,200-note vault — and it used to run
    // inside the shell build(), so every autosave, sync tick and tab tap paid
    // it. Caching it here is what fixed that, and reusing the same instance is
    // how you can tell it is still cached.

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

  test(
    'a scan that changes nothing does not rewrite the search index',
    () async {
      // The search index is ~43 MB of JSON encoded to ~12 MB of gzip.
      // buildStorage returns the *same instance* when every note hit the cache,
      // so identity is an exact "nothing to write" test. The worker path has
      // always had that guard; this in-process path - the one the suite
      // overwhelmingly exercises - and the Android background service did not,
      // so every no-op scan rewrote the whole file.
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
      await controller.refreshIndex(always: true);

      // Positive control first: without it this test passes vacuously if the
      // search index is never written at all, or if the filename changes.
      expect(
        storage.writes.where((path) => path.contains('search-index')),
        isNotEmpty,
        reason: 'the first build must actually write one',
      );

      storage.writes.clear();
      await controller.refreshIndex(always: true);

      expect(
        storage.writes.where((path) => path.contains('search-index')),
        isEmpty,
        reason: 'nothing changed, so there is nothing to write',
      );
    },
  );

  test('a bulk resolve clears every record it covers', () async {
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
    await controller.openVault(
      const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    await controller
        .refreshIndex(always: true)
        .timeout(const Duration(seconds: 5));
    controller.cloud = server.config;

    for (final name in ['a', 'b', 'c']) {
      await storage.writeText('notes/$name.typ', 'local $name');
      await createSyncConflict(
        controller.vault!,
        'notes/$name.typ',
        localBytes: utf8.encode('local $name'),
        // Nextcloud deleted, this device changed - a real conflict shape, and
        // the one this fake server can represent without a prior upload.
        remoteBytes: null,
      );
    }
    await controller.refreshSyncConflicts();
    expect(controller.syncConflicts, hasLength(3));

    final resolved = await controller.resolveAllConflicts(
      SyncConflictResolution.keepLocal,
    );

    expect(resolved, 3);
    expect(controller.syncConflicts, isEmpty);
    expect(controller.syncError, isNull);
    // Every local copy won, and each was uploaded once.
    for (final name in ['a', 'b', 'c']) {
      expect(server.uploaded, contains('notes/$name.typ'));
      expect(await storage.readText('notes/$name.typ'), 'local $name');
    }
  });

  test('a failed save is reported even if the user kept typing', () async {
    // The revision guard was on the failure branch too, so a save that failed
    // while the user typed one more character was discarded: no status, no
    // notify, and the autosave timer already cancelled. The edit was gone with
    // the UI still showing a save as pending.
    final storage = _FailingWriteStorage();
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

    controller.edit('#import "/_system/tylog.typ" as tylog\n// first\n');
    storage.failWrites = true;
    final saving = controller.save();
    // The user types again while the write is in flight, moving the revision.
    controller.edit('#import "/_system/tylog.typ" as tylog\n// second\n');
    expect(await saving, isFalse);

    expect(
      controller.status,
      contains('Save failed'),
      reason: 'a write that never landed must say so',
    );
    expect(
      controller.dirty,
      isTrue,
      reason: 'still unsaved, so idle maintenance retries it',
    );
  });

  test('editor save commits the note and durable database queues', () async {
    final storage = _MemoryStorage();
    final database = TyLogDatabase(NativeDatabase.memory());
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
      database: Future.value(database),
      now: () => DateTime.fromMillisecondsSinceEpoch(100),
    );
    addTearDown(controller.dispose);
    addTearDown(database.close);
    await controller.openVault(
      const VaultEntry(id: 'database-save', name: 'Database', path: '/db'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);

    controller.edit('${controller.source}\nSaved through SQLite\n');
    expect(await controller.save(syncAfter: false), isTrue);

    expect(await database.select(database.nodes).get(), hasLength(1));
    expect(await database.select(database.revisions).get(), hasLength(2));
    expect(await database.select(database.outboxEntries).get(), hasLength(2));
    expect(
      await database.select(database.derivedInvalidations).get(),
      hasLength(2),
    );
  });

  test('page and daily creation persist their initial durable rows', () async {
    final storage = _MemoryStorage();
    final database = TyLogDatabase(NativeDatabase.memory());
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
      database: Future.value(database),
      now: () => DateTime(2026, 7, 2, 12),
    );
    addTearDown(controller.dispose);
    addTearDown(database.close);
    await controller.openVault(
      const VaultEntry(id: 'database-create', name: 'Database', path: '/db'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);

    const template = '_system/templates/project.typ';
    await storage.writeText(
      template,
      '#show: tylog.note.with(id: "template", title: "Template", kind: "note")\n'
      'Template body\n',
    );
    final page = await controller.createPage(
      'Project',
      kind: 'project',
      template: template,
      knownIds: <String>{},
      now: DateTime(2026, 7, 2, 12),
    );
    final daily = await controller.ensureTodayNote(DateTime(2026, 7, 3));

    expect(page, 'projects/Project.typ');
    expect(daily, 'daily/2026/07/2026-07-03.typ');
    final nodes = await database.select(database.nodes).get();
    expect(nodes, hasLength(3));
    final project = nodes.singleWhere((node) => node.type == 'project');
    expect(project.title, 'Project');
    expect(project.content, contains('Template body'));
    final journal = nodes.singleWhere(
      (node) => jsonDecode(node.attributesJson)['path'] == daily,
    );
    expect(journal.title, '2026-07-03');
    expect(await database.select(database.revisions).get(), hasLength(3));
  });

  test(
    'startup daily creation rolls back when durable persistence fails',
    () async {
      final storage = _MemoryStorage();
      final database = TyLogDatabase(NativeDatabase.memory());
      await database.customStatement('''
      CREATE TRIGGER reject_startup_note
      BEFORE INSERT ON nodes
      BEGIN SELECT RAISE(ABORT, 'forced database failure'); END
    ''');
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
        database: Future.value(database),
        now: () => DateTime(2026, 7, 4, 12),
      );
      addTearDown(controller.dispose);
      addTearDown(database.close);

      await controller.openVault(
        const VaultEntry(id: 'startup-failure', name: 'Database', path: '/db'),
        storage: storage,
      );

      expect(controller.vault, isNull);
      expect(await storage.exists('daily/2026/07/2026-07-04.typ'), isFalse);
      expect(await database.select(database.nodes).get(), isEmpty);
    },
  );

  test(
    'database save failure restores the file and keeps the editor dirty',
    () async {
      final storage = _MemoryStorage();
      final database = TyLogDatabase(NativeDatabase.memory());
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
        database: Future.value(database),
      );
      addTearDown(controller.dispose);
      addTearDown(database.close);
      await controller.openVault(
        const VaultEntry(id: 'database-failure', name: 'Database', path: '/db'),
        storage: storage,
      );
      await _waitUntil(() => controller.index != null);
      final path = controller.note!;
      final before = await storage.readBytes(path);
      final pendingBefore = controller.vault!.isPendingSyncWrite(path);
      await database.customStatement('''
      CREATE TRIGGER reject_note_insert
      BEFORE INSERT ON nodes
      BEGIN SELECT RAISE(ABORT, 'forced database failure'); END
    ''');
      await database.customStatement('''
        CREATE TRIGGER reject_note_outbox
        BEFORE INSERT ON outbox_entries
        BEGIN SELECT RAISE(ABORT, 'forced database failure'); END
      ''');

      controller.edit('${controller.source}\nMust roll back\n');
      final saved = await controller.save(syncAfter: false);
      expect(saved, isFalse);

      expect(controller.dirty, isTrue);
      expect(controller.status, contains('Save failed'));
      expect(await storage.readBytes(path), before);
      expect(controller.vault!.isStaleNote(path), isFalse);
      expect(controller.vault!.isPendingSyncWrite(path), pendingBefore);
    },
  );

  test('created-note database failure rolls back the file and row', () async {
    final storage = _MemoryStorage();
    final database = TyLogDatabase(NativeDatabase.memory());
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
      database: Future.value(database),
    );
    addTearDown(controller.dispose);
    addTearDown(database.close);
    await controller.openVault(
      const VaultEntry(
        id: 'database-create-failure',
        name: 'Database',
        path: '/db',
      ),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    final initialNodes = await database.select(database.nodes).get();
    final initialRevisions = await database.select(database.revisions).get();
    await database.customStatement('''
      CREATE TRIGGER reject_created_note
      BEFORE INSERT ON nodes
      BEGIN SELECT RAISE(ABORT, 'forced database failure'); END
    ''');

    await expectLater(
      controller.createPage('No Phantom'),
      throwsA(isA<Exception>()),
    );
    expect(await storage.exists('notes/No Phantom.typ'), isFalse);
    expect(await database.select(database.nodes).get(), initialNodes);
    expect(await database.select(database.revisions).get(), initialRevisions);

    await storage.writeText(
      'notes/Existing.typ',
      '#show: tylog.note.with(id: "existing", title: "Existing")\n',
    );
    expect(await controller.createPage('Existing'), 'notes/Existing.typ');
    expect(await storage.exists('notes/Existing.typ'), isTrue);
  });

  test(
    'persistCreatedNote rolls back an externally materialized file',
    () async {
      final storage = _MemoryStorage();
      final database = TyLogDatabase(NativeDatabase.memory());
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
        database: Future.value(database),
      );
      addTearDown(controller.dispose);
      addTearDown(database.close);
      await controller.openVault(
        const VaultEntry(
          id: 'database-import-failure',
          name: 'Database',
          path: '/db',
        ),
        storage: storage,
      );
      await _waitUntil(() => controller.index != null);
      final initialNodes = await database.select(database.nodes).get();
      await database.customStatement('''
      CREATE TRIGGER reject_imported_note
      BEFORE INSERT ON nodes
      BEGIN SELECT RAISE(ABORT, 'forced database failure'); END
    ''');
      const path = 'articles/Imported.typ';
      await storage.writeText(
        path,
        '#show: tylog.note.with(id: "imported", title: "Imported")\n',
      );

      await expectLater(
        controller.persistCreatedNote(path),
        throwsA(isA<Exception>()),
      );
      expect(await storage.exists(path), isFalse);
      expect(await database.select(database.nodes).get(), initialNodes);
    },
  );

  test('closed-note mutation uses the same durable persistence path', () async {
    final storage = _MemoryStorage();
    final database = TyLogDatabase(NativeDatabase.memory());
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
      database: Future.value(database),
    );
    addTearDown(controller.dispose);
    addTearDown(database.close);
    await controller.openVault(
      const VaultEntry(id: 'database-mutation', name: 'Database', path: '/db'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    const path = 'notes/closed.typ';
    await storage.writeText(
      path,
      '#show: tylog.note.with(id: "closed", title: "Closed")\nBody',
    );

    expect(
      await controller.mutateNote(path, (source) => '$source\nChanged'),
      isTrue,
    );

    final closed = await (database.select(
      database.nodes,
    )..where((node) => node.id.equals('closed'))).getSingle();
    expect(closed.id, 'closed');
    expect(await database.select(database.revisions).get(), hasLength(2));
  });

  test('deleting a disposable note records a durable tombstone', () async {
    final storage = _MemoryStorage();
    final database = TyLogDatabase(NativeDatabase.memory());
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
      database: Future.value(database),
    );
    addTearDown(controller.dispose);
    addTearDown(database.close);
    await controller.openVault(
      const VaultEntry(id: 'database-delete', name: 'Database', path: '/db'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    final path = controller.note!;
    expect(await controller.save(syncAfter: false), isTrue);

    controller.edit('');
    expect(await controller.save(syncAfter: false), isTrue);

    expect(await storage.exists(path), isFalse);
    final node = (await database.select(database.nodes).get()).singleWhere(
      (value) => jsonDecode(value.attributesJson)['path'] == path,
    );
    expect(node.content, isEmpty);
    expect(jsonDecode(node.attributesJson), contains('deletedAtMs'));
    expect(await database.select(database.revisions).get(), hasLength(3));
  });

  test(
    'explicit note deletion removes the file and records a tombstone',
    () async {
      final storage = _MemoryStorage();
      final database = TyLogDatabase(NativeDatabase.memory());
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
        database: Future.value(database),
      );
      addTearDown(controller.dispose);
      addTearDown(database.close);
      await controller.openVault(
        const VaultEntry(id: 'database-delete', name: 'Database', path: '/db'),
        storage: storage,
      );
      await _waitUntil(() => controller.index != null);
      const path = 'articles/paper.typ';
      await storage.writeText(
        path,
        '#show: tylog.note.with(id: "paper", title: "Paper")\nBody',
      );
      expect(await controller.mutateNote(path, (source) => source), isTrue);
      await storage.delete(path);

      expect(await controller.deleteNote(path), isTrue);

      expect(await storage.exists(path), isFalse);
      final node = await (database.select(
        database.nodes,
      )..where((table) => table.id.equals('paper'))).getSingle();
      expect(node.content, isEmpty);
      expect(jsonDecode(node.attributesJson), contains('deletedAtMs'));
      expect(await database.select(database.revisions).get(), hasLength(3));
    },
  );

  test('note reads retry when a closed-note mutation overlaps', () async {
    final storage = _SnapshotReadStorage();
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'stable-read', name: 'Stable', path: '/stable'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    const path = 'notes/closed.typ';
    await storage.writeText(path, 'before');
    storage.arm(path);

    final reading = controller.readNote(path);
    await storage.reached.future;
    expect(await controller.mutateNote(path, (_) => 'after'), isTrue);
    storage.release();

    expect(await reading, contains('after'));
  });

  test(
    'a save of an older snapshot reports false and keeps the newer edit',
    () async {
      final storage = _GatedWriteStorage();
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

      controller.edit('#import "/_system/tylog.typ" as tylog\n// first\n');
      storage.armWrite();
      final saving = controller.save(syncAfter: false);
      await storage.gateReached.future;
      controller.edit('#import "/_system/tylog.typ" as tylog\n// second\n');
      controller.cancelPendingWork();
      storage.releaseWrite();

      expect(await saving, isFalse);
      expect(controller.dirty, isTrue);
      expect(controller.source, contains('// second'));
      expect(await storage.readText(controller.note!), contains('// first'));
    },
  );

  test('a batch skips records that vanished under it', () async {
    // Every iteration reloads syncConflicts from disk, and that reload
    // self-heals - so a record captured in the snapshot can already be gone.
    // Resolving it anyway uploads the live local file for a path that no
    // longer disagrees, and counts work that did not happen.
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
    await controller.openVault(
      const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    await controller
        .refreshIndex(always: true)
        .timeout(const Duration(seconds: 5));
    controller.cloud = server.config;

    for (final name in ['gone', 'real']) {
      await storage.writeText('notes/$name.typ', 'local $name');
    }
    // Only 'real' has a record on disk; 'gone' is the shape a self-heal leaves
    // behind — still in the in-memory snapshot, already absent from the vault.
    await createSyncConflict(
      controller.vault!,
      'notes/real.typ',
      localBytes: utf8.encode('local real'),
      remoteBytes: null,
    );
    await controller.refreshSyncConflicts();
    // Ordered second on purpose: resolving the first record reloads the list
    // from disk, and that reload is what drops this one.
    controller.syncConflicts = [
      ...controller.syncConflicts,
      SyncConflict(
        id: 'gone',
        path: 'notes/gone.typ',
        recordPath: '.tylog/conflicts/gone.json',
        createdAt: DateTime.utc(2026),
        localExists: true,
        remoteExists: false,
      ),
    ];

    final resolved = await controller.resolveAllConflicts(
      SyncConflictResolution.keepLocal,
    );

    expect(resolved, 1, reason: 'only the record that still existed');
    expect(server.uploaded, contains('notes/real.typ'));
    expect(
      server.uploaded,
      isNot(contains('notes/gone.typ')),
      reason: 'a vanished record must not push its local file',
    );
  });

  test('a half-failed batch reports what actually resolved', () async {
    // Nothing half-succeeded in the original version of this test: every
    // request failed, so it asserted 0 of 3 and never exercised the partial
    // case - which is the risky one, because the count is incremented after
    // the break check and a resolve could return early without erroring.
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
    await controller.openVault(
      const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
      storage: storage,
    );
    await _waitUntil(() => controller.index != null);
    controller.cloud = server.config;

    for (final name in ['a', 'b', 'c']) {
      await storage.writeText('notes/$name.typ', 'local $name');
      await createSyncConflict(
        controller.vault!,
        'notes/$name.typ',
        localBytes: utf8.encode('local $name'),
        remoteBytes: null,
      );
    }
    await controller.refreshSyncConflicts();
    // The second upload fails; the first has already landed.
    server.failUploadsAfter = 1;

    final resolved = await controller.resolveAllConflicts(
      SyncConflictResolution.keepLocal,
    );

    expect(resolved, 1, reason: 'exactly what actually landed');
    expect(
      controller.syncConflicts,
      hasLength(2),
      reason: 'the untouched records must still be there',
    );
    expect(controller.syncError, isNotNull);
  });

  test(
    'a batch over a disconnected vault refuses instead of claiming success',
    () async {
      // resolveConflict used to return silently when the config was not ready,
      // so the batch counted every no-op as a success and the snackbar said
      // "Resolved 3" over a vault where nothing had happened.
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
      controller.cloud = null;
      controller.syncConflicts = [
        for (final name in ['a', 'b', 'c'])
          SyncConflict(
            id: name,
            path: 'notes/$name.typ',
            recordPath: '.tylog/conflicts/$name.json',
            createdAt: DateTime.utc(2026),
            localExists: true,
            remoteExists: true,
          ),
      ];

      expect(
        await controller.resolveAllConflicts(SyncConflictResolution.keepLocal),
        0,
      );
      expect(controller.syncError, isNotNull, reason: 'it must say why');
      expect(controller.syncConflicts, hasLength(3));
    },
  );

  test('a resolve refuses while another owner holds the vault lock', () async {
    // The resolve is the one operation that deliberately overwrites a side of a
    // disagreement, and it was the only vault write that took no lock at all.
    // A background pass mid-flight would be reconciling against a listing taken
    // before this write landed.
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
    controller.cloud = const NextcloudConfig(
      serverUrl: 'http://127.0.0.1:1/remote.php/dav/files/alice/V',
      username: 'alice',
      password: 'secret',
    );

    expect(await VaultLock.acquire(storage, 'service'), isTrue);

    final resolved = await controller.resolveConflict(
      SyncConflict(
        id: 'c',
        path: 'notes/a.typ',
        recordPath: '.tylog/conflicts/c.json',
        createdAt: DateTime.utc(2026),
        localExists: true,
        remoteExists: true,
      ),
      SyncConflictResolution.keepLocal,
    );

    expect(resolved, isFalse);
    expect(controller.syncError, contains('sync is running'));
    // And it left the other owner's lock alone.
    expect(await VaultLock.heldByOther(storage, 'ui-resolve'), isTrue);
  });

  test('a resolve does not hand the vault away mid-sync', () async {
    // The lock is re-entrant by owner and release() deletes the file, so a
    // resolve taken under syncNow's own 'ui' name would have released the
    // running sync's lock the moment it finished - inviting the background
    // service in mid-pass, from the same process.
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
    controller.cloud = const NextcloudConfig(
      serverUrl: 'http://127.0.0.1:1/remote.php/dav/files/alice/V',
      username: 'alice',
      password: 'secret',
    );

    // A sync in flight, holding the lock as the UI does.
    expect(await VaultLock.acquire(storage, 'ui'), isTrue);

    await controller.resolveConflict(
      SyncConflict(
        id: 'c',
        path: 'notes/a.typ',
        recordPath: '.tylog/conflicts/c.json',
        createdAt: DateTime.utc(2026),
        localExists: true,
        remoteExists: true,
      ),
      SyncConflictResolution.keepLocal,
    );

    expect(
      await VaultLock.heldByOther(storage, 'service'),
      isTrue,
      reason: "the running sync's lock must survive the resolve",
    );
  });

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

  test(
    'the post-sync reindex goes through the scan driver, not an inline one',
    () async {
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
      controller.edit(
        '#import "/_system/tylog.typ" as tylog\n// synced edit\n',
      );
      expect(await controller.syncNow(trigger: 'setup'), isTrue);

      expect(
        await storage.exists(donor),
        isTrue,
        reason:
            'the sync-triggered reindex did not publish the index donor, so it '
            'is not going through _scan',
      );
    },
  );

  test(
    'failed syncs refresh only downloaded content and report the error first',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      final storage = _GatedScanStorage();
      final inspector = _FakeInspector();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: inspector,
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

      server.propfindStatus = HttpStatus.unauthorized;
      storage.writes.clear();
      expect(await controller.syncNow(trigger: 'manual'), isFalse);
      expect(await controller.syncNow(trigger: 'manual'), isFalse);
      expect(
        storage.writes.where((path) => path == donor),
        isEmpty,
        reason: 'two 401s must not publish a new index',
      );

      server.propfindStatus = 207;
      server._files['notes/a.typ'] = utf8.encode('#let a = "remote"');
      server._etags['notes/a.typ'] = '"remote-a"';
      server._files['notes/b.typ'] = utf8.encode('#let b = "remote"');
      server._etags['notes/b.typ'] = '"remote-b"';
      server.failGets.add('notes/b.typ');
      final downloadedA = Completer<void>();
      server.onGet = (path) {
        if (path == 'notes/a.typ') {
          storage.armGate();
          downloadedA.complete();
        }
      };
      final scansBeforeFailure = inspector.calls;

      final failed = controller.syncNow(trigger: 'manual');
      await downloadedA.future.timeout(const Duration(seconds: 5));
      await storage.gateReached.future.timeout(const Duration(seconds: 5));
      expect(controller.syncError, isNotNull);
      expect(controller.syncing, isTrue);

      storage.release();
      expect(await failed.timeout(const Duration(seconds: 10)), isFalse);
      expect(inspector.calls, scansBeforeFailure + 1);
      expect(await storage.readText('notes/a.typ'), '#let a = "remote"');
    },
  );

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
    'poll pauses rejected credentials until config changes or retry runs',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await _GatedWebDavServer.start();
      addTearDown(() => server.server.close(force: true));
      var now = DateTime.utc(2026);
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
        now: () => now,
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
        storage: _MemoryStorage(),
      );
      await _waitUntil(() => controller.index != null);
      controller.cloud = server.config;
      server.propfindStatus = HttpStatus.unauthorized;
      server.armGate();

      final first = controller.pollTick();
      await server.gateReached.future;
      await controller.pollTick();
      expect(server.propfinds, 1, reason: 'preflight stays single-flight');
      server.releaseGate.complete();
      await first;
      expect(server.propfinds, 1);

      now = now.add(const Duration(hours: 1));
      await controller.pollTick();
      expect(server.propfinds, 1, reason: '401 pauses automatic attempts');

      // The same pause applies to forbidden credentials and automatic startup,
      // resume, and autosave triggers after a manual auth failure.
      server.propfindStatus = HttpStatus.forbidden;
      controller.cloud = NextcloudConfig(
        serverUrl: server.config.serverUrl,
        username: 'alice',
        password: 'forbidden',
      );
      await controller.pollTick();
      final after403 = server.propfinds;
      expect(await controller.syncNow(trigger: 'setup'), isFalse);
      expect(await controller.syncNow(trigger: 'resume'), isFalse);
      expect(await controller.syncNow(trigger: 'autosave'), isFalse);
      expect(
        server.propfinds,
        after403,
        reason: 'automatic triggers stay paused after 403',
      );

      server.propfindStatus = 207;
      controller.cloud = NextcloudConfig(
        serverUrl: server.config.serverUrl,
        username: 'alice',
        password: 'changed',
      );
      await controller.pollTick();
      expect(
        server.propfinds,
        3,
        reason: 'changed credentials retry automatically',
      );

      expect(await controller.syncNow(trigger: 'retry'), isTrue);
      expect(server.propfinds, 4, reason: 'retry bypasses the auth pause');
    },
  );

  test('poll backoff grows to five minutes and resets after success', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await _GatedWebDavServer.start();
    addTearDown(() => server.server.close(force: true));
    var now = DateTime.utc(2026);
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      inspector: _FakeInspector(),
      reconcileTasks: (_) async {},
      now: () => now,
    );
    addTearDown(controller.dispose);
    await controller.openVault(
      const VaultEntry(id: 'local', name: 'Local vault', path: '/not-used'),
      storage: _MemoryStorage(),
    );
    await _waitUntil(() => controller.index != null);
    controller.cloud = server.config;
    server.propfindStatus = HttpStatus.internalServerError;

    for (final delay in const [25, 50, 100, 200, 300]) {
      final before = server.propfinds;
      await controller.pollTick();
      expect(server.propfinds, before + 1);
      now = now.add(Duration(seconds: delay - 1));
      await controller.pollTick();
      expect(server.propfinds, before + 1);
      now = now.add(const Duration(seconds: 1));
    }

    server.propfindStatus = 207;
    final beforeSuccess = server.propfinds;
    await controller.pollTick();
    expect(server.propfinds, beforeSuccess + 1);

    server.propfindStatus = HttpStatus.internalServerError;
    final beforeResetFailure = server.propfinds;
    await controller.pollTick();
    expect(server.propfinds, beforeResetFailure + 1);
    now = now.add(const Duration(seconds: 24));
    await controller.pollTick();
    expect(server.propfinds, beforeResetFailure + 1);
    now = now.add(const Duration(seconds: 1));
    await controller.pollTick();
    expect(server.propfinds, beforeResetFailure + 2);
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
      expect(
        controller.hasSyncConflicts,
        isTrue,
        reason: 'the conflict itself still waits for review',
      );
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

  test(
    'rating and deletion during a scan queue one follow-up without cancelling',
    () async {
      final storage = _GatedScanStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.openVault(
        const VaultEntry(
          id: 'mutations',
          name: 'Mutations',
          path: '/mutations',
        ),
        storage: storage,
      );
      await _waitUntil(() => controller.index != null);
      const kept = 'articles/kept.typ';
      const removed = 'articles/removed.typ';
      const source = '''
#show: tylog.note.with(
  id: "article",
  title: "Article",
  kind: "article",
  properties: ("rating": "unread",),
)
''';
      await controller.vault!.saveNote(kept, source);
      await controller.vault!.saveNote(
        removed,
        source.replaceAll('article', 'removed'),
      );
      await controller.refreshIndex(always: true);
      expect(controller.index!.notesByPath, containsPair(kept, isNotNull));
      expect(controller.index!.notesByPath, containsPair(removed, isNotNull));

      storage.armGate();
      final scan = controller.refreshIndex(always: true);
      await storage.gateReached.future;
      final rating = controller.mutateNote(
        kept,
        (value) => replaceNoteProperty(value, 'rating', '4'),
      );
      await controller.vault!.storage.delete(removed);
      final deletionRefresh = controller.refreshIndex(always: true);
      storage.release();
      await scan;
      await Future.wait([rating, deletionRefresh]);

      expect(controller.cancelRebuild, isFalse);
      expect(controller.status, isNot('Index rebuild cancelled'));
      final keptNote = controller.index!.notesByPath[kept];
      expect(keptNote, isNotNull);
      expect(keptNote!.properties['rating'], '4');
      expect(controller.index!.notesByPath, isNot(contains(removed)));
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

class _GatedOpenStorage extends _MemoryStorage {
  Completer<void> reached = Completer<void>();
  Completer<void> _release = Completer<void>();
  bool _armed = false;
  bool failAfterGate = false;

  void arm() {
    reached = Completer<void>();
    _release = Completer<void>();
    _armed = true;
  }

  void release() {
    _armed = false;
    _release.complete();
  }

  @override
  Future<String> readText(String path) async {
    if (_armed && path.endsWith('.typ')) {
      _armed = false;
      reached.complete();
      await _release.future;
      if (failAfterGate) throw const FileSystemException('old open failed');
    }
    return super.readText(path);
  }
}

class _SnapshotReadStorage extends _MemoryStorage {
  String? _path;
  Completer<void> reached = Completer<void>();
  Completer<void> _release = Completer<void>();

  void arm(String path) {
    _path = path;
    reached = Completer<void>();
    _release = Completer<void>();
  }

  void release() {
    _path = null;
    _release.complete();
  }

  @override
  Future<String> readText(String path) async {
    final result = await super.readText(path);
    if (path == _path) {
      _path = null;
      reached.complete();
      await _release.future;
    }
    return result;
  }
}

/// Fails writes on demand, to prove a lost write is never silent.
class _FailingWriteStorage extends _MemoryStorage {
  bool failWrites = false;

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    if (failWrites && path.endsWith('.typ')) {
      throw const FileSystemException('disk full');
    }
    return super.writeBytes(path, bytes);
  }
}

class _GatedWriteStorage extends _MemoryStorage {
  Completer<void> gateReached = Completer<void>();
  Completer<void> _release = Completer<void>();
  var _gateWrite = false;

  void armWrite() {
    gateReached = Completer<void>();
    _release = Completer<void>();
    _gateWrite = true;
  }

  void releaseWrite() {
    _gateWrite = false;
    _release.complete();
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    if (_gateWrite && path.endsWith('.typ')) {
      _gateWrite = false;
      gateReached.complete();
      await _release.future;
    }
    return super.writeBytes(path, bytes);
  }
}

class _MemoryStorage extends VaultStorage {
  final Map<String, Uint8List> _files = {};

  /// Paths written, so a test can assert a write did *not* happen.
  final writes = <String>[];
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
    writes.add(path);
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

class _IndexReadGatedStorage extends _GatedStorage {
  bool indexReadStarted = false;

  @override
  Future<Uint8List> readBytes(String path) async {
    if (path == TylogVaultPaths.index) {
      indexReadStarted = true;
      await gate.future;
    }
    return super.readBytes(path);
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

  /// Fail every PUT past this many, so a batch can half-succeed.
  int? failUploadsAfter;
  int propfindStatus = 207;
  int propfinds = 0;
  final failGets = <String>{};
  void Function(String path)? onGet;
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
          propfinds++;
          if (_gateArmed) {
            _gateArmed = false;
            gateReached.complete();
            await releaseGate.future;
          }
          request.response.statusCode = propfindStatus;
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
          if (failGets.contains(path)) {
            request.response.statusCode = HttpStatus.internalServerError;
          } else if (bytes == null) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.headers.set(HttpHeaders.etagHeader, _etags[path]!);
            request.response.add(bytes);
            onGet?.call(path);
          }
        case 'PUT':
          final bytes = await request.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          if (failUploadsAfter != null &&
              uploaded.length >= failUploadsAfter!) {
            request.response.statusCode = HttpStatus.internalServerError;
            break;
          }
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
