String isoDay(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Mon, July 6"; the year is appended only when it is not the current year.
// ponytail: English-only names, add intl if localization is ever needed.
String humanDate(DateTime day, {DateTime? now}) {
  final label =
      '${_weekdayNames[day.weekday - 1]}, ${_monthNames[day.month - 1]} ${day.day}';
  return day.year == (now ?? DateTime.now()).year
      ? label
      : '$label, ${day.year}';
}

String compactHumanDate(DateTime day) =>
    '${_weekdayNames[day.weekday - 1]}, ${_monthNames[day.month - 1].substring(0, 3)} ${day.day}';
