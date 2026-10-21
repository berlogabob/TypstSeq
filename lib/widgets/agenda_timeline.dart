import 'dart:async';

import 'package:flutter/material.dart';

import 'constants.dart';

const kAgendaRowHeight = 56.0;
const _timeWidth = 48.0;

class AgendaEntry {
  const AgendaEntry({
    required this.start,
    this.end,
    required this.title,
    this.detail,
    this.onTap,
  });

  final DateTime start;
  final DateTime? end;
  final String title;

  /// A short second line, e.g. the room.
  final String? detail;
  final VoidCallback? onTap;
}

/// A day's events in time order: a time column, a thin rail with a dot per
/// event, the running event tinted, and a "now" dot that moves along the rail.
class AgendaTimeline extends StatefulWidget {
  const AgendaTimeline({
    super.key,
    required this.entries,
    this.now,
    this.showNow = true,
  });

  final List<AgendaEntry> entries;

  /// Clock for tests; defaults to [DateTime.now].
  final DateTime Function()? now;

  /// False for days other than today.
  final bool showNow;

  @override
  State<AgendaTimeline> createState() => _AgendaTimelineState();
}

class _AgendaTimelineState extends State<AgendaTimeline> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Centre of the now dot in list coordinates.
  static double _nowY(List<AgendaEntry> entries, DateTime now) {
    const h = kAgendaRowHeight;
    double fraction(DateTime from, DateTime to) {
      final span = to.difference(from).inSeconds;
      return span <= 0
          ? 0
          : (now.difference(from).inSeconds / span).clamp(0.0, 1.0);
    }

    if (now.isBefore(entries.first.start)) return kSpace4;
    final last = entries.last;
    if (!now.isBefore(last.start)) {
      final end = last.end;
      return end != null && now.isBefore(end)
          ? (entries.length - 1) * h + h / 2 + fraction(last.start, end) * h / 2
          : entries.length * h - kSpace4;
    }
    for (var i = 0; i + 1 < entries.length; i++) {
      if (!now.isBefore(entries[i].start) &&
          now.isBefore(entries[i + 1].start)) {
        return i * h +
            h / 2 +
            fraction(entries[i].start, entries[i + 1].start) * h;
      }
    }
    return kSpace4;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final now = (widget.now ?? DateTime.now)();
    final entries = [...widget.entries]
      ..sort((a, b) => a.start.compareTo(b.start));
    if (entries.isEmpty) return const SizedBox.shrink();
    final current = entries.indexWhere(
      (e) => !now.isBefore(e.start) && e.end != null && now.isBefore(e.end!),
    );
    const railX = _timeWidth + kSpace16 / 2;

    Widget row(int i) {
      final entry = entries[i];
      final past = !(entry.end ?? entry.start).isAfter(now);
      final detail = entry.detail?.trim() ?? '';
      final content = SizedBox(
        height: kAgendaRowHeight,
        child: Row(
          children: [
            SizedBox(
              width: _timeWidth,
              // Rows keep a fixed height (the now dot is placed by it): large
              // system font sizes scale the text down instead of overflowing.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_hm(entry.start), style: text.bodyMedium),
                    if (entry.end case final end?)
                      Text(
                        _hm(end),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: kSpace16,
              child: Center(
                child: Container(
                  width: kSpace8,
                  height: kSpace8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: past ? scheme.outline : scheme.surface,
                    border: Border.all(color: scheme.outline),
                  ),
                ),
              ),
            ),
            Expanded(
              // The real width stays inside the box, so a long title ends in
              // an ellipsis and only an over-tall pair of lines scales down.
              child: LayoutBuilder(
                builder: (context, box) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: box.maxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            color: past ? scheme.onSurfaceVariant : null,
                          ),
                        ),
                        if (detail.isNotEmpty)
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      return InkWell(
        key: i == current ? const ValueKey('agenda-current') : null,
        borderRadius: BorderRadius.circular(kRadiusSmall),
        onTap: entry.onTap,
        child: i == current
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                ),
                child: content,
              )
            : content,
      );
    }

    return Stack(
      children: [
        Positioned(
          left: railX - 1,
          top: kSpace4,
          bottom: kSpace4,
          width: 2,
          child: ColoredBox(color: scheme.outlineVariant),
        ),
        Column(children: [for (var i = 0; i < entries.length; i++) row(i)]),
        if (widget.showNow)
          Positioned(
            key: const ValueKey('agenda-now-dot'),
            left: railX - 5,
            top: _nowY(entries, now) - 5,
            width: 10,
            height: 10,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
