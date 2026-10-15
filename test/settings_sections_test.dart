import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/ds/app_section.dart';
import 'package:tylog/widgets/ds/app_tile.dart';
import 'package:tylog/widgets/settings_sheet.dart';

void main() {
  testWidgets('Settings sections preserve every tool callback and info rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsSheet(
            vaultPath: '/vault',
            cloud: null,
            syncing: false,
            syncStatusSubtitle: 'Offline',
            onNextcloud: () => calls.add('Sync'),
            vaultCount: 1,
            themeMode: ThemeMode.system,
            onThemeModeChanged: (_) => calls.add('Appearance'),
            onManageVaults: () => calls.add('Vaults'),
            onEnableReminders: () async => calls.add('Task reminders'),
            onMigrateEntityTypes: () async => calls.add('Migrate entity types'),
            onStripImportNoise: () async =>
                calls.add('Clean up imported notes'),
            onImportVault: () async => calls.add('Import vault'),
            onInstallModule: () async => calls.add('Modules'),
            onProblems: () => calls.add('Problems'),
            onRebuildIndex: () => calls.add('Rebuild index'),
            onRelinkVault: () => calls.add('Relink vault'),
            onSemanticSearch: () => calls.add('Semantic search'),
            onTypstHelp: () => calls.add('Typst help'),
            onCheckForUpdates: () => calls.add('Check for updates'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<AppSection>(find.byType(AppSection))
          .map((section) => section.title),
      ['General', 'AI and processing', 'Storage and sync', 'Tools', 'About'],
    );
    for (final title in ['Local folder', 'App version']) {
      expect(find.text(title), findsOneWidget);
      expect(find.widgetWithText(ListTile, title), findsNothing);
      expect(find.widgetWithText(AppTile, title), findsNothing);
    }
    final appearance = tester.getSize(find.text('Appearance'));
    expect(appearance.height, lessThan(30));
    final chips = ['Auto', 'Light', 'Dark']
        .map(
          (label) =>
              tester.getTopLeft(find.widgetWithText(ChoiceChip, label)).dy,
        )
        .toSet();
    expect(chips, hasLength(1));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dark'));
    for (final title in [
      'Task reminders',
      'Vaults',
      'Sync',
      'Problems',
      'Rebuild index',
      'Relink vault',
      'Migrate entity types',
      'Clean up imported notes',
      'Import vault',
      'Modules',
      'Semantic search',
      'Check for updates',
      'Typst help',
    ]) {
      await tester.ensureVisible(find.widgetWithText(AppTile, title));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppTile, title));
      await tester.pump();
      expect(calls.last, title);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
