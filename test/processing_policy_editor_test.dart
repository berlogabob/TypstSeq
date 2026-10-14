import 'package:flutter/material.dart';
import 'package:tylog/widgets/app_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/processing_policy_editor.dart';

void main() {
  testWidgets('radio choices emit exclusive flags and preserve the time', (
    tester,
  ) async {
    var fly = false;
    var scheduled = false;
    final changes = <(bool, bool, String)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ProcessingPolicyEditor(
              icon: AppIcons.screenshot,
              title: 'Processing',
              onTheFly: fly,
              scheduled: scheduled,
              time: '03:00',
              onChanged: (nextFly, nextScheduled, time) {
                changes.add((nextFly, nextScheduled, time));
                setState(() {
                  fly = nextFly;
                  scheduled = nextScheduled;
                });
              },
              onProcessNow: () {},
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'off',
    );
    expect(find.text('Every day at 03:00'), findsNothing);
    await tester.tap(find.text('On schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Every day at 03:00'), findsOneWidget);
    await tester.tap(find.text('Right after it is added'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'watch',
    );
    expect(find.text('Every day at 03:00'), findsNothing);
    await tester.tap(find.text('Only when I ask'));
    await tester.pumpAndSettle();
    expect(changes, [
      (false, true, '03:00'),
      (true, false, '03:00'),
      (false, false, '03:00'),
    ]);
  });

  testWidgets(
    'both inputs true shows On schedule and time edits normalize flags',
    (tester) async {
      final changes = <(bool, bool, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessingPolicyEditor(
              icon: AppIcons.screenshot,
              title: 'Processing',
              onTheFly: true,
              scheduled: true,
              time: '03:00',
              onChanged: (fly, scheduled, time) =>
                  changes.add((fly, scheduled, time)),
              onProcessNow: () {},
            ),
          ),
        ),
      );
      final group = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      final schedule = tester.widget<RadioListTile<String>>(
        find.widgetWithText(RadioListTile<String>, 'On schedule'),
      );
      expect(group.groupValue, schedule.value);
      expect(find.text('Every day at 03:00'), findsOneWidget);
      expect(changes, isEmpty);
      await tester.tap(find.text('Every day at 03:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(changes, [(false, true, '03:00')]);
    },
  );

  for (final busy in [false, true]) {
    testWidgets(
      'policy controls disabled when ${busy ? 'busy' : 'read-only'}',
      (tester) async {
        var requests = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProcessingPolicyEditor(
                icon: AppIcons.screenshot,
                title: 'Processing',
                onTheFly: false,
                scheduled: true,
                time: '03:00',
                enabled: busy,
                busy: busy,
                status: 'Processing status',
                onChanged: (_, _, _) => fail('Policy controls are disabled'),
                onProcessNow: () => requests++,
              ),
            ),
          ),
        );
        expect(find.byType(RadioListTile<String>), findsNWidgets(3));
        for (final radio in tester.widgetList<RadioListTile<String>>(
          find.byType(RadioListTile<String>),
        )) {
          expect(radio.enabled, isFalse);
        }
        await tester.tap(find.text('Right after it is added'));
        await tester.tap(find.text('Every day at 03:00'));
        await tester.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsNothing);
        expect(find.text('Processing status'), findsOneWidget);
        final button = tester.widget<TextButton>(find.byType(TextButton));
        if (busy) {
          expect(button.onPressed, isNull);
        } else {
          await tester.tap(find.text('Process now'));
          expect(requests, 1);
        }
      },
    );
  }
}
