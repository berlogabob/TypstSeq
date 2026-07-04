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
    expect(find.byTooltip('Graph'), findsOneWidget);
    expect(find.byTooltip('Search knowledge'), findsOneWidget);
    expect(find.byTooltip('Vaults'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('Quick actions'), findsNothing);
  });

  testWidgets('settings menu shows real app data', (tester) async {
    final version = await appVersion();

    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
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

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Source'));
    await tester.pump();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Preview'), findsOneWidget);
    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(find.text('Edit source'), findsOneWidget);
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

  testWidgets('editor dock wraps selections and inserts headings', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    field.controller!.text = 'hello';
    await tester.tap(find.byType(TextField));
    await tester.pump();
    field.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    );
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();
    expect(field.controller!.text, '*hello*');

    field.controller!.selection = const TextSelection.collapsed(offset: 0);
    await tester.tap(find.byTooltip('Heading'));
    await tester.pump();
    expect(field.controller!.text, '= *hello*');
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
    await tester.pumpWidget(MaterialApp(home: _knowledgeScreen()));

    expect(find.text('Search notes and files'), findsOneWidget);
    expect(find.byTooltip('Knowledge sections'), findsOneWidget);
  });

  testWidgets('knowledge search fits a phone-width screen', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: _knowledgeScreen()));

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Search notes and files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('knowledge screen can open directly on Problems', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _knowledgeScreen(initialView: KnowledgeView.problems)),
    );

    expect(find.text('No PKMS problems'), findsOneWidget);
    expect(find.text('Search notes and files'), findsNothing);
  });

  testWidgets('knowledge gives sync conflicts the first filter position', (
    tester,
  ) async {
    const conflict = PkmsProblem(
      code: 'sync-conflict',
      severity: PkmsSeverity.warning,
      subject: 'journal/today.typ.remote-conflict-1',
      message: 'Both copies changed.',
    );
    await tester.pumpWidget(
      MaterialApp(home: _knowledgeScreen(problems: const [conflict])),
    );

    expect(
      tester.getTopLeft(find.text('Conflicts: 1')).dx,
      lessThan(tester.getTopLeft(find.text('All')).dx),
    );
    await tester.tap(find.text('Conflicts: 1'));
    await tester.pump();
    expect(find.text('Both copies changed.'), findsOneWidget);
  });
}

KnowledgeScreen _knowledgeScreen({
  KnowledgeView initialView = KnowledgeView.search,
  List<PkmsProblem> problems = const [],
}) => KnowledgeScreen(
  initialView: initialView,
  index: const VaultIndex(notesByPath: {}, backlinksByTarget: {}),
  search: PkmsSearchIndex.empty(),
  tags: PkmsTagRegistry.empty,
  files: PkmsFileRegistry.empty,
  collections: PkmsCollectionRegistry.empty,
  problems: problems,
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
  onResolveConflict: (_) async {},
  onCleanSyncCaches: () async {},
);
