import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/pkms_registry.dart';

void main() {
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

    final report = await validatePkms(dir, index);
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

    final report = await validatePkms(
      dir,
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
