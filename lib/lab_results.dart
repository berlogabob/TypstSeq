import 'package:flutter/foundation.dart';
import 'package:tylog_core/tylog_core.dart';

// shortcut: one notifier for all vaults; move into WorkspaceController for multi-vault use.
final labResultsNotifier = ValueNotifier<Map<String, LabResult>>(const {});

Future<void> refreshLabResults(VaultStorage storage) async =>
    labResultsNotifier.value = await loadLabResults(storage);

List<NoteRef> labRefusalIncoming(
  Iterable<TaskRef> tasks,
  Map<String, LabResult> results,
  Set<String> decided,
  String day,
) => [
  for (final task in tasks)
    if (loanEquipmentIds(task).isNotEmpty &&
        results[task.id]?.stateFor(task) == 'refused' &&
        !decided.contains('lab-refused-${task.id}'))
      NoteRef(
        id: 'lab-refused-${task.id}',
        path: 'olt:lab-refused/${task.id}',
        title: 'OpenLabTwin refused: ${results[task.id]!.reason ?? ''}',
        kind: 'lab',
        date: day,
        outgoingLinks: const [],
        properties: {'source': 'lab', 'note': task.notePath},
      ),
];
