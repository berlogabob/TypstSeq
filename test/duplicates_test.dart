import 'package:flutter/material.dart';
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
    await tester.pumpWidget(
      MaterialApp(home: MaintenancePage(settings: settings)),
    );
    await tester.tap(find.text('Duplicates'));
    await tester.pumpAndSettle();
    expect(find.text('AndreSabino'), findsOneWidget);
    expect(find.textContaining('2 backlinks'), findsOneWidget);
    expect(find.textContaining('notes/AndreSabino.typ'), findsOneWidget);
  });
}
