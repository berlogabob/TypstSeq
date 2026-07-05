import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/search_index.dart';

void main() {
  test('search index persists, ranks titles, and filters tags', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_search_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/notes').create();
    await File('${dir.path}/notes/A.typ').writeAsString('alpha body knowledge');
    await File('${dir.path}/notes/B.typ').writeAsString('alpha body');
    final index = VaultIndex(
      notesByPath: {
        'notes/A.typ': const NoteRef(
          id: 'a',
          path: 'notes/A.typ',
          title: 'Alpha',
          tags: ['pkms'],
          outgoingLinks: [],
          fingerprint: 'a',
        ),
        'notes/B.typ': const NoteRef(
          id: 'b',
          path: 'notes/B.typ',
          title: 'Other',
          tags: ['other'],
          outgoingLinks: [],
          fingerprint: 'b',
        ),
      },
      backlinksByTarget: const {},
    );
    final search = await PkmsSearchIndex.build(dir, index);
    final file = File('${dir.path}/search.json.gz');
    await search.save(file);
    final loaded = await PkmsSearchIndex.load(file);

    expect(loaded.search('alpha').first.id, 'a');
    expect(loaded.search('body', tag: 'pkms').single.id, 'a');
    expect(await file.length(), greaterThan(0));
  });
}
