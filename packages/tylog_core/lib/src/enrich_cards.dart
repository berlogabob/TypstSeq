import 'enrich.dart';
import 'loan.dart';
import 'models.dart';
import 'scanner.dart' show locateTypstCalls, taskField;

enum EnrichRowState { linked, willLink, ambiguous, propose }

String enrichTargetLabel(String shortTitle, Object? color) {
  final title = shortTitle.replaceFirstMapped(
    RegExp(r'\s+\[(\d+)\](?=\s|$)'),
    (m) => ' unit ${m[1]}',
  );
  return color is String && color.isNotEmpty ? '$title · $color' : title;
}

class EnrichCardRow {
  const EnrichCardRow({
    required this.state,
    required this.surface,
    required this.target,
    required this.candidates,
    required this.decision,
    required this.highlightStart,
    required this.highlightEnd,
  });

  final EnrichRowState state;
  final String surface;
  final NoteRef? target;
  final List<EnrichCandidate> candidates;
  final EnrichDecision? decision;
  final int highlightStart;
  final int highlightEnd;
}

class EnrichLineCard {
  const EnrichLineCard({
    required this.line,
    this.taskId,
    required this.text,
    required this.rows,
    required this.loan,
    required this.due,
    required this.warning,
    required this.willLinkCount,
    required this.primaryLabel,
    required this.key,
  });

  final int line;
  final String? taskId;
  final String text;
  final List<EnrichCardRow> rows;
  final EnrichLoanOffer? loan;
  final String? due;
  final String? warning;
  final int willLinkCount;
  final String? primaryLabel;
  final String key;
}

List<EnrichLineCard> acceptAllOrder(List<EnrichLineCard> cards) =>
    cards.reversed.toList();

Future<void> acceptCard(
  EnrichLineCard card,
  Iterable<EnrichCardRow> rows, {
  required Future<void> Function(EnrichMention, NoteRef) acceptLink,
  required Future<void> Function(EnrichLoanOffer) acceptLoan,
}) async {
  for (final row in rows) {
    if (row.state == EnrichRowState.willLink) {
      await acceptLink(row.decision!.mention, row.target!);
    }
  }
  if (card.loan != null) await acceptLoan(card.loan!);
}

String? enrichPrimaryLabel(int willLinkCount, EnrichLoanOffer? loan) {
  if (willLinkCount == 0 && loan == null) return null;
  final link = willLinkCount > 0 ? 'Link $willLinkCount' : '';
  final label = loan == null
      ? link
      : (link.isEmpty ? 'Track loan' : '$link + track loan');
  return loan?.due == null ? label : '$label · due ${loan!.due}';
}

