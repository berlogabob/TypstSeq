import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/snack.dart';

void main() {
  Widget host(String? warning) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          showLoadWarning(context, warning);
          return const SizedBox();
        },
      ),
    ),
  );

  testWidgets('shows the registry load warning once as a snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      host('Could not read vaults.json; saved as .corrupt'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Could not read vaults.json'), findsOneWidget);
  });

  testWidgets('shows nothing without a warning', (tester) async {
    await tester.pumpWidget(host(null));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsNothing);
  });
}
