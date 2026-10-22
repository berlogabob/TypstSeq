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
}
