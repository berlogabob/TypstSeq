const _relative = [
  'today сегодня hoje',
  'tomorrow завтра amanhã',
  'yesterday вчера ontem',
];
const _weekdays = [
  'monday mon понедельник пн segunda segunda-feira seg',
  'tuesday tue вторник вт terça terça-feira ter',
  'wednesday wed среда ср quarta quarta-feira qua',
  'thursday thu четверг чт quinta quinta-feira qui',
  'friday fri пятница пт sexta sexta-feira sex',
  'saturday sat суббота сб sábado sáb sab',
  'sunday sun воскресенье вс domingo dom',
];
const _months = [
  'january jan январь января янв janeiro',
  'february feb февраль февраля фев fevereiro fev',
  'march mar март марта мар março',
  'april apr апрель апреля апр abril abr',
  'may май мая maio',
  'june jun июнь июня июн junho',
  'july jul июль июля июл julho',
  'august aug август августа авг agosto ago',
  'september sep sept сентябрь сентября сен сент setembro set',
  'october oct октябрь октября окт outubro out',
  'november nov ноябрь ноября ноя novembro',
  'december dec декабрь декабря дек dezembro dez',
];
const _units = {
  'd': 1,
  'day': 1,
  'days': 1,
  'день': 1,
  'дня': 1,
  'дней': 1,
  'dia': 1,
  'dias': 1,
  'w': 7,
  'week': 7,
  'weeks': 7,
  'неделя': 7,
  'неделю': 7,
  'недели': 7,
  'недель': 7,
  'semana': 7,
  'semanas': 7,
};

/// Parses date suggestions relative to [now], best first; returns empty for unrecognized text.
List<DateTime> parseDateWords(String text, DateTime now) {
  var input = text.trim().toLowerCase();
  if (input.isEmpty) return [];
  var hour = 0;
  var minute = 0;
  final time = RegExp(r'\s+(\d{1,2}):(\d{2})$').firstMatch(input);
  if (time != null) {
    hour = int.parse(time[1]!);
    minute = int.parse(time[2]!);
    if (hour > 23 || minute > 59) return [];
    input = input.substring(0, time.start).trim();
  }

  DateTime offset(int days) =>
      DateTime(now.year, now.month, now.day + days, hour, minute);

  final words = <String, int>{};
  for (var i = 0; i < _relative.length; i++) {
    for (final word in _relative[i].split(' ')) {
      words[word] = [0, 1, -1][i];
    }
  }
  for (var i = 0; i < _weekdays.length; i++) {
    final days = (i + 1 - now.weekday) % 7;
    for (final word in _weekdays[i].split(' ')) {
      words[word] = days == 0 ? 7 : days;
    }
  }
  if (words.containsKey(input)) return [offset(words[input]!)];
  if (input.length >= 2) {
    final matches = words.entries
        .where((entry) => entry.key.startsWith(input))
        .map((entry) => entry.value)
        .toSet();
    if (matches.length == 1) return [offset(matches.single)];
  }

  final relative = RegExp(
    r'^(?:\+(\d+)([dw])|(?:in|через|em)\s+(\d+)\s+(\S+))$',
  ).firstMatch(input);
  if (relative != null) {
    final count = int.tryParse(relative[1] ?? relative[3]!);
    final unit = _units[relative[2] ?? relative[4]!];
    if (count == null || unit == null) return [];
    return [offset(count * unit)];
  }

  var year = now.year;
  int? month;
  int? day;
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(input);
  final dotted = RegExp(
    r'^(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?$',
  ).firstMatch(input);
  final named = RegExp(r'^(\d{1,2})\s+(\S+)$').firstMatch(input);
  if (iso != null) {
    year = int.parse(iso[1]!);
    month = int.parse(iso[2]!);
    day = int.parse(iso[3]!);
  } else if (dotted != null) {
    day = int.parse(dotted[1]!);
    month = int.parse(dotted[2]!);
    year = dotted[3] == null ? now.year : int.parse(dotted[3]!);
  } else if (named != null) {
    day = int.parse(named[1]!);
    for (var i = 0; i < _months.length; i++) {
      if (_months[i].split(' ').contains(named[2])) month = i + 1;
    }
  }
  if (month == null || day == null) return [];
  final date = DateTime(year, month, day, hour, minute);
  // DateTime normalizes impossible dates into the following month.
  return date.year == year && date.month == month && date.day == day
      ? [date]
      : [];
}
