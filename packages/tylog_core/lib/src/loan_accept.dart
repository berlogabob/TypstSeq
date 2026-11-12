import 'enrich.dart';
import 'loan.dart';
import 'models.dart';

Future<bool> acceptLoan({
  required String path,
  required EnrichLoanOffer offer,
  required TaskRef? conflict,
  required String Function() noteId,
  required DateTime Function() now,
  required Future<bool> Function(TaskRef) confirmDouble,
  required Future<void> Function() recordFeedback,
  required Future<String> Function() readSource,
  required Future<EnrichMentions?> Function() readMentions,
  required Future<bool> Function(String Function(String)) mutateNote,
  required bool Function(String) mutationIsCurrent,
  required Future<Map<String, Object?>> Function() readSidecar,
  required Future<void> Function(Map<String, Object?>) writeSidecar,
}) async {
  if (conflict != null && !await confirmDouble(conflict)) return false;
  await recordFeedback();
  final source = await readSource();
  final mentions = await readMentions();
  final tracked = trackAsLoan(
    source,
    offer,
    loanTaskId(noteId(), offer),
    now(),
  );
  if (tracked != source &&
      await mutateNote((current) => current == source ? tracked : current) &&
      mutationIsCurrent(tracked) &&
      mentions != null &&
      enrichContentSha(source) == mentions.contentSha) {
    final shifted = consumeEnrichLine(
      await readSidecar(),
      offer.line,
      tracked.split('\n').length - source.split('\n').length,
    );
    shifted['content_sha'] = enrichContentSha(tracked);
    await writeSidecar(shifted);
  }
  return true;
}
