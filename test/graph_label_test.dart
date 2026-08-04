import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/graph_label.dart';

void main() {
  group('prettyGraphLabel', () {
    test('humanizes slugs', () {
      expect(
        prettyGraphLabel('large-language-models'),
        'Large language models',
      );
      expect(prettyGraphLabel('ai'), 'Ai');
      expect(prettyGraphLabel(''), '');
    });

    test('cyrillic slugs get spaces and keep their letters', () {
      expect(
        prettyGraphLabel('машинное-обучение'),
        'Машинное обучение',
      );
    });
  });

  group('graphLabelSpec fit ladder', () {
    test('large cell: two name lines plus count, size capped at 22', () {
      final spec = graphLabelSpec(const Size(400, 300))!;
      expect(spec.fontSize, 22);
      expect(spec.showCount, isTrue);
      expect(spec.maxLines, 2);
    });

    test('font size scales with area and floors at 10', () {
      final mid = graphLabelSpec(const Size(160, 120))!;
      expect(mid.fontSize, closeTo(0.09 * 138.6, 0.5));
      final small = graphLabelSpec(const Size(60, 40))!;
      expect(small.fontSize, 10);
    });

    test('short cell drops the count line before dropping the name', () {
      // Big area drives the font up; 45px of height then only fits one
      // name line once the count line is sacrificed.
      final spec = graphLabelSpec(const Size(800, 45))!;
      expect(spec.showCount, isFalse);
      expect(spec.maxLines, 1);
    });

    test('tiny cell gets no label at all', () {
      expect(graphLabelSpec(const Size(38, 60)), isNull);
      expect(graphLabelSpec(const Size(60, 24)), isNull);
    });
  });
}
