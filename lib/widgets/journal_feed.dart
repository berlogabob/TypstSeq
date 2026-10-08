import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models.dart';
import '../rich_editor.dart';
import '../vault.dart';
import 'date_format.dart';
import 'loading.dart';
import 'task_row.dart';
import 'task_fields.dart';

class JournalFeed extends StatefulWidget {
  const JournalFeed({
    super.key,
    this.events = const [],
    required this.vault,
    required this.index,
    required this.onOpenPath,
    this.resolveKind,
    this.onAtomTap,
    this.onSetStatus,
    this.onSetField,
  });

  final Future<void> Function(TaskRef, String)? onSetStatus;
  final Future<void> Function(TaskRef, String, String)? onSetField;
  final List<CalendarItem> events;
  final Vault? vault;
  final VaultIndex? index;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<String>? onAtomTap;

  /// Note kind behind a `#tylog.ref-note` target, for the chip icon. Supplied by
  /// the shell so it can use the retained [LinkResolver] — this used to be
  /// computed here, which meant building a whole-vault resolver per chip.
  final String? Function(String target)? resolveKind;

  @override
  State<JournalFeed> createState() => _JournalFeedState();
}

class _JournalFeedState extends State<JournalFeed> {
  Future<Uint8List?> _readAsset(String path) async {
    final v = widget.vault;
    if (v == null) return null;
    try {
      return await v.storage.readBytes(path.replaceFirst(RegExp(r'^/+'), ''));
    } catch (_) {
      return null;
    }
  }

  final sources = <String, Future<String>>{};
  final _loadedPaths = <String>{};
  final _scroll = ScrollController();
  int _visibleDays = 1;
  bool _growing = false;
  bool _bootstrapping = false;
  double _extentAtGrow = -1;

