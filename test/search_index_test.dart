import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/search_index.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  test('search index persists, ranks titles, and filters tags', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_search_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/notes').create();
    await File('${dir.path}/notes/A.typ').writeAsString('alpha body knowledge');
    await File('${dir.path}/notes/B.typ').writeAsString('alpha body');
    final index = VaultIndex(
      notesByPath: {
        'notes/A.typ': const NoteRef(
          id: 'a',
          path: 'notes/A.typ',
          title: 'Alpha',
          tags: ['pkms'],
          outgoingLinks: [],
          fingerprint: 'a',
        ),
        'notes/B.typ': const NoteRef(
          id: 'b',
          path: 'notes/B.typ',
          title: 'Other',
          tags: ['other'],
          outgoingLinks: [],
          fingerprint: 'b',
        ),
      },
      backlinksByTarget: const {},
    );
    final search = await PkmsSearchIndex.buildStorage(LocalVaultStorage(dir), index);
    final file = File('${dir.path}/search.json.gz');
    await search.saveStorage(LocalVaultStorage(dir), 'search.json.gz');
    final loaded = await PkmsSearchIndex.loadStorage(
      LocalVaultStorage(dir),
      'search.json.gz',
    );

    expect(loaded.search('alpha').first.id, 'a');
    expect(loaded.search('body', tag: 'pkms').single.id, 'a');
    expect(await file.length(), greaterThan(0));
  });

  test('search index filters by task status', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_search_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/notes').create();
    await File('${dir.path}/notes/tasks.typ').writeAsString('task notes');
    final index = VaultIndex(
      notesByPath: {
        'notes/tasks.typ': const NoteRef(
          id: 'tasks',
          path: 'notes/tasks.typ',
          title: 'My Tasks',
          outgoingLinks: [],
          fingerprint: 'tasks',
        ),
      },
      backlinksByTarget: const {},
      tasks: [
        const TaskRef(
          id: 'task1',
          notePath: 'notes/tasks.typ',
          text: 'Write code',
          status: 'todo',
        ),
        const TaskRef(
          id: 'task2',
          notePath: 'notes/tasks.typ',
          text: 'Review PR',
          status: 'done',
        ),
        const TaskRef(
          id: 'task3',
          notePath: 'notes/tasks.typ',
          text: 'Test feature',
          status: 'todo',
        ),
      ],
    );
    final search = await PkmsSearchIndex.buildStorage(LocalVaultStorage(dir), index);

    // Search for all tasks
    final allTasks = search.search('').where((r) => r.kind == 'task').toList();
    expect(allTasks.length, equals(3));

    // Filter by status: todo
    final todoTasks = search.search('', status: 'todo').where((r) => r.kind == 'task').toList();
    expect(todoTasks.length, equals(2));
    expect(todoTasks.every((r) => r.id == 'task1' || r.id == 'task3'), isTrue);

    // Filter by status: done
    final doneTasks = search.search('', status: 'done').where((r) => r.kind == 'task').toList();
    expect(doneTasks.length, equals(1));
    expect(doneTasks.first.id, equals('task2'));
  });
}
