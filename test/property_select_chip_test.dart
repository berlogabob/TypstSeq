import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/property_select_chip.dart';

void main() {
  Widget harness({
    required String? value,
    required ValueChanged<String> onChanged,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: PropertySelectChip(
            value: value,
            options: articleStatusOptions,
            labels: articleStatusLabels,
            onChanged: onChanged,
          ),
        ),
      );

  testWidgets('hit area meets the 48dp minimum tap target even though the '
      'painted pill stays small', (tester) async {
    await tester.pumpWidget(harness(value: 'unread', onChanged: (_) {}));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(PropertySelectChip));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  testWidgets('tapping opens the popup menu and selecting an option reports '
      'its value', (tester) async {
    String? picked;
    await tester.pumpWidget(
      harness(
        value: 'unread',
        onChanged: (value) => picked = value,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PropertySelectChip));
    await tester.pumpAndSettle();

    expect(find.text(articleStatusLabels['extracted']!), findsOneWidget);
    await tester.tap(find.text(articleStatusLabels['extracted']!));
    await tester.pumpAndSettle();

    expect(picked, 'extracted');
  });
}
