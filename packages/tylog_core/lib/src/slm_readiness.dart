/// When is a class ready to be handed from the general model to a small one?
///
/// Every enrichment decision is about one entity, and the entity's kind gives
/// its class, so the feedback ledger is already tagged by class. A class is
/// suggested once its ledger is large and varied enough; nothing switches
/// without the user accepting, and the answer is a [Decision] row.
library;

import 'attention.dart';
import 'enrich.dart';
import 'models.dart';
import 'ontology.dart';

/// Calibration knobs, not measured values: the smallest ledger worth fitting
/// or evaluating a small model on. Tune once a first class gets close.
const kSlmMinDecisions = 200;
const kSlmMinEntities = 20;

const slmDecisionSource = 'slm';
String slmDecisionItem(String kind) => 'slm:$kind';

class ClassReadiness {
  const ClassReadiness({
    required this.kind,
    required this.pages,
    required this.accepts,
    required this.rejects,
    required this.entities,
  });

  /// The top class under the ontology root: a `lab` counts towards `place`.
  final String kind;

  /// Entity notes of this class in the vault.
  final int pages;
  final int accepts;
  final int rejects;

  /// Distinct entities the decisions are about.
  final int entities;

  /// What still keeps the class from being suggested; empty when ready.
  List<String> get missing => [
    if (accepts + rejects < kSlmMinDecisions)
      '${kSlmMinDecisions - accepts - rejects} more decisions',
    if (entities < kSlmMinEntities)
      '${kSlmMinEntities - entities} more distinct entities',
    if (rejects == 0) 'at least one rejection',
  ];

  bool get ready => missing.isEmpty;
}

/// One row per class that has entity notes or decisions, busiest first.
List<ClassReadiness> classReadiness(
  VaultIndex index,
  Iterable<EnrichFeedback> feedback,
  Ontology ontology,
) {
  String top(String kind) {
    final lineage = ontology.lineage(kind);
    final root = lineage.indexOf('thing');
    return root > 0 ? lineage[root - 1] : lineage.first;
  }

  final kindById = <String, String>{};
  final pages = <String, int>{};
  for (final note in index.notes) {
    if (!isEnrichTarget(note, ontology) || note.kind == 'note') continue;
    final kind = top(note.kind);
    kindById[note.id] = kind;
    pages[kind] = (pages[kind] ?? 0) + 1;
  }
  final accepts = <String, int>{};
  final rejects = <String, int>{};
  final entities = <String, Set<String>>{};
  for (final event in feedback) {
    final kind = kindById[event.entity];
    if (kind == null || event.shown) continue;
    final counts = event.accepted ? accepts : rejects;
    counts[kind] = (counts[kind] ?? 0) + 1;
    (entities[kind] ??= {}).add(event.entity);
  }
  return [
    for (final kind in pages.keys)
      ClassReadiness(
        kind: kind,
        pages: pages[kind]!,
        accepts: accepts[kind] ?? 0,
        rejects: rejects[kind] ?? 0,
        entities: entities[kind]?.length ?? 0,
      ),
  ]..sort((a, b) => (b.accepts + b.rejects).compareTo(a.accepts + a.rejects));
}

/// Ready classes the user has not answered yet: the cards to show.
List<ClassReadiness> slmSuggestions(
  Iterable<ClassReadiness> readiness,
  Iterable<Decision> decisions,
) {
  final answered = {
    for (final decision in decisions)
      if (decision.source == slmDecisionSource &&
          const {'accepted', 'rejected'}.contains(decision.action))
        decision.item,
  };
  return [
    for (final row in readiness)
      if (row.ready && !answered.contains(slmDecisionItem(row.kind))) row,
  ];
}

String slmReadinessReport(Iterable<ClassReadiness> readiness) {
  final out = StringBuffer(
    '| Class | pages | accepts | rejects | entities | ready | missing |\n'
    '| --- | ---: | ---: | ---: | ---: | --- | --- |\n',
  );
  for (final row in readiness) {
    out.writeln(
      '| ${row.kind} | ${row.pages} | ${row.accepts} | ${row.rejects} | '
      '${row.entities} | ${row.ready ? 'yes' : 'no'} | '
      '${row.missing.join('; ')} |',
    );
  }
  out.writeln(
    '\nReady = at least $kSlmMinDecisions decisions about '
    '$kSlmMinEntities distinct entities, with at least one rejection.',
  );
  return out.toString();
}
