import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/unified_board.dart';
import 'support/temp_dir.dart';

void main() {
  testWidgets('switch persists view and saves fallback canvas to entity board', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('unified-board'),
    ))!;
    addTearDown(() => deleteTempDir(dir));
    final vault = Vault(dir);
    const entity = NoteRef(
      id: 'project',
      path: 'project.typ',
      title: 'Project',
      outgoingLinks: [],
    );
    const index = VaultIndex(
      notesByPath: {'project.typ': entity},
      backlinksByTarget: {},
    );
    const legacy =
        '{"schema":2,"id":"project-wb","title":"Old","layout":"free","cards":[{"id":"old","type":"text","text":"Legacy card","x":30,"y":30}],"frames":[],"edges":[],"viewport":{"x":0,"y":0,"zoom":1}}';
    await tester.runAsync(() async {
      await vault.storage.createDirectory('boards');
      await vault.storage.writeText(boardPath('project-wb'), legacy);
      await writeBoard(
        vault.storage,
        const Board(
          id: 'project',
          title: 'Project',
          scopeEntity: 'project',
          extra: {'future': 'preserved'},
        ),
      );
    });
    Future<void> poll(bool Function() ready) async {
      for (var i = 0; i < 500 && !ready(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final switches = find.byType(SegmentedButton<String>);
      final selected = switches.evaluate().isEmpty
          ? null
          : tester.widget<SegmentedButton<String>>(switches).selected;
      expect(
        ready(),
        isTrue,
        reason: 'Board view did not become ready; selected: $selected',
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedBoard(
          entity: entity,
          vault: vault,
          index: index,
          setStatus: (_, _) async {},
          mutateNote: (_, _) async => false,
          refreshIndex: () async => index,
        ),
      ),
    );
    bool switchReady() {
      final switches = find.byType(SegmentedButton<String>);
      return switches.evaluate().isNotEmpty &&
          tester.widget<SegmentedButton<String>>(switches).onSelectionChanged !=
              null;
    }

    await poll(switchReady);
    await tester.tap(find.text('Whiteboard'));
    await tester.pump();
    await poll(
      () => find.byKey(const ValueKey('board-card-old')).evaluate().isNotEmpty,
    );
    Board? saved;
    for (var i = 0; i < 500; i++) {
      saved = await tester.runAsync<Board?>(
        () => readBoard(vault.storage, 'project'),
      );
      if (saved?.layout == 'free') break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(saved?.schema, 2);
    expect(saved?.layout, 'free');
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('board-card-old'))),
    );
    await gesture.moveBy(const Offset(20, 20));
    await gesture.moveBy(const Offset(40, 40));
    await gesture.moveBy(const Offset(40, 40));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 500; i++) {
      saved = await tester.runAsync<Board?>(
        () => readBoard(vault.storage, 'project'),
      );
      if (saved?.cards.isNotEmpty == true && saved!.cards.single.x != 30) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(saved?.cards.single.id, 'old');
    expect(saved?.extra['future'], 'preserved');
    expect(
      await tester.runAsync(
        () => vault.storage.readText(boardPath('project-wb')),
      ),
      legacy,
    );
    await poll(switchReady);
    await tester.tap(find.text('Tree'));
    await tester.pump();
    await poll(() => find.text('Pin to whiteboard').evaluate().isNotEmpty);
    for (var i = 0; i < 500; i++) {
      saved = await tester.runAsync<Board?>(
        () => readBoard(vault.storage, 'project'),
      );
      if (saved?.layout == 'tree') break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(saved?.layout, 'tree');
    await tester.pumpWidget(const SizedBox());
  });
}
