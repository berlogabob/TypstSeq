import 'package:crypto/crypto.dart';

class TextChunk {
  const TextChunk({
    required this.id,
    required this.sourceVersionId,
    required this.start,
    required this.end,
    required this.text,
    required this.sha256,
  });

  final String id;
  final String sourceVersionId;
  final int start;
  final int end;
  final String text;
  final String sha256;
}

List<TextChunk> chunkText({
  required String sourceVersionId,
  required String text,
  int targetLength = 800,
  int overlap = 120,
}) {
  if (targetLength <= 0 || overlap < 0 || overlap >= targetLength) {
    throw ArgumentError('overlap must be >= 0 and smaller than targetLength');
  }
  final chunks = <TextChunk>[];
  var start = 0;
  while (start < text.length) {
    final end = (start + targetLength).clamp(0, text.length);
    final value = text.substring(start, end);
    final hash = sha256.convert(value.codeUnits).toString();
    chunks.add(
      TextChunk(
        id: '$sourceVersionId:$start:$end',
        sourceVersionId: sourceVersionId,
        start: start,
        end: end,
        text: value,
        sha256: hash,
      ),
    );
    if (end == text.length) break;
    start = end - overlap;
  }
  return chunks;
}
