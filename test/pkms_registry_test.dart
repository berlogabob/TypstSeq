import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog_core/validation.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  test(
    'validator rejects unknown task vocabulary and retains extension kinds',
    () async {
      final dir = await Directory('.dart_tool').createTemp('vocabulary-');
      addTearDown(() => dir.delete(recursive: true));
      final index = VaultIndex(
        notesByPath: const {
          'notes/a.typ': NoteRef(
            id: 'a',
            path: 'notes/a.typ',
            title: 'A',
            kind: 'custom',
            outgoingLinks: [],
          ),
        },
        backlinksByTarget: const {},
        tasks: const [
          TaskRef(
            id: 't',
            notePath: 'notes/a.typ',
            text: 'Call',
            status: 'unknown',
            priority: 'unknown',
          ),
        ],
      );
      final report = await validatePkmsStorage(LocalVaultStorage(dir), index);
      for (final code in ['invalid-task-status', 'invalid-task-priority']) {
        expect(
          report.problems.singleWhere((p) => p.code == code).severity,
          PkmsSeverity.error,
        );
      }
      expect(
        report.problems
            .singleWhere((p) => p.code == 'extension-note-kind')
            .severity,
        PkmsSeverity.warning,
      );
      expect(index.notes.single.kind, 'custom');
    },
  );

  test('v5 validator reports missing and unsafe Typst attachments', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_validate_');
    addTearDown(() => dir.delete(recursive: true));
    final index = VaultIndex(
      notesByPath: {
        'notes/a.typ': const NoteRef(
          id: '',
          path: 'notes/a.typ',
          title: 'A',
          outgoingLinks: [],
          attachments: [
            AttachmentRef(path: 'assets/missing.pdf'),
            AttachmentRef(path: '../outside.pdf'),
          ],
        ),
      },
      backlinksByTarget: const {},
      tasks: const [TaskRef(id: '', notePath: 'notes/a.typ', text: '')],
    );

    final report = await validatePkmsStorage(LocalVaultStorage(dir), index);
    expect(report.count('missing-attachment'), 1);
    expect(report.count('unsafe-attachment-path'), 1);
    expect(report.count('invalid-note-id'), 1);
    expect(report.count('invalid-task-id'), 1);
    expect(report.count('invalid-task-text'), 1);
  });

  test('v5 validator preserves and warns about custom Typst files', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_custom_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/_system').create(recursive: true);
    const custom = '#let note(..args) = [custom]';
    await File('${dir.path}/_system/tylog.typ').writeAsString(custom);
    const customTheme = '#let document(body) = body';
    await File('${dir.path}/_system/theme.typ').writeAsString(customTheme);

    final report = await validatePkmsStorage(
      LocalVaultStorage(dir),
      const VaultIndex(notesByPath: {}, backlinksByTarget: {}),
    );

    expect(report.count('custom-typst-helper'), 1);
    expect(report.count('custom-typst-theme'), 1);
    expect(await File('${dir.path}/_system/tylog.typ').readAsString(), custom);
    expect(
      await File('${dir.path}/_system/theme.typ').readAsString(),
      customTheme,
    );
  });
}
