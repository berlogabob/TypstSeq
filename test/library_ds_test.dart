import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/ds/app_empty_state.dart';
import 'package:tylog/widgets/ds/library_toolbar.dart';

void main() {
  testWidgets('toolbar typing filters and clear restores results', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    const titles = ['Alpha', 'Beta'];
    var query = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                LibraryToolbar(
                  controller: controller,
                  hintText: 'Search notes',
                  onChanged: (value) => setState(() => query = value),
                  chips: [
                    LibraryFilterChip(
                      label: 'person',
                      count: 2,
                      selected: false,
                      onSelected: (_) {},
                    ),
                  ],
                ),
                for (final title in titles)
                  if (title.toLowerCase().contains(query.toLowerCase()))
                    Text(title),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Clear search'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'person · 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ALP');
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(query, isEmpty);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsNothing);
  });

  testWidgets('empty state renders content and calls both actions', (
    tester,
  ) async {
    var primary = 0;
    var secondary = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppEmptyState(
            icon: Icons.description_outlined,
            title: 'No notes yet',
            hint: 'Create a note to get started.',
            primaryAction: FilledButton(
              onPressed: () => primary++,
              child: const Text('New note'),
            ),
            secondaryAction: OutlinedButton(
              onPressed: () => secondary++,
              child: const Text('New entity'),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Create a note to get started.'), findsOneWidget);
    await tester.tap(find.text('New note'));
    await tester.tap(find.text('New entity'));
    expect(primary, 1);
    expect(secondary, 1);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppEmptyState(
            icon: Icons.search,
            title: 'Nothing matches',
            hint: 'Try another search.',
          ),
        ),
      ),
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
