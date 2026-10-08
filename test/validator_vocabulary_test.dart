import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/models.dart';
import 'package:tylog_core/validation.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  test('validator reports invalid task status as error', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_validate_');
    addTearDown(() => dir.delete(recursive: true));

    final index = VaultIndex(
      notesByPath: const {},
      backlinksByTarget: const {},
      tasks: [
        TaskRef(
          id: 'test-task',
          notePath: 'notes/test.typ',
          text: 'Test task',
          status: 'invalid-status',
          priority: 'normal',
        ),
      ],
    );

    final report = await validatePkmsStorage(LocalVaultStorage(dir), index);
    expect(report.count('invalid-task-status'), 1);
    expect(report.problems[0].code, 'invalid-task-status');
    expect(report.problems[0].severity, PkmsSeverity.error);
  });

  test('validator reports invalid task priority as error', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_validate_');
    addTearDown(() => dir.delete(recursive: true));

    final index = VaultIndex(
      notesByPath: const {},
      backlinksByTarget: const {},
      tasks: [
        TaskRef(
          id: 'test-task',
          notePath: 'notes/test.typ',
          text: 'Test task',
          status: 'todo',
          priority: 'invalid-priority',
        ),
      ],
    );

    final report = await validatePkmsStorage(LocalVaultStorage(dir), index);
    expect(report.count('invalid-task-priority'), 1);
    expect(report.problems[0].code, 'invalid-task-priority');
    expect(report.problems[0].severity, PkmsSeverity.error);
  });

  test('validator reports unknown extension kind as warning', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_validate_');
    addTearDown(() => dir.delete(recursive: true));

    final index = VaultIndex(
      notesByPath: {
        'notes/test.typ': NoteRef(
          id: 'test-note',
          path: 'notes/test.typ',
          title: 'Test Note',
          outgoingLinks: [],
          kind: 'unknown-extension-kind',
        ),
      },
      backlinksByTarget: const {},
      tasks: const [],
    );

    final report = await validatePkmsStorage(LocalVaultStorage(dir), index);
    expect(report.count('extension-note-kind'), 1);
    expect(report.problems[0].code, 'extension-note-kind');
    expect(report.problems[0].severity, PkmsSeverity.warning);
  });
}
