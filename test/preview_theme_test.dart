import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tylog/widgets/settings_sheet.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog_core/src/vault.dart' show legacyManagedTheme;

void main() {
  test('managed theme upgrades v1 but preserves edited v1 and v2', () async {
    final root = await Directory.systemTemp.createTemp('tylog-theme-');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();
    final theme = File('${root.path}/_system/theme.typ');
    final current = await theme.readAsString();
    expect(current, startsWith('// tylog-theme-version: 2'));
    // Real vault copies carry one trailing newline less than the bundle.
    for (final legacy in [legacyManagedTheme, legacyManagedTheme.trimRight()]) {
      await theme.writeAsString(legacy);
      await vault.ensureCreated();
      expect(await theme.readAsString(), current);
    }
    for (final edited in [
      '$legacyManagedTheme// custom\n',
      '$current// custom\n',
    ]) {
      await theme.writeAsString(edited);
      await vault.ensureCreated();
      expect(await theme.readAsString(), edited);
    }
  });

  test('PDF paper defaults to A4 and saves in the existing registry', () async {
    final root = await Directory.systemTemp.createTemp('tylog-paper-');
    addTearDown(() => root.delete(recursive: true));
    final registry = VaultRegistry(File('${root.path}/vaults.json'), [], '');
    expect(registry.pdfPaper, 'a4');
    await registry.setPdfPaper('us-letter');
    final saved = jsonDecode(await registry.file.readAsString()) as Map;
    expect(saved['pdfPaper'], 'us-letter');
    expect(saved['themeMode'], 'system');
  });

  testWidgets('PDF page size offers all four papers and reports selection', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsSheet(
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
            onPdfPaperChanged: (paper) => selected = paper,
          ),
        ),
      ),
    );
    expect(find.text('PDF page size'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.value, 'a4');
    expect(dropdown.items!.map((item) => item.value), [
      'a4',
      'us-letter',
      'a5',
      'us-legal',
    ]);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Letter').last);
    await tester.pumpAndSettle();
    expect(selected, 'us-letter');
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .value,
      'us-letter',
    );
  });

  final hasTypst = Process.runSync('which', ['typst']).exitCode == 0;
  for (final (label, inputs, width, height) in [
    ('default A4', <String>[], 595.276, 841.89),
    ('continuous preview', ['tylog-page-width=360'], 360.0, null),
    ('Letter export', ['tylog-paper=us-letter'], 612.0, 792.0),
  ]) {
    test('theme compiles $label with expected page dimensions', () async {
      final root = await Directory.systemTemp.createTemp('tylog-layout-');
      addTearDown(() => root.delete(recursive: true));
      await File('typst/vault/theme.typ').copy('${root.path}/theme.typ');
      await File('${root.path}/note.typ').writeAsString(
        '#import "theme.typ": document\n#show: document\n'
        '${List.filled(height == null ? 100 : 1, 'A paragraph of text.\n\n').join()}',
      );
      final result = Process.runSync('typst', [
        'compile',
        '--root',
        root.path,
        for (final input in inputs) ...['--input', input],
        '${root.path}/note.typ',
        '${root.path}/page-{n}.svg',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final pages = root
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.svg'))
          .toList();
      expect(pages, hasLength(1));
      final svg = await pages.single.readAsString();
      if (inputs.isEmpty) {
        await File('${root.path}/theme.typ').writeAsString(legacyManagedTheme);
        final legacy = Process.runSync('typst', [
          'compile',
          '--root',
          root.path,
          '${root.path}/note.typ',
          '${root.path}/legacy.svg',
        ]);
        expect(legacy.exitCode, 0, reason: '${legacy.stderr}');
        expect(await File('${root.path}/legacy.svg').readAsString(), svg);
      }

      final dimensions = RegExp(
        r'<svg[^>]*width="([\d.]+)pt"[^>]*height="([\d.]+)pt"',
      ).firstMatch(svg)!;
      expect(double.parse(dimensions[1]!), closeTo(width, 0.01));
      if (height != null) {
        expect(double.parse(dimensions[2]!), closeTo(height, 0.01));
      } else {
        expect(double.parse(dimensions[2]!), greaterThan(841.89));
      }
    }, skip: !hasTypst ? 'Host Typst CLI unavailable' : false);
  }
}
