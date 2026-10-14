import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync/nfc.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

void main() {
  test('matches NFC for representative path strings', () {
    const strings = [
      'notes/ascii-123.typ',
      'notes/café-Über-Æ.typ',
      'notes/c\u0327a\u0303o.typ',
      'notes/ção.typ',
      'notes/й.typ',
      'notes/и\u0306.typ',
      'notes/한글.typ',
      'notes/\u1100\u1161.typ',
      'notes/😀.typ',
      'notes/\uD834\uDD1E.typ',
      '',
    ];
    for (final s in strings) {
      expect(nfcPath(s), unorm.nfc(s), reason: s);
      expect(nfcPath(s), unorm.nfc(s), reason: 'cached: $s');
    }
  });

  test('returns stable strings unchanged', () {
    for (final s in ['notes/ação.typ', 'notes/й.typ', 'notes/한글.typ', '']) {
      expect(identical(nfcPath(s), s), isTrue);
    }
  });

  test('matches NFC for randomized mixed strings', () {
    final random = Random(42);
    const alphabet = [
      'a',
      'c',
      'o',
      '/',
      '.',
      'é',
      'ç',
      'ã',
      'Æ',
      'ʃ',
      'и',
      'й',
      '\u0482',
      '\u048A',
      '\u04FF',
      '\u0300',
      '\u0301',
      '\u0306',
      '\u0327',
      '\u0340',
      '\u0483',
      '\u0489',
      '\u0308',
      '한',
      '\uAC00',
      '\uD7A3',
      '\u1100',
      '\u1161',
      '\u11A8',
      'Ω',
      'α',
      'א',
      '中',
      '😀',
      '\uD834\uDD1E',
    ];
    for (var i = 0; i < 5000; i++) {
      final s = List.generate(
        random.nextInt(32),
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
      expect(nfcPath(s), unorm.nfc(s), reason: 'sample $i: $s');
    }
  });

  test('normalizes 20000 ASCII and Cyrillic paths within 200 ms', () {
    final paths = List.generate(
      20000,
      (i) => i.isEven ? 'notes/project-$i.typ' : 'заметки/мой-проект-$i.typ',
    );
    for (final path in paths.take(1000)) {
      nfcPath(path);
    }
    var unchanged = 0;
    final stopwatch = Stopwatch()..start();
    for (final path in paths) {
      if (identical(nfcPath(path), path)) unchanged++;
    }
    stopwatch.stop();
    expect(unchanged, paths.length);
    expect(stopwatch.elapsedMilliseconds, lessThan(200));
  });
}
