import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/pkms_registry.dart';
import 'package:tylog/search_index.dart';

void main() {
  test('search index persists, ranks titles, and filters tags', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_search_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/pages').create();
    await File('${dir.path}/pages/A.typ').writeAsString('alpha body knowledge');
    await File('${dir.path}/pages/B.typ').writeAsString('alpha body');
    final index = VaultIndex(
      notesByPath: {
        'pages/A.typ': const NoteRef(
          id: 'a',
          path: 'pages/A.typ',
          title: 'Alpha',
          tags: ['pkms'],
          outgoingLinks: [],
          fingerprint: 'a',
        ),
        'pages/B.typ': const NoteRef(
          id: 'b',
          path: 'pages/B.typ',
          title: 'Other',
          tags: ['other'],
          outgoingLinks: [],
          fingerprint: 'b',
        ),
      },
      backlinksByTarget: const {},
    );
    final search = await PkmsSearchIndex.build(
      dir,
      index,
      PkmsFileRegistry(
        files: {
          'manual': const PkmsFileEntry(
            id: 'manual',
            path: 'assets/manual.pdf',
            title: 'Reference Manual',
            kind: 'pdf',
            status: 'reference',
            tags: ['pkms'],
          ),
        },
      ),
    );
    final file = File('${dir.path}/search.json.gz');
    await search.save(file);
    final loaded = await PkmsSearchIndex.load(file);

    expect(loaded.search('alpha').first.id, 'a');
    expect(loaded.search('body', tag: 'pkms').single.id, 'a');
    expect(loaded.search('manual', fileKind: 'pdf').single.id, 'manual');
    expect(await file.length(), greaterThan(0));
  });
}