List<EnrichLineCard> enrichLineCards({
  required List<EnrichDecision> decisions,
  required List<EnrichLoanOffer> loans,
  required List<String> lines,
  Map<String, List<TaskRef>> openLoans = const {},
}) {
  final source = lines.join('\n');
  final taskLines = <int, (String?, String?, bool)>{};
  for (final call in locateTypstCalls(source, names: const {'tylog.task'})) {
    final first = '\n'.allMatches(source.substring(0, call.start)).length + 1;
    final parts = call.source.split('\n');
    for (var i = 0; i < parts.length; i++) {
      final textLine = RegExp(
        r'^\s*text\s*:\s*"(?:\\.|[^"\\])*"\s*,?\s*$',
      ).hasMatch(parts[i]);
      taskLines[first + i] = (
        taskField(call.source, 'id'),
        textLine ? taskField(call.source, 'text') : null,
        RegExp(r'"loan"\s*:\s*true').hasMatch(call.source),
      );
    }
  }
  final byLine = <int, List<EnrichDecision>>{};
  final loansByLine = <int, EnrichLoanOffer>{};
  for (final decision in decisions) {
    final line = decision.mention.line;
    final task = taskLines[line];
    if (task != null &&
        (task.$1 == null ||
            task.$2 == null ||
            (decision.mention.type.toLowerCase() != 'person' &&
                !(decision.mention.type.toLowerCase() == 'equipment' &&
                    !task.$3)))) {
      continue;
    }
    if (line >= 1 && line <= lines.length) {
      (byLine[line] ??= []).add(decision);
    }
  }
  for (final loan in loans) {
    if (!taskLines.containsKey(loan.line) &&
        loan.line >= 1 &&
        loan.line <= lines.length) {
      loansByLine[loan.line] = loan;
    }
  }
  final numbers = {...byLine.keys, ...loansByLine.keys}.toList()
    ..removeWhere((line) => _startsUnclosedCall(lines[line - 1]))
    ..sort();
  final markup = RegExp(r'#tylog\.ref-note\("((?:\\.|[^"\\])*)"\)\[([^\]]*)\]');
  return [
    for (final line in numbers)
      (() {
        final source = lines[line - 1];
        final matches = markup.allMatches(source).toList();
        final text =
            taskLines[line]?.$2 ??
            source
                .replaceAllMapped(markup, (match) => match[2]!)
                .replaceFirst(RegExp(r'^\s*[-+*] '), '');
        final rows = <EnrichCardRow>[];
        void add(
          EnrichRowState state,
          String surface,
          NoteRef? target,
          List<EnrichCandidate> candidates,
          EnrichDecision? decision,
        ) {
          final start = enrichSurfaceIndex(text, surface);
          rows.add(
            EnrichCardRow(
              state: state,
              surface: surface,
              target: target,
              candidates: candidates,
              decision: decision,
              highlightStart: start,
              highlightEnd: start < 0 ? -1 : start + surface.length,
            ),
          );
        }

        for (final decision in byLine[line] ?? <EnrichDecision>[]) {
          final state = decision.choose
              ? EnrichRowState.ambiguous
              : decision.status == EnrichStatus.propose
              ? EnrichRowState.propose
              : EnrichRowState.willLink;
          add(
            state,
            decision.mention.surface,
            state == EnrichRowState.willLink ? decision.target : null,
            decision.candidates,
            decision,
          );
        }
        final loan = loansByLine[line];
        if (loan != null) {
          final targets = {
            for (final row in rows)
              if (row.state == EnrichRowState.willLink) row.target?.id,
          };
          for (final note in loan.equipment) {
            if (targets.contains(note.id)) continue;
            final matching = matches.where(
              (match) =>
                  match[1]!.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!) ==
                  note.id,
            );
            add(
              EnrichRowState.linked,
              matching.isEmpty ? note.title : matching.first[2]!,
              note,
              const [],
              null,
            );
          }
        }
        // Preserve input order for rows at the same position.
        final indexed = rows.indexed.toList();
        indexed.sort((a, b) {
          final aPos = a.$2.highlightStart < 0
              ? text.length + 1
              : a.$2.highlightStart;
          final bPos = b.$2.highlightStart < 0
              ? text.length + 1
              : b.$2.highlightStart;
          final order = aPos.compareTo(bPos);
          return order != 0 ? order : a.$1.compareTo(b.$1);
        });
        final sorted = [for (final entry in indexed) entry.$2];
        final count = rows
            .where((row) => row.state == EnrichRowState.willLink)
            .length;
        final signatures = [
          for (final row in rows)
            '${row.state.name}:${row.surface}:${row.target?.id ?? ''}',
        ]..sort();
        final conflict = loan == null ? null : openLoanFor(loan, openLoans);
        return EnrichLineCard(
          line: line,
          taskId: taskLines[line]?.$1,
          text: text,
          rows: sorted,
          loan: loan,
          due: loan?.due,
          warning: conflict == null ? null : loanOutSinceText(conflict),
          willLinkCount: count,
          primaryLabel: enrichPrimaryLabel(count, loan),
          key:
              '$line|${source.replaceAllMapped(markup, (match) => match[2]!).replaceFirst(RegExp(r'^\s*[-+*] '), '')}|${signatures.join('|')}|${loan != null}',
        );
      })(),
  ];
}

// A stale sidecar must never turn the beginning of a call into editable prose.
bool _startsUnclosedCall(String line) {
  final start = RegExp(r'^\s*#[\w.-]+\(').firstMatch(line);
  if (start == null) return false;
  return !locateTypstCalls(
    line,
    anyName: true,
  ).any((call) => call.start == line.indexOf('#'));
}
