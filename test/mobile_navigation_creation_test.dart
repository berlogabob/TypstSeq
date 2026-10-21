// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:tylog/widgets/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/knowledge_screen.dart';
import 'package:tylog/models.dart';
import 'package:tylog_core/search_index.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/widgets/idea_hub.dart';
import 'package:tylog/widgets/ds/app_sheet.dart';
import 'package:tylog/widgets/constants.dart';
import 'package:tylog/widgets/audio_shelf.dart';
import 'package:tylog/widgets/audio_sheets.dart';
import 'package:tylog/widgets/audio_note_screen.dart';
import 'package:tylog/widgets/screenshot_strip.dart';
import 'package:tylog/widgets/screenshot_view.dart';
import 'package:tylog/widgets/sync_dashboard.dart';
import 'package:tylog/widgets/work_surface.dart';
import 'package:tylog/widgets/journal_feed.dart';

Future<void> _emptyStartup() async {}

Future<dynamic> _mount(WidgetTester tester, _GatedStorage storage) async {
  await storage.writeText('notes/current.typ', 'Original');
  await tester.pumpWidget(
    const MaterialApp(home: HomeScreen(startup: _emptyStartup)),
  );
  await tester.pumpAndSettle();
  final dynamic home = tester.state(find.byType(HomeScreen));
  home.workspace.vault = Vault.withStorage(storage);
  home.workspace.index = const VaultIndex(
    notesByPath: {},
    backlinksByTarget: {},
  );
  home.workspace.replaceNote('notes/current.typ', 'Original');
  home.sourceController.text = 'Original';
  home.richController.loadSource('Original');
  home.workspace.notifyListeners();
  await tester.pump();
  return home;
}

Future<dynamic> _mountToday(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final home = await _mount(tester, _GatedStorage());
  const path = 'daily/2026/10/2026-10-14.typ';
  await home.workspace.vault.storage.writeText(path, 'Original');
  home.workspace.replaceNote(path, 'Original');
  home.workspace.notifyListeners();
  await tester.pumpAndSettle();
  return home;
}

void _dirty(dynamic home) {
  home.sourceController.text = 'Unsaved edit';
  home.workspace.edit('Unsaved edit');
}

Future<void> _selectLibraryTab(WidgetTester tester, String label) async {
  final tab = find.widgetWithText(Tab, label);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
  final labels = [
    'Notes',
    'Articles',
    'Screenshots',
    'Tasks',
    'Calendar',
    'Audio',
  ];
  expect(
    DefaultTabController.of(tester.element(tab)).index,
    labels.indexOf(label),
  );
}

Future<void> _prepareSearchResult(dynamic home) async {
  final storage = home.workspace.vault.storage as _GatedStorage;
  await storage.writeText('notes/cervejaria.typ', 'cervejaria');
  await storage.writeText(
    'notes/run.typ',
    '#show: tylog.note.with(id: "run", title: "Пробежка")\n',
  );
  await storage.writeText(
    'daily/2023/04/2023-04-01.typ',
    '#show: tylog.note.with(id: "2023-04-01", title: "2023-04-01", kind: "daily")\n'
    '- #tylog.ref-note("Пробежка")[Пробежка]\n',
  );
  final index = VaultIndex(
    notesByPath: {
      'notes/cervejaria.typ': const NoteRef(
        id: 'cervejaria',
        path: 'notes/cervejaria.typ',
        title: 'Cervejaria',
        outgoingLinks: [],
      ),
      'notes/run.typ': const NoteRef(
        id: 'run',
        path: 'notes/run.typ',
        title: 'Пробежка',
        outgoingLinks: [],
      ),
      'daily/2023/04/2023-04-01.typ': const NoteRef(
        id: '2023-04-01',
        path: 'daily/2023/04/2023-04-01.typ',
        title: '2023-04-01',
        kind: 'daily',
        outgoingLinks: ['Пробежка'],
      ),
    },
    backlinksByTarget: const {},
  );
  home.workspace.index = index;
  home.workspace.searchIndex.replaceWith(
    await PkmsSearchIndex.buildStorage(storage, index),
  );
  home.workspace.searchReady = true;
  home.workspace.notifyListeners();
}

