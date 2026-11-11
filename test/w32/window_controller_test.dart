import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

void main() {
  group('TyLogWindowController unit boundaries', () {
    final long = '${'a' * 50} ${'b' * 100} ${'c' * 50}';

    test('softBreaks splits the long line at the last space', () {
      expect(TyLogWindowController.softBreaks(long, 0, long.length), [152]);
    });

    test('unitStart and unitEnd on the long line', () {
      expect(TyLogWindowController.unitStart(long, 160), 152);
      expect(TyLogWindowController.unitStart(long, 151), 0);
      expect(TyLogWindowController.unitEnd(long, 0), 152);
      expect(TyLogWindowController.unitEnd(long, 152), long.length);
    });

    test('unitStart and unitEnd around a newline', () {
      final t = 'ab\ncd';
      expect(TyLogWindowController.unitStart(t, 3), 3);
      expect(TyLogWindowController.unitStart(t, 2), 0);
      expect(TyLogWindowController.unitEnd(t, 0), 2);
      expect(TyLogWindowController.unitEnd(t, 3), 5);
    });

    test('offsets clamp to the text', () {
      expect(TyLogWindowController.unitStart(long, -5), 0);
      expect(TyLogWindowController.unitEnd(long, 999), long.length);
    });

    test('empty text', () {
      expect(TyLogWindowController.unitStart('', 0), 0);
      expect(TyLogWindowController.unitEnd('', 0), 0);
      expect(TyLogWindowController.softBreaks('', 0, 0), isEmpty);
    });
  });
}
