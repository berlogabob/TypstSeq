import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  // Thursday; date-only suggestions use local midnight, not the current time.
  final now = DateTime(2026, 10, 8, 10, 45);
  final relative = <(String, int)>[
    ('today', 0), ('tomorrow', 1), ('yesterday', -1),
    ('сегодня', 0), ('завтра', 1), ('вчера', -1),
    ('hoje', 0), ('amanhã', 1), ('ontem', -1),
    ('+3d', 3), ('+2w', 14), ('in 2 weeks', 14), ('in 3 days', 3),
    ('через 2 дня', 2), ('через 1 день', 1), ('через 5 дней', 5),
    ('через 2 недели', 14), ('em 2 dias', 2), ('em 1 dia', 1),
    ('em 2 semanas', 14),
    // Unambiguous prefixes must work in the suggestion list.
    ('зав', 1), ('tom', 1), ('amanh', 1),
    ('  TOMORROW  ', 1), ('ЗАВТРА', 1), ('HOJE', 0),
  ];
  for (final (text, days) in relative) {
    test('relative date: $text', () {
      final expected = DateTime(2026, 10, 8 + days);
      final candidates = parseDateWords(text, now);
      expect(candidates, isNotEmpty);
      expect(candidates.first, expected);
      expect(candidates.toSet().length, candidates.length);
    });
  }

  final weekdays = <(List<String>, int)>[
    (
      ['monday', 'mon', 'понедельник', 'пн', 'segunda', 'seg', 'segunda-feira'],
      4,
    ),
    (['tuesday', 'tue', 'вторник', 'вт', 'terça', 'ter', 'terça-feira'], 5),
    (['wednesday', 'wed', 'среда', 'ср', 'quarta', 'qua', 'quarta-feira'], 6),
    (['thursday', 'thu', 'четверг', 'чт', 'quinta', 'qui', 'quinta-feira'], 7),
    (['friday', 'fri', 'пятница', 'пт', 'sexta', 'sex', 'sexta-feira'], 1),
    (['saturday', 'sat', 'суббота', 'сб', 'sábado', 'sáb'], 2),
    (['sunday', 'sun', 'воскресенье', 'вс', 'domingo', 'dom'], 3),
  ];
  for (final (words, days) in weekdays) {
    for (final word in words) {
      test('next weekday: $word', () {
        expect(parseDateWords(word, now).first, DateTime(2026, 10, 8 + days));
      });
    }
  }

  for (final text in [
    '15 oct',
    '15 october',
    '15 окт',
    '15 октября',
    '15 out',
    '15 outubro',
    '15.10',
    '15.10.2026',
    '2026-10-15',
  ]) {
    test('calendar date: $text', () {
      expect(parseDateWords(text, now).first, DateTime(2026, 10, 15));
    });
    test('calendar date and time: $text 14:30', () {
      expect(
        parseDateWords('$text 14:30', now).first,
        DateTime(2026, 10, 15, 14, 30),
      );
    });
  }
  for (final (text, days) in <(String, int)>[
    ('today', 0),
    ('tomorrow', 1),
    ('fri', 1),
    ('+3d', 3),
    ('+2w', 14),
    ('in 2 weeks', 14),
    ('сегодня', 0),
    ('зав', 1),
    ('пн', 4),
    ('через 2 дня', 2),
    ('hoje', 0),
    ('amanhã', 1),
    ('seg', 4),
    ('em 2 dias', 2),
  ]) {
    test('relative date and time: $text 14:30', () {
      expect(
        parseDateWords('$text 14:30', now).first,
        DateTime(2026, 10, 8 + days, 14, 30),
      );
    });
  }

  for (final text in [
    '',
    '   ',
    'garbage',
    'not a date',
    'абракадабра',
    'sem data',
    '31.02.2026',
    '2026-13-15',
    '15.10.2026 25:00',
    'tomorrow 14:99',
  ]) {
    test('unrecognized or invalid: "$text"', () {
      expect(parseDateWords(text, now), isEmpty);
    });
  }
}
