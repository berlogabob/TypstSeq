import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/namespace_migration.dart';
import 'package:tylog/vault.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog_core/namespace_plan.dart';

void main() {
  test('namespace header retains explicit and legacy parents', () {
    const note = NoteRef(
      id: 'child',
      path: 'child.typ',
      title: 'A/B',
      project: 'legacy',
      partOf: ['existing', 'legacy'],
      outgoingLinks: [],
      properties: {
        'part_of': ['existing'],
      },
    );
    const source =
        '#show: tylog.note.with(id: "child", title: "A/B", project: "legacy", properties: ("part_of": ("existing",),))';
    final updated = namespaceHeader(
      source,
      note,
      const NamespaceChange(
        existingId: 'child',
        fullPath: 'A/B',
        newTitle: 'B',
        parentPath: 'A',
      ),
      'new-parent',
    );
    expect(scanNote('child.typ', updated).partOf.toSet(), {
      'existing',
      'legacy',
      'new-parent',
    });
  });

  test('namespace header accepts missing and multiline fields', () {
    const note = NoteRef(
      id: 'child',
      path: 'child.typ',
      title: 'A/B',
      aliases: ['old'],
      outgoingLinks: [],
    );
    const change = NamespaceChange(
      existingId: 'child',
      fullPath: 'A/B',
      newTitle: 'B',
      parentPath: 'A',
    );
    for (final source in [
      '#show: tylog.note.with(id: "child", title: "A/B")',
      '#show: tylog.note.with(id: "child", title: "A/B", aliases: (\n "old",\n))',
      '#show: tylog.note.with(id: "child")',
    ]) {
      final result = scanNote(
        'child.typ',
        namespaceHeader(source, note, change, 'parent'),
      );
      expect(result.title, 'B');
      expect(result.aliases, containsAll(['old', 'A/B']));
    }
  });

  testWidgets('migration rejects a cycle before writing', (tester) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'namespace-cycle-',
      );
      try {
        final vault = Vault(directory);
        const parent = NoteRef(
          id: 'parent',
          path: 'parent.typ',
          title: 'A',
          partOf: ['child'],
          outgoingLinks: [],
        );
        const child = NoteRef(
          id: 'child',
          path: 'child.typ',
          title: 'A/B',
          outgoingLinks: [],
        );
        var writes = 0;
        await expectLater(
          applyNamespacePlan(
            vault,
            [parent, child],
            namespacePlan([parent, child]),
            mutate: (_, _) async {
              writes++;
              return true;
            },
          ),
          throwsStateError,
        );
        expect(writes, 0);
      } finally {
        await directory.delete(recursive: true);
      }
    });
    await tester.pump();
  });

  testWidgets('migration creates parents and preserves existing metadata', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'namespace-test-',
      );
      try {
        final vault = Vault(directory);
        await vault.page(
          'A/B/C',
          eventPath: 'notes/child.typ',
          metadata: const NoteMetadataDraft(
            id: 'child',
            title: 'A/B/C',
            properties: {'custom': 'kept'},
          ),
        );
        const note = NoteRef(
          id: 'child',
          path: 'notes/child.typ',
          title: 'A/B/C',
          outgoingLinks: [],
          properties: {'custom': 'kept'},
        );
        final plan = namespacePlan([note]);
        await applyNamespacePlan(
          vault,
          [note],
          plan,
          mutate: (path, transform) async {
            await vault.saveNote(
              path,
              transform(await vault.storage.readText(path)),
            );
            return true;
          },
        );
        final source = await vault.storage.readText('notes/child.typ');
        expect(source, contains('title: "C"'));
        expect(source, contains('"A/B/C"'));
        expect(source, contains('"custom": "kept"'));
        expect(source, contains('"part_of":'));
        expect(await vault.storage.exists('notes/A.typ'), isTrue);
        expect(await vault.storage.exists('notes/B.typ'), isTrue);
        final scanned = await scanVaultStorage(vault.storage);
        expect(namespacePlan(scanned.notes).changes, isEmpty);
      } finally {
        await directory.delete(recursive: true);
      }
    });
    await tester.pump();
  });
}
