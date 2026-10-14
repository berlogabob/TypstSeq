// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/knowledge_screen.dart';
import 'package:tylog/models.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/widgets/idea_hub.dart';
import 'package:tylog/widgets/screenshot_strip.dart';

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

void main() {
  FlutterLocalNotificationsPlatform.instance = _FakeNotificationsPlatform();
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
        matching: find.byIcon(Icons.library_books),
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
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isTrue,
      );
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
