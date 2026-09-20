import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/retrieval/chunking.dart';

void main() {
  test('overlap at surrogate boundary still progresses', () {
    final chunks = chunkText(
      sourceVersionId: 'v',
      text: 'a😀b',
      targetLength: 2,
      overlap: 1,
    );
    expect(chunks.map((chunk) => chunk.start), orderedEquals([0, 1, 3]));
    expect(chunks.last.end, 4);
  });

  test(
    'chunking is deterministic and preserves overlapping source offsets',
    () {
      final chunks = chunkText(
        sourceVersionId: 'v1',
        text: 'abcdefghij',
        targetLength: 6,
        overlap: 2,
      );
      expect(chunks.map((chunk) => chunk.id), ['v1:0:6', 'v1:4:10']);
      expect(chunks[0].text, 'abcdef');
      expect(chunks[1].text, 'efghij');
      expect(chunks[0].sha256, hasLength(64));
    },
  );

  test('invalid chunk parameters are rejected', () {
    expect(
      () => chunkText(
        sourceVersionId: 'v',
        text: 'x',
        targetLength: 2,
        overlap: 2,
      ),
      throwsArgumentError,
    );
  });

  test('hashes UTF-8 and never splits surrogate pairs', () {
    final chunks = chunkText(
      sourceVersionId: 'v',
      text: 'a😀b',
      targetLength: 3,
      overlap: 0,
    );
    expect(chunks.map((chunk) => chunk.text), ['a😀', 'b']);
    expect(chunks.every((chunk) => chunk.text.runes.isNotEmpty), isTrue);
  });
}
