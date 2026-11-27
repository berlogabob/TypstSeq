import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tylog/widgets/ds/ds.dart';

Widget _app(Widget body) => MaterialApp(
  theme: tyLogTheme(Brightness.light),
  home: Scaffold(body: body),
);

void main() {
  group('AppTile', () {
    testWidgets('tappable tile calls onTap and meets the 48dp target', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          AppTile(
            icon: AppIcons.settings,
            title: 'Settings',
            subtitle: 'Appearance, sync',
            onTap: () => taps++,
          ),
        ),
      );
      await tester.tap(find.text('Settings'));
      expect(taps, 1);
      expect(
        tester.getSize(find.byType(ListTile)).height,
        greaterThanOrEqualTo(kMinTapTarget),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).size, kIcon);
    });

    testWidgets('disabled tile ignores taps; info row has no handler', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              AppTile(
                icon: AppIcons.sync,
                title: 'Sync now',
                enabled: false,
                onTap: () => taps++,
              ),
              const AppTile(icon: AppIcons.folder, title: 'Local folder'),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Sync now'), warnIfMissed: false);
      await tester.tap(find.text('Local folder'), warnIfMissed: false);
      expect(taps, 0);
      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect(tiles[0].enabled, isFalse);
      expect(tiles[1].onTap, isNull);
    });

    testWidgets('selected state reaches the ListTile', (tester) async {
      await tester.pumpWidget(
        _app(
          const AppTile(icon: AppIcons.folder, title: 'Vault', selected: true),
        ),
      );
      expect(tester.widget<ListTile>(find.byType(ListTile)).selected, isTrue);
    });

    testWidgets('single-line subtitle stays on one line', (tester) async {
      await tester.pumpWidget(
        _app(
          AppTile(
            icon: AppIcons.folder,
            title: 'Local folder',
            subtitle: 'very/long/path/' * 20,
            singleLineSubtitle: true,
          ),
        ),
      );
      final subtitle = tester.widget<Text>(
        find.textContaining('very/long/path/'),
      );
      expect(subtitle.maxLines, 1);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('AppSection shows a heading, tiles and an optional divider', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            AppSection(
              title: 'General',
              divider: false,
              children: [AppTile(icon: AppIcons.settings, title: 'Appearance')],
            ),
            AppSection(
              title: 'About',
              children: [AppTile(icon: AppIcons.cloud, title: 'Version')],
            ),
          ],
        ),
      ),
    );
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('About')),
      matchesSemantics(label: 'About', isHeader: true),
    );
    handle.dispose();
  });

  group('AppSheet', () {
    Future<void> open(WidgetTester tester, WidgetBuilder builder) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppSheet<void>(context, builder: builder),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows one handle, title, subtitle, trailing and children', (
      tester,
    ) async {
      var skipped = 0;
      await open(
        tester,
        (context) => AppSheet(
          title: 'From whom?',
          subtitle: 'Shared text',
          trailing: TextButton(
            onPressed: () => skipped++,
            child: const Text('Skip'),
          ),
          children: const [ListTile(title: Text('Ada'))],
        ),
      );
      expect(find.text('From whom?'), findsOneWidget);
      expect(find.text('Shared text'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      expect(skipped, 1);
      // showAppSheet turns the Material drag handle off: AppSheet draws its own.
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.showDragHandle, isFalse);
      final title = tester.widget<Text>(find.text('From whom?'));
      expect(
        title.style,
        Theme.of(tester.element(find.text('Ada'))).textTheme.titleLarge,
      );
    });

    testWidgets('long content scrolls instead of overflowing', (tester) async {
      await open(
        tester,
        (context) => AppSheet(
          title: 'Many',
          children: [
            for (var i = 0; i < 60; i++) ListTile(title: Text('Row $i')),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Row 0'), findsOneWidget);
      expect(find.text('Row 59').hitTestable(), findsNothing);
    });

    testWidgets('body variant bounds a list that scrolls itself', (
      tester,
    ) async {
      await open(
        tester,
        (context) => AppSheet.body(
          title: 'Pick',
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < 60; i++) ListTile(title: Text('Item $i')),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Pick'), findsOneWidget);
      expect(find.text('Item 0'), findsOneWidget);
    });
  });

  group('showConfirmDialog', () {
    Future<bool?> ask(
      WidgetTester tester, {
      required String tap,
      bool destructive = false,
    }) async {
      bool? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showConfirmDialog(
                context,
                title: 'Delete calendar?',
                message: 'Remove Work from TyLog?',
                confirmLabel: 'Delete',
                confirmKey: const ValueKey('confirm'),
                destructive: destructive,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (destructive) {
        final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('confirm')),
        );
        final scheme = tyLogColorScheme(Brightness.light);
        expect(button.style?.backgroundColor?.resolve({}), scheme.error);
        expect(button.style?.foregroundColor?.resolve({}), scheme.onError);
      }
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('confirm returns true', (tester) async {
      expect(await ask(tester, tap: 'Delete'), isTrue);
    });

    testWidgets('cancel returns false', (tester) async {
      expect(await ask(tester, tap: 'Cancel'), isFalse);
    });

    testWidgets('destructive confirm is error-coloured', (tester) async {
      expect(await ask(tester, tap: 'Delete', destructive: true), isTrue);
    });
  });

  testWidgets('showSnack shows a floating message with action and duration', (
    tester,
  ) async {
    var undone = 0;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSnack(
              context,
              'Moved',
              duration: const Duration(seconds: 10),
              action: SnackBarAction(label: 'Undo', onPressed: () => undone++),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Moved'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 10),
    );
    await tester.tap(find.text('Undo'));
    expect(undone, 1);
  });

  group('LibraryToolbar', () {
    Future<void> pump(
      WidgetTester tester, {
      required Size size,
      List<Widget> trailing = const [],
      List<Widget> chips = const [],
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          LibraryToolbar(
            controller: controller,
            hintText: 'Search notes',
            onChanged: (_) {},
            trailing: trailing,
            chips: chips,
          ),
        ),
      );
    }

    Padding outer(WidgetTester tester) => tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(LibraryToolbar),
            matching: find.byType(Padding),
          )
          .first,
    );

    testWidgets('portrait keeps 8dp gaps and full chip targets', (
      tester,
    ) async {
      var picked = false;
      await pump(
        tester,
        size: const Size(400, 800),
        trailing: [
          IconButton(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onPressed: () {},
          ),
        ],
        chips: [
          LibraryFilterChip(
            label: 'Person',
            icon: AppIcons.folder,
            selected: false,
            onSelected: (value) => picked = value,
          ),
        ],
      );
      expect(
        outer(tester).padding,
        const EdgeInsets.symmetric(horizontal: kSpace16, vertical: kSpace8),
      );
      expect(find.byTooltip('Sort'), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
      expect(chip.materialTapTargetSize, isNull);
      expect(
        tester.getSize(find.byType(ChoiceChip)).height,
        greaterThanOrEqualTo(kMinTapTarget),
      );
      await tester.tap(find.text('Person'));
      expect(picked, isTrue);
    });

    testWidgets('phone landscape drops vertical gaps and shrinks chips', (
      tester,
    ) async {
      await pump(
        tester,
        size: const Size(800, 400),
        chips: [
          LibraryFilterChip(label: 'All', selected: true, onSelected: (_) {}),
        ],
      );
      expect(
        outer(tester).padding,
        const EdgeInsets.symmetric(horizontal: kSpace16),
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byType(ChoiceChip))
            .materialTapTargetSize,
        MaterialTapTargetSize.shrinkWrap,
      );
    });

    testWidgets('many chips scroll sideways instead of overflowing', (
      tester,
    ) async {
      await pump(
        tester,
        size: const Size(320, 640),
        chips: [
          for (var i = 0; i < 12; i++)
            LibraryFilterChip(
              label: 'Kind $i',
              count: i,
              selected: i == 0,
              onSelected: (_) {},
            ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Kind 0 · 0'), findsOneWidget);
      expect(find.text('Kind 11 · 11').hitTestable(), findsNothing);
    });

    testWidgets('no chip row is built without chips', (tester) async {
      await pump(tester, size: const Size(400, 800));
      expect(find.byType(SingleChildScrollView), findsNothing);
    });
  });

  testWidgets('AppEmptyState.error shows the reason and a retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      _app(
        AppEmptyState.error(
          title: 'Could not read jobs',
          hint: 'Storage is unavailable',
          primaryAction: FilledButton(
            onPressed: () => retries++,
            child: const Text('Retry'),
          ),
        ),
      ),
    );
    expect(find.text('Storage is unavailable'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(AppIcons.warning));
    expect(icon.color, tyLogColorScheme(Brightness.light).error);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Could not read jobs')),
      matchesSemantics(label: 'Could not read jobs', isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('AppEmptyState.error keeps raw details behind a button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AppEmptyState.error(
          title: 'Could not load sync status',
          hint: 'Check the connection, then retry.',
          details: 'SocketException: Connection refused (errno 111)',
        ),
      ),
    );
    expect(find.textContaining('SocketException'), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(
        SelectableText,
        'SocketException: Connection refused (errno 111)',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('AppSheet rows line up with the sheet title', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<void>(
              context,
              builder: (_) => const AppSheet(
                title: 'Which text?',
                children: [ListTile(title: Text('Original'))],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Original')).dx,
      tester.getTopLeft(find.text('Which text?')).dx,
    );
  });

  testWidgets('AppEmptyState hides hint and actions while loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        AppEmptyState(
          icon: AppIcons.daily,
          title: 'Indexing…',
          hint: 'Write in Today.',
          loading: true,
          primaryAction: FilledButton(
            onPressed: () {},
            child: const Text('New'),
          ),
        ),
      ),
    );
    expect(find.byType(LoadingIndicator), findsOneWidget);
    expect(find.text('Write in Today.'), findsNothing);
    expect(find.text('New'), findsNothing);
    // Same height as the icon, so the title stays put when loading ends.
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.byType(LoadingIndicator),
                  matching: find.byType(SizedBox),
                )
                .first,
          )
          .height,
      greaterThanOrEqualTo(kIconLarge),
    );
  });

  testWidgets('AppEmptyState icon is the large focal size', (tester) async {
    await tester.pumpWidget(
      _app(
        const AppEmptyState(
          icon: AppIcons.daily,
          title: 'No notes yet',
          hint: 'Write in Today.',
        ),
      ),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).size, kIconLarge);
  });

  group('AppSearchField', () {
    testWidgets('reports text, clears it and lines up inside a sheet', (
      tester,
    ) async {
      final changes = <String>[];
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (_) => AppSheet(
                  title: 'Choose note',
                  children: [
                    AppSearchField(
                      fieldKey: const Key('search'),
                      hintText: 'Filter notes',
                      onChanged: changes.add,
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const Key('search'))).dx,
        tester.getTopLeft(find.text('Choose note')).dx,
      );
      expect(find.byTooltip('Clear search'), findsNothing);
      await tester.enterText(find.byKey(const Key('search')), 'ana');
      await tester.pump();
      expect(changes.last, 'ana');
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(changes.last, '');
      expect(find.text('ana'), findsNothing);
      expect(find.byTooltip('Clear search'), findsNothing);
    });

    testWidgets('uses the caller controller when given', (tester) async {
      final controller = TextEditingController(text: 'travel');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          AppSearchField(
            controller: controller,
            hintText: 'Search',
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('travel'), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsOneWidget);
    });
  });
}
