import 'dart:convert';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  VaultIndex sample() => VaultIndex(
    notesByPath: {
      'notes/a.typ': const NoteRef(
        id: 'a',
        path: 'notes/a.typ',
        title: 'Alpha',
        outgoingLinks: [],
      ),
    },
    backlinksByTarget: const {},
    tasks: const [],
  );

  test('gzip round trip preserves the index', () {
    final bytes = sample().let(encodeVaultIndexBytes);
    expect(bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b, isTrue,
        reason: 'index cache must be gzip on disk');
    final decoded = decodeVaultIndexBytes(bytes);
    expect(decoded.notes.single.title, 'Alpha');
  });

  test('plain JSON written by older builds still decodes', () {
    final plain = utf8.encode(jsonEncode(sample().toJson()));
    final decoded = decodeVaultIndexBytes(plain);
    expect(decoded.notes.single.path, 'notes/a.typ');
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
