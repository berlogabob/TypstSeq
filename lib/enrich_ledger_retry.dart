import 'package:tylog_core/tylog_core.dart';

class EnrichLedgerRetry {
  final Map<String, List<EnrichFeedback>> _pending = {};

  Future<Object?> append(
    String ledger,
    List<EnrichFeedback> events,
    Future<void> Function(EnrichFeedback event) write,
  ) async {
    final combined = [...?_pending[ledger], ...events];
    for (var i = 0; i < combined.length; i++) {
      try {
        await write(combined[i]);
      } catch (error) {
        final start = combined.length - i > 500 ? combined.length - 500 : i;
        _pending[ledger] = combined.sublist(start);
        return error;
      }
    }
    _pending.remove(ledger);
    return null;
  }
}
