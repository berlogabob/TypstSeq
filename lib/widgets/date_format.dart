import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

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

String compactHumanDate(DateTime day, {DateTime? now, String? locale}) {
  initializeDateFormatting();
  final language = Intl.verifiedLocale(
    locale ?? WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
    DateFormat.localeExists,
    onFailure: (_) => 'en',
  );
  return day.year == (now ?? DateTime.now()).year
      ? DateFormat('EEE d MMM', language).format(day)
      : DateFormat('d MMM y', language).format(day);
}

/// A stored timestamp for status lines: 'today 03:01' or '8 Oct 09:05' in
/// local time; text that is not a timestamp is returned as is.
String shortStamp(String raw, {DateTime? now}) {
  final at = DateTime.tryParse(raw)?.toLocal();
  if (at == null) return raw;
  final today = now ?? DateTime.now();
  final hm = DateFormat('HH:mm').format(at);
  return at.year == today.year && at.month == today.month && at.day == today.day
      ? 'today $hm'
      : '${DateFormat('d MMM').format(at)} $hm';
}

class CompactDateTitle extends StatelessWidget {
  const CompactDateTitle({super.key, required this.day, this.dirty = false});
  final DateTime day;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final label = compactHumanDate(day);
    // Another year goes on its own line: the app-bar slot can be ~64 dp, and
    // one line '29 Mar 2023' scaled down to a quarter of its size.
    final year = ' ${day.year}';
    final text = label.endsWith(year)
        ? '${label.substring(0, label.length - year.length)}\n${day.year}'
        : label;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '$text${dirty ? ' •' : ''}',
        maxLines: 2,
        textAlign: TextAlign.center,
        // Two lines at the small title size fit the bar without shrinking.
        style: identical(text, label)
            ? null
            : Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

String monthYear(DateTime day) => '${_monthNames[day.month - 1]} ${day.year}';

String monthDay(DateTime day) =>
    '${_monthNames[day.month - 1].substring(0, 3)} ${day.day}';
