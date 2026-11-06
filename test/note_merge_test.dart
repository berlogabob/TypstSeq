import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';
import 'package:tylog_core/tylog_core.dart' show loadDecisions;

class _DelayedStorage extends LocalVaultStorage {
  _DelayedStorage(super.root);

  int activeReads = 0;
  int maxActiveReads = 0;

  @override
  Future<String> readText(String path) async {
    activeReads++;
    if (activeReads > maxActiveReads) maxActiveReads = activeReads;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return await super.readText(path);
    } finally {
      activeReads--;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'merges cross-folder prose with percent signs and vertical bars',
    () async {
      final root = await Directory.systemTemp.createTemp('merge-percent-');
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
          'Keep.',
          const NoteMetadataDraft(id: 'a', title: 'A'),
        ),
      );
      await storage.writeText(
        'notes/other/b.typ',
        replaceNoteHeader(
          'Progress: 50% | remaining: 50%.',
          const NoteMetadataDraft(id: 'b', title: 'B'),
        ),
      );
      workspace.index = await scanVaultStorage(storage);
      await workspace.mergeDuplicate(
        await workspace.previewDuplicateMerge(
          'notes/a.typ',
          'notes/other/b.typ',
        ),
      );
      final result = await storage.readText('notes/a.typ');
      expect(result, contains('Progress: 50% | remaining: 50%.'));
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
    },
  );
  test(
    'merges matching custom text properties and rejects disagreements',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'merge-matching-property-',
      );
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
      for (final id in ['a', 'b']) {
        await storage.writeText(
          'notes/$id.typ',
          replaceNoteHeader(
            'Body $id.\n',
            NoteMetadataDraft(
              id: id,
              title: id.toUpperCase(),
              properties: const {'role': 'author'},
            ),
          ),
        );
      }
      workspace.index = await scanVaultStorage(storage);
      final preview = await workspace.previewDuplicateMerge(
        'notes/a.typ',
        'notes/b.typ',
      );
      await workspace.mergeDuplicate(preview);
      final result = await storage.readText('notes/a.typ');
      expect(scanNote('notes/a.typ', result).properties['role'], 'author');
      expect(result, contains('Body b.'));
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
      await storage.writeText(
        'notes/c.typ',
        replaceNoteHeader(
          '',
          const NoteMetadataDraft(
            id: 'c',
            title: 'C',
            properties: {'role': 'editor'},
          ),
        ),
      );
      workspace.index = await scanVaultStorage(storage);
      await expectLater(
        workspace.previewDuplicateMerge('notes/a.typ', 'notes/c.typ'),
        throwsStateError,
      );
      expect(await storage.readText('notes/a.typ'), result);
      expect(await storage.exists('notes/c.typ'), isTrue);
    },
  );
  test(
    'merges matching scalar properties and rejects differing values',
    () async {
      final root = await Directory.systemTemp.createTemp('merge-scalars-');
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
      for (final id in ['a', 'b']) {
        await storage.writeText(
          'notes/$id.typ',
          replaceNoteHeader(
            'Body $id.',
            NoteMetadataDraft(
              id: id,
              title: id.toUpperCase(),
              properties: const {'count': 3, 'enabled': true, 'empty': null},
            ),
          ),
        );
      }
      workspace.index = await scanVaultStorage(storage);
      await workspace.mergeDuplicate(
        await workspace.previewDuplicateMerge('notes/a.typ', 'notes/b.typ'),
      );
      final result = await storage.readText('notes/a.typ');
      expect(
        scanNote('notes/a.typ', result).properties,
        containsPair('count', 3),
      );
      expect(
        scanNote('notes/a.typ', result).properties,
        containsPair('enabled', true),
      );
      expect(
        scanNote('notes/a.typ', result).properties,
        containsPair('empty', null),
      );
      expect(result, contains('Body b.'));
      expect(await storage.exists('notes/b.typ'), isFalse);
      final compile = Process.runSync('typst', [
        'compile',
        '--root',
        root.path,
        '${root.path}/notes/a.typ',
        '${root.path}/out.pdf',
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stderr}');
      await storage.writeText(
        'notes/c.typ',
        replaceNoteHeader(
          '',
          const NoteMetadataDraft(
            id: 'c',
            title: 'C',
            properties: {'count': 4},
          ),
        ),
      );
      workspace.index = await scanVaultStorage(storage);
      await expectLater(
        workspace.previewDuplicateMerge('notes/a.typ', 'notes/c.typ'),
        throwsStateError,
      );
      expect(await storage.readText('notes/a.typ'), result);
      expect(await storage.exists('notes/c.typ'), isTrue);
    },
  );
  test('merges cross-folder prose with ampersands and plus signs', () async {
    final root = await Directory.systemTemp.createTemp('merge-punctuation-');
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
        'Keep.\n',
        const NoteMetadataDraft(id: 'a', title: 'A'),
      ),
    );
    await storage.writeText(
      'notes/other/b.typ',
      replaceNoteHeader(
        'Research & development + operations.\n',
        const NoteMetadataDraft(id: 'b', title: 'B'),
      ),
    );
    workspace.index = await scanVaultStorage(storage);
    final preview = await workspace.previewDuplicateMerge(
      'notes/a.typ',
      'notes/other/b.typ',
    );
    await workspace.mergeDuplicate(preview);
    final result = await storage.readText('notes/a.typ');
    expect(result, contains('Research & development + operations.'));
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
  test('merges inline raw text from another folder', () async {
    final root = await Directory.systemTemp.createTemp('merge-raw-');
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
        'Keep.\n',
        const NoteMetadataDraft(id: 'a', title: 'A'),
      ),
    );
    await storage.writeText(
      'notes/other/b.typ',
      replaceNoteHeader(
        'Run `hello-world`.\n',
        const NoteMetadataDraft(id: 'b', title: 'B'),
      ),
    );
    workspace.index = await scanVaultStorage(storage);
    final preview = await workspace.previewDuplicateMerge(
      'notes/a.typ',
      'notes/other/b.typ',
    );
    await workspace.mergeDuplicate(preview);
    expect(
      await storage.readText('notes/a.typ'),
      contains('Run `hello-world`.'),
    );
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
  test('merges canonical custom properties and refuses conflicts', () async {
    final root = await Directory.systemTemp.createTemp('merge-properties-');
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
        'Keep.\n',
        const NoteMetadataDraft(
          id: 'a',
          title: 'A',
          properties: {'existing': 'kept'},
        ),
      ),
    );
    await storage.writeText(
      'notes/b.typ',
      replaceNoteHeader(
        'Other.\n',
        const NoteMetadataDraft(
          id: 'b',
          title: 'B',
          properties: {'custom': 'value', 'count': 3},
        ),
      ),
    );
    workspace.index = await scanVaultStorage(storage);
    final preview = await workspace.previewDuplicateMerge(
      'notes/a.typ',
      'notes/b.typ',
    );
    await workspace.mergeDuplicate(preview);
    final text = await storage.readText('notes/a.typ');
    expect(
      scanNote('notes/a.typ', text).properties,
      containsPair('existing', 'kept'),
    );
    expect(
      scanNote('notes/a.typ', text).properties,
      containsPair('custom', 'value'),
    );
    expect(scanNote('notes/a.typ', text).properties, containsPair('count', 3));
    expect(text, contains('Other.'));
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
    await storage.writeText(
      'notes/c.typ',
      replaceNoteHeader(
        '',
        const NoteMetadataDraft(
          id: 'c',
          title: 'C',
          properties: {'custom': 'different'},
        ),
      ),
    );
    workspace.index = await scanVaultStorage(storage);
    await expectLater(
      workspace.previewDuplicateMerge('notes/a.typ', 'notes/c.typ'),
      throwsStateError,
    );
    expect(await storage.exists('notes/c.typ'), isTrue);
    expect(await storage.readText('notes/a.typ'), text);
  });
  test('merge preview reads candidate notes concurrently', () async {
    final root = await Directory.systemTemp.createTemp('merge-parallel-');
    final storage = _DelayedStorage(root);
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
    for (var i = 0; i < 12; i++) {
      await storage.writeText(
        'notes/$i.typ',
        replaceNoteHeader('', NoteMetadataDraft(id: 'n$i', title: 'N$i')),
      );
    }
    workspace.index = await scanVaultStorage(storage);
    storage.maxActiveReads = 0;
    await workspace.previewDuplicateMerge('notes/0.typ', 'notes/1.typ');
    expect(storage.maxActiveReads, greaterThan(1));
    expect(storage.maxActiveReads, lessThanOrEqualTo(4));
  });
  test(
    'preserves a canonical duplicate date and project, rejecting conflicts',
    () async {
      final root = await Directory.systemTemp.createTemp('merge-metadata-');
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
          'Keep.\n',
          const NoteMetadataDraft(id: 'a', title: 'A'),
        ),
      );
      await storage.writeText(
        'notes/b.typ',
        replaceNoteHeader(
          'Other.\n',
          const NoteMetadataDraft(
            id: 'b',
            title: 'B',
            date: '2026-11-04',
            project: 'project-one',
          ),
        ),
      );
      workspace.index = await scanVaultStorage(storage);
      final preview = await workspace.previewDuplicateMerge(
        'notes/a.typ',
        'notes/b.typ',
      );
      await workspace.mergeDuplicate(preview);
      final result = await storage.readText('notes/a.typ');
      final merged = scanNote('notes/a.typ', result);
      expect(merged.date, '2026-11-04');
      expect(merged.project, 'project-one');
      expect(result, contains('Other.'));
      expect(await storage.exists('notes/b.typ'), isFalse);
      final compile = Process.runSync('typst', [
        'compile',
        '--root',
        root.path,
        '${root.path}/notes/a.typ',
        '${root.path}/out.pdf',
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stderr}');
      await storage.writeText(
        'notes/c.typ',
        replaceNoteHeader(
          '',
          const NoteMetadataDraft(id: 'c', title: 'C', date: '2026-11-05'),
        ),
      );
      workspace.index = await scanVaultStorage(storage);
      await expectLater(
        workspace.previewDuplicateMerge('notes/a.typ', 'notes/c.typ'),
        throwsStateError,
      );
      expect(await storage.exists('notes/c.typ'), isTrue);
    },
  );
  test('merges a cross-folder body containing a web URL', () async {
    final root = await Directory.systemTemp.createTemp('merge-url-');
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
        'Keep.\n',
        const NoteMetadataDraft(id: 'a', title: 'A'),
      ),
    );
    await storage.writeText(
      'notes/other/b.typ',
      replaceNoteHeader(
        'See https://example.com/path.\n',
        const NoteMetadataDraft(id: 'b', title: 'B'),
      ),
    );
    workspace.index = await scanVaultStorage(storage);
    final preview = await workspace.previewDuplicateMerge(
      'notes/a.typ',
      'notes/other/b.typ',
    );
    await workspace.mergeDuplicate(preview);
    expect(
      await storage.readText('notes/a.typ'),
      contains('See https://example.com/path.'),
    );
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
  test('merges headings and lists from another folder', () async {
    final root = await Directory.systemTemp.createTemp('merge-list-');
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
        '= Details\n\n- First item\n- *Second* item\n',
        const NoteMetadataDraft(id: 'b', title: 'B'),
      ),
    );
    workspace.index = await scanVaultStorage(storage);
    final preview = await workspace.previewDuplicateMerge(
      'notes/a.typ',
      'notes/other/b.typ',
    );
    await workspace.mergeDuplicate(preview);
    final text = await storage.readText('notes/a.typ');
    expect(text, contains('= Details\n\n- First item\n- *Second* item'));
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
  test('merges emphasized text from another folder', () async {
    final root = await Directory.systemTemp.createTemp('merge-emphasis-');
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
        'A *bold* and _emphasized_ paragraph.\n',
        const NoteMetadataDraft(id: 'b', title: 'B'),
      ),
    );
    await storage.writeText(
      'notes/ref.typ',
      '#import "/_system/tylog.typ" as tylog\n#tylog.ref-note("b")[B]\n',
    );
    workspace.index = await scanVaultStorage(storage);
    final preview = await workspace.previewDuplicateMerge(
      'notes/a.typ',
      'notes/other/b.typ',
    );
    expect(
      preview.files,
      containsAll(['notes/a.typ', 'notes/other/b.typ', 'notes/ref.typ']),
    );
    await workspace.mergeDuplicate(preview);
    final text = await storage.readText('notes/a.typ');
    expect(text, contains('A *bold* and _emphasized_ paragraph.'));
    expect(
      await storage.readText('notes/ref.typ'),
      contains('#tylog.ref-note("a")'),
    );
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
