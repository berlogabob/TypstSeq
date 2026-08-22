import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

/// When a Typst inspect throws, the scan may fall back to the cached entry
/// rather than downgrading a good note over a hiccup. That is right only while
/// the cache still describes the bytes on disk.
///
/// It used to keep the cached metadata for *changed* bytes too, and then stamp
/// it with the new file's fingerprint and content hash — an entry describing
/// one version of a note while claiming to be another. It then passed every
/// later check, was never re-inspected, and was published to peers as
/// authoritative.
class _FlakyInspector implements TypstInspector {
  _FlakyInspector({required this.title});

  String title;
  bool throwNext = false;

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    if (throwNext) throw StateError('typst hiccup');
    return [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {
          'schema': 1,
          'entity': 'note',
          'id': 'a',
          'title': title,
          'kind': 'note',
          'properties': <String, Object?>{},
        },
      ),
    ];
  }
}

void main() {
  test('a failed inspect never labels old metadata with new bytes', () async {
    final root = await Directory.systemTemp.createTemp('tylog_flaky_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText(
      'notes/a.typ',
      '#import "/_system/tylog.typ" as tylog\n\n= Original\n',
    );

    final inspector = _FlakyInspector(title: 'Original title');
    final first = await scanVaultStorage(storage, inspector: inspector);
    final before = first.notesByPath['notes/a.typ']!;
    expect(before.title, 'Original title');

    // The file changes and the inspect fails on the new bytes.
    await storage.writeText(
      'notes/a.typ',
      '#import "/_system/tylog.typ" as tylog\n\n= Rewritten\n',
    );
    inspector.throwNext = true;
    final second = await scanVaultStorage(
      storage,
      inspector: inspector,
      previous: first,
    );
    final after = second.notesByPath['notes/a.typ']!;

    expect(
      after.metadataSource,
      isNot('typst-query'),
      reason: 'metadata from the old bytes must not claim to be a real query',
    );
    expect(
      after.contentHash,
      isNot(before.contentHash),
      reason: 'the hash follows the new bytes',
    );

    expect(
      after.title,
      isNot(before.title),
      reason: 'metadata describing the old bytes must not survive them',
    );

    // Self-correction: a note that failed once is not retried on unchanged
    // bytes (retrying known-bad notes would burn the inspection budget every
    // scan), but the next real edit must pick it up.
    inspector
      ..throwNext = false
      ..title = 'Rewritten title';
    await storage.writeText(
      'notes/a.typ',
      '#import "/_system/tylog.typ" as tylog\n\n= Rewritten again\n',
    );
    final third = await scanVaultStorage(
      storage,
      inspector: inspector,
      previous: second,
    );
    expect(third.notesByPath['notes/a.typ']!.title, 'Rewritten title');
  });
}
