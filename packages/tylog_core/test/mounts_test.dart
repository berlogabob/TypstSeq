import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/mounts.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

void main() {
  test('registry preserves unknown properties and rejects invalid ids', () {
    final json =
        '[{"id":"course-1","name":"Course","source":{"kind":"github","repo":"a/b","ref":"main","future":2},"push":false,"extra":{"x":1}}]';
    expect(jsonDecode(encodeMounts(parseMounts(json))), jsonDecode(json));
    expect(
      () => Mount(
        id: '../bad',
        name: 'Bad',
        source: MountSource(kind: 'folder'),
        push: false,
      ),
      throwsFormatException,
    );
    expect(
      () => parseMounts(json.replaceFirst('course-1', 'Bad')),
      throwsFormatException,
    );
  });

  test('composite routes storage and scanner links across mounts', () async {
    final root = await Directory.systemTemp.createTemp('mounts-test');
    addTearDown(() => root.delete(recursive: true));
    final main = LocalVaultStorage(Directory('${root.path}/main'));
    final source = LocalVaultStorage(Directory('${root.path}/source'));
    await main.writeText(
      'notes/main.typ',
      '#show: tylog.note.with(id: "main", title: "Main")\n#tylog.ref-note("target")[link]\n',
    );
    await source.writeText(
      'notes/x.typ',
      '#show: tylog.note.with(id: "target", title: "Target")\n',
    );
    final storage = CompositeVaultStorage(main, {
      'course': ReadOnlyVaultStorage(source),
    });
    expect(storage.syncIdentity, main.syncIdentity);
    expect(
      await storage.readText('ext/course/notes/x.typ'),
      contains('target'),
    );
    expect(await storage.exists('ext/course/notes/x.typ'), isTrue);
    expect(
      (await storage.stat('ext/course/notes/x.typ'))?.path,
      'ext/course/notes/x.typ',
    );
    expect(
      await storage.hash('ext/course/notes/x.typ'),
      await source.hash('notes/x.typ'),
    );
    expect((await storage.list()).map((e) => e.path), contains('ext'));
    expect(
      (await storage.list(path: 'ext')).map((e) => e.path),
      contains('ext/course'),
    );
    expect(
      (await storage.list(path: 'ext/course/notes')).map((e) => e.path),
      contains('ext/course/notes/x.typ'),
    );
    expect(
      (await storage.list(recursive: true)).map((e) => e.path),
      contains('ext/course/notes/x.typ'),
    );
    await expectLater(
      storage.writeText('ext/course/notes/x.typ', 'bad'),
      throwsUnsupportedError,
    );
    await expectLater(
      storage.delete('ext/course/notes/x.typ'),
      throwsUnsupportedError,
    );
    await expectLater(
      storage.writeText('ext/removed/note.typ', 'bad'),
      throwsUnsupportedError,
    );
    await expectLater(
      storage.createDirectory('ext/removed'),
      throwsUnsupportedError,
    );
    expect(await main.exists('ext'), isFalse);
    expect(await source.readText('notes/x.typ'), contains('target'));
    final index = await scanVaultStorage(storage);
    expect(index.notesByPath.keys, contains('ext/course/notes/x.typ'));
    expect(
      index.backlinksByTarget['ext/course/notes/x.typ'],
      contains('notes/main.typ'),
    );
  });
}
