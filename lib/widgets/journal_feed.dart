import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../models.dart';
import '../rich_editor.dart';
import '../vault.dart';
import 'date_format.dart';
import 'loading.dart';

class JournalFeed extends StatefulWidget {
  const JournalFeed({
    super.key,
    required this.vault,
    required this.index,
    required this.onOpenPath,
  });

  final Vault? vault;
  final VaultIndex? index;
  final ValueChanged<String> onOpenPath;

  @override
  State<JournalFeed> createState() => _JournalFeedState();
}

class _JournalFeedState extends State<JournalFeed> {
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
    return _loadedPaths.contains(days[_visibleDays - 1].path);
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

  List<NoteRef> _days() =>
      (widget.index?.notes ?? const <NoteRef>[])
          .where((note) => note.kind == 'daily')
          .toList()
        ..sort((a, b) => (b.date ?? b.path).compareTo(a.date ?? a.path));

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
        final source = sources.putIfAbsent(
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
            onTap: () => widget.onOpenPath(day.path),
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
                  const Divider(),
                  FutureBuilder<String>(
                    future: source,
                    builder: (context, snapshot) => snapshot.hasData
                        ? TyLogReadView(source: snapshot.data!)
                        : const LinearProgressIndicator(),
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
