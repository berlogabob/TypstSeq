import 'package:material_ui/material_ui.dart';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/settings/maintenance_page.dart';
import 'package:tylog/widgets/settings_sheet.dart';
import 'package:tylog/workspace_controller.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog_core/tylog_core.dart';

NoteRef note(
  String path,
  String title, {
  String kind = 'note',
  List<String> aliases = const [],
}) => NoteRef(
  id: path,
  path: path,
  title: title,
  kind: kind,
  aliases: aliases,
  outgoingLinks: const [],
);

void main() {
  final notes = [
    note('notes/AndreSabino.typ', 'AndreSabino', kind: 'person'),
    note('notes/André Sabino.typ', 'André Sabino'),
    note(
      'notes/iade1.typ',
      'IADE',
      kind: 'organization',
      aliases: ['Institute'],
    ),
    note('notes/iade2.typ', 'Iade', aliases: ['Institute']),
    note('notes/iade3.typ', 'University', aliases: ['IADE']),
    note('daily/ignored.typ', 'IADE', kind: 'daily'),
    note('notes/blank.typ', '!!!'),
  ];
  final index = VaultIndex(
    notesByPath: {for (final n in notes) n.path: n},
    backlinksByTarget: const {
      'notes/AndreSabino.typ': ['daily/a.typ', 'daily/b.typ'],
    },
  );

  test(
    'finds title and alias matches without duplicate rows or empty keys',
    () {
      final groups = findDuplicates(
        index,
      ).map((g) => g.map((n) => n.path).toSet()).toList();
      expect(groups, hasLength(3));
      expect(
        groups,
        contains(equals({'notes/AndreSabino.typ', 'notes/André Sabino.typ'})),
      );
      expect(
        groups,
        contains(
          equals({'notes/iade1.typ', 'notes/iade2.typ', 'notes/iade3.typ'}),
        ),
      );
      expect(groups, contains(equals({'notes/iade1.typ', 'notes/iade2.typ'})));
    },
  );

  testWidgets('Maintenance shows duplicate pages and backlink counts', (
    tester,
  ) async {
    final workspace = WorkspaceController(
      taskScheduler: TaskScheduler(),
      reconcileTasks: (_) async {},
    )..index = index;
    addTearDown(workspace.dispose);
    final settings = SettingsSheet(
      workspace: workspace,
      vaultPath: '/vault',
      cloud: null,
      syncing: false,
      syncStatusSubtitle: '',
      onNextcloud: () {},
      vaultCount: 1,
      themeMode: ThemeMode.system,
      onThemeModeChanged: (_) {},
      onManageVaults: () {},
      onEnableReminders: () async {},
      onMigrateEntityTypes: () async {},
      onStripImportNoise: () async {},
      onImportVault: () async {},
      onInstallModule: () async {},
    );
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: MaintenancePage(settings: settings)),
    );
    await tester.tap(find.text('Duplicates'));
    await tester.pumpAndSettle();
    expect(find.text('AndreSabino'), findsOneWidget);
    expect(find.textContaining('2 backlinks'), findsOneWidget);
    expect(find.textContaining('notes/AndreSabino.typ'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Merge into…').first);
    await tester.pumpAndSettle();
    expect(find.text('Choose a page to keep'), findsOneWidget);
    expect(find.textContaining('Page to remove:'), findsOneWidget);
    expect(find.textContaining('notes/André Sabino.typ'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'latest health report opens directly from Maintenance at 360 dp',
    (tester) async {
      final storage = _TestStorage();
      final opened = <String>[];
      await storage.writeText('_system/health/not-a-date.json', '{}');
      await storage.writeText(
        '_system/health/2026-11-04.json',
        '{"issues":[]}',
      );
      await storage.writeText(
        '_system/health/2026-11-03.json',
        '{"issues":[]}',
      );
      final settings = SettingsSheet(
        storage: storage,
        onOpenPath: opened.add,
        workspace: WorkspaceController(
          taskScheduler: TaskScheduler(),
          reconcileTasks: (_) async {},
        ),
        vaultPath: '/vault',
        cloud: null,
        syncing: false,
        syncStatusSubtitle: '',
        onNextcloud: () {},
        vaultCount: 1,
        themeMode: ThemeMode.system,
        onThemeModeChanged: (_) {},
        onManageVaults: () {},
        onEnableReminders: () async {},
        onMigrateEntityTypes: () async {},
        onStripImportNoise: () async {},
        onImportVault: () async {},
        onInstallModule: () async {},
      );
      addTearDown(settings.workspace!.dispose);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: MaintenancePage(settings: settings)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Latest health report'), findsOneWidget);
      expect(find.text('2026-11-04'), findsOneWidget);
      await tester.tap(find.text('Latest health report'));
      expect(opened, ['_system/health/2026-11-04.json']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Duplicates stays reachable while the index is unavailable', (
    tester,
  ) async {
    final workspace = WorkspaceController(
      taskScheduler: TaskScheduler(),
      reconcileTasks: (_) async {},
    )..status = 'Index refresh failed: test';
    addTearDown(workspace.dispose);
    final settings = SettingsSheet(
      workspace: workspace,
      vaultPath: '/vault',
      cloud: null,
      syncing: false,
      syncStatusSubtitle: '',
      onNextcloud: () {},
      vaultCount: 1,
      themeMode: ThemeMode.system,
      onThemeModeChanged: (_) {},
      onManageVaults: () {},
      onEnableReminders: () async {},
      onMigrateEntityTypes: () async {},
      onStripImportNoise: () async {},
      onImportVault: () async {},
      onInstallModule: () async {},
    );
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: MaintenancePage(settings: settings)),
    );

    await tester.tap(find.text('Duplicates'));
    await tester.pumpAndSettle();

    expect(find.text('Index could not be loaded'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestStorage extends VaultStorage {
  final files = <String, List<int>>{};

  @override
  Future<bool> exists(String path) async =>
      files.keys.any((file) => file == path || file.startsWith('$path/'));

  @override
  Future<void> createDirectory(String path) async {}

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async => [
    for (final file in files.keys.where((file) => file.startsWith('$path/')))
      VaultStorageEntry(path: file, isDirectory: false),
  ];

  @override
  Future<VaultStorageEntry?> stat(String path) async => files.containsKey(path)
      ? VaultStorageEntry(
          path: path,
          isDirectory: false,
          size: files[path]!.length,
        )
      : null;

  @override
  Future<Uint8List> readBytes(String path) async =>
      Uint8List.fromList(files[path]!);

  @override
  Future<String> hash(String path) async => path;

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    files[path] = bytes;
  }

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }
}
