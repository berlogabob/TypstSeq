import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

void main() {
  testWidgets('a Typst comment line is drawn small and faint, text intact', (
    tester,
  ) async {
    final c = TyLogEditingController(
      source: 'text\n\n// tylog:auto-entities\n== Mentions\n',
      onSourceChanged: (_) {},
      onError: (e) => fail('$e'),
      onProtectedTap: (_) {},
      nextTaskId: (_) async => 'x',
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
      ),
    );
    final base = Theme.of(context).textTheme.bodyLarge!;
    final spans = <TextSpan>[];
    c
        .buildTextSpan(context: context, style: base, withComposing: false)
        .visitChildren((span) {
          if (span is TextSpan && (span.text ?? '').isNotEmpty) spans.add(span);
          return true;
        });
    TextSpan spanWith(String text) =>
        spans.firstWhere((span) => span.text!.contains(text));
    final comment = spanWith('tylog:auto-entities');
    expect(
      comment.style!.fontSize,
      lessThan(spanWith('text').style!.fontSize!),
    );
    expect(comment.style!.color, Theme.of(context).colorScheme.outline);
    expect(c.text, contains('// tylog:auto-entities'));
  });
}
