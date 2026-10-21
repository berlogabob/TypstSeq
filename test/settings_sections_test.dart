import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/settings_sheet.dart';

void main() {
  SettingsSheet sheet({
    Map<String, dynamic> calendars = const {},
    Future<void> Function(Map<String, dynamic>)? onConfigure,
  }) => SettingsSheet(
    calendarSettings: calendars,
    onConfigureCalendars: onConfigure,
    vaultPath: '/vault',
    cloud: null,
    syncing: false,
    syncStatusSubtitle: 'Offline',
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

  testWidgets('Other ICS calendar can be added and rejects http', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: sheet(onConfigure: (value) async => saved = value),
        ),
      ),
    );
    await tester.tap(find.text('Calendars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other (ICS link)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Other');
    await tester.enterText(
      find.byType(TextField).at(1),
      'http://example.org/calendar.ics',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://example.org/calendar.ics',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved?['feeds'], hasLength(1));
    expect(saved?['feeds'].single['kind'], 'ics');
  });

  testWidgets('IADE preset adds classes and lab feeds', (tester) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: sheet(onConfigure: (value) async => saved = value),
        ),
      ),
    );
    await tester.tap(find.text('Calendars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IADE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved?['feeds'], hasLength(2));
    expect(
      saved?['feeds'].map((feed) => feed['kind']),
      containsAll(['iade-timetable', 'ics']),
    );
  });

  testWidgets('Settings home has six groups and refreshes its summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          home: SettingsSheet(
            vaultPath: '/vault',
            cloud: null,
            syncing: false,
            syncStatusSubtitle: 'Offline',
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title as Text).data),
      [
        'General',
        'Calendars',
        'AI',
        'Sync and storage',
        'Maintenance',
        'About',
      ],
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Letter').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Auto · Letter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
