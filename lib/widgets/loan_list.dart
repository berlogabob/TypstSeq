import 'package:material_ui/material_ui.dart';
import 'package:tylog_core/tylog_core.dart'
    show TaskRef, isOpenLoan, loanEquipmentIds, loanOutFor;
import 'constants.dart';
import 'ds/app_sheet.dart';

class LoanList extends StatelessWidget {
  const LoanList({
    super.key,
    required this.loans,
    required this.titleOf,
    required this.now,
    required this.onOpen,
    this.empty = 'Nothing out',
    this.summary,
  });

  final List<TaskRef> loans;
  final String Function(String equipmentId) titleOf;
  final DateTime now;
  final ValueChanged<TaskRef> onOpen;
  final String empty;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    if (loans.isEmpty) {
      return ListTile(title: Text(empty));
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: loans.length + (summary == null ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (summary != null && i == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: kSpace12),
            child: Text(
              summary!,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          );
        }
        if (summary != null) i--;
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
  String? summary,
}) async {
  await showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: AppSheet.body(
        title: title,
        child: LoanList(
          loans: loans,
          titleOf: titleOf,
          now: DateTime.now(),
          onOpen: onOpen,
          summary: summary,
        ),
      ),
    ),
  );
}
