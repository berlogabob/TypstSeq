import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('CLI init, index, doctor, and export work without Flutter', () async {
    final typst = await Process.run('typst', ['--version']);
    if (typst.exitCode != 0) {
      markTestSkipped('Typst is not installed');
      return;
    }
    final repository = Directory.current.parent.parent.absolute;
    final root = await Directory.systemTemp.createTemp('tylog_cli_');
    addTearDown(() => root.delete(recursive: true));
    final environment = {
      ...Platform.environment,
      'TYLOG_REPOSITORY_ROOT': repository.path,
    };

    final init = await _cli(['init', root.path], environment);
    expect(init.exitCode, 0, reason: init.stderr.toString());
    const notePath = 'notes/CLI.typ';
    await File('${root.path}/$notePath').writeAsString(
      '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "cli", title: "CLI", kind: "note")
= CLI

#tylog.task(id: "cli-task", text: "Run the CLI", status: "done")
''',
    );

    final index = await _cli(['index', root.path, '--force'], environment);
    expect(index.exitCode, 0, reason: index.stderr.toString());
    expect(
      await File('${root.path}/${TylogVaultPaths.index}').exists(),
      isTrue,
    );
    expect(
      await File('${root.path}/${TylogVaultPaths.searchIndex}').exists(),
      isTrue,
    );
    final indexed =
        jsonDecode(
              await File(
                '${root.path}/${TylogVaultPaths.index}',
              ).readAsString(),
            )
            as Map;
    expect(
      (indexed['notes'] as List).cast<Map>().map((note) => note['path']),
      contains(notePath),
    );

    final doctor = await _cli(['doctor', root.path], environment);
    expect(doctor.exitCode, 0, reason: doctor.stdout.toString());

    final pdf = File('${root.path}/outputs/CLI.pdf');
    final export = await _cli([
      'export',
      '${root.path}/$notePath',
      pdf.path,
    ], environment);
    expect(export.exitCode, 0, reason: export.stderr.toString());
    expect(await pdf.length(), greaterThan(100));
  });

  test('CLI inspector reports missing Typst clearly', () async {
    final root = await Directory.systemTemp.createTemp('tylog_no_typst_');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/note.typ').writeAsString('= Note');

    await expectLater(
      CliTypstInspector(
        root,
        executable: '__missing_typst__',
      ).inspect(const TypstDocumentInput(path: 'note.typ', source: '= Note')),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Typst executable not found'),
        ),
      ),
    );
  });
}

Future<ProcessResult> _cli(
  List<String> arguments,
  Map<String, String> environment,
) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'bin/tylog.dart', ...arguments],
  workingDirectory: Directory.current.path,
  environment: environment,
);
