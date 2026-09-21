import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:tylog/rich_editor.dart';

void main() {
  test('P12 model append benchmark stays bounded for a long plain note', () {
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (_) {},
      onError: (error) => fail('editor error: $error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    final samples = <int>[];
    for (var i = 0; i < 1200; i++) {
      final watch = Stopwatch()..start();
      final text = '${controller.text}\nmodel-$i';
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      samples.add(watch.elapsedMicroseconds);
    }
    samples.sort();
    final p95 = samples[(samples.length * 0.95).floor()];
    // ignore: avoid_print
    print(
      'P12 model appends=${samples.length} p50_us=${samples[600]} '
      'p95_us=$p95 max_us=${samples.last}',
    );
    expect(controller.text, contains('model-1199'));
    expect(p95, lessThan(50000));
  });
}

final _source =
    '''#show: tylog.note.with(id: "p12-model", title: "P12 model")
${List<String>.filled(900, 'A long active paragraph keeps the model workload realistic for the frame budget.').join('\n')}
''';
