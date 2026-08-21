import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tylog_core/scanner.dart';

/// A note whose `#image("/assets/…")` target has not synced yet cannot compile,
/// so it degrades to the source-based fallback parser and loses its metadata.
/// That is why the mid-sync A24 showed 432 of 4,225 notes on the fallback (10%)
/// while the fully-synced P30 showed 18 (0.35%) — the number was measuring how
/// much of the vault had arrived, not anything about the notes.
void main() {
  const png = '/assets/logseq/0001_1648739775137_0.png';

  group('missingImagePlaceholders', () {
    test('supplies a placeholder for a referenced-but-absent image', () {
      final files = missingImagePlaceholders(
        source: '#image("$png")',
        notePath: 'notes/a.typ',
        available: const {},
      );
      expect(files.keys, ['assets/logseq/0001_1648739775137_0.png']);
      expect(files.values.single, isNotEmpty);
    });

    test('leaves present files alone so real bytes are never shadowed', () {
      final files = missingImagePlaceholders(
        source: '#image("$png")',
        notePath: 'notes/a.typ',
        available: const {'assets/logseq/0001_1648739775137_0.png'},
      );
      expect(files, isEmpty);
    });

    test('resolves a relative reference against the note directory', () {
      final files = missingImagePlaceholders(
        source: '#figure(image("pics/x.jpg"))',
        notePath: 'notes/sub/a.typ',
        available: const {},
      );
      expect(files.keys, ['notes/sub/pics/x.jpg']);
    });

    test('walks .. and drops a reference that escapes the vault root', () {
      expect(
        missingImagePlaceholders(
          source: '#image("../shared/y.png")',
          notePath: 'notes/sub/a.typ',
          available: const {},
        ).keys,
        ['notes/shared/y.png'],
      );
      expect(
        missingImagePlaceholders(
          source: '#image("../../outside.png")',
          notePath: 'notes/a.typ',
          available: const {},
        ),
        isEmpty,
      );
    });

    test('ignores non-image references — data files need their real bytes', () {
      expect(
        missingImagePlaceholders(
          source: '#let d = csv("/data/t.csv")\n#image("/a/b.dat")',
          notePath: 'notes/a.typ',
          available: const {},
        ),
        isEmpty,
      );
    });

    test('emits one entry for a path referenced repeatedly', () {
      final files = missingImagePlaceholders(
        source: '#image("$png")\n#image("$png")',
        notePath: 'notes/a.typ',
        available: const {},
      );
      expect(files, hasLength(1));
    });
  });

  /// The placeholder bytes have to satisfy the real compiler, not just look
  /// like an image: the widely-copied 67-byte 1×1 PNG carries a bad CRC and
  /// Typst rejects it. Parse-level tests cannot see that.
  test('a missing image compiles once the placeholder is supplied', () {
    if (Process.runSync('which', ['typst']).exitCode != 0) {
      markTestSkipped('typst not on PATH');
      return;
    }
    final repoRoot = Directory.current.path.endsWith('packages/tylog_core')
        ? Directory.current.parent.parent.path
        : Directory.current.path;
    final root = Directory('$repoRoot/.dart_tool/tylog_missing_image_test')
      ..createSync(recursive: true);
    addTearDown(() => root.deleteSync(recursive: true));

    final note = File('${root.path}/notes/a.typ')
      ..createSync(recursive: true)
      ..writeAsStringSync('#image("/assets/missing.png")');

    List<int> compile() => Process.runSync('typst', [
      'compile',
      '--root',
      root.path,
      note.path,
      '${root.path}/out.pdf',
    ]).exitCode == 0
        ? const [0]
        : const [1];

    expect(compile(), const [1], reason: 'missing image must fail to compile');

    final placeholders = missingImagePlaceholders(
      source: note.readAsStringSync(),
      notePath: 'notes/a.typ',
      available: const {},
    );
    for (final entry in placeholders.entries) {
      File('${root.path}/${entry.key}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(entry.value);
    }

    expect(compile(), const [0], reason: 'placeholder must satisfy Typst');
  });

  test('every placeholder format Typst is offered actually compiles', () {
    if (Process.runSync('which', ['typst']).exitCode != 0) {
      markTestSkipped('typst not on PATH');
      return;
    }
    final repoRoot = Directory.current.path.endsWith('packages/tylog_core')
        ? Directory.current.parent.parent.path
        : Directory.current.path;
    final root = Directory('$repoRoot/.dart_tool/tylog_placeholder_formats')
      ..createSync(recursive: true);
    addTearDown(() => root.deleteSync(recursive: true));

    for (final name in ['a.png', 'a.jpg', 'a.gif', 'a.svg', 'a.webp']) {
      final bytes = imagePlaceholder(name);
      expect(bytes, isNotNull, reason: '$name should have a placeholder');
      File('${root.path}/$name').writeAsBytesSync(bytes as Uint8List);
      final note = File('${root.path}/n.typ')
        ..writeAsStringSync('#image("/$name")');
      final run = Process.runSync('typst', [
        'compile',
        '--root',
        root.path,
        note.path,
        '${root.path}/out.pdf',
      ]);
      expect(run.exitCode, 0, reason: '$name placeholder: ${run.stderr}');
    }
  });
}
