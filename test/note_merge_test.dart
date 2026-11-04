import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';
import 'package:tylog_core/tylog_core.dart' show loadDecisions;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('merges a plain body from another folder', () async {
    final root = await Directory.systemTemp.createTemp('merge-folders-');
    final storage = LocalVaultStorage(root);
    final vault = Vault.withStorage(storage);
    await vault.ensureCreated();
    final workspace = WorkspaceController(
      taskScheduler: TaskScheduler(),
      reconcileTasks: (_) async {},
    )..vault = vault;
    addTearDown(() async {
      workspace.dispose();
      await root.delete(recursive: true);
    });
    await storage.createDirectory('notes/other');
    await storage.writeText(
      'notes/a.typ',
      replaceNoteHeader(
        'Original.\n',
        const NoteMetadataDraft(id: 'a', title: 'A'),
      ),
    );
    await storage.writeText(
      'notes/other/b.typ',
      replaceNoteHeader(
        'A useful plain paragraph.\n',
        const NoteMetadataDraft(id: 'b', title: 'B'),
      ),
    );
    workspace.index = await scanVaultStorage(storage);
    final preview = await workspace.previewDuplicateMerge(
      'notes/a.typ',
      'notes/other/b.typ',
    );
    await storage.writeText(
      'notes/other/b.typ',
      replaceNoteHeader(
        '#image("photo.png")\n',
        const NoteMetadataDraft(id: 'b', title: 'B'),
      ),
    );
    await expectLater(
      workspace.previewDuplicateMerge('notes/a.typ', 'notes/other/b.typ'),
      throwsStateError,
    );
    await storage.writeText(
      'notes/other/b.typ',
      replaceNoteHeader(
        'A useful plain paragraph.\n',
        const NoteMetadataDraft(id: 'b', title: 'B'),
      ),
    );
    await workspace.mergeDuplicate(preview);
    final text = await storage.readText('notes/a.typ');
    expect(text, contains('A useful plain paragraph.'));
    expect(await storage.exists('notes/other/b.typ'), isFalse);
    expect(await loadDecisions(storage), hasLength(1));
    final compile = Process.runSync('typst', [
      'compile',
      '--root',
      root.path,
      '${root.path}/notes/a.typ',
      '${root.path}/out.pdf',
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stderr}');
  });
  test(
    'preview and merge an empty duplicate, preserving metadata and links',
    () async {
      final root = await Directory.systemTemp.createTemp('merge-test-');
      final storage = LocalVaultStorage(root);
      final vault = Vault.withStorage(storage);
      await vault.ensureCreated();
      final workspace =
          WorkspaceController(
              taskScheduler: TaskScheduler(),
              reconcileTasks: (_) async {},
            )
            ..vault = vault
            ..deviceId = 'test';
      addTearDown(() async {
        workspace.dispose();
        await root.delete(recursive: true);
      });
      await storage.writeText(
        'notes/keep.typ',
        replaceNoteHeader(
          'Keep body\n',
          const NoteMetadataDraft(
            id: 'keep',
            title: 'Andre',
            aliases: ['A'],
            properties: {
              'part_of': ['parent-a'],
              'custom': 'keep',
            },
          ),
        ),
      );
      await storage.writeText(
        'notes/lose.typ',
        replaceNoteHeader(
          '',
          const NoteMetadataDraft(
            id: 'lose',
            title: 'André',
            aliases: ['B'],
            properties: {
              'part_of': ['parent-b'],
            },
          ),
        ),
      );
      await storage.writeText(
        'notes/ref.typ',
        '#import "/_system/tylog.typ" as tylog\n#tylog.ref-note("lose")[André] and #tylog.ref-note("B")[custom]\n',
      );
      workspace.index = await scanVaultStorage(storage);
      final preview = await workspace.previewDuplicateMerge(
        'notes/keep.typ',
        'notes/lose.typ',
      );
      expect(preview.files.toSet(), {
        'notes/keep.typ',
        'notes/lose.typ',
        'notes/ref.typ',
      });
      await workspace.mergeDuplicate(preview);
      final keep = scanNote(
        'notes/keep.typ',
        await storage.readText('notes/keep.typ'),
      );
      expect(keep.aliases.toSet(), containsAll(['A', 'B', 'André']));
      expect(keep.partOf.toSet(), {'parent-a', 'parent-b'});
      expect(keep.properties['custom'], 'keep');
      expect(await storage.readText('notes/keep.typ'), contains('Keep body'));
      expect(await storage.exists('notes/lose.typ'), isFalse);
      expect(
        await storage.readText('notes/ref.typ'),
        contains('#tylog.ref-note("keep")'),
      );
      expect(await loadDecisions(storage), hasLength(1));
      for (final path in ['notes/keep.typ', 'notes/ref.typ']) {
        final compile = Process.runSync('typst', [
          'compile',
          '--root',
          root.path,
          '${root.path}/$path',
          '${root.path}/out.pdf',
        ]);
        expect(compile.exitCode, 0, reason: '${compile.stderr}');
      }
    },
  );

  test(
    'merges a canonical duplicate with body and repoints its links',
    () async {
      final root = await Directory.systemTemp.createTemp('merge-test-');
      final storage = LocalVaultStorage(root);
      final vault = Vault.withStorage(storage);
      await vault.ensureCreated();
      final workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        reconcileTasks: (_) async {},
      )..vault = vault;
      addTearDown(() async {
        workspace.dispose();
        await root.delete(recursive: true);
      });
      await storage.writeText(
        'notes/a.typ',
        replaceNoteHeader('', const NoteMetadataDraft(id: 'a', title: 'A')),
      );
      await storage.writeText(
        'notes/b.typ',
        replaceNoteHeader(
          'Important body with #tylog.ref-note("b")[B].\n',
          const NoteMetadataDraft(id: 'b', title: 'B'),
        ),
      );
      workspace.index = await scanVaultStorage(storage);
      final preview = await workspace.previewDuplicateMerge(
        'notes/a.typ',
        'notes/b.typ',
      );
      await workspace.mergeDuplicate(preview);
      final merged = await storage.readText('notes/a.typ');
      expect(merged, contains('== Merged from B'));
      expect(merged, contains('Important body with #tylog.ref-note("a")[A].'));
      expect(await storage.exists('notes/b.typ'), isFalse);
      final compile = Process.runSync('typst', [
        'compile',
        '--root',
        root.path,
        '${root.path}/notes/a.typ',
        '${root.path}/out.pdf',
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stderr}');
    },
  );
  test(
    'merges tagged canonical pages without losing either set of tags',
    () async {
      final root = await Directory.systemTemp.createTemp('merge-tags-');
      final storage = LocalVaultStorage(root);
      final vault = Vault.withStorage(storage);
      await vault.ensureCreated();
      final workspace = WorkspaceController(
        taskScheduler: TaskScheduler(),
        reconcileTasks: (_) async {},
      )..vault = vault;
      addTearDown(() async {
        workspace.dispose();
        await root.delete(recursive: true);
      });
      await storage.writeText(
        'notes/a.typ',
        replaceNoteHeader(
          'Keep body\n',
          const NoteMetadataDraft(
            id: 'a',
            title: 'A',
            tags: ['keep', 'shared'],
          ),
        ),
      );
      await storage.writeText(
        'notes/b.typ',
        replaceNoteHeader(
          'Other body\n',
          const NoteMetadataDraft(
            id: 'b',
            title: 'B',
            tags: ['other', 'shared'],
          ),
        ),
      );
      workspace.index = await scanVaultStorage(storage);
      final preview = await workspace.previewDuplicateMerge(
        'notes/a.typ',
        'notes/b.typ',
      );
      expect(preview.files, containsAll(['notes/a.typ', 'notes/b.typ']));
      await workspace.mergeDuplicate(preview);
      final text = await storage.readText('notes/a.typ');
      expect(scanNote('notes/a.typ', text).tags.toSet(), {
        'keep',
        'shared',
        'other',
      });
      expect(text, contains('Keep body'));
      expect(text, contains('Other body'));
      expect(await storage.exists('notes/b.typ'), isFalse);
      expect(await loadDecisions(storage), hasLength(1));
      final compile = Process.runSync('typst', [
        'compile',
        '--root',
        root.path,
        '${root.path}/notes/a.typ',
        '${root.path}/out.pdf',
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stderr}');
    },
  );
}