  // Growing past a day whose content hasn't loaded yet cascades: pending
  // rows render as tiny placeholders, so "near the bottom" stays true and
  // one fling would inflate the window to every day at once. Gate all
  // growth on the newest visible day having finished loading.
  bool _lastVisibleLoaded(List<NoteRef> days) {
    if (_visibleDays > days.length) return true;
    return days[_visibleDays - 1].path.isEmpty ||
        _loadedPaths.contains(days[_visibleDays - 1].path);
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(JournalFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vault != oldWidget.vault) {
      sources.clear();
      _visibleDays = 1;
    }
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Newest day first.
  ///
  /// Keyed on the day, never the path: a daily whose header omitted `date:`
  /// used to fall back to `daily/2026/08/...`, and `d` sorts above `2` — so a
  /// handful of undated notes pushed *today* six entries down a feed that
  /// loads one day at a time. The scanner now derives the day from the path,
  /// and this fallback keeps a stray null from ever outranking a real day.
  List<NoteRef> _days() {
    final days = (widget.index?.notes ?? const <NoteRef>[])
        .where((note) => note.kind == 'daily')
        .toList();
    return days..sort((a, b) => _dayKey(b).compareTo(_dayKey(a)));
  }

  List<CalendarItem> _eventsOn(String day) =>
      widget.events.where((e) => e.date == day).toList()
        ..sort((a, b) => (a.start ?? '').compareTo(b.start ?? ''));

  Widget _eventRow(CalendarItem event) => ListTile(
    dense: true,
    leading: const Icon(Icons.event),
    title: Text(event.title),
    subtitle: event.start == null
        ? null
        : Text(
            event.start!.contains('T')
                ? event.start!
                      .split('T')
                      .last
                      .substring(0, min(5, event.start!.split('T').last.length))
                : event.start!,
          ),
    onTap: () => widget.onOpenPath(event.notePath),
    trailing: event.notePath.startsWith('events/')
        ? IconButton(
            tooltip: 'Write about this',
            icon: const Icon(Icons.edit_note),
            onPressed: () => widget.onOpenPath(event.notePath),
          )
        : null,
  );

  static final _dayInPath = RegExp(r'(\d{4}-\d{2}-\d{2})\.typ$');

  static String _dayKey(NoteRef note) =>
      note.date ?? _dayInPath.firstMatch(note.path)?.group(1) ?? '';

  // Grows the window by one day at a time as the user nears the bottom of
  // the loaded content. `_growing` blocks re-entry until the frame that
  // applied the growth has actually rendered, so a burst of scroll events
  // (or the extra height the new day adds) can't trigger a second grow for
  // the same trigger.
  void _onScroll() {
    if (_growing || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.extentAfter >= 600) return;
    // The previous growth must be laid out before the next one: a freshly
    // added day renders as a tiny pending row at first, so "near the bottom"
    // stays true for several notifications and one fling would cascade
    // through many days. Once the day's content lands, maxScrollExtent jumps
    // past the latch and normal scrolling re-arms growth.
    if (position.maxScrollExtent <= _extentAtGrow + 1) return;
    final days = _days();
    if (_visibleDays >= days.length) return;
    if (!_lastVisibleLoaded(days)) return;
    _growing = true;
    _extentAtGrow = position.maxScrollExtent;
    setState(() => _visibleDays += 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _growing = false);
  }

  // Viewport bootstrap: a short "today" note may not fill the screen, so
  // there is nothing to scroll and `_onScroll` never fires. After each frame,
  // grow by one more day only while the list still isn't scrollable AND more
  // days remain — both conditions are re-checked every iteration, so this
  // terminates as soon as either goes false instead of free-running.
  void _scheduleBootstrapCheck() {
    if (_bootstrapping) return;
    _bootstrapping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapping = false;
      if (!mounted || !_scroll.hasClients) return;
      final days = _days();
      final canScroll = _scroll.position.maxScrollExtent > 0;
      final hasMore = _visibleDays < days.length;
      if (canScroll || !hasMore) return;
      if (!_lastVisibleLoaded(days)) {
        // Content still loading may yet fill the viewport; re-check after it
        // lands (the FutureBuilder's completion schedules a frame).
        _scheduleBootstrapCheck();
        return;
      }
      setState(() => _visibleDays += 1);
      _scheduleBootstrapCheck();
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _days();
    if (days.isEmpty) {
      return const Center(child: Text('No journal pages yet'));
    }
    final visible = min(_visibleDays, days.length);
    final hasMore = visible < days.length;
    _scheduleBootstrapCheck();
    return ListView.builder(
      key: const PageStorageKey('journal-feed'),
      controller: _scroll,
      itemCount: visible + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= visible) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: LoadingIndicator()),
          );
        }
        final day = days[index];
        final source = day.path.isEmpty
            ? Future.value('')
            : sources.putIfAbsent(
                day.path,
                // whenComplete registers before FutureBuilder subscribes, so the
                // loaded marker is set by the time the completion frame's
                // bootstrap/scroll checks run.
                () =>
                    widget.vault!.storage.readText(day.path)
                      ..whenComplete(() => _loadedPaths.add(day.path)),
              );
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: day.path.isEmpty ? null : () => widget.onOpenPath(day.path),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    day.date == null
                        ? day.title
                        : humanDate(DateTime.parse(day.date!)),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  // Collapsed: a term of recurring classes used to bury the
                  // day's own text under a screen of rows.
                  if (_eventsOn(_dayKey(day)) case final events
                      when events.isNotEmpty)
                    ExpansionTile(
                      dense: true,
                      tilePadding: EdgeInsets.zero,
                      shape: const Border(),
                      title: Text('Agenda · ${events.length}'),
                      children: [for (final e in events) _eventRow(e)],
                    ),
                  const Divider(),
                  FutureBuilder<String>(
                    future: source,
                    builder: (context, snapshot) {
                      if (day.path.isEmpty) return const SizedBox.shrink();
                      if (!snapshot.hasData) {
                        return const LinearProgressIndicator();
                      }
                      if (TyLogDocument.parse(
                        snapshot.data!,
                      ).visibleText.trim().isEmpty) {
                        return TextButton.icon(
                          onPressed: () => widget.onOpenPath(day.path),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Start writing…'),
                        );
                      }
                      return TyLogReadView(
                        source: snapshot.data!,
                        taskBuilder: (source) {
                          final parsed = taskFromSource(
                            source,
                            notePath: day.path,
                          );
                          final task =
                              widget.index?.tasks
                                  .where(
                                    (t) =>
                                        t.id == parsed.id &&
                                        t.notePath == day.path,
                                  )
                                  .firstOrNull ??
                              parsed;
                          return TaskRow(
                            task: task,
                            onOpenPath: widget.onOpenPath,
                            onSetStatus: widget.onSetStatus,
                            onSetField: widget.onSetField,
                          );
                        },
                        imageResolver: _readAsset,
                        resolveKind: widget.resolveKind,
                        onAtomTap: widget.onAtomTap,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
