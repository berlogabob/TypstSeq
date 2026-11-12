/// Parses an explicitly stated loan return date relative to the note's day.
String? parseLoanDue(String line, DateTime noteDate) {
  final text = line.toLowerCase();
  final base = DateTime.utc(noteDate.year, noteDate.month, noteDate.day);
  final wordBefore = RegExp(r'[\p{L}\p{M}\p{N}_]$', unicode: true);
  final wordAfter = RegExp(r'^[\p{L}\p{M}\p{N}_]', unicode: true);
  final weekdays = <String, int>{
    for (final names in [
      ['monday', 'mon', 'segunda', 'понедельника'],
      ['tuesday', 'tue', 'terça', 'terca', 'вторника'],
      ['wednesday', 'wed', 'quarta', 'среды'],
      ['thursday', 'thu', 'quinta', 'четверга'],
      ['friday', 'fri', 'sexta', 'пятницы'],
      ['saturday', 'sat', 'sábado', 'sabado', 'субботы'],
      ['sunday', 'sun', 'domingo', 'воскресенья'],
    ].indexed)
      for (final name in names.$2) name: names.$1 + 1,
  };
  final months = <String, int>{
    for (final names in [
      ['january', 'jan', 'janeiro', 'января'],
      ['february', 'feb', 'fevereiro', 'февраля'],
      ['march', 'mar', 'março', 'marco', 'марта'],
      ['april', 'apr', 'abril', 'апреля'],
      ['may', 'maio', 'мая'],
      ['june', 'jun', 'junho', 'июня'],
      ['july', 'jul', 'julho', 'июля'],
      ['august', 'aug', 'agosto', 'августа'],
      ['september', 'sep', 'setembro', 'сентября'],
      ['october', 'oct', 'outubro', 'октября'],
      ['november', 'nov', 'novembro', 'ноября'],
      ['december', 'dec', 'dezembro', 'декабря'],
    ].indexed)
      for (final name in names.$2) name: names.$1 + 1,
  };
  DateTime? checked(int year, int month, int day) {
    if (day < 1 || day > 31) return null;
    final date = DateTime.utc(year, month, day);
    return date.month == month && date.day == day ? date : null;
  }

  DateTime? monthDay(int day, int month) {
    var date = checked(base.year, month, day);
    if (date == null) return null;
    if (!date.isAfter(base)) date = checked(base.year + 1, month, day);
    return date;
  }

  var first = text.length + 1;
  var longest = 0;
  DateTime? result;
  void find(String pattern, DateTime? Function(Match) resolve) {
    for (final match in RegExp(pattern, unicode: true).allMatches(text)) {
      if ((match.start > 0 &&
              wordBefore.hasMatch(text.substring(0, match.start))) ||
          (match.end < text.length &&
              wordAfter.hasMatch(text.substring(match.end)))) {
        continue;
      }
      if (match.start < first ||
          (match.start == first && match.end - match.start > longest)) {
        first = match.start;
        longest = match.end - match.start;
        result = resolve(match);
      }
    }
  }

  String alternatives(Iterable<String> names) =>
      (names.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|');
  final englishWeekdays = alternatives(
    weekdays.keys.where(
      (n) =>
          RegExp(r'^[a-z]+$').hasMatch(n) &&
          !{
            'segunda',
            'terca',
            'quarta',
            'quinta',
            'sexta',
            'sabado',
            'domingo',
          }.contains(n),
    ),
  );
  final portugueseWeekdays = alternatives([
    'segunda',
    'terça',
    'terca',
    'quarta',
    'quinta',
    'sexta',
    'sábado',
    'sabado',
    'domingo',
  ]);
  final russianWeekdays = alternatives(
    weekdays.keys.where((n) => RegExp(r'^[а-я]+$', unicode: true).hasMatch(n)),
  );
  final englishMonths = alternatives(
    months.keys.where(
      (n) => {
        'january',
        'jan',
        'february',
        'feb',
        'march',
        'mar',
        'april',
        'apr',
        'may',
        'june',
        'jun',
        'july',
        'jul',
        'august',
        'aug',
        'september',
        'sep',
        'october',
        'oct',
        'november',
        'nov',
        'december',
        'dec',
      }.contains(n),
    ),
  );
  final portugueseMonths = alternatives([
    'janeiro',
    'fevereiro',
    'março',
    'marco',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ]);
  final russianMonths = alternatives(
    months.keys.where((n) => RegExp(r'^[а-я]+$', unicode: true).hasMatch(n)),
  );
  find(
    r'(?:(?:until|till|by)\s+tomorrow|(?:até|ate)\s+amanh[ãa]|до\s+завтра)',
    (_) => base.add(const Duration(days: 1)),
  );
  find(
    '(?:until|till|by)\\s+($englishWeekdays)|(?:até|ate)\\s+($portugueseWeekdays)(?:-feira)?|до\\s+($russianWeekdays)',
    (m) {
      final delta = (weekdays[m[1] ?? m[2] ?? m[3]]! - base.weekday + 7) % 7;
      return base.add(Duration(days: delta == 0 ? 7 : delta));
    },
  );
  find(
    '(?:until|till|by)\\s+(\\d{1,2})(?:st|nd|rd|th)?\\s+($englishMonths)',
    (m) => monthDay(int.parse(m[1]!), months[m[2]]!),
  );
  find(
    '(?:until|till|by)\\s+($englishMonths)\\s+(\\d{1,2})(?:st|nd|rd|th)?',
    (m) => monthDay(int.parse(m[2]!), months[m[1]]!),
  );
  find(
    '(?:até|ate)\\s+(\\d{1,2})\\s+de\\s+($portugueseMonths)',
    (m) => monthDay(int.parse(m[1]!), months[m[2]]!),
  );
  find(
    'до\\s+(\\d{1,2})\\s+($russianMonths)',
    (m) => monthDay(int.parse(m[1]!), months[m[2]]!),
  );
  find(r'(?:até|ate)\s+dia\s+(\d{1,2})|до\s+(\d{1,2})(?!\s+[\p{L}\p{M}])', (m) {
    final day = int.parse(m[1] ?? m[2]!);
    final target = DateTime.utc(
      base.year,
      base.month + (day > base.day ? 0 : 1),
    );
    return checked(target.year, target.month, day);
  });
  find(
    r'(?:for\s+(\d+)\s+(days?|weeks?)|por\s+(\d+)\s+(dias|semanas)|на\s+(\d+)\s+(день|дня|дней|недели|недель))',
    (m) {
      final count = int.tryParse(m[1] ?? m[3] ?? m[5]!);
      if (count == null || count < 1 || count > 365) return null;
      final unit = m[2] ?? m[4] ?? m[6]!;
      final weeks =
          unit.startsWith('week') ||
          unit.startsWith('semana') ||
          unit.startsWith('недел');
      return base.add(Duration(days: count * (weeks ? 7 : 1)));
    },
  );
  find(
    r'(?:for\s+(?:a|one)\s+day|for\s+a\s+week|por\s+uma\s+semana|на\s+неделю)',
    (m) => base.add(Duration(days: m[0]!.endsWith('day') ? 1 : 7)),
  );
  if (first > text.length &&
      RegExp(
        r'\bweekend\b|\bfim\s+de\s+semana\b|на\s+выходные',
        unicode: true,
      ).hasMatch(text) &&
      !RegExp(
        r'\d{1,4}[-/.]\d{1,2}(?:[-/.]\d{1,4})?',
        unicode: true,
      ).hasMatch(text) &&
      !RegExp(
        '\\b\\d{1,2}(?:st|nd|rd|th)?\\s+(?:${alternatives(months.keys)})|(?:${alternatives(months.keys)})\\s+\\d{1,2}',
        unicode: true,
      ).hasMatch(text)) {
    final delta = (DateTime.monday - base.weekday + 7) % 7;
    result = base.add(Duration(days: delta == 0 ? 7 : delta));
  }
  if (result == null) return null;
  return '${result!.year.toString().padLeft(4, '0')}-${result!.month.toString().padLeft(2, '0')}-${result!.day.toString().padLeft(2, '0')}';
}
