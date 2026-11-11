import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/enrich_ledger_retry.dart';
import 'package:tylog_core/tylog_core.dart';

EnrichFeedback event(int number) => EnrichFeedback(
  surface: '$number',
  entity: '',
  accepted: true,
  note: '',
  at: '',
);

void main() {
  test(
    'retries unwritten events before new events and clears on success',
    () async {
      final retry = EnrichLedgerRetry();
      final written = <String>[];
      final failure = StateError('failed');
      final error = await retry.append(
        'ledger',
        [event(1), event(2), event(3)],
        (e) async {
          if (e.surface == '2') throw failure;
          written.add(e.surface);
        },
      );
      expect(error, same(failure));
      expect(written, ['1']);

      expect(
        await retry.append('other', [event(9)], (e) async {
          written.add(e.surface);
        }),
        isNull,
      );
      expect(
        await retry.append('ledger', [event(4)], (e) async {
          written.add(e.surface);
        }),
        isNull,
      );
      expect(written, ['1', '9', '2', '3', '4']);

      await retry.append('ledger', [event(5)], (e) async {
        written.add(e.surface);
      });
      expect(written, ['1', '9', '2', '3', '4', '5']);
    },
  );

  test('caps pending events at 500 by dropping the oldest', () async {
    final retry = EnrichLedgerRetry();
    await retry.append('ledger', [for (var i = 0; i < 503; i++) event(i)], (
      e,
    ) async {
      throw StateError('failed');
    });
    final written = <String>[];
    await retry.append('ledger', [], (e) async => written.add(e.surface));
    expect(written, [for (var i = 3; i < 503; i++) '$i']);
  });
}
