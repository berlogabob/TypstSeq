import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';

void main() {
  test(
    'archive read releases cached content and keeps the next entry readable',
    () async {
      final root = await Directory('.dart_tool').createTemp('archive-release-');
      addTearDown(() => root.delete(recursive: true));
      final bytes = List<int>.filled(4096, 65);
      final zip = File('${root.path}/fixture.zip');
      await zip.writeAsBytes(
        ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile('a.txt', bytes.length, bytes))
            ..addFile(ArchiveFile('b.txt', bytes.length, bytes)),
        ),
      );
      final input = InputFileStream(zip.path);
      final entries = ZipDecoder().decodeStream(input);
      final snapshot = RemoteArchiveSnapshot(
        source: zip,
        input: input,
        files: {for (final file in entries) file.name: file},
      );
      addTearDown(snapshot.close);
      final first = entries.first;
      expect(first.content, bytes);
      expect(first.isCompressed, isFalse, reason: 'content is cached');
      expect(snapshot.read('a.txt'), bytes);
      expect(
        first.isCompressed,
        isTrue,
        reason: 'only compressed raw content remains',
      );
      expect(snapshot.read('b.txt'), bytes);
      expect(entries.last.isCompressed, isTrue);
    },
  );
}
