import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/unified_board.dart';

void main() {
  testWidgets('switch persists view and saves fallback canvas to entity board', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('unified-board'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
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
      for (var i = 0; i < 100 && !ready(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(ready(), isTrue);
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
    await poll(() => find.text('Kanban').evaluate().isNotEmpty);
    await tester.tap(find.text('Whiteboard'));
    await tester.pump();
    await poll(
      () => find.byKey(const ValueKey('board-card-old')).evaluate().isNotEmpty,
    );
    Board? saved;
    for (var i = 0; i < 100; i++) {
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
    for (var i = 0; i < 100; i++) {
      saved = await tester.runAsync<Board?>(
        () => readBoard(vault.storage, 'project'),
      );
      if (saved?.cards.isNotEmpty == true) break;
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
    await tester.tap(find.text('Tree'));
    await tester.pump();
    await poll(() => find.text('Pin to whiteboard').evaluate().isNotEmpty);
    expect(
      (await tester.runAsync(
        () => readBoard(vault.storage, 'project'),
      ))?.layout,
      'tree',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
