import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/knowledge_screen.dart';
import 'package:tylog/main.dart';
import 'package:tylog/models.dart';
import 'package:tylog/search_index.dart';

void main() {
  testWidgets('TyLog shell renders', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    expect(find.text('TyLog'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.byTooltip('Save'), findsNothing);
    expect(find.byTooltip('Graph'), findsNothing);
    expect(find.byTooltip('Search knowledge'), findsOneWidget);
    expect(find.byIcon(Icons.sync_alt), findsOneWidget);
    expect(find.byTooltip('Vaults'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const Key('quick-capture')), findsOneWidget);
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

  testWidgets('preview edits the cursor block and navigates adjacent blocks', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    await tester.tap(find.text('Journal').last);
    await tester.pump();

    await tester.tap(find.byTooltip('Source'));
    await tester.pump();
    expect(find.byTooltip('Preview'), findsOneWidget);
    final source = tester.widget<TextField>(find.byType(TextField));
    source.controller!.value = const TextEditingValue(
      text: '= One\n\nSecond\n\nThird',
      selection: TextSelection.collapsed(offset: 10),
    );
    await tester.tap(find.byTooltip('Preview'));
    await tester.pump();

    TextField block() =>
        tester.widget<TextField>(find.byKey(const Key('preview-block-editor')));
    expect(block().controller!.text, 'Second');
    await tester.tap(find.byKey(const Key('preview-block-previous')));
    await tester.pump();
    expect(block().controller!.text, '= One');
    await tester.tap(find.byKey(const Key('preview-block-next')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('preview-block-editor')),
      'Second changed',
    );
    await tester.pump();

    expect(find.text('Edit source'), findsOneWidget);
    await tester.tap(find.text('Edit source'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '= One\n\nSecond changed\n\nThird',
    );
    expect(find.byTooltip('Preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('graph remains available from overflow', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    expect(find.byTooltip('Graph'), findsNothing);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Graph'), findsOneWidget);
  });

  testWidgets('sync status opens details without raw telemetry', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pump();

    final syncButton = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          const {
            'Nextcloud Desktop',
            'Sync not connected',
            'Syncing…',
            'Sync paused',
            'Needs attention',
            'Ready to sync',
            'Up to date',
          }.contains(widget.tooltip),
    );
    expect(syncButton, findsOneWidget);
    await tester.tap(syncButton);
    await tester.pumpAndSettle();

    expect(find.text('Nextcloud sync'), findsOneWidget);
    expect(find.textContaining('Sync('), findsNothing);
    expect(find.textContaining('↑'), findsNothing);
    expect(find.textContaining('↓'), findsNothing);
  });

  testWidgets('journal mode hides Typst system prelude', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Journal').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('#import'), findsNothing);
    expect(find.textContaining('#show:'), findsNothing);
  });

  testWidgets('journal keeps focus while typing consecutive characters', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Journal').last);
    await tester.pumpAndSettle();
    final editor = find.byType(TextField);
    await tester.tap(editor);
    await tester.pump();

    for (final value in const ['a', 'ab', 'abc']) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        ),
      );
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
    }

    expect(tester.widget<TextField>(editor).controller!.text, 'abc');
  });

  testWidgets('editor changes are autosaved', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Journal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Source'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'autosave text');
    await tester.pump();

    expect(find.text('Autosave pending...'), findsOneWidget);
  });

  testWidgets('typing during autosave keeps the newer editor text dirty', (
    tester,
  ) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Journal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Source'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'first draft');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.enterText(find.byType(TextField), 'newer draft');
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'newer draft');
    expect(find.text('Autosave pending...'), findsOneWidget);
    expect(find.text('TyLog •'), findsOneWidget);
  });

  testWidgets('Magic menu exposes the complete command set', (tester) async {
    await tester.pumpWidget(const TyLogApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Journal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    for (final label in const [
      'Note link',
      'Tag',
      'Task',
      'Date',
      'Project',
      'Citation',
      'Attachment',
      'Heading',
      'Bold',
      'Italic',
      'Table',
      'Equation',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.text('Report'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Report'), findsOneWidget);
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

    expect(find.text('Search notes, tasks, and attachments'), findsOneWidget);
    expect(find.byTooltip('Knowledge sections'), findsOneWidget);
  });

  testWidgets('knowledge search fits a phone-width screen', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: _knowledgeScreen()));

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Search notes, tasks, and attachments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('knowledge screen can open directly on Problems', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: _knowledgeScreen(initialView: KnowledgeView.problems)),
    );

    expect(find.text('No vault problems'), findsOneWidget);
    expect(find.text('Search notes, tasks, and attachments'), findsNothing);
  });

  testWidgets('knowledge problems opens sync conflicts', (tester) async {
    const conflict = PkmsProblem(
      code: 'sync-conflict',
      severity: PkmsSeverity.warning,
      subject: 'daily/2026/07/today.typ.remote-conflict-1',
      message: 'Both copies changed.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: _knowledgeScreen(
          initialView: KnowledgeView.problems,
          problems: const [conflict],
        ),
      ),
    );
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
  problems: problems,
  onOpenNote: (_) {},
  onResolveConflict: (_) async {},
  onCleanSyncCaches: () async {},
  onSetTaskStatus: (_, _) async {},
);
