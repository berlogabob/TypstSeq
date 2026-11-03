import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('namespace header fields are balanced and compile', () async {
    final root = Directory.current.path.endsWith('packages/tylog_core')
        ? Directory.current.parent.parent.path
        : Directory.current.path;
    final dir = await Directory(
      '$root/.dart_tool/namespace_header_test',
    ).create(recursive: true);
    addTearDown(() => dir.delete(recursive: true));
    for (final header in [
      '#show: tylog.note.with(id: "child", title: "A/B")',
      '#show: tylog.note.with(id: "child", title: "A/B", aliases: (\n "old",\n))',
      '#show: tylog.note.with(id: "child")',
    ]) {
      var output = replaceNoteFields(header, {
        'title': '"B"',
        'aliases': '("old", "A/B",)',
      });
      output = replaceNotePartOf(
        output,
        const NoteMetadataDraft(id: 'child', title: 'B'),
        ['parent'],
      );
      final note = scanNote('child.typ', output);
      expect(note.title, 'B');
      expect(note.aliases, containsAll(['old', 'A/B']));
      expect(note.partOf, ['parent']);
      if (Process.runSync('which', ['typst']).exitCode == 0) {
        final file = File('${dir.path}/test.typ');
        await file.writeAsString(
          '#import "/typst/tylog/lib.typ" as tylog\n$output\n',
        );
        final result = await Process.run('typst', [
          'compile',
          '--root',
          root,
          file.path,
          '${file.path}.pdf',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}\n$output');
      }
    }
  });
}
