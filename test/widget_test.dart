import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/knowledge_screen.dart';
import 'package:tylog/main.dart';
import 'package:tylog/models.dart';
import 'package:tylog/pkms_registry.dart';
import 'package:tylog/search_index.dart';

void main() {
  testWidgets('TyLog shell renders', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    expect(find.text('TyLog'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.byTooltip('Save'), findsNothing);
    expect(find.byTooltip('Journal'), findsOneWidget);
    expect(find.byTooltip('Source'), findsOneWidget);
    expect(find.byTooltip('Preview'), findsNothing);
    expect(find.byTooltip('Graph'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byTooltip('Quick actions'), findsOneWidget);
  });

  testWidgets('settings menu shows real app data', (tester) async {
    final version = await appVersion();

    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Local folder'), findsOneWidget);
    expect(find.text('Nextcloud settings'), findsOneWidget);
    expect(find.text('Sync server status'), findsOneWidget);
    expect(find.text('App version'), findsOneWidget);
    await tester.pump();
    expect(find.text(version), findsOneWidget);
  });

  testWidgets('source preview actions toggle both ways', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    final sourceButton = find.byIcon(Icons.code).first;
    await tester.tap(sourceButton);
    await tester.pump();
    expect(find.byTooltip('Preview'), findsOneWidget);
    await tester.tap(sourceButton);
    await tester.pump();
    expect(find.byTooltip('Source'), findsOneWidget);
    await tester.tap(sourceButton);
    await tester.pump();

    expect(find.byTooltip('Preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('journal mode hides Typst system prelude', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isNot(contains('#import')));
    expect(field.controller?.text, isNot(contains('#note')));
  });

  testWidgets('editor changes are autosaved', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'autosave text');
    await tester.pump();

    expect(find.text('Autosave pending...'), findsOneWidget);
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
    await tester.pumpWidget(
      MaterialApp(
        home: KnowledgeScreen(
          index: const VaultIndex(notesByPath: {}, backlinksByTarget: {}),
          search: PkmsSearchIndex.empty(),
          tags: PkmsTagRegistry(
            tags: {
              'pkms': PkmsTagEntry(slug: 'pkms', title: 'PKMS', type: 'topic'),
            },
          ),
          files: PkmsFileRegistry(
            files: {
              'manual': PkmsFileEntry(
                id: 'manual',
                path: 'assets/manual.pdf',
                kind: 'pdf',
                status: 'reference',
              ),
            },
          ),
          collections: PkmsCollectionRegistry.empty,
          problems: const [],
          onOpenNote: (_) {},
          onOpenFile: (_) {},
          onSaveTag: (_) async {},
          onDeleteTag: (_) async {},
          onMergeTag: (_, _) async {},
          onImportFile: () async {},
          onSaveFile: (_) async {},
          onDeleteFile: (_) async {},
          onSaveCollection: (_) async {},
          onExportCollection: (_) async {},
          onMigrateLegacy: () async {},
        ),
      ),
    );

    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Problems'), findsOneWidget);
    expect(find.text('Collections'), findsOneWidget);
  });
}
