import 'dart:io';

import 'scanner.dart';

class CliTypstInspector implements TypstInspector {
  const CliTypstInspector(this.root, {this.executable = 'typst'});

  final Directory root;
  final String executable;

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    final ProcessResult result;
    try {
      result = await Process.run(executable, [
        'eval',
        'query(metadata)',
        '--root',
        root.absolute.path,
        '--in',
        input.path,
      ], workingDirectory: root.absolute.path);
    } on ProcessException catch (error) {
      throw StateError(
        'Typst executable not found; install Typst 0.15.0 or newer (${error.message})',
      );
    }
    if (result.exitCode != 0) {
      final message = result.stderr.toString().trim();
      throw StateError(
        message.isEmpty ? 'Typst metadata query failed' : message,
      );
    }
    return decodeTypstMetadataRecords(result.stdout.toString());
  }
}
