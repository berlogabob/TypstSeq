// Journal feed windowing tests need a *real* vault opened through the app's
// normal boot path (`VaultRegistry.load()` -> `Vault.ensureCreated()` ->
// `WorkspaceController.openVault()` -> background `rebuildIndex()`), because
// `_JournalFeed` is private to lib/app_mobile.dart and can only be reached by
// driving the full `TyLogApp()` into journal mode.
//
// That real vault I/O is genuine dart:io work, and the default `flutter test`
// binding (`AutomatedTestWidgetsFlutterBinding`) runs each test inside a
// FakeAsync zone: it advances a *virtual* clock so Timer-based waits can be
// fast-forwarded without a real delay, but a bare dart:io Future (file
// exists/read/write) started from that zone never actually gets driven to
// completion by `pump()`/`pumpAndSettle()` — the test just "settles" with the
// operation forever pending, and the vault silently never finishes opening
// (confirmed empirically while writing this test: `pumpAndSettle()` returns
// without error, but `workspace.index` stays null forever). This file uses
// `LiveTestWidgetsFlutterBinding` instead, which runs on the real clock, so
// the app's own real I/O actually completes. Real I/O also means the vault's
// background index rebuild reaches `TaskScheduler.reconcile()`, which calls
// into `flutter_local_notifications` — a plugin never registered under
// `flutter test` — so a fake `FlutterLocalNotificationsPlatform` is installed
// below purely to keep that unrelated, pre-existing gap from crashing these
// tests (production code is unchanged; this is test-only scaffolding).
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

class _FakeNotificationsPlatform extends FlutterLocalNotificationsPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required dynamic scheduledDate,
    String? payload,
    dynamic matchDateTimeComponents,
  }) async {}
}

/// Points `getApplicationDocumentsDirectory()` at a fresh temp directory,
/// creates a real vault there (via the app's own [Vault] API) with one
/// `daily/...` note per entry in [dailies], and registers it as the active
/// vault so `TyLogApp()` opens straight into it — the same mechanism
/// `test/vault_registry_test.dart` uses to make path_provider work headless.
/// A non-empty map value is appended after the day's default (heading-only)
/// template so tests can control how tall a given day renders.
Future<Directory> seedJournalVault(
  List<MapEntry<DateTime, String>> dailies,
) async {
  final base = await Directory.systemTemp.createTemp('tylog_journal_feed_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        _pathProviderChannel,
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? base.path
            : null,
      );
  final vaultDir = Directory('${base.path}/vault');
  final vault = Vault(vaultDir);
  await vault.ensureCreated();
  for (final entry in dailies) {
    final path = await vault.dailyNote(entry.key);
    if (entry.value.isNotEmpty) {
      final file = File('${vaultDir.path}/$path');
      await file.writeAsString(
        '${await file.readAsString()}\n${entry.value}\n',
      );
    }
  }
  final vaultEntry = VaultEntry(
    id: 'vault',
    name: 'Vault',
    path: vaultDir.path,
  );
  await File('${base.path}/vaults.json').writeAsString(
    jsonEncode({
      'version': 3,
      'active': vaultEntry.id,
      'onboardingComplete': true,
      'vaults': [vaultEntry.toJson()],
    }),
  );
  return base;
}

Future<void> teardownJournalVault(Directory base) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, null);
  await base.delete(recursive: true);
}

/// Body long enough that a single day reliably overflows the default test
/// viewport, so the feed becomes scrollable with just that one day loaded.
String longJournalBody() => List.generate(
  60,
  (i) => 'Filler journal line $i padding the day well past viewport height.',
).join('\n\n');

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  FlutterLocalNotificationsPlatform.instance = _FakeNotificationsPlatform();

  testWidgets('journal feed shows only the newest day at first', (
    tester,
  ) async {
    final now = DateTime.now();
    final days = [for (var i = 0; i < 5; i++) now.subtract(Duration(days: i))];
    final base = await seedJournalVault([
      for (final day in days) MapEntry(day, longJournalBody()),
    ]);
    addTearDown(() => teardownJournalVault(base));

    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Journal').last);
    await tester.pumpAndSettle();

    expect(find.byType(TyLogReadView), findsOneWidget);
    expect(find.text(humanDate(days[0])), findsOneWidget);
    expect(find.text(humanDate(days[4])), findsNothing);
    // The loader sentinel row exists below the fold but is deliberately NOT
    // asserted here: ListView.builder only builds rows near the viewport, so
    // the sentinel isn't in the tree until the user scrolls toward it —
    // which is exactly the lazy behavior under test.
  });

  // NOTE deliberately absent: a per-trigger "+1 day per scroll" widget test.
  // Under LiveTestWidgetsFlutterBinding the lazy list disposes far rows and
  // relayouts shift the clamped position between pumps, so counting built
  // TyLogReadViews per trigger is non-deterministic (verified empirically:
  // the window state itself grows exactly once per near-bottom trigger —
  // the extent latch in _JournalFeedState._onScroll — but the built-widget
  // count at assert time depends on viewport geometry). The load-everything
  // regression is pinned by the two tests in this file; one-per-trigger is
  // enforced by the latch and was verified live on device.

  testWidgets(
    'journal feed bootstrap-grows past a viewport-filling tiny today',
    (tester) async {
      final now = DateTime.now();
      final days = [
        for (var i = 0; i < 5; i++) now.subtract(Duration(days: i)),
      ];
      final base = await seedJournalVault([
        MapEntry(days[0], ''), // today: heading only, cannot fill the screen
        for (final day in days.skip(1)) MapEntry(day, longJournalBody()),
      ]);
      addTearDown(() => teardownJournalVault(base));

      await tester.pumpWidget(const TyLogApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Journal').last);
      await tester.pumpAndSettle();

      final rendered = find.byType(TyLogReadView).evaluate().length;
      expect(rendered, greaterThanOrEqualTo(2));
      expect(rendered, lessThan(5));
    },
  );
}
