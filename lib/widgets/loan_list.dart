import 'package:material_ui/material_ui.dart';
import 'package:tylog_core/tylog_core.dart'
    show TaskRef, isOpenLoan, loanEquipmentIds, loanOutFor;

class LoanList extends StatelessWidget {
  const LoanList({
    super.key,
    required this.loans,
    required this.titleOf,
    required this.now,
    required this.onOpen,
    this.empty = 'Nothing out',
  });

  final List<TaskRef> loans;
  final String Function(String equipmentId) titleOf;
  final DateTime now;
  final ValueChanged<TaskRef> onOpen;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (loans.isEmpty) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(empty));
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: loans.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final task = loans[i];
        final duration = loanOutFor(task, now);
        final purpose = task.properties['purpose'];
        final details = <String>[
          if (loanEquipmentIds(task).isNotEmpty)
            loanEquipmentIds(task).map(titleOf).join(', '),
          if (purpose != null && '$purpose'.isNotEmpty) '$purpose',
          if (duration != null)
            '${isOpenLoan(task) ? 'out' : 'returned after'} ${_duration(duration)}',
        ];
        return ListTile(
          key: ValueKey('loan-${task.id}'),
          title: Text(task.text),
          subtitle: Text(details.join(' · ')),
          trailing: Icon(
            isOpenLoan(task) ? Icons.outbox_outlined : Icons.check,
          ),
          onTap: () => onOpen(task),
        );
      },
    );
  }
}

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  return hours == 0 ? '${value.inMinutes} min' : '$hours h $minutes min';
}

Future<void> showLoanSheet(
  BuildContext context, {
  required String title,
  required List<TaskRef> loans,
  required String Function(String equipmentId) titleOf,
  required ValueChanged<TaskRef> onOpen,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(title)),
            Flexible(
              child: LoanList(
                loans: loans,
                titleOf: titleOf,
                now: DateTime.now(),
                onOpen: onOpen,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
