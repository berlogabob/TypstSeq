import 'package:test/test.dart';
import 'package:tylog_core/maintenance.dart';
import 'package:tylog_core/models.dart';

class _CachedTask extends TaskRef {
  const _CachedTask() : super(id: 't', notePath: 'notes/a.typ', text: 'Task');

  @override
  Map<String, Object?> toJson() => throw StateError('cached task encoded');
}

void main() {
  test('reused entries are not encoded; changed derived data is detected', () {
    const task = _CachedTask();
    const note = NoteRef(
      id: 'a',
      path: 'notes/a.typ',
      title: 'A',
      outgoingLinks: [],
    );
    VaultIndex index({
      String issue = 'one',
      List<TaskRef> tasks = const [task],
    }) => VaultIndex(
      notesByPath: const {'notes/a.typ': note},
      backlinksByTarget: const {},
      attachmentBacklinksByPath: const {},
      tasks: tasks,
      issueLines: {
        'notes/a.typ': [issue],
      },
    );
    expect(sameIndexContents(index(), index()), isTrue);
    expect(sameIndexContents(index(), index(issue: 'two')), isFalse);
    expect(sameIndexContents(index(), index(tasks: const [])), isFalse);
    final original = TaskRef(id: 't', notePath: 'notes/a.typ', text: 'Task');
    final equal = TaskRef(id: 't', notePath: 'notes/a.typ', text: 'Task');
    final changed = TaskRef(id: 't', notePath: 'notes/a.typ', text: 'Changed');
    expect(
      sameIndexContents(index(tasks: [original]), index(tasks: [equal])),
      isTrue,
    );
    expect(
      sameIndexContents(index(tasks: [original]), index(tasks: [changed])),
      isFalse,
    );
  });
}
