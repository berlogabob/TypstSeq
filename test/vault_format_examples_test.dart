import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vault format Typst examples compile with the shipped TyLog package', () {
    final document = File('docs/vault-format.md').readAsStringSync();
    final examples = RegExp(
      r'```typst\n([\s\S]*?)\n```',
    ).allMatches(document).map((match) => match.group(1)!).toList();
    expect(
      examples,
      isNotEmpty,
      reason: 'Add at least one compile-checked example',
    );

    final directory = Directory('.dart_tool/vault_format_examples')
      ..createSync(recursive: true);
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    for (var index = 0; index < examples.length; index++) {
      final source = File('${directory.path}/example-$index.typ')
        ..writeAsStringSync(
          '#import "/typst/tylog/lib.typ" as tylog\n${examples[index]}\n',
        );
      final result = Process.runSync('typst', [
        'compile',
        '--root',
        Directory.current.path,
        source.path,
        '${source.path}.pdf',
      ]);
      expect(
        result.exitCode,
        0,
        reason:
            'Example $index did not compile:\n${result.stderr}\n${examples[index]}',
      );
    }
  });
}
