import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

/// Records the base-file handoff so tests can assert the shared file set is
/// sent once per scan instead of once per note (the 850 MB-per-inspect storm).
class _BaseAwareInspector implements TypstInspector, BaseFilesInspector {
  final baseCalls = <Map<String, Uint8List>>[];
  final perInspectFiles = <Map<String, Uint8List>>[];

  @override
  Future<void> setBaseFiles(Map<String, Uint8List> files) async {
    baseCalls.add(files);
  }

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    perInspectFiles.add(input.files);
    return [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {
          'schema': 1,
          'entity': 'note',
          'id': input.path.split('/').last.replaceFirst('.typ', ''),
          'title': 'T',
          'kind': 'note',
        },
      ),
    ];
  }
}

class _PlainInspector implements TypstInspector {
  final perInspectFiles = <Map<String, Uint8List>>[];

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    perInspectFiles.add(input.files);
    return const [];
  }
}

String _note(String id) =>
    '#show: tylog.note.with(\n'
    '  id: "$id",\n'
    '  title: "T",\n'
    '  kind: "note",\n'
    ')\n';

/// Every format the vault actually contains. webp was the gap that mattered:
/// 598 webp files on the real vault, 38.6 MB of the 50.4 MB pulled through SAF
/// on any changed note, because they fell through to a real read.
/// Only formats Typst can actually decode — verified against the 0.15 CLI,
/// which accepts webp and rejects bmp/avif with "unknown image format". A note
/// referencing a format Typst cannot read fails to compile whatever bytes we
/// ship, so a placeholder would buy nothing there.
const _placeholderFormats = ['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp'];

void main() {
  late Directory root;
  late LocalVaultStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog-base-files');
    storage = LocalVaultStorage(root);
    await storage.writeText('notes/a.typ', _note('a'));
    await storage.writeText('notes/b.typ', _note('b'));
    await storage.writeBytes('assets/pic.png', [9, 9, 9]);
    await storage.writeBytes('assets/data.csv', [104, 105]); // "hi"
  });

  tearDown(() => root.delete(recursive: true));

  test('base-aware inspector gets the file set once, empty maps per note',
      () async {
    final inspector = _BaseAwareInspector();
    final index = await scanVaultStorage(storage, inspector: inspector);

    expect(index.notes, hasLength(2));
    expect(inspector.baseCalls, hasLength(1),
        reason: 'shared files must cross the boundary once per scan');
    expect(inspector.baseCalls.single.keys, contains('assets/pic.png'));
    // Image assets travel as tiny same-format placeholders: a metadata query
    // needs `#image()` to resolve, not the real pixels — shipping a vault's
    // 850 MB of images to every scan OOM-killed the app on device.
    final pic = inspector.baseCalls.single['assets/pic.png']!;
    expect(pic.length, lessThan(200));
    expect(pic, isNot(orderedEquals([9, 9, 9])),
        reason: 'real image bytes must not be read or shipped');
    // Non-image files keep their real bytes (a note may read() them).
    expect(
      inspector.baseCalls.single['assets/data.csv'],
      orderedEquals([104, 105]),
    );
    expect(inspector.perInspectFiles, hasLength(2));
    for (final files in inspector.perInspectFiles) {
      expect(files, isEmpty,
          reason: 'per-note inputs must not re-ship the vault');
    }
  });

  // Repo rule: writers must compile, not parse — a placeholder with broken
  // CRCs would silently degrade every image-bearing note to the fallback
  // parser (typst validates image bytes). Compile all four formats for real.
  test('image placeholders compile under the typst CLI', () async {
    final typst = await Process.run('typst', ['--version']).then(
      (r) => r.exitCode == 0,
      onError: (_) => false,
    );
    if (!typst) {
      // ignore: avoid_print
      print('typst CLI not found; placeholder compile check skipped');
      return;
    }
    for (final ext in _placeholderFormats) {
      await File('${root.path}/p.$ext').writeAsBytes(
        imagePlaceholder('x.$ext')!,
      );
    }
    await File('${root.path}/t.typ').writeAsString([
      for (final ext in _placeholderFormats)
        if (ext != 'jpeg') '#image("p.$ext")',
    ].join('\n'));
    final result = await Process.run('typst', [
      'compile',
      '--root',
      root.path,
      '${root.path}/t.typ',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('plain inspector still receives the full map per note', () async {
    final inspector = _PlainInspector();
    await scanVaultStorage(storage, inspector: inspector);

    expect(inspector.perInspectFiles, hasLength(2));
    for (final files in inspector.perInspectFiles) {
      expect(files.keys, contains('assets/pic.png'));
    }
  });
}
