import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog_core/namespace_plan.dart';

void main() {
  testWidgets(
    'import preview lists changes and skipped titles and requires approval',
    (tester) async {
      const plan = NamespacePlan(
        [
          NamespaceChange(fullPath: 'A', newTitle: 'A'),
          NamespaceChange(
            existingId: 'child',
            fullPath: 'A/B',
            newTitle: 'B',
            parentPath: 'A',
          ),
        ],
        ['A//bad'],
      );
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showDialog<bool>(
                context: context,
                builder: (context) => namespaceImportDialog(context, plan),
              ),
              child: const Text('Preview'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Preview'));
      await tester.pump();
      expect(find.textContaining('Create: A'), findsOneWidget);
      expect(find.textContaining('Update: A/B'), findsOneWidget);
      expect(find.textContaining('Skipped: A//bad'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(result, isFalse);
    },
  );
}
