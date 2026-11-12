import 'enrich.dart';
import 'loan.dart';
import 'models.dart';

enum EnrichRowState { linked, willLink, ambiguous, propose }

String enrichTargetLabel(String shortTitle, Object? color) =>
    color is String && color.isNotEmpty ? '$shortTitle · $color' : shortTitle;

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
  final String text;
  final List<EnrichCardRow> rows;
  final EnrichLoanOffer? loan;
  final String? due;
  final String? warning;
  final int willLinkCount;
  final String? primaryLabel;
  final String key;
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
  final byLine = <int, List<EnrichDecision>>{};
  final loansByLine = <int, EnrichLoanOffer>{};
  for (final decision in decisions) {
    final line = decision.mention.line;
    if (line >= 1 && line <= lines.length) {
      (byLine[line] ??= []).add(decision);
    }
  }
  for (final loan in loans) {
    if (loan.line >= 1 && loan.line <= lines.length) {
      loansByLine[loan.line] = loan;
    }
  }
  final numbers = {...byLine.keys, ...loansByLine.keys}.toList()..sort();
  final markup = RegExp(r'#tylog\.ref-note\("((?:\\.|[^"\\])*)"\)\[([^\]]*)\]');
  return [
    for (final line in numbers)
      (() {
        final source = lines[line - 1];
        final matches = markup.allMatches(source).toList();
        final text = source
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
          final start = surface.isEmpty
              ? -1
              : text.toLowerCase().indexOf(surface.toLowerCase());
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
          text: text,
          rows: sorted,
          loan: loan,
          due: loan?.due,
          warning: conflict == null ? null : loanOutSinceText(conflict),
          willLinkCount: count,
          primaryLabel: enrichPrimaryLabel(count, loan),
          key: '$line|$text|${signatures.join('|')}|${loan != null}',
        );
      })(),
  ];
}