Future<void> _showRunSearch(WidgetTester tester, dynamic home) async {
  await _prepareSearchResult(home);
  tester.widget<NavigationRail>(find.byType(NavigationRail)).onDestinationSelected!(3);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Search notes, tasks, and attachments',
    ),
    'пробежка',
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Future<void> _openCervejariaResult(WidgetTester tester, dynamic home) async {
  await _prepareSearchResult(home);
  final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
  nav.onDestinationSelected!(3);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search notes, tasks, and attachments',
    ),
    'cervejaria',
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cervejaria'));
  await tester.pumpAndSettle();
}

void main() {
  FlutterLocalNotificationsPlatform.instance = _FakeNotificationsPlatform();

  testWidgets('screenshot notes open in ScreenshotView until edited', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(400, 800));
    final storage = home.workspace.vault.storage as _GatedStorage;
    const screenshotPath = 'screenshots/shot.typ';
    const regularPath = 'notes/regular.typ';
    await storage.writeText(screenshotPath, '== Description\nA screenshot');
    await storage.writeText(regularPath, 'A regular note');
    home.workspace.index = const VaultIndex(
      notesByPath: {
        screenshotPath: NoteRef(
          id: 'shot',
          path: screenshotPath,
          title: 'Screenshot',
          kind: 'screenshot',
          outgoingLinks: [],
        ),
        regularPath: NoteRef(
          id: 'regular',
          path: regularPath,
          title: 'Regular',
          outgoingLinks: [],
        ),
      },
      backlinksByTarget: {},
    );
    home.workspace.notifyListeners();
    await tester.pumpAndSettle();

    tester.widget<TodayPage>(find.byType(TodayPage)).onOpenPath(screenshotPath);
    await tester.pumpAndSettle();
    expect(find.byType(ScreenshotView), findsOneWidget);
    expect(find.byType(TyLogRichEditor), findsNothing);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(TyLogRichEditor), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    tester.widget<TodayPage>(find.byType(TodayPage)).onOpenPath(regularPath);
    await tester.pumpAndSettle();
    expect(find.byType(ScreenshotView), findsNothing);
    expect(find.byType(TyLogRichEditor), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    tester.widget<TodayPage>(find.byType(TodayPage)).onOpenPath(screenshotPath);
    await tester.pumpAndSettle();
    expect(find.byType(ScreenshotView), findsOneWidget);
    expect(find.byType(TyLogRichEditor), findsNothing);
  });

  for (final destination in [1, 2, 3]) {
    testWidgets('system back from destination $destination returns to Today', (
      tester,
    ) async {
      final home = await _mountToday(tester, const Size(400, 800));
      // Search must return to Today even when opened from Library.
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      if (destination == 3) {
        nav.onDestinationSelected!(2);
        await tester.pumpAndSettle();
      }
      nav.onDestinationSelected!(destination);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(home.primaryDestination, 0);
      expect(home.mode, 'normal');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final tab in [
    'Notes',
    'Articles',
    'Screenshots',
    'Tasks',
    'Calendar',
    'Audio',
  ]) {
    testWidgets('Library $tab system back returns to Today', (tester) async {
      final home = await _mountToday(tester, const Size(480, 800));
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .onDestinationSelected!(2);
      await tester.pumpAndSettle();
      await _selectLibraryTab(tester, tab);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(home.primaryDestination, 0);
      expect(home.mode, 'normal');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Today note editor system back returns to Today', (tester) async {
    final home = await _mountToday(tester, const Size(400, 800));
    tester
        .widget<TodayPage>(find.byType(TodayPage))
        .onOpenPath('notes/current.typ');
    await tester.pumpAndSettle();
    expect(home.workspace.note, 'notes/current.typ');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(home.primaryDestination, 0);
    expect(find.byType(TodayPage), findsOneWidget);
    expect(home.workspace.note, isNot('notes/current.typ'));
    await tester.pumpWidget(const SizedBox());
  });

  for (final destination in [1, 2]) {
    testWidgets('note editor system back restores list $destination', (
      tester,
    ) async {
      final home = await _mountToday(tester, const Size(400, 800));
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .onDestinationSelected!(destination);
      await tester.pumpAndSettle();
      if (destination == 2) {
        await _selectLibraryTab(tester, 'Tasks');
        tester
            .widget<LibraryView>(find.byType(LibraryView))
            .onOpenPath('notes/current.typ');
      } else {
        tester
            .widget<JournalFeed>(find.byType(JournalFeed))
            .onOpenPath('notes/current.typ');
      }
      await tester.pumpAndSettle();
      expect(home.mode, 'normal');
      final hadBackArrow = find.byType(BackButton).evaluate().isNotEmpty;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(home.mode, destination == 2 ? 'library' : 'journal');
      expect(hadBackArrow, isTrue);
      expect(home.primaryDestination, destination);
      if (destination == 2) {
        expect(
          DefaultTabController.of(tester.element(find.byType(TabBar))).index,
          3,
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(home.primaryDestination, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('shelf reading system back restores Library tab', (tester) async {
    final home = await _mountToday(tester, const Size(400, 800));
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(2);
    await tester.pumpAndSettle();
    await _selectLibraryTab(tester, 'Articles');
    tester
        .widget<LibraryView>(find.byType(LibraryView))
        .onReadPath('notes/current.typ');
    await tester.pumpAndSettle();
    expect(home.mode, 'read');
    final hadBackArrow = find.byType(BackButton).evaluate().isNotEmpty;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(home.mode, 'library');
    expect(hadBackArrow, isTrue);
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBar))).index,
      1,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Search result opens editor and back returns to Search', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(400, 800));
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(3);
    await tester.pumpAndSettle();
    tester
        .widget<KnowledgeScreen>(find.byType(KnowledgeScreen))
        .onOpenNote('notes/current.typ');
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeScreen), findsNothing);
    expect(home.workspace.note, 'notes/current.typ');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(home.primaryDestination, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping a Search result keeps the mobile shell route alive', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(400, 800));
    await _openCervejariaResult(tester, home);
    expect(home.workspace.note, 'notes/cervejaria.typ');
    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping a Search result keeps the rail shell route alive', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(1100, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    await _prepareSearchResult(home);
    rail.onDestinationSelected!(3);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Search notes, tasks, and attachments',
      ),
      'cervejaria',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cervejaria'));
    await tester.pumpAndSettle();
    expect(home.workspace.note, 'notes/cervejaria.typ');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping a daily Cyrillic Search result opens that daily note', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(1100, 800));
    await _showRunSearch(tester, home);
    expect(find.text('2023-04-01'), findsOneWidget);
    await tester.tap(find.text('2023-04-01'));
    await tester.pumpAndSettle();
    expect(home.workspace.note, 'daily/2023/04/2023-04-01.typ');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the day title does not jump between Today and another day', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(360, 800));
    final title = find.byType(CompactDateTitle);
    final today = tester.getRect(title);
    expect(find.byTooltip('Previous day'), findsNothing);
    expect(find.byTooltip('Next day'), findsNothing);
    await _prepareSearchResult(home);
    tester.widget<NavigationBar>(find.byType(NavigationBar)).onDestinationSelected!(3);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Search notes, tasks, and attachments',
      ),
      'пробежка',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2023-04-01'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.getRect(title).left, closeTo(today.left, 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a past day opened from Search has a readable title on a phone', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(370, 890));
    await _prepareSearchResult(home);
    tester.widget<NavigationBar>(find.byType(NavigationBar)).onDestinationSelected!(3);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Search notes, tasks, and attachments',
      ),
      'пробежка',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2023-04-01'));
    await tester.pumpAndSettle();
    final title = find.descendant(
      of: find.byType(CompactDateTitle),
      matching: find.byType(Text),
    );
    // Each of the two rendered lines must stay at a readable height.
    expect(tester.getRect(title).height / 2, greaterThanOrEqualTo(12));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping an entity Cyrillic Search result opens that note', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(1100, 800));
    await _showRunSearch(tester, home);
    expect(find.text('Пробежка'), findsOneWidget);
    await tester.tap(find.text('Пробежка'));
    await tester.pumpAndSettle();
    expect(home.workspace.note, 'notes/run.typ');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back from a Search result returns to Search, not empty Today', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(400, 800));
    await _prepareSearchResult(home);
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    nav.onDestinationSelected!(3);
    await tester.pumpAndSettle();
    final searchField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search notes, tasks, and attachments',
    );
    await tester.enterText(searchField, 'cervejaria');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cervejaria'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(KnowledgeScreen), findsOneWidget);
    expect(home.primaryDestination, 3);
    expect(tester.widget<TextField>(searchField).controller!.text, 'cervejaria');
    expect(find.text('Cervejaria'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('macOS rail destinations have no back arrow', (tester) async {
    await _mountToday(tester, const Size(1100, 800));
    for (final destination in [0, 1, 2]) {
      tester
          .widget<NavigationRail>(find.byType(NavigationRail))
          .onDestinationSelected!(destination);
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final origin in [0, 1, 2]) {
    testWidgets('Graph system back restores destination $origin', (
      tester,
    ) async {
      final home = await _mountToday(tester, const Size(400, 800));
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      if (origin != 0) {
        nav.onDestinationSelected!(origin);
        await tester.pumpAndSettle();
      }
      final originalMode = home.mode;
      nav.onDestinationSelected!(4);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Graph').last);
      await tester.pumpAndSettle();
      expect(home.mode, 'graph');
      final hadBackArrow = find.byType(BackButton).evaluate().isNotEmpty;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(home.mode, originalMode);
      expect(hadBackArrow, isTrue);
      expect(home.primaryDestination, origin);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final view in ['Read', 'Preview', 'Source', 'Split']) {
    testWidgets('$view system back restores editor', (tester) async {
      final home = await _mountToday(tester, const Size(400, 800));
      await tester.tap(find.byTooltip('View mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(view).last);
      await tester.pumpAndSettle();
      expect(home.mode, view.toLowerCase());
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(home.mode, 'normal');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('More closes to its origin on system back', (tester) async {
    final home = await _mountToday(tester, const Size(400, 800));
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    nav.onDestinationSelected!(2);
    await tester.pumpAndSettle();
    nav.onDestinationSelected!(4);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(home.mode, 'library');
    expect(home.primaryDestination, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Context shows a back arrow and closes on system back', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(400, 800));
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(4);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Context'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Context'), findsNothing);
    expect(home.primaryDestination, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('nested Split returns to Source before the editor', (
    tester,
  ) async {
    final home = await _mountToday(tester, const Size(400, 800));
    for (final view in ['Source', 'Split']) {
      await tester.tap(find.byTooltip('View mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(view).last);
      await tester.pumpAndSettle();
    }
    home.sourceController.text = 'Edited source';
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(home.mode, 'source');
    expect(home.sourceController.text, 'Edited source');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(home.mode, 'normal');
    expect(home.richController.text, contains('Edited source'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sync dashboard has an arrow and pops on system back', (
    tester,
  ) async {
    await _mountToday(tester, const Size(400, 800));
    final button = tester.widget<SyncIconButton>(find.byType(SyncIconButton));
    button.onPressed();
    await tester.pumpAndSettle();
    expect(find.byType(SyncDashboardScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SyncDashboardScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Library recording appears and opens without restarting', (
    tester,
  ) async {
    final storage = _GatedStorage();
    final home = await _mount(tester, storage);
    home.workspace.index = VaultIndex(notesByPath: {}, backlinksByTarget: {});
    home.mode = 'library';
    home.primaryDestination = 2;
    home.workspace.notifyListeners();
    await tester.pumpAndSettle();
    await _selectLibraryTab(tester, 'Audio');
    tester.widget<AudioShelf>(find.byType(AudioShelf)).onRecord();
    await tester.pumpAndSettle();
    // Deliver the completed take at the recorder/UI boundary without a mic.
    Navigator.of(tester.element(find.byType(BottomSheet))).pop(
      AudioTake(
        Uint8List.fromList([1, 2, 3]),
        'aac',
        const [1, 2],
        1000,
        DateTime(2026, 10, 16, 12),
      ),
    );
    await tester.pumpAndSettle();
    expect(await storage.exists('notes/Audio 20261016-120000.typ'), isTrue);
    expect(
      await storage.exists('assets/audio/2026/10/20261016-120000.aac'),
      isTrue,
    );
    expect(find.byType(AudioNoteScreen), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Audio 20261016-120000'), findsOneWidget);
    await tester.tap(find.text('Audio 20261016-120000'));
    await tester.pumpAndSettle();
    expect(find.byType(AudioNoteScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'landscape uses an icon rail without overflow and switches screens',
    (tester) async {
      final home = await _mountToday(tester, const Size(780, 360));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.labelType, NavigationRailLabelType.none);
      expect(rail.destinations, hasLength(5));
      expect(rail.scrollable, isTrue);
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 48);
      expect(tester.takeException(), isNull);
      final library = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(AppIcons.library),
      );
      await tester.ensureVisible(library);
      await tester.tap(library);
      await tester.pumpAndSettle();
      expect(home.primaryDestination, 2);
      expect(home.mode, 'library');
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'landscape Today has a single agenda row opening a bounded sheet',
    (tester) async {
      await _mountToday(tester, const Size(780, 360));
      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(IdeaHubStrip), findsNothing);
      expect(find.byType(ScreenshotStrip), findsNothing);
      final agenda = find.text('Agenda · 0');
      final header = find.ancestor(of: agenda, matching: find.byType(ListTile));
      expect(header, findsOneWidget);
      expect(tester.getSize(header).height, 56);
      expect(tester.widget<Text>(agenda).maxLines, 1);
      expect(find.byKey(const PageStorageKey('today-agenda')), findsNothing);
      expect(find.text('All tasks →'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(agenda);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AppSheet), findsOneWidget);
      final handle = find.descendant(
        of: find.byType(AppSheet),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints?.maxWidth == kMinTapTarget &&
              widget.constraints?.maxHeight == kSpace4,
        ),
      );
      expect(handle, findsOneWidget);
      final grip = find.descendant(
        of: handle,
        matching: find.byType(DecoratedBox),
      );
      expect(grip.hitTestable(), findsOneWidget);
      expect(tester.getSize(grip), const Size(kMinTapTarget, kSpace4));
      expect(
        tester.getSize(find.byType(BottomSheet)).height,
        lessThanOrEqualTo(288),
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(find.text('All tasks →'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('All tasks →'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('portrait keeps the bottom navigation and inline agenda', (
    tester,
  ) async {
    await _mountToday(tester, const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 56);
    expect(find.byType(IdeaHubStrip), findsOneWidget);
    expect(find.byType(ScreenshotStrip), findsOneWidget);
    expect(find.byKey(const PageStorageKey('today-agenda')), findsOneWidget);
    expect(find.text('All tasks →'), findsNothing);
    await tester.tap(find.text('Agenda · 0'));
    await tester.pumpAndSettle();
    expect(find.text('All tasks →'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final destination in [0, 1, 2, 3]) {
    testWidgets('destination $destination responds before a delayed save', (
      tester,
    ) async {
      final storage = _GatedStorage();
      final home = await _mount(tester, storage);
      home.primaryDestination = destination == 0 ? 2 : 0;
      home.mode = destination == 0 ? 'library' : 'normal';
      _dirty(home);
      home.workspace.notifyListeners();
      await tester.pump();
      final release = Completer<void>();
      storage.writeGate = release.future;
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      nav.onDestinationSelected!(destination);
      await tester.pump();
      expect(storage.blockedWrites, greaterThan(0));
      expect(home.primaryDestination, destination);
      expect(
        home.mode,
        destination == 1
            ? 'journal'
            : destination == 2
            ? 'library'
            : 'normal',
      );
      expect(home.workspace.note, 'notes/current.typ');
      expect(home.sourceController.text, 'Unsaved edit');
      if (destination == 3) {
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.widgetWithText(AppBar, 'Search'), findsOneWidget);
        Navigator.of(
          tester.element(find.byType(HomeScreen, skipOffstage: false)),
        ).pop();
      }
      release.complete();
      await tester.pumpAndSettle();
      expect(await storage.readText('notes/current.typ'), 'Unsaved edit');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a newer tab wins while Today waits for a dirty save', (
    tester,
  ) async {
    final storage = _GatedStorage();
    final home = await _mount(tester, storage);
    home.primaryDestination = 2;
    home.mode = 'library';
    _dirty(home);
    home.workspace.notifyListeners();
    await tester.pump();
    final release = Completer<void>();
    storage.writeGate = release.future;
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    nav.onDestinationSelected!(0);
    await tester.pump();
    expect(home.primaryDestination, 0);
    nav.onDestinationSelected!(1);
    await tester.pump();
    expect(home.primaryDestination, 1);
    expect(home.mode, 'journal');
    release.complete();
    await tester.pumpAndSettle();
    expect(home.primaryDestination, 1);
    expect(home.mode, 'journal');
    expect(home.workspace.note, 'notes/current.typ');
    expect(home.sourceController.text, 'Unsaved edit');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Search opens before presets load and a later tab wins', (
    tester,
  ) async {
    final storage = _GatedStorage();
    final home = await _mount(tester, storage);
    await storage.writeText(
      '_system/saved-searches.json',
      '{"schema":1,"searches":[]}',
    );
    final release = Completer<void>();
    storage.gatedReadPath = '_system/saved-searches.json';
    storage.readGate = release.future;
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    nav.onDestinationSelected!(3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(storage.blockedReads, 1);
    expect(home.primaryDestination, 3);
    expect(find.widgetWithText(AppBar, 'Search'), findsOneWidget);
    Navigator.of(
      tester.element(find.byType(HomeScreen, skipOffstage: false)),
    ).pop();
    await tester.pumpAndSettle();
    nav.onDestinationSelected!(2);
    await tester.pump();
    release.complete();
    await tester.pumpAndSettle();
    expect(home.primaryDestination, 2);
    expect(home.mode, 'library');
    expect(find.byType(KnowledgeScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'entity creation returns its path and metadata during a blocked scan',
    (tester) async {
      final storage = _GatedStorage();
      final home = await _mount(tester, storage);
      final release = Completer<void>();
      storage.listGate = release.future;
      final Future<void> scan = home.workspace.rebuildIndex();
      await tester.pump();
      NoteRef? result;
      var completed = false;
      final Future<NoteRef?> creation = home.createEntityForTesting();
      creation.then((value) {
        result = value;
        completed = true;
      });
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'Ada');
      await tester.enterText(fields.at(1), 'person');
      await tester.enterText(fields.at(2), 'Countess');
      await tester.enterText(fields.at(3), 'ada@example.test');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result?.path, 'notes/Ada.typ');
      expect(result?.kind, 'person');
      expect(result?.aliases, ['Countess']);
      expect(result?.properties['email'], 'ada@example.test');
      expect(home.workspace.rebuilding, isTrue);
      release.complete();
      await tester.pumpAndSettle();
      await scan;
      await tester.pumpWidget(const SizedBox());
    },
  );
}

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

class _GatedStorage extends VaultStorage {
  final Map<String, Uint8List> _files = {};
  final Set<String> _directories = {''};

  bool failWrites = false;
  Future<void>? writeGate;
  Future<void>? readGate;
  Future<void>? listGate;
  String? gatedReadPath;
  int blockedWrites = 0;
  int blockedReads = 0;

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    if (path == 'notes/current.typ' && writeGate != null) {
      blockedWrites++;
      await writeGate;
    }
    if (failWrites && path.endsWith('.typ')) {
      throw const FileSystemException('injected write failure');
    }
    _files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    if (path == gatedReadPath && readGate != null) {
      blockedReads++;
      await readGate;
    }
    return _files[path]!;
  }

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
  Future<String> hash(String path) async =>
      sha256.convert(_files[path]!).toString();

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    if (recursive && listGate != null) await listGate;
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
