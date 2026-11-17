import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  TaskRef task(String status) => TaskRef(
    id: 't',
    notePath: 'n.typ',
    text: 'loan',
    status: status,
    properties: const {
      'loan': true,
      'equipment': ['a', 'b'],
    },
  );
  String row(
    String at,
    String tag,
    String step,
    String status, [
    String reason = '',
  ]) =>
      '{"at":"2026-01-${at}T00:00:00Z","task":"t","tag":"$tag","step":"$step","status":"$status","reason":"$reason"}';
  test('latest result per tag and step determines state', () {
    final results = labResults([
      [
        row('02', 'a', 'out', 'recorded'),
        row('01', 'a', 'out', 'refused'),
        row('01', 'b', 'out', 'skipped'),
        'invalid',
        '{}',
      ].join('\n'),
      row('03', 'b', 'out', 'recorded'),
    ]);
    expect(results['t']!.stateFor(task('doing')), 'recorded');
    expect(results['t']!.stateFor(task('done')), 'pending');
    final refused = labResults([
      row('01', 'a', 'out', 'recorded'),
      row('02', 'a', 'return', 'refused', 'not on shelf'),
    ]);
    expect(refused['t']!.stateFor(task('done')), 'refused');
    expect(refused['t']!.reason, 'not on shelf');
    final returned = labResults([
      [
        for (final tag in ['a', 'b']) ...[
          row('01', tag, 'out', 'recorded'),
          row('02', tag, 'return', 'recorded'),
        ],
      ].join('\n'),
    ]);
    expect(returned['t']!.stateFor(task('done')), 'recorded');
    expect(labResults(['bad\n{}']), isEmpty);
  });
}
