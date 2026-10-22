import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/settings/ai_page.dart';
import 'package:tylog/widgets/settings_sheet.dart';

SettingsSheet settings() => SettingsSheet(
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
  screenshotsMode: 'off',
  screenshotsTime: '03:00',
  onConfigureScreenshots: (_, _) async {},
  onProcessScreenshots: () async {},
  readScreenshotsStatus: () async => 'Ready',
);

Future<void> pumpSettings(WidgetTester tester, {Size size = const Size(400, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: settings()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("searching OCR opens Screenshots", (tester) async {
    await pumpSettings(tester);

    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      'OCR',
    );
    await tester.pump();
    expect(find.text('Screenshots'), findsOneWidget);
    expect(find.text('AI › Screenshots'), findsOneWidget);

    await tester.tap(find.text('Screenshots'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Screenshots'), findsOneWidget);
  });

  testWidgets('wide Settings shows the home and selected page side by side', (
    tester,
  ) async {
    await pumpSettings(tester, size: const Size(1200, 800));

    expect(find.byKey(const ValueKey('settings-search')), findsOneWidget);
    await tester.tap(find.text('AI').first);
    await tester.pumpAndSettle();
    expect(find.byType(AiPage), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-search')), findsOneWidget);
  });

  testWidgets('narrow Settings still pushes a group page', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.byType(AiPage), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-search')), findsNothing);
  });
}
