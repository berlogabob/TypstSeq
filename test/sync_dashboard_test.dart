
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/widgets/loading.dart';
import 'package:tylog/widgets/sync_dashboard.dart';

/// The Sync dashboard holds a *snapshot* of the controller rather than
/// listening to it, and `_run` refuses to act while that snapshot says a sync
/// is in flight. So a snapshot stuck on `syncing: true` silently disables every
/// action on the screen — including conflict resolution — and the only recovery
/// is force-quitting the app.
///
/// Seen on a real device: the spinner claimed "Syncing…" for nine minutes after
/// the sync service had stopped, while the banner simultaneously said sync was
/// paused pending conflict review. Resolving one conflict worked; the next tap
/// did nothing, with no message.
SyncDashboardData _data({
  required bool syncing,
  List<SyncConflict>? conflicts,
  String? error,
}) => SyncDashboardData(
      storageName: 'TyLog',
      storageLocation: 'TyLog',
      cloud: const NextcloudConfig(
        serverUrl: 'https://example.invalid',
        username: 'u',
        password: 'p',
        remoteFolder: 'TyLogVault',
      ),
      syncing: syncing,
      vaultOpen: true,
      desktopManaged: false,
      storageHealthy: true,
      conflicts: conflicts ?? const [],
      error: error,
      events: const [],
    );

SyncConflict _conflict(String path) => SyncConflict(
  id: 'c-$path',
  path: path,
  recordPath: '.tylog/conflicts/c.json',
  createdAt: DateTime.utc(2026, 8, 7),
  localExists: true,
  remoteExists: true,
  localSnapshot: '.tylog/conflicts/c.local',
  remoteSnapshot: '.tylog/conflicts/c.remote',
);

