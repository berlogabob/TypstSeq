import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/controlled_editor.dart';
import 'package:tylog/knowledge_screen.dart';
import 'package:tylog/main.dart';
import 'package:tylog/models.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/report.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/saved_searches.dart';
import 'package:tylog/search_index.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/widgets/work_surface.dart';
import 'package:typst_flutter/typst_flutter.dart';

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

Future<void> setViewMode(WidgetTester tester, String mode) async {
  await tester.tap(find.byTooltip('View mode'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode).last);
  await tester.pump();
}

Future<void> openSource(WidgetTester tester) => setViewMode(tester, 'Source');

Future<void> openMagicAction(WidgetTester tester, String label) async {
  // The dock slides open over 150ms after the editor gains focus; let it
  // finish before aiming at its buttons.
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Insert'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(label),
    100,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  FlutterLocalNotificationsPlatform.instance = _FakeNotificationsPlatform();
  test('humanDate formats the day and hides the current year', () {
    expect(
      humanDate(DateTime(2026, 7, 6), now: DateTime(2026, 7, 13)),
      'Mon, July 6',
    );
    expect(
      humanDate(DateTime(2025, 12, 31), now: DateTime(2026, 7, 13)),
      'Wed, December 31, 2025',
    );
  });

  testWidgets('TyLog shell renders', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.colorScheme.surface, const Color(0xFFF8FAFC));
    expect(app.theme!.colorScheme.onSurfaceVariant, const Color(0xFF3F414A));
    expect(app.theme!.hintColor, const Color(0xFF5F616A));
    expect(app.darkTheme!.brightness, Brightness.dark);
    expect(
      app.darkTheme!.scaffoldBackgroundColor,
      app.darkTheme!.colorScheme.surface,
    );
    // AppBar leads with the note title (a human-readable date once a daily
    // note is open) instead of an app title. No vault opens in tests, so the
    // fallback title shows here.
    expect(find.text('TyLog'), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Today')),
      findsOneWidget,
    );
    expect(find.text('Save'), findsNothing);
    expect(find.byTooltip('Save'), findsNothing);
    expect(find.byTooltip('Graph'), findsNothing);
    expect(find.text('Search'), findsOneWidget);
    expect(find.byTooltip('View mode'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const Key('quick-capture')), findsNothing);
    expect(find.byTooltip('Quick actions'), findsNothing);
    // Launch lands in the journal editor with today's file open.
    expect(find.byKey(const Key('rich-journal-editor')), findsOneWidget);
  });

  testWidgets('settings menu shows real app data', (tester) async {
    final version = await appVersion();

    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).last);
    await tester.pumpAndSettle();
    // Settings is now the second item in the More sheet (right after
    // Vaults), so it's visible without scrolling.
    final settings = find.widgetWithText(ListTile, 'Settings');
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Local folder'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Import Logseq/Obsidian vault'), findsOneWidget);
    expect(find.text('Nextcloud settings'), findsNothing);
    expect(find.text('Sync server status'), findsNothing);
    expect(find.text('App version'), findsOneWidget);
    await tester.pump();
    expect(find.text(version), findsOneWidget);

    await tester.tap(find.text('Vaults'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Add or create vault'), findsOneWidget);
  });

  testWidgets('journal rich editor shows one body and formats the selection', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    await openSource(tester);
    const raw = '= Heading\n\nVisible text\n\n#custom()[Secret]';
    await tester.enterText(find.byType(TextField), raw);

    await setViewMode(tester, 'Edit');
    final rich = find.byKey(const Key('rich-journal-editor'));
    expect(rich, findsOneWidget);
    expect(tester.widget<TextField>(rich).readOnly, isFalse);
    expect(tester.widget<TextField>(rich).focusNode!.hasFocus, isFalse);
    expect(find.text('Done'), findsNothing);
    expect(find.byTooltip('Bold'), findsNothing);
    expect(
      tester.widget<TextField>(rich).controller!.text,
      'Heading\n\nVisible text\n\n\uFFFC',
    );
    expect(find.text('Secret'), findsOneWidget);

    await tester.tap(rich);
    // Let the formatting dock finish sliding open before aiming at it.
    await tester.pumpAndSettle();
    expect(find.byTooltip('Bold'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Bold'));
    final controller = tester.widget<TextField>(rich).controller!;
    final start = controller.text.indexOf('Visible text');
    controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + 'Visible text'.length,
    );
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();
    expect(find.byKey(const Key('rich-journal-editor')), findsOneWidget);
    tester.widget<TextField>(rich).focusNode!.unfocus();
    await tester.pump();
    expect(tester.widget<TextField>(rich).focusNode!.hasFocus, isFalse);
    expect(find.byTooltip('Bold'), findsNothing);

    await openSource(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '= Heading\n\n#strong[Visible text]\n\n#custom()[Secret]',
    );
    expect(find.byTooltip('View mode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view chooser opens read preview source and editor modes', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();
    expect(find.byTooltip('View mode'), findsOneWidget);
    await setViewMode(tester, 'Read');
    expect(find.byType(SelectionArea), findsWidgets);
    expect(find.byTooltip('View mode'), findsNothing);
    await tester.tap(find.byTooltip('Back to edit'));
    await tester.pump();

    await setViewMode(tester, 'Preview');

    expect(
      tester
          .widget<TypstDocumentViewer>(find.byType(TypstDocumentViewer))
          .renderMode,
      TypstRenderMode.svg,
    );
    await setViewMode(tester, 'Source');

    expect(find.byType(TextField), findsOneWidget);
    await setViewMode(tester, 'Edit');

    expect(find.byKey(const Key('rich-journal-editor')), findsOneWidget);
  });

  testWidgets('reading mode reflows phone text and keeps only reader controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TyLogApp());
    await tester.pump();
    await openSource(tester);
    await tester.enterText(
      find.byType(TextField),
      List.generate(
        80,
        (index) =>
            'Paragraph $index has enough words to wrap naturally on a phone screen.',
      ).join('\n\n'),
    );
    await setViewMode(tester, 'Read');
    await tester.pump();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byTooltip('View mode'), findsNothing);
    expect(find.byTooltip('Back to edit'), findsOneWidget);
    expect(find.byTooltip('Reading settings'), findsOneWidget);
    expect(find.text('Agenda'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('reading-document'))).width,
      lessThanOrEqualTo(324),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('reading-progress')),
          )
          .value,
      closeTo(0, 0.01),
    );

    final scroll = tester
        .widget<SingleChildScrollView>(find.byKey(const Key('reading-scroll')))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent / 2);
    await tester.pump();
    final oldFraction = scroll.offset / scroll.position.maxScrollExtent;
    final oldFontSize = MediaQuery.textScalerOf(
      tester.element(find.byKey(const Key('reading-document'))),
    ).scale(16);

    await tester.tap(find.byTooltip('Reading settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reading-font-larger')));
    await tester.pump();
    await tester.pump();

    expect(find.text('110%'), findsOneWidget);
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byKey(const Key('reading-document'))),
      ).scale(16),
      greaterThan(oldFontSize),
    );
    expect(
      scroll.offset / scroll.position.maxScrollExtent,
      closeTo(oldFraction, 0.02),
    );

    await tester.tap(find.byKey(const Key('reading-night-mode')));
    await tester.pump();
    expect(
      Theme.of(
        tester.element(find.byKey(const Key('reading-document'))),
      ).brightness,
      Brightness.dark,
    );

    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('reading-progress')),
          )
          .value,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading mode handles system back and fullscreen restoration', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(const TyLogApp());
    await tester.pump();
    await setViewMode(tester, 'Read');
    await tester.tap(find.byTooltip('Reading settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reading-fullscreen')));
    await tester.pump();
    expect(
      calls,
      contains(
        isMethodCall(
          'SystemChrome.setEnabledSystemUIMode',
          arguments: 'SystemUiMode.immersiveSticky',
        ),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('rich-journal-editor')), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      calls,
      contains(
        isMethodCall(
          'SystemChrome.setEnabledSystemUIMode',
          arguments: 'SystemUiMode.edgeToEdge',
        ),
      ),
    );
  });

  testWidgets('graph remains available from overflow', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    expect(find.byTooltip('Graph'), findsNothing);
    await tester.tap(find.byType(NavigationDestination).last);
    await tester.pumpAndSettle();
    expect(find.text('Graph'), findsOneWidget);
    expect(find.text('Sync'), findsNothing);
  });

  testWidgets('Articles starts with Markdown batch import', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Articles'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('import-markdown-articles')), findsOneWidget);
    expect(find.text('Import Markdown articles'), findsOneWidget);
    expect(
      find.text('Select one or more .md or .markdown files'),
      findsOneWidget,
    );
  });

  testWidgets('sync status opens the full dashboard', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    final syncButton = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          const {
            'Nextcloud Desktop',
            'Sync not connected',
            'Syncing…',
            'Sync paused',
            'Needs attention',
            'Vault not open',
            'Folder access unavailable',
            'Ready to sync',
            'Up to date',
            'Synced',
          }.contains(widget.tooltip),
    );
    expect(syncButton, findsOneWidget);
    await tester.tap(syncButton);
    await tester.pumpAndSettle();

    expect(find.text('Sync'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Diagnostics log'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Diagnostics log'), findsOneWidget);
    expect(find.textContaining('Sync('), findsNothing);
    expect(find.textContaining('↑'), findsNothing);
    expect(find.textContaining('↓'), findsNothing);
    expect(find.text('Copy diagnostics'), findsOneWidget);
  });

  test('sync status blocks unopened and unhealthy vaults', () {
    final closed = syncStatusKind(
      vaultOpen: false,
      storageHealthy: false,
      cloudConfigured: true,
      desktopManaged: false,
      syncing: false,
      error: 'Open failed',
      conflicts: 0,
      result: null,
    );
    final unhealthy = syncStatusKind(
      vaultOpen: true,
      storageHealthy: false,
      cloudConfigured: true,
      desktopManaged: false,
      syncing: false,
      error: null,
      conflicts: 0,
      result: null,
    );

    expect(syncStatusTitle(closed), 'Vault not open');
    expect(syncStatusAction(closed), isNull);
    expect(syncStatusTitle(unhealthy), 'Folder access unavailable');
    expect(syncStatusAction(unhealthy), isNull);
    expect(vaultEntryLocation(null), isNull);
    expect(
      vaultEntryLocation(
        const VaultEntry(
          id: 'tree',
          name: 'Tygo',
          path: '',
          storageKind: 'android-tree',
          treeUri: 'content://provider/tree/primary%3ATygo',
        ),
      ),
      'content://provider/tree/primary%3ATygo',
    );
  });

  test('a fresh error outranks the spinner but not the setup sync', () {
    // syncNow clears syncError as it starts, so an error present during a sync
    // is one that happened just now - a resolve that failed, say. Ranking
    // `syncing` above it meant it was never rendered, which is
    // indistinguishable from a button that did nothing.
    expect(
      syncStatusKind(
        vaultOpen: true,
        storageHealthy: true,
        cloudConfigured: true,
        desktopManaged: false,
        syncing: true,
        error: 'Upload failed',
        conflicts: 0,
        result: null,
      ),
      SyncStatusKind.paused,
    );
    // And it outranks pending conflicts, which are a different fact.
    expect(
      syncStatusKind(
        vaultOpen: true,
        storageHealthy: true,
        cloudConfigured: true,
        desktopManaged: false,
        syncing: false,
        error: 'Upload failed',
        conflicts: 3,
        result: null,
      ),
      SyncStatusKind.paused,
    );
  });

  test('active initial sync wins over not-configured status', () {
    final kind = syncStatusKind(
      vaultOpen: true,
      storageHealthy: true,
      cloudConfigured: false,
      desktopManaged: false,
      syncing: true,
      error: null,
      conflicts: 0,
      result: null,
    );

    expect(kind, SyncStatusKind.syncing);
    expect(syncStatusTitle(kind), 'Syncing…');
  });

  test('rename-only sync is reported as a completed change', () {
    final kind = syncStatusKind(
      vaultOpen: true,
      storageHealthy: true,
      cloudConfigured: true,
      desktopManaged: false,
      syncing: false,
      error: null,
      conflicts: 0,
      result: const SyncResult(
        trigger: 'manual',
        uploaded: 0,
        downloaded: 0,
        skipped: 3,
        conflicts: 0,
        remoteCount: 3,
        renamed: 1,
      ),
    );

    expect(kind, SyncStatusKind.synced);
    expect(syncStatusTitle(kind), 'Synced');
  });

  test('sync status distinguishes configured+error from not-configured', () {
    // Regression test: Settings tile should not show 'Not configured'
    // when Nextcloud IS configured but sync is paused due to error.
    final withError = syncStatusKind(
      vaultOpen: true,
      storageHealthy: true,
      cloudConfigured: true,
      desktopManaged: false,
      syncing: false,
      error: 'Connection timeout',
      conflicts: 0,
      result: null,
    );

    expect(syncStatusTitle(withError), 'Sync paused');
    expect(syncStatusTitle(withError), isNot('Not configured'));

    // Same with conflicts: should not show 'Not configured'
    final withConflicts = syncStatusKind(
      vaultOpen: true,
      storageHealthy: true,
      cloudConfigured: true,
      desktopManaged: false,
      syncing: false,
      error: null,
      conflicts: 2,
      result: null,
    );

    expect(
      syncStatusTitle(withConflicts, conflicts: 2),
      '2 conflicts need review',
    );
    expect(
      syncStatusTitle(withConflicts, conflicts: 2),
      isNot('Not configured'),
    );
  });

  testWidgets('journal mode hides Typst system prelude', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Journal').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('#import'), findsNothing);
    expect(find.textContaining('#show:'), findsNothing);
  });

  // Journal feed windowing (scroll-triggered lazy loading) is covered in
  // test/journal_feed_test.dart, which needs a real (Live) test binding to
  // exercise actual vault I/O — see the comment at the top of that file.

  testWidgets('source keeps focus while typing consecutive characters', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await openSource(tester);
    final editor = find.byType(TextField);
    await tester.tap(editor);
    await tester.pump();

    for (final value in const ['a', 'ab', 'abc']) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        ),
      );
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
    }

    expect(tester.widget<TextField>(editor).controller!.text, 'abc');
  });

  testWidgets('journal renders a trailing newline before the next character', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();
    final editor = find.byKey(const Key('rich-journal-editor'));
    await tester.tap(editor);
    await tester.pump();
    final controller = tester.widget<TextField>(editor).controller!;

    controller.value = const TextEditingValue(
      text: 'строка\n',
      selection: TextSelection.collapsed(offset: 7),
    );
    await tester.pump();
    expect(controller.text, 'строка\n');

    controller.value = const TextEditingValue(
      text: 'строка\n\n',
      selection: TextSelection.collapsed(offset: 8),
    );
    await tester.pump();
    expect(controller.text, 'строка\n\n');

    controller.value = const TextEditingValue(
      text: 'строка\n\nм',
      selection: TextSelection.collapsed(offset: 9),
      composing: TextRange(start: 8, end: 9),
    );
    await tester.pump();
    expect(controller.text, 'строка\n\nм');
  });

  testWidgets('editor changes are autosaved', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await openSource(tester);

    await tester.enterText(find.byType(TextField), 'autosave text');
    await tester.pump();

    // Pending autosave shows as the dirty marker on the AppBar date title.
    expect(find.textContaining('•'), findsOneWidget);
  });

  testWidgets('typing during autosave keeps the newer editor text dirty', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await openSource(tester);

    await tester.enterText(find.byType(TextField), 'first draft');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.enterText(find.byType(TextField), 'newer draft');
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'newer draft');
    // Dirty marker moved to the AppBar date title.
    expect(find.textContaining('•'), findsOneWidget);
  });

  testWidgets('failed save keeps the current note during navigation', (
    tester,
  ) async {
    final storage = _FailingStorage();
    final vault = Vault.withStorage(storage);
    await storage.writeText('notes/a.typ', 'Note A');
    await storage.writeText('notes/b.typ', 'Note B');
    storage.failWrites = true;

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (controller.status == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    controller.vault = vault;
    controller.replaceNote('notes/a.typ', 'Note A');
    home.sourceController.text = 'unsaved edit A';
    controller.edit('unsaved edit A');
    home.mode = 'library';
    controller.notifyListeners();
    await tester.pump();

    final page = tester.widget<LibraryView>(find.byType(LibraryView));
    page.onOpenPath('notes/b.typ');
    await tester.pump();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (!controller.status.contains('Save failed') &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(controller.note, 'notes/a.typ');
    expect(controller.source, 'unsaved edit A');
    expect(controller.dirty, isTrue);
    expect(controller.status, contains('Save failed'));
    storage.failWrites = false;
    page.onOpenPath('notes/b.typ');
    await tester.pump();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (controller.note != 'notes/b.typ' &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(controller.note, 'notes/b.typ');
    expect(controller.source, 'Note B');
    expect(controller.dirty, isFalse);
  });

  testWidgets('latest note selection wins across a delayed vault read', (
    tester,
  ) async {
    final oldStorage = _DelayedStorage();
    final newStorage = _DelayedStorage();
    await oldStorage.writeText('notes/a.typ', 'Old note');
    await newStorage.writeText('notes/b.typ', 'New note');
    final oldVault = Vault.withStorage(oldStorage);
    final newVault = Vault.withStorage(newStorage);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    controller.vault = oldVault;
    controller.replaceNote('notes/current.typ', 'Current note');
    home.mode = 'library';
    controller.notifyListeners();
    await tester.pump();

    final page = tester.widget<LibraryView>(find.byType(LibraryView));
    final releaseOldRead = Completer<void>();
    oldStorage.readGate = releaseOldRead.future;
    oldStorage.gatedPath = 'notes/a.typ';
    page.onOpenPath('notes/a.typ');
    await tester.pump();
    controller.vault = newVault;
    page.onOpenPath('notes/b.typ');
    await tester.pump();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (controller.note != 'notes/b.typ' &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(controller.note, 'notes/b.typ');
    expect(controller.source, 'New note');

    releaseOldRead.complete();
    await tester.pump();
    expect(controller.note, 'notes/b.typ');
    expect(controller.source, 'New note');
  });

  testWidgets('a delayed note read is ignored after disposal', (tester) async {
    final storage = _DelayedStorage();
    await storage.writeText('notes/a.typ', 'Old note');
    final vault = Vault.withStorage(storage);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    controller.vault = vault;
    home.mode = 'library';
    controller.notifyListeners();
    await tester.pump();
    final release = Completer<void>();
    storage.readGate = release.future;
    storage.gatedPath = 'notes/a.typ';
    final page = tester.widget<LibraryView>(find.byType(LibraryView));
    page.onOpenPath('notes/a.typ');
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    release.complete();
    await tester.pump();
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('a delayed Today path cannot overwrite a later note selection', (
    tester,
  ) async {
    final storage = _DelayedStorage();
    await storage.writeText('notes/b.typ', 'New note');
    final vault = Vault.withStorage(storage);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    controller.vault = vault;
    controller.replaceNote('notes/current.typ', 'Current note');
    home.mode = 'library';
    controller.notifyListeners();
    await tester.pump();

    final releaseTodayPath = Completer<void>();
    storage.existsGate = releaseTodayPath.future;
    storage.gateNextExists = true;
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is NavigationDestination && widget.label == 'Today',
      ),
    );
    await tester.pump();
    final page = tester.widget<LibraryView>(find.byType(LibraryView));
    page.onOpenPath('notes/b.typ');
    await tester.pump();
    expect(controller.note, 'notes/b.typ');
    expect(controller.source, 'New note');

    releaseTodayPath.complete();
    await tester.pump();
    expect(controller.note, 'notes/b.typ');
    expect(controller.source, 'New note');
  });

  testWidgets('inserted images reach the preview compiler file map', (
    tester,
  ) async {
    final storage = _DelayedStorage();
    await storage.writeBytes('assets/pic.png', [1, 2, 3]);
    final vault = Vault.withStorage(storage);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    controller.vault = vault;
    controller.replaceNote('notes/current.typ', '');
    home.sourceController.text = '';
    final editor = tester.widget<TyLogRichEditor>(find.byType(TyLogRichEditor));
    editor.controller.loadSource('');
    editor.controller.applyMagic(
      const MagicRequest(
        action: MagicAction.attachment,
        value: '/assets/pic.png',
        kind: 'image',
      ),
    );
    await tester.pump();
    home.mode = 'preview';
    controller.notifyListeners();
    await tester.pump();
    var viewer = tester.widget<TypstDocumentViewer>(
      find.byType(TypstDocumentViewer),
    );
    expect(viewer.files!['assets/pic.png'], [1, 2, 3]);

    home.mode = 'source';
    controller.notifyListeners();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'No image reference');
    await tester.pump();
    home.mode = 'preview';
    controller.notifyListeners();
    await tester.pump();
    viewer = tester.widget<TypstDocumentViewer>(
      find.byType(TypstDocumentViewer),
    );
    expect(viewer.files!.containsKey('assets/pic.png'), isFalse);
  });

  testWidgets('old note assets cannot repopulate a newer note preview', (
    tester,
  ) async {
    final storage = _DelayedStorage();
    await storage.writeText('notes/a.typ', '#image("/assets/old.png")');
    await storage.writeText('notes/b.typ', 'New note');
    await storage.writeBytes('assets/old.png', [4, 5, 6]);
    final vault = Vault.withStorage(storage);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    controller.vault = vault;
    controller.replaceNote('notes/current.typ', 'Current note');
    home.mode = 'library';
    controller.notifyListeners();
    await tester.pump();
    final releaseAsset = Completer<void>();
    storage.readGate = releaseAsset.future;
    storage.gatedPath = 'assets/old.png';
    final page = tester.widget<LibraryView>(find.byType(LibraryView));
    page.onOpenPath('notes/a.typ');
    await tester.pump();
    page.onOpenPath('notes/b.typ');
    await tester.pump();
    home.mode = 'preview';
    controller.notifyListeners();
    await tester.pump();
    var viewer = tester.widget<TypstDocumentViewer>(
      find.byType(TypstDocumentViewer),
    );
    expect(viewer.files!.containsKey('assets/old.png'), isFalse);
    releaseAsset.complete();
    await tester.pump();
    viewer = tester.widget<TypstDocumentViewer>(
      find.byType(TypstDocumentViewer),
    );
    expect(viewer.files!.containsKey('assets/old.png'), isFalse);
  });

  testWidgets('share PDF waits for the current asset load', (tester) async {
    final storage = _DelayedStorage();
    await storage.writeBytes('assets/pic.png', [1, 2, 3]);
    final vault = Vault.withStorage(storage);
    final releaseAsset = Completer<void>();
    storage.readGate = releaseAsset.future;
    storage.gatedPath = 'assets/pic.png';
    String? compiledSource;
    Map<String, Uint8List>? compiledFiles;
    String? sharedName;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onCompilePdf: ({required source, required files}) async {
            compiledSource = source;
            compiledFiles = files;
            return Uint8List.fromList([1, 2, 3]);
          },
          onSharePdf: (name, _) async => sharedName = name,
        ),
      ),
    );
    await tester.pump();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    const source = '#image("/assets/pic.png")';
    controller.vault = vault;
    controller.replaceNote('notes/current.typ', source);
    home.sourceController.text = source;
    controller.notifyListeners();
    await tester.pump();
    storage.readGate = releaseAsset.future;
    storage.gatedPath = 'assets/pic.png';

    unawaited(home.sharePdfForTesting());
    await tester.pump();
    await tester.pump();
    expect(compiledSource, isNull);
    expect(sharedName, isNull);
    releaseAsset.complete();
    await tester.pump();
    await tester.pump();
    expect(compiledSource, source);
    expect(compiledFiles!['assets/pic.png'], [1, 2, 3]);
    expect(sharedName, 'current');
  });

  testWidgets('share PDF reports a missing asset without sharing', (
    tester,
  ) async {
    var compileCalls = 0;
    var shareCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onCompilePdf: ({required source, required files}) async {
            compileCalls++;
            return compileSourcePdf(source: source, files: files);
          },
          onSharePdf: (_, _) async => shareCalls++,
        ),
      ),
    );
    await tester.pump();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    const source = '#image("/assets/missing.png")';
    controller.vault = Vault.withStorage(_FailingStorage());
    controller.replaceNote('notes/missing.typ', source);
    home.sourceController.text = source;
    controller.notifyListeners();
    await tester.pump();
    unawaited(home.sharePdfForTesting());
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(compileCalls, 1);
    expect(shareCalls, 0);
    expect(find.text('Explain Typst error'), findsOneWidget);
  });

  testWidgets('share PDF drops a stale export after note switch', (
    tester,
  ) async {
    final compileGate = Completer<void>();
    var shareCalls = 0;
    String? compiledSource;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onCompilePdf: ({required source, required files}) async {
            compiledSource = source;
            await compileGate.future;
            return Uint8List.fromList([4, 5, 6]);
          },
          onSharePdf: (_, _) async => shareCalls++,
        ),
      ),
    );
    await tester.pump();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    const sourceA = 'A';
    const sourceB = 'B';
    controller.vault = Vault.withStorage(_FailingStorage());
    controller.replaceNote('notes/a.typ', sourceA);
    home.sourceController.text = sourceA;
    controller.notifyListeners();
    await tester.pump();
    unawaited(home.sharePdfForTesting());
    await tester.pump();
    expect(compiledSource, sourceA);
    controller.replaceNote('notes/b.typ', sourceB);
    home.sourceController.text = sourceB;
    controller.notifyListeners();
    compileGate.complete();
    await tester.pump();
    await tester.pump();
    expect(shareCalls, 0);
  });

  testWidgets('new page opens before a gated refresh and deduplicates taps', (
    tester,
  ) async {
    final storage = _GatedScanStorage();
    final vault = Vault.withStorage(storage);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    controller.vault = vault;
    controller.replaceNote('notes/current.typ', 'Current note');
    home.mode = 'library';
    controller.notifyListeners();
    await tester.pump();

    final releaseScan = Completer<void>();
    storage.listGate = releaseScan.future;
    storage.gateNextList = true;
    var page = tester.widget<LibraryView>(find.byType(LibraryView));
    page.onCreateNote('note');
    page.onCreateNote('note');
    await tester.pump();
    expect(find.text('New page'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Created');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(controller.note, 'notes/Created.typ');
    expect(controller.source, contains('Created'));
    expect(storage.listCalls, greaterThanOrEqualTo(1));
    releaseScan.complete();
    await tester.pumpAndSettle();
    expect(await storage.exists('notes/Created.typ'), isTrue);
    expect(find.text('New page'), findsNothing);
  });

  testWidgets('new page save failure preserves the original buffer', (
    tester,
  ) async {
    final storage = _FailingStorage();
    await storage.writeText('notes/current.typ', 'Current note');
    final vault = Vault.withStorage(storage);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    controller.vault = vault;
    controller.replaceNote('notes/current.typ', 'Current note');
    home.sourceController.text = 'Unsaved current edit';
    controller.edit('Unsaved current edit');
    home.mode = 'library';
    controller.notifyListeners();
    await tester.pump();
    storage.failWrites = true;
    final page = tester.widget<LibraryView>(find.byType(LibraryView));
    page.onCreateNote('note');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Should not create');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(controller.note, 'notes/current.typ');
    expect(controller.source, 'Unsaved current edit');
    expect(controller.dirty, isTrue);
    expect(await storage.exists('notes/Should not create.typ'), isFalse);
    expect(find.textContaining('Save failed'), findsOneWidget);
  });

  testWidgets('stale new page request cannot create after vault switch', (
    tester,
  ) async {
    final oldStorage = _FailingStorage();
    final newStorage = _FailingStorage();
    await newStorage.writeText('notes/b.typ', 'New vault note');
    final oldVault = Vault.withStorage(oldStorage);
    final newVault = Vault.withStorage(newStorage);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    controller.vault = oldVault;
    controller.replaceNote('notes/current.typ', 'Current note');
    home.mode = 'library';
    controller.notifyListeners();
    await tester.pump();
    final page = tester.widget<LibraryView>(find.byType(LibraryView));
    page.onCreateNote('note');
    await tester.pump();
    expect(find.text('New page'), findsOneWidget);
    controller.vault = newVault;
    page.onOpenPath('notes/b.typ');
    await tester.pump();
    final dialogField = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogField, 'Stale page');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(await oldStorage.exists('notes/Stale page.typ'), isFalse);
    expect(controller.note, 'notes/b.typ');
    expect(controller.source, 'New vault note');
  });

  testWidgets('new page creation error is visible and retryable', (
    tester,
  ) async {
    final storage = _FailingStorage();
    final vault = Vault.withStorage(storage);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    final controller = home.workspace;
    controller.vault = vault;
    controller.replaceNote('notes/current.typ', 'Current note');
    home.mode = 'library';
    controller.notifyListeners();
    await tester.pump();
    storage.failWrites = true;
    var page = tester.widget<LibraryView>(find.byType(LibraryView));
    page.onCreateNote('note');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Retry me');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(find.textContaining('Could not create page'), findsOneWidget);
    storage.failWrites = false;
    page = tester.widget<LibraryView>(find.byType(LibraryView));
    page.onCreateNote('note');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Created after retry');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(controller.note, 'notes/Created after retry.typ');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Magic menu exposes the complete command set', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rich-journal-editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();

    for (final label in const [
      'Insert',
      'Note link',
      'Mention',
      'Tag',
      'Date',
      'Citation',
      'Attachment',
      'Equation',
      'Text style',
      'Bold',
      'Italic',
      'Underline',
      'Strikethrough',
      'Highlight',
      'Monospace',
      'Structure',
      'Task',
      'Project',
      'Heading',
      'Table',
      'Report',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('H1'), findsWidgets);
  });

  testWidgets('Magic Table validates size and leaves the editor writable', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();
    final editor = find.byKey(const Key('rich-journal-editor'));
    await tester.tap(editor);
    await tester.pump();

    await openMagicAction(tester, 'Table');
    expect(find.text('Table size'), findsOneWidget);
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(fields.at(0)).controller!.text, '2');
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '2');

    await tester.enterText(fields.at(0), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Insert'));
    await tester.pump();
    expect(find.text('Use 1–10'), findsOneWidget);

    await tester.enterText(fields.at(0), '3');
    await tester.enterText(fields.at(1), '4');
    await tester.tap(find.widgetWithText(FilledButton, 'Insert'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(editor);
    expect(field.controller!.text, contains('￼'));
    expect(field.focusNode!.hasFocus, isTrue);

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '${field.controller!.text}x',
        selection: TextSelection.collapsed(
          offset: field.controller!.text.length + 1,
        ),
      ),
    );
    await tester.pump();
    expect(field.controller!.text, endsWith('x'));
  });

  testWidgets('Magic Equation prompts and Cancel restores focus', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();
    final editor = find.byKey(const Key('rich-journal-editor'));
    await tester.tap(editor);
    await tester.pump();

    await openMagicAction(tester, 'Equation');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);

    await openMagicAction(tester, 'Equation');
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'x + y',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(editor).controller!.text, contains('￼'));
    expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
  });

  testWidgets('source Magic Cancel restores source focus', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();
    await openSource(tester);
    await tester.pumpAndSettle();
    final editor = find.byType(TextField);
    await tester.tap(editor);
    await tester.pump();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Magic'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
  });

  testWidgets('TyLog fits a phone-width screen', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('knowledge screen exposes all PKMS work areas', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _knowledgeScreen()));

    expect(find.text('Search notes, tasks, and attachments'), findsOneWidget);
    expect(find.byTooltip('Knowledge sections'), findsOneWidget);
  });

  testWidgets('knowledge search fits a phone-width screen', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: _knowledgeScreen()));

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Search notes, tasks, and attachments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('knowledge screen can open directly on Problems', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _knowledgeScreen(initialView: KnowledgeView.problems)),
    );

    expect(find.text('No vault problems'), findsOneWidget);
    expect(find.text('Search notes, tasks, and attachments'), findsNothing);
  });

  testWidgets('knowledge problems show details and open the affected note', (
    tester,
  ) async {
    String? opened;
    const conflict = PkmsProblem(
      code: 'sync-conflict',
      severity: PkmsSeverity.error,
      subject: 'daily/2026/07/today.typ.remote-conflict-1',
      message: 'Both copies changed.',
      detail: 'Raw compiler output',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: _knowledgeScreen(
          initialView: KnowledgeView.problems,
          problems: const [conflict],
          onOpenNote: (path) => opened = path,
        ),
      ),
    );
    expect(find.text('Both copies changed.'), findsOneWidget);
    expect(find.text('Raw compiler output'), findsNothing);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('Raw compiler output'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(
      icon.color,
      Theme.of(tester.element(find.byType(KnowledgeScreen))).colorScheme.error,
    );

    await tester.tap(find.widgetWithText(ListTile, 'Both copies changed.'));
    await tester.pumpAndSettle();
    expect(opened, conflict.subject);
  });

  testWidgets('knowledge problems groups a large same-code flood', (
    tester,
  ) async {
    final flood = [
      for (var i = 0; i < 8; i++)
        PkmsProblem(
          code: 'metadata-fallback',
          severity: PkmsSeverity.warning,
          subject: 'notes/note-$i.typ',
          message: 'Typst metadata was unavailable; using legacy parsing.',
        ),
    ];
    const smallGroup = [
      PkmsProblem(
        code: 'metadata-query-failed',
        severity: PkmsSeverity.warning,
        subject: 'notes/broken-a.typ',
        message: "A note's formatting couldn't be read.",
        detail: 'Typst metadata query failed: boom',
      ),
      PkmsProblem(
        code: 'metadata-query-failed',
        severity: PkmsSeverity.warning,
        subject: 'notes/broken-b.typ',
        message: "A note's formatting couldn't be read.",
        detail: 'Typst metadata query failed: boom',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: _knowledgeScreen(
          initialView: KnowledgeView.problems,
          problems: [...flood, ...smallGroup],
        ),
      ),
    );

    // Collapsed: one summary tile for the 8-strong flood; the 2-item group
    // still renders its rows directly, same as before grouping existed.
    expect(
      find.text('Typst metadata was unavailable; using legacy parsing.'),
      findsOneWidget,
    );
    expect(find.textContaining('8 notes · notes/note-0.typ'), findsOneWidget);
    expect(find.text('notes/broken-a.typ'), findsOneWidget);
    expect(find.text('notes/broken-b.typ'), findsOneWidget);
    expect(find.text('notes/note-0.typ'), findsNothing);

    await tester.tap(find.textContaining('8 notes · notes/note-0.typ'));
    await tester.pumpAndSettle();

    expect(find.text('notes/note-0.typ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('notes/note-7.typ'),
      100,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('notes/note-7.typ'), findsOneWidget);
  });

  testWidgets('problems show a Fix button only for fixable codes', (
    tester,
  ) async {
    final fixed = <List<PkmsProblem>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: _knowledgeScreen(
          initialView: KnowledgeView.problems,
          problems: const [
            PkmsProblem(
              code: 'metadata-fallback',
              severity: PkmsSeverity.warning,
              subject: 'notes/legacy.typ',
              message: 'Typst metadata was unavailable; using legacy parsing.',
            ),
            PkmsProblem(
              code: 'unverified-note-metadata',
              severity: PkmsSeverity.info,
              subject: 'notes/fallback.typ',
              message: 'Typst metadata was read by the safe fallback scanner.',
            ),
          ],
          onFixProblems: (list) async {
            fixed.add(list);
            return const []; // pretend everything got resolved
          },
        ),
      ),
    );

    // Fixable code gets a Convert button; the info-only one does not.
    expect(find.widgetWithText(TextButton, 'Convert'), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Convert'));
    await tester.pumpAndSettle();

    expect(fixed, hasLength(1));
    expect(fixed.single.single.subject, 'notes/legacy.typ');
    // The list redrew from the callback's result (empty → "No vault problems").
    expect(find.text('No vault problems'), findsOneWidget);
  });

  testWidgets(
    'KnowledgeScreen shows saved searches and invokes callback with status',
    (tester) async {
      final invokedQueries = <(String query, String? tag, String? status)>[];
      final searches = [
        SavedSearch(name: 'To-do', query: '', status: 'todo'),
        SavedSearch(name: 'Tagged', query: 'flutter', tag: 'dart'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _knowledgeScreen(
              savedSearches: searches,
              search: (query, tag, status) async {
                invokedQueries.add((query, tag, status));
                return const [];
              },
            ),
          ),
        ),
      );

      // Verify both saved search chips are rendered
      expect(find.text('To-do'), findsOneWidget);
      expect(find.text('Tagged'), findsOneWidget);

      // Tap the "To-do" preset
      await tester.tap(find.text('To-do'));
      await tester.pumpAndSettle();

      // Verify the search was invoked with the preset's status and empty query
      expect(invokedQueries.last, ('', null, 'todo'));

      // Tap the "Tagged" preset
      await tester.tap(find.text('Tagged'));
      await tester.pumpAndSettle();

      // Verify the search was invoked with the preset's query and tag
      expect(invokedQueries.last, ('flutter', 'dart', null));
    },
  );

  testWidgets('KnowledgeScreen refreshes when search becomes ready', (
    tester,
  ) async {
    final state = _SearchStateProbe();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _knowledgeScreen(
            searchState: state,
            searchReady: () => state.ready,
            searchRevision: () => state.revision,
            search: (_, _, _) async {
              calls++;
              return const [
                PkmsSearchResult(
                  id: 'ready',
                  path: 'notes/ready.typ',
                  title: 'Ready result',
                  kind: 'note',
                  tags: [],
                  score: 1,
                ),
              ];
            },
          ),
        ),
      ),
    );
    expect(find.text('Indexing search…'), findsOneWidget);
    expect(calls, 0);
    state.publish(ready: true, revision: 1);
    await tester.pump();
    await tester.pump();
    expect(find.text('Ready result'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('KnowledgeScreen distinguishes an empty search result', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _knowledgeScreen(search: (_, _, _) async => const []),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Indexing search…'), findsNothing);
  });

  testWidgets('KnowledgeScreen opens a retrieved note', (tester) async {
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _knowledgeScreen(
            search: (_, _, _) async => const [
              PkmsSearchResult(
                id: 'paper',
                path: 'articles/paper.typ',
                title: 'Paper',
                kind: 'article',
                tags: ['research'],
                score: 1,
              ),
            ],
            onOpenNote: (path) => opened = path,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Paper'), findsOneWidget);
    await tester.tap(find.text('Paper'));
    await tester.pumpAndSettle();
    expect(opened, 'articles/paper.typ');
  });

  testWidgets('KnowledgeScreen drops delayed results from an older query', (
    tester,
  ) async {
    final oldResult = Completer<List<PkmsSearchResult>>();
    final newResult = Completer<List<PkmsSearchResult>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _knowledgeScreen(
            search: (query, _, _) {
              if (query == 'old') return oldResult.future;
              if (query == 'new') return newResult.future;
              return Future.value(const <PkmsSearchResult>[]);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 130));
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 130));
    newResult.complete(const [
      PkmsSearchResult(
        id: 'new',
        path: 'notes/new.typ',
        title: 'New result',
        kind: 'note',
        tags: [],
        score: 1,
      ),
    ]);
    await tester.pump();
    oldResult.complete(const [
      PkmsSearchResult(
        id: 'old',
        path: 'notes/old.typ',
        title: 'Old result',
        kind: 'note',
        tags: [],
        score: 1,
      ),
    ]);
    await tester.pump();
    expect(find.text('New result'), findsOneWidget);
    expect(find.text('Old result'), findsNothing);
  });

  testWidgets('KnowledgeScreen resamples a replacement search state', (
    tester,
  ) async {
    final oldState = _SearchStateProbe();
    final newState = _SearchStateProbe()
      ..ready = true
      ..revision = 1;
    Widget screen(_SearchStateProbe state) => Scaffold(
      body: _knowledgeScreen(
        searchState: state,
        searchReady: () => state.ready,
        searchRevision: () => state.revision,
        search: (_, _, _) async => const [
          PkmsSearchResult(
            id: 'replacement',
            path: 'notes/replacement.typ',
            title: 'Replacement result',
            kind: 'note',
            tags: [],
            score: 1,
          ),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: screen(oldState)));
    expect(find.text('Indexing search…'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: screen(newState)));
    await tester.pump();
    expect(find.text('Replacement result'), findsOneWidget);
  });

  testWidgets('KnowledgeScreen removes search listener on dispose', (
    tester,
  ) async {
    final state = _SearchStateProbe()..ready = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _knowledgeScreen(
            searchState: state,
            searchReady: () => state.ready,
            searchRevision: () => state.revision,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    state.publish(ready: true, revision: 1);
    await tester.pump();
    expect(find.byType(KnowledgeScreen), findsNothing);
  });

  testWidgets('saved searches stay current across saves, delete, and failure', (
    tester,
  ) async {
    var stored = <SavedSearch>[];
    var failSave = false;
    Future<void> save(SavedSearch search) async {
      if (failSave) throw StateError('write failed');
      stored = [...stored.where((item) => item.name != search.name), search];
    }

    Future<void> delete(SavedSearch search) async {
      stored = stored.where((item) => item.name != search.name).toList();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgeScreen(
            index: const VaultIndex(notesByPath: {}, backlinksByTarget: {}),
            search: (_, _, _) async => const [],
            problems: const [],
            onOpenNote: (_) {},
            onSaveSearch: save,
            onDeleteSearch: delete,
          ),
        ),
      ),
    );

    Future<void> saveNamed(String name, String query) async {
      await tester.enterText(find.byType(TextField).first, query);
      await tester.pump();
      await tester.tap(find.widgetWithText(ActionChip, 'Save'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, name);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
    }

    await saveNamed('First', 'one');
    await saveNamed('Second', 'two');
    expect(stored.map((item) => item.name), ['First', 'Second']);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);

    await tester.longPress(find.text('Second'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(stored.map((item) => item.name), ['First']);
    expect(find.text('Second'), findsNothing);

    failSave = true;
    await saveNamed('Failed', 'three');
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Failed'), findsNothing);
    expect(find.textContaining('Could not save search'), findsOneWidget);
  });

  testWidgets('saved-search controls stay locked during a delayed write', (
    tester,
  ) async {
    final release = Completer<void>();
    var deletes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgeScreen(
            index: const VaultIndex(notesByPath: {}, backlinksByTarget: {}),
            search: (_, _, _) async => const [],
            problems: const [],
            onOpenNote: (_) {},
            savedSearches: const [SavedSearch(name: 'First', query: 'one')],
            onSaveSearch: (_) => release.future,
            onDeleteSearch: (_) async => deletes++,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'two');
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, 'Save'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Second');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    expect(find.widgetWithText(ActionChip, 'Save'), findsNothing);
    await tester.longPress(find.text('First'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    expect(deletes, 0);
    release.complete();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, 'Save'), findsOneWidget);
  });
}

class _FailingStorage extends VaultStorage {
  final Map<String, Uint8List> _files = {};
  final Set<String> _directories = {''};

  bool failWrites = false;

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    if (failWrites && path.endsWith('.typ')) {
      throw const FileSystemException('injected write failure');
    }
    _files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List> readBytes(String path) async => _files[path]!;

  @override
  Future<bool> exists(String path) async =>
      _files.containsKey(path) || _directories.contains(path);

  @override
  Future<void> createDirectory(String path) async => _directories.add(path);

  @override
  Future<void> delete(String path) async => _files.remove(path);

  @override
  Future<VaultStorageEntry?> stat(String path) async {
    final bytes = _files[path];
    if (bytes == null) return null;
    return VaultStorageEntry(
      path: path,
      isDirectory: false,
      size: bytes.length,
      modified: DateTime.utc(2026, 7, 14),
    );
  }

  @override
  Future<String> hash(String path) async => base64.encode(_files[path]!);

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final prefix = path.isEmpty ? '' : '$path/';
    bool included(String candidate) =>
        candidate.startsWith(prefix) &&
        candidate != path &&
        (recursive || !candidate.substring(prefix.length).contains('/'));
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
}

class _DelayedStorage extends _FailingStorage {
  Future<void>? readGate;
  String? gatedPath;
  Future<void>? existsGate;
  bool gateNextExists = false;

  @override
  Future<Uint8List> readBytes(String path) async {
    final gate = path == gatedPath ? readGate : null;
    if (gate != null) {
      readGate = null;
      await gate;
    }
    return super.readBytes(path);
  }

  @override
  Future<bool> exists(String path) async {
    final gate = gateNextExists ? existsGate : null;
    if (gate != null) {
      gateNextExists = false;
      await gate;
    }
    return super.exists(path);
  }
}

class _GatedScanStorage extends _FailingStorage {
  Future<void>? listGate;
  bool gateNextList = false;
  int listCalls = 0;

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    listCalls++;
    final gate = gateNextList && recursive ? listGate : null;
    if (gate != null) {
      gateNextList = false;
      await gate;
    }
    return super.list(path: path, recursive: recursive);
  }
}

KnowledgeScreen _knowledgeScreen({
  KnowledgeView initialView = KnowledgeView.search,
  List<PkmsProblem> problems = const [],
  ValueChanged<String>? onOpenNote,
  Future<List<PkmsProblem>?> Function(List<PkmsProblem>)? onFixProblems,
  List<SavedSearch> savedSearches = const [],
  Listenable? searchState,
  bool Function()? searchReady,
  int Function()? searchRevision,
  Future<List<PkmsSearchResult>> Function(
    String query,
    String? tag,
    String? status,
  )?
  search,
}) => KnowledgeScreen(
  initialView: initialView,
  index: const VaultIndex(notesByPath: {}, backlinksByTarget: {}),
  search: search ?? (_, _, _) async => const [],
  problems: problems,
  onOpenNote: onOpenNote ?? (_) {},
  onFixProblems: onFixProblems,
  savedSearches: savedSearches,
  searchState: searchState,
  searchReady: searchReady,
  searchRevision: searchRevision,
);

class _SearchStateProbe extends ChangeNotifier {
  bool ready = false;
  int revision = 0;

  void publish({required bool ready, int? revision}) {
    this.ready = ready;
    if (revision != null) this.revision = revision;
    notifyListeners();
  }
}
