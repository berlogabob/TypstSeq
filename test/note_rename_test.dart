import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';
import 'package:tylog_core/storage.dart' show indexDirtyPath;

class _Workspace extends WorkspaceController {
  _Workspace()
    : super(taskScheduler: TaskScheduler(), reconcileTasks: (_) async {});
  int refreshes = 0;
  @override
  Future<void> refreshIndex({
    bool updateStatus = true,
    bool always = false,
  }) async {
    refreshes++;
  }
}

void _compile(Directory root, String path) {
  final result = Process.runSync('typst', [
    'compile',
    '--root',
    root.path,
    '${root.path}/$path',
    '${root.path}/out.pdf',
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}\n$path');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late VaultStorage storage;
  late _Workspace workspace;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog-rename-');
    storage = LocalVaultStorage(root);
    final vault = Vault.withStorage(storage);
    await vault.ensureCreated();
    workspace = _Workspace()..vault = vault;
  });
  tearDown(() async {
    workspace.dispose();
    await root.delete(recursive: true);
  });

  Future<void> seed() async {
    await storage.writeText(
      'notes/old-stem.typ',
      replaceNoteHeader(
        'Body\n',
        const NoteMetadataDraft(
          id: 'stable-id',
          title: 'проаерка',
          aliases: ['old alias'],
          properties: {'custom': 'preserved'},
        ),
      ),
    );
    await storage.writeText(
      'notes/title-ref.typ',
      '#import "/_system/tylog.typ" as tylog\n'
          'Before #tylog.ref-note("проаерка", heading: "Section")[проаерка] after\n'
          '// #tylog.ref-note("проаерка")[проаерка]\n',
    );
    await storage.writeText(
      'notes/stem-ref.typ',
      '#import "/_system/tylog.typ" as tylog\n'
          '#tylog.ref-note("old-stem")[Custom label] and '
          '#tylog.ref-note("old alias")[проаерка]\n',
    );
    await storage.writeText('notes/unrelated.typ', 'Unrelated *bytes*\r\n');
    workspace.index = await scanVaultStorage(storage);
    workspace.linkResolver = LinkResolver(workspace.index!.notes);
  }

  test(
    'rename preserves identity and surgically rewrites indexed backlinks',
    () async {
      await seed();
      final before = await storage.readBytes('notes/unrelated.typ');
      workspace.replaceNote(
        'notes/title-ref.typ',
        await storage.readText('notes/title-ref.typ'),
      );
      workspace.edit('${workspace.source}Unsaved edit\n');
      const title = 'Проверка "quotes" # [label]';
      final result = await workspace.renameNote(
        'notes/old-stem.typ',
        ' $title ',
      );
      expect(result.succeeded, isTrue, reason: result.message);
      expect(result.path, 'notes/$title.typ');
      expect(await storage.exists('notes/old-stem.typ'), isFalse);
      final renamed = scanNote(
        result.path!,
        await storage.readText(result.path!),
      );
      expect(renamed.title, title);
      expect(renamed.id, 'stable-id');
      expect(renamed.aliases, ['old alias']);
      expect(renamed.properties['custom'], 'preserved');
      expect(
        await storage.readText('notes/title-ref.typ'),
        '#import "/_system/tylog.typ" as tylog\n'
        'Before #tylog.ref-note("Проверка \\"quotes\\" # [label]", heading: "Section")[Проверка "quotes" \\# \\[label\\]] after\n'
        '// #tylog.ref-note("проаерка")[проаерка]\nUnsaved edit\n',
      );
      final stem = await storage.readText('notes/stem-ref.typ');
      expect(stem, contains('[Custom label]'));
      expect(stem, isNot(contains('"old-stem"')));
      expect(stem, isNot(contains('"old alias"')));
      expect(workspace.source, await storage.readText('notes/title-ref.typ'));
      expect(workspace.dirty, isFalse);
      expect(workspace.savedRevision, workspace.editRevision);
      expect(await storage.readBytes('notes/unrelated.typ'), before);
      expect(workspace.refreshes, greaterThan(0));
      for (final path in [
        result.path!,
        'notes/title-ref.typ',
        'notes/stem-ref.typ',
      ]) {
        _compile(root, path);
      }
      final markers = await storage.list(path: indexDirtyPath);
      expect(markers, isNotEmpty);
    },
  );

  test('renaming the open note keeps its buffer and path consistent', () async {
    await seed();
    workspace.replaceNote(
      'notes/old-stem.typ',
      await storage.readText('notes/old-stem.typ'),
    );
    workspace.edit('${workspace.source}Latest buffer\n');
    final result = await workspace.renameNote(
      'notes/old-stem.typ',
      'Corrected',
    );
    expect(result.succeeded, isTrue);
    expect(workspace.note, 'notes/Corrected.typ');
    expect(workspace.source, await storage.readText(workspace.note!));
    expect(workspace.source, contains('Latest buffer'));
    expect(workspace.dirty, isFalse);
    expect(scanNote(workspace.note!, workspace.source).id, 'stable-id');
    _compile(root, workspace.note!);
  });

  test('rename refuses title and file collisions and invalid titles', () async {
    await seed();
    await storage.writeText(
      'notes/different.typ',
      replaceNoteHeader(
        'Other\n',
        const NoteMetadataDraft(id: 'other', title: 'Taken'),
      ),
    );
    workspace.index = await scanVaultStorage(storage);
    final before = await storage.readBytes('notes/old-stem.typ');
    expect(
      (await workspace.renameNote('notes/old-stem.typ', 'Taken')).failure,
      RenameNoteFailure.collision,
    );
    await storage.writeText('notes/Unindexed.typ', 'Do not overwrite\n');
    expect(
      (await workspace.renameNote('notes/old-stem.typ', 'Unindexed')).failure,
      RenameNoteFailure.collision,
    );
    for (final title in [' ', 'bad/name', r'bad\name', 'bad\nname']) {
      expect(
        (await workspace.renameNote('notes/old-stem.typ', title)).failure,
        RenameNoteFailure.invalidTitle,
      );
    }
    expect(await storage.readBytes('notes/old-stem.typ'), before);
    expect(await storage.readText('notes/Unindexed.typ'), 'Do not overwrite\n');
  });
}