void main() {
  // The reported symptom: resolve one conflict, then every later tap does
  // nothing until the app is force-quit. Cause is `_run`'s `running` flag, held
  // for the whole of `resolveConflict` — which awaits `refreshIndex(always:
  // true)`, which awaits any running scan plus a queued repeat. On a large
  // vault that is hours, so the user got exactly one resolve per scan cycle,
  // with the row still showing its chevron and no message.
  testWidgets('a second conflict resolves while the first is still working', (
    tester,
  ) async {
    var resolved = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDashboardScreen(
          load: () async => _data(
            syncing: false,
            conflicts: [_conflict('notes/A.typ'), _conflict('notes/B.typ')],
          ),
          onSync: () async {},
          onConfigure: () async => true,
          onResolve: (_) async {
            resolved++;
            // Stands in for the inline full-vault rescan.
            await Future<void>.delayed(const Duration(seconds: 30));
          },
          onResolveAll: (_) async {},
          onCopyDiagnostics: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('notes/A.typ'));
    await tester.pump();
    // Deliberately not settling: the point is to tap while the first is in
    // flight, which is exactly what a user with a backlog does.
    await tester.tap(find.text('notes/B.typ'));
    await tester.pump();

    expect(resolved, 2, reason: 'one resolve must not block the next');

    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
  });

  // A running sync must not block resolution either: resolving is one Depth:0
  // probe and one file write, and while conflicts exist a sync essentially
  // cannot start anyway (the poll returns early, and Sync now is disabled).
  testWidgets('a conflict resolves even while a sync is running', (
    tester,
  ) async {
    var resolved = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDashboardScreen(
          load: () async =>
              _data(syncing: true, conflicts: [_conflict('notes/A.typ')]),
          onSync: () async {},
          onConfigure: () async => true,
          onResolve: (_) async => resolved++,
          onResolveAll: (_) async {},
          onCopyDiagnostics: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('notes/A.typ'));
    await tester.pump();

    expect(resolved, 1);
  });

  // A resolve is a network write plus an index refresh - seconds to minutes on
  // a busy vault - and the row used to be byte-identical to one nobody had
  // tapped for the whole of it. Twice during the A24 incident that made a
  // working resolve look like a dead button, and both times the conclusion
  // drawn from it was wrong.
  testWidgets('a resolve in flight says so on its own row', (tester) async {
    final finish = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDashboardScreen(
          load: () async => _data(
            syncing: false,
            conflicts: [_conflict('notes/A.typ'), _conflict('notes/B.typ')],
          ),
          onSync: () async {},
          onConfigure: () async => true,
          onResolve: (_) async => finish.future,
          onResolveAll: (_) async {},
          onCopyDiagnostics: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(LoadingIndicator), findsNothing);

    await tester.tap(find.text('notes/A.typ'));
    await tester.pump();

    expect(
      find.text('Resolving… uploading and cleaning up'),
      findsOneWidget,
      reason: 'the tapped row must say it is working',
    );
    // Only the tapped row: the other conflict is untouched.
    expect(find.text('Both copies changed'), findsOneWidget);

    finish.complete();
    await tester.pumpAndSettle();

    expect(find.text('Resolving… uploading and cleaning up'), findsNothing);
    expect(find.text('Both copies changed'), findsNWidgets(2));
  });

  testWidgets('conflict rows are keyed by id, not by position', (tester) async {
    // The rows rebuild twice a second from a fresh snapshot. Unkeyed, a list
    // that reorders between two reloads moves a different record under the
    // finger mid-tap.
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDashboardScreen(
          load: () async => _data(
            syncing: false,
            conflicts: [_conflict('notes/A.typ'), _conflict('notes/B.typ')],
          ),
          onSync: () async {},
          onConfigure: () async => true,
          onResolve: (_) async {},
          onResolveAll: (_) async {},
          onCopyDiagnostics: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('conflict-c-notes/A.typ')), findsOneWidget);
    expect(find.byKey(const ValueKey('conflict-c-notes/B.typ')), findsOneWidget);
  });

  // Two independent mechanisms hid failures, and either alone was enough.
  testWidgets('an error is visible while a sync is running', (tester) async {
    // syncStatusKind ranked `syncing` above `error`, and the error only ever
    // reached the screen through the status card's subtitle - so during a sync
    // it was not merely deprioritised, it was never rendered.
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDashboardScreen(
          load: () async => _data(
            syncing: true,
            error: 'Nextcloud changed while you were deciding',
          ),
          onSync: () async {},
          onConfigure: () async => true,
          onResolve: (_) async {},
          onResolveAll: (_) async {},
          onCopyDiagnostics: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('sync-error-card')), findsOneWidget);
    expect(
      find.text('Nextcloud changed while you were deciding'),
      findsOneWidget,
    );
  });

  testWidgets('an error is visible while conflicts are pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDashboardScreen(
          load: () async => _data(
            syncing: false,
            conflicts: [_conflict('notes/A.typ')],
            error: 'Upload failed: connection reset',
          ),
          onSync: () async {},
          onConfigure: () async => true,
          onResolve: (_) async {},
          onResolveAll: (_) async {},
          onCopyDiagnostics: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('sync-error-card')), findsOneWidget);
    expect(find.text('Upload failed: connection reset'), findsOneWidget);
    // The conflict is still listed too; they are different facts.
    expect(find.text('notes/A.typ'), findsOneWidget);
  });

  testWidgets('resolve all asks which side, then applies one choice', (
    tester,
  ) async {
    SyncConflictResolution? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDashboardScreen(
          load: () async => _data(
            syncing: false,
            conflicts: [
              _conflict('notes/A.typ'),
              _conflict('notes/B.typ'),
              _conflict('notes/C.typ'),
            ],
          ),
          onSync: () async {},
          onConfigure: () async => true,
          onResolve: (_) async {},
          onResolveAll: (choice) async => applied = choice,
          onCopyDiagnostics: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Resolve all 3'));
    await tester.pumpAndSettle();

    // Nothing is preselected: a bulk choice can discard whatever the other
    // side added, which is the mistake the single dialog was fixed to stop
    // making.
    expect(find.text('Resolve 3 conflicts'), findsOneWidget);
    expect(applied, isNull);

    await tester.tap(find.text("Keep Nextcloud's version"));
    await tester.pumpAndSettle();

    expect(applied, SyncConflictResolution.keepRemote);
  });

  testWidgets('resolve all is not offered for a single conflict', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDashboardScreen(
          load: () async =>
              _data(syncing: false, conflicts: [_conflict('notes/A.typ')]),
          onSync: () async {},
          onConfigure: () async => true,
          onResolve: (_) async {},
          onResolveAll: (_) async {},
          onCopyDiagnostics: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Resolve all'), findsNothing);
  });

  testWidgets('a slow load landing late does not overwrite a fresher one', (
    tester,
  ) async {
    // First load is slow and reports syncing; the second is fast and reports
    // idle. Without single-flight the slow one lands last and pins the screen.
    var loads = 0;
    var resolved = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDashboardScreen(
          load: () async {
            loads++;
            if (loads == 1) {
              await Future<void>.delayed(const Duration(seconds: 3));
              return _data(
                syncing: true,
                conflicts: [_conflict('notes/A.typ')],
              );
            }
            return _data(syncing: false, conflicts: [_conflict('notes/A.typ')]);
          },
          onSync: () async {},
          onConfigure: () async => true,
          onResolve: (_) async => resolved++,
          onResolveAll: (_) async {},
          onCopyDiagnostics: () async {},
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('notes/A.typ'));
    await tester.pumpAndSettle();

    expect(resolved, 1, reason: 'the stale in-flight load must not win');
  });
}
