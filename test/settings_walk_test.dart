import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/audio_processing_settings.dart';
import 'package:tylog/ai/ai_settings.dart';
import 'package:tylog/audio/processing_policy.dart';
import 'package:tylog/widgets/settings_sheet.dart';

void main() {
  testWidgets('settings pages keep every setting reachable with Back', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
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
          audioPolicyRead: () async => const AudioPolicy(),
          audioPolicyWrite: (_) async {},
          onProcessAudio: () async {},
          readAi: () async => const AiSettings(),
          writeAi: (_) async {},
          readScreenshotsStatus: () async => 'Ready',
          onConfigureScreenshots: (_, _) async {},
          onProcessScreenshots: () async {},
          onCheckForUpdates: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openGroup(String title, List<String> labels) async {
      await tester.tap(find.text(title).first);
      await tester.pumpAndSettle();
      for (final label in labels) {
        expect(
          find.text(label),
          findsWidgets,
          reason: 'Missing $title > $label',
        );
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    }

    await openGroup('General', [
      'Appearance',
      'PDF page size',
      'Task reminders',
    ]);
    await openGroup('Calendars', ['No calendars configured']);
    await openGroup('Sync and storage', ['Local folder', 'Vaults', 'Sync']);
    await openGroup('Maintenance', [
      'Problems',
      'Rebuild index',
      'Relink vault',
      'Migrate entity types',
      'Clean up imported notes',
      'Import vault',
      'Modules',
      'Semantic search',
    ]);
    await openGroup('About', [
      'App version',
      'Check for updates',
      'Typst help',
    ]);

    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    for (final (page, label) in const [
      ('Servers', 'Servers'),
      ('Audio', 'Transcription quality'),
      ('Articles', 'Articles'),
      ('Screenshots', 'Screenshots (OCR)'),
    ]) {
      await tester.tap(find.text(page).first);
      await tester.pumpAndSettle();
      expect(
        find.text(label),
        findsWidgets,
        reason: 'Missing AI > $page > $label',
      );
      if (page == 'Screenshots') {
        // The OCR server and model live here too, not only the schedule.
        expect(
          find.byType(AudioProcessingSettings),
          findsOneWidget,
          reason: 'Missing AI > Screenshots > server and model',
        );
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('AI'), findsOneWidget);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });
}
