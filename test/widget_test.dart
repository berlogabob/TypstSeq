import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/knowledge_screen.dart';
import 'package:tylog/main.dart';
import 'package:tylog/models.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/search_index.dart';
import 'package:tylog/vault_registry.dart';
import 'package:typst_flutter/typst_flutter.dart';

Future<void> setViewMode(WidgetTester tester, String mode) async {
  await tester.tap(find.byTooltip('View mode'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode).last);
  await tester.pump();
}

Future<void> openSource(WidgetTester tester) => setViewMode(tester, 'Source');

Future<void> openMagicAction(WidgetTester tester, String label) async {
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
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    // Settings is now the second item in the More sheet (right after
    // Vaults), so it's visible without scrolling.
    await tester.tap(find.widgetWithText(ListTile, 'Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Local folder'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
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
    await tester.pump();
    expect(find.byTooltip('Bold'), findsOneWidget);
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
    expect(find.byType(SelectableText), findsWidgets);
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
    await tester.tap(find.text('More').last);
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

    expect(syncStatusTitle(withConflicts, conflicts: 2), '2 conflicts need review');
    expect(syncStatusTitle(withConflicts, conflicts: 2), isNot('Not configured'));
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

  testWidgets('Magic menu exposes the complete command set', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rich-journal-editor')));
    await tester.pump();
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
}

KnowledgeScreen _knowledgeScreen({
  KnowledgeView initialView = KnowledgeView.search,
  List<PkmsProblem> problems = const [],
  ValueChanged<String>? onOpenNote,
  Future<List<PkmsProblem>?> Function(List<PkmsProblem>)? onFixProblems,
}) => KnowledgeScreen(
  initialView: initialView,
  index: const VaultIndex(notesByPath: {}, backlinksByTarget: {}),
  search: PkmsSearchIndex.empty(),
  problems: problems,
  onOpenNote: onOpenNote ?? (_) {},
  onFixProblems: onFixProblems,
);
