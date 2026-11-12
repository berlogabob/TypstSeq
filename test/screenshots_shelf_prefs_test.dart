import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/work_surface.dart';

const _safari = NoteRef(
  id: 'shot-safari',
  path: 'screenshots/2026/10/safari.typ',
  title: 'Safari shot',
  kind: 'screenshot',
  outgoingLinks: [],
  properties: {'source_app': 'Safari'},
  modifiedMillis: 1000,
);
const _photos = NoteRef(
  id: 'shot-photos',
  path: 'screenshots/2026/10/photos.typ',
  title: 'Photos shot',
  kind: 'screenshot',
  outgoingLinks: [],
  properties: {'source_app': 'Photos'},
  modifiedMillis: 2000,
);

Widget _library({
  Map<String, String> shelfPrefs = const {},
  ValueChanged<Map<String, String>>? onShelfPrefsChanged,
}) => MaterialApp(
  home: Scaffold(
    body: LibraryView(
      initialTab: 2,
      index: VaultIndex(
        notesByPath: {_safari.path: _safari, _photos.path: _photos},
        backlinksByTarget: const {},
      ),
      calendar: const [],
      dayMarks: (daily: <String>{}, refs: <String>{}),
      progressByPath: const {},
      shelfPrefs: shelfPrefs,
      onShelfPrefsChanged: onShelfPrefsChanged,
      onOpenPath: (_) {},
      onOpenDay: (_) {},
      onSetTaskStatus: (_, _) async {},
      onSetReadStatus: (_, _) async {},
      onSetRelevance: (_, _) async {},
      onCreateNote: (_) {},
      onCreateEntity: () {},
      onImportMarkdownArticles: () async {},
      onReadPath: (_) {},
      onDeleteArticle: (_) async {},
    ),
  ),
);

void main() {
  testWidgets('screenshots library: group choice is reported for persistence', (
    tester,
  ) async {
    final saved = <Map<String, String>>[];
    await tester.pumpWidget(_library(onShelfPrefsChanged: saved.add));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('screenshots-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group by source app').last);
    await tester.pumpAndSettle();

    expect(saved, isNotEmpty);
    expect(saved.last['screenshots.group'], 'source');
  });

  testWidgets('screenshots library: sort and group restore from saved prefs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _library(
        shelfPrefs: const {
          'screenshots.sort': 'title',
          'screenshots.group': 'source',
        },
      ),
    );
    await tester.pumpAndSettle();

    // Source grouping restored: one header per app.
    expect(find.text('Safari · 1'), findsOneWidget);
    expect(find.text('Photos · 1'), findsOneWidget);
    expect(
      find.byTooltip('Sort: Title'),
      findsOneWidget,
      reason: 'restored sort shows in the sort control tooltip',
    );
  });
}
