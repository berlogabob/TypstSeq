
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
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
SyncDashboardData _data({required bool syncing, List<SyncConflict>? conflicts}) =>
    SyncDashboardData(
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
  testWidgets('actions come back once a background sync ends', (tester) async {
    // A poll-triggered sync that starts and finishes while the screen is open.
    var syncing = true;
    var resolved = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDashboardScreen(
          load: () async => _data(
            syncing: syncing,
            conflicts: [_conflict('daily/2024/12/2024-12-24.typ')],
          ),
          onSync: () async {},
          onConfigure: () async => true,
          onResolve: (_) async => resolved++,
          onCopyDiagnostics: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // While a sync really is running, taps are refused. That part is intended.
    await tester.tap(find.text('daily/2024/12/2024-12-24.typ'));
    await tester.pump();
    expect(resolved, 0, reason: 'a tap during a sync is deliberately ignored');

    // The sync ends with the screen already open and nothing else happening.
    // The dashboard has to notice by itself: before the fix nothing re-read
    // `syncing` once `_run` had returned, so this stayed refused forever and
    // only force-quitting the app recovered it.
    syncing = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    await tester.tap(find.text('daily/2024/12/2024-12-24.typ'));
    await tester.pump();
    expect(resolved, 1, reason: 'the dashboard recovered without a restart');
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
