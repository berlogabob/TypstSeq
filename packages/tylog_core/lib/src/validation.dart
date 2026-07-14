import 'dart:io';

import 'models.dart';
import 'scanner.dart';
import 'storage.dart';

class PkmsValidationReport {
  const PkmsValidationReport({required this.problems});

  final List<PkmsProblem> problems;

  int count(String code) =>
      problems.where((problem) => problem.code == code).length;

  String summary() =>
      'validation errors=${problems.where((p) => p.severity == PkmsSeverity.error).length} '
      'warnings=${problems.where((p) => p.severity == PkmsSeverity.warning).length}';
}

Future<PkmsValidationReport> validatePkms(Directory root, VaultIndex index) =>
    validatePkmsStorage(LocalVaultStorage(root), index);

Future<PkmsValidationReport> validatePkmsStorage(
  VaultStorage storage,
  VaultIndex index,
) async {
  final problems = <PkmsProblem>[...index.problems];
  if (await storage.exists('_system/tylog.typ') &&
      classifyTylogHelper(await storage.readText('_system/tylog.typ')) ==
          TylogHelperKind.custom) {
    problems.add(
      const PkmsProblem(
        code: 'custom-typst-helper',
        severity: PkmsSeverity.warning,
        subject: '_system/tylog.typ',
        message: 'Custom Typst helper compatibility cannot be verified.',
        fix:
            'Keep the custom helper compatible with note, ref-note, tag, task, date-ref, and attachment.',
      ),
    );
  }

  const standardKinds = {'note', 'daily', 'project', 'article', 'research'};
  const taskStatuses = {'todo', 'doing', 'done', 'cancelled'};
  const priorities = {'low', 'normal', 'high', 'urgent'};

  for (final note in index.notes) {
    if (!standardKinds.contains(note.kind)) {
      problems.add(
        PkmsProblem(
          code: 'extension-note-kind',
          severity: PkmsSeverity.warning,
          subject: note.path,
          message: 'Unknown note kind is preserved: ${note.kind}',
        ),
      );
    }
    if (note.metadataSource != 'typst-query') {
      problems.add(
        PkmsProblem(
          code: 'unverified-note-metadata',
          severity: PkmsSeverity.info,
          subject: note.path,
          message: 'Typst metadata was read by the safe fallback scanner.',
          fix: 'Fix Typst compilation errors to restore query verification.',
        ),
      );
    }
    for (final attachment in note.attachments) {
      if (!isSafeVaultPath(attachment.path)) {
        problems.add(
          PkmsProblem(
            code: 'unsafe-attachment-path',
            severity: PkmsSeverity.error,
            subject: note.path,
            message: 'Attachment path must stay inside the vault.',
            fix: 'Choose a path under assets/.',
          ),
        );
      } else if (!await storage.exists(attachment.path)) {
        problems.add(
          PkmsProblem(
            code: 'missing-attachment',
            severity: PkmsSeverity.error,
            subject: note.path,
            message: 'Missing attachment: ${attachment.path}',
            fix: 'Restore the file or remove the attachment call.',
          ),
        );
      }
    }
  }

  for (final task in index.tasks) {
    if (!taskStatuses.contains(task.status)) {
      problems.add(
        PkmsProblem(
          code: 'invalid-task-status',
          severity: PkmsSeverity.error,
          subject: task.id,
          message: 'Unknown task status: ${task.status}',
        ),
      );
    }
    if (!priorities.contains(task.priority)) {
      problems.add(
        PkmsProblem(
          code: 'invalid-task-priority',
          severity: PkmsSeverity.error,
          subject: task.id,
          message: 'Unknown task priority: ${task.priority}',
        ),
      );
    }
  }

  for (final entity in await storage.list(recursive: true)) {
    if (entity.isDirectory || !entity.path.contains('.remote-conflict-')) {
      continue;
    }
    final subject = entity.path;
    problems.add(
      PkmsProblem(
        code: 'sync-conflict',
        severity: PkmsSeverity.error,
        subject: subject,
        message: 'A synced file has a conflict copy.',
        fix: 'Tap to compare and merge the versions.',
      ),
    );
  }

  _duplicates(
    index.notes.map((note) => MapEntry(note.id, note.path)),
    'duplicate-note-id',
    problems,
  );
  _duplicates(
    [
      for (final note in index.notes)
        for (final alias in note.aliases) MapEntry(alias, note.path),
    ],
    'duplicate-alias',
    problems,
  );
  problems.sort((a, b) {
    final severity = b.severity.index.compareTo(a.severity.index);
    return severity != 0 ? severity : a.subject.compareTo(b.subject);
  });
  return PkmsValidationReport(problems: problems);
}

bool isSafeVaultPath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.startsWith(r'\')) {
    return false;
  }
  if (RegExp(r'^[A-Za-z]:[\/]').hasMatch(path)) return false;
  return !path.replaceAll('\\', '/').split('/').contains('..');
}

void _duplicates(
  Iterable<MapEntry<String, String>> values,
  String code,
  List<PkmsProblem> problems,
) {
  final owners = <String, Set<String>>{};
  for (final entry in values) {
    if (entry.key.isNotEmpty) {
      owners.putIfAbsent(entry.key, () => {}).add(entry.value);
    }
  }
  for (final entry in owners.entries.where((entry) => entry.value.length > 1)) {
    problems.add(
      PkmsProblem(
        code: code,
        severity: PkmsSeverity.error,
        subject: entry.key,
        message: '${entry.key} is owned by ${entry.value.join(', ')}',
        fix: 'Keep one canonical owner and rename or merge the others.',
      ),
    );
  }
}
