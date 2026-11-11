import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/reading_log.dart';

void main() {
  test('finished', () {
    expect(readingLogLine('A'), '- Read: A');
  });

  test('stars', () {
    expect(readingLogLine('A', rating: '3'), '- Read: A — ★★★☆☆');
  });

  test('trashed without url', () {
    expect(readingLogLine('A', rating: 'shit'), '- Read: A — 🗑');
  });

  test('trashed with url', () {
    expect(
      readingLogLine('A', rating: 'shit', url: ' https://x.io/a?b=1 '),
      '- Read: A — 🗑 #link("https://x.io/a?b=1")',
    );
  });

  test('quote escaped', () {
    expect(
      readingLogLine('A', rating: 'shit', url: 'https://x.io/"q'),
      r'- Read: A — 🗑 #link("https://x.io/\"q")',
    );
  });

  group('applyReadingLog', () {
    test('appends under a new Reading heading, keeping existing text', () {
      expect(
        applyReadingLog('= Day\nnote\n', 'A', '- Read: A', rated: false),
        '= Day\nnote\n\n== Reading\n- Read: A\n',
      );
    });

    test('is applied to the current text, so a concurrent edit survives', () {
      const edited = '= Day\nwritten meanwhile\n\n== Reading\n- Read: B\n';
      final out = applyReadingLog(edited, 'A', '- Read: A', rated: false);
      expect(out, contains('written meanwhile'));
      expect(out, endsWith('- Read: B\n- Read: A\n'));
    });

    test('rating upgrades the finished line instead of duplicating', () {
      expect(
        applyReadingLog(
          '== Reading\n- Read: A\n',
          'A',
          '- Read: A — ★★★☆☆',
          rated: true,
        ),
        '== Reading\n- Read: A — ★★★☆☆\n',
      );
    });

    test('already logged today is left unchanged', () {
      const source = '== Reading\n- Read: A — ★★★☆☆\n';
      expect(applyReadingLog(source, 'A', '- Read: A', rated: false), source);
    });
  });
}
