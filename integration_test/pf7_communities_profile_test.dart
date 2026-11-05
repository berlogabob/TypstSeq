import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/workspace_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PF7 community view cold and repeated derivation', (_) async {
    const noteCount = 10067;
    const tagCount = 48;
    final notes = <String, NoteRef>{};
    for (var i = 0; i < noteCount; i++) {
      final tags = <String>[
        'tag-${i % tagCount}',
        'tag-${(i + 1) % tagCount}',
        'tag-${(i + 7) % tagCount}',
      ];
      final path = 'notes/note-$i.typ';
      notes[path] = NoteRef(
        id: 'note-$i',
        path: path,
        title: 'Note $i',
        outgoingLinks: const [],
        tags: tags,
      );
    }
    final controller =
        WorkspaceController(
            taskScheduler: TaskScheduler(),
            reconcileTasks: (_) async {},
          )
          ..index = VaultIndex(notesByPath: notes, backlinksByTarget: const {})
          ..indexRevision = 1;
    addTearDown(controller.dispose);

    final cold = Stopwatch()..start();
    await controller.refreshDerived();
    cold.stop();
    expect(controller.communities, isNotNull);
    final result = controller.communities;

    final repeated = Stopwatch()..start();
    await controller.refreshDerived();
    repeated.stop();
    expect(identical(controller.communities, result), isTrue);

    // The P30 profile run reports these values in flutter drive's output.
    // The 10,067-note synthetic index matches the current device-vault size;
    // it does not stand in for SAF or real-vault frame measurements.
    // ignore: avoid_print
    print(
      'PF7_COMMUNITIES notes=$noteCount tags=$tagCount '
      'coldMs=${cold.elapsedMilliseconds} '
      'repeatedMs=${repeated.elapsedMilliseconds} '
      'clusters=${result!.clusterOrder.length}',
    );
  });
}
