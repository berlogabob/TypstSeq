import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

// ignore: avoid_print
void Function(String) jankSink = print;

bool _started = false;

void startJankMonitor({bool force = false}) {
  if (_started ||
      !(kProfileMode || force || const bool.fromEnvironment('TYLOG_JANK'))) {
    return;
  }
  _started = true;
  final sinceStart = Stopwatch()..start();
  final sinceTick = Stopwatch()..start();
  jankSink('TYLOG_JANK start');

  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final timing in timings) {
      if (timing.totalSpan > const Duration(milliseconds: 100)) {
        jankSink(
          'TYLOG_JANK frame build=${timing.buildDuration.inMilliseconds}ms '
          'raster=${timing.rasterDuration.inMilliseconds}ms '
          'total=${timing.totalSpan.inMilliseconds}ms '
          't=${sinceStart.elapsedMilliseconds}ms',
        );
      }
    }
  });

  Timer.periodic(const Duration(milliseconds: 50), (_) {
    final elapsed = sinceTick.elapsed;
    sinceTick.reset();
    if (elapsed > const Duration(milliseconds: 250)) {
      jankSink(
        'TYLOG_JANK stall isolate=${elapsed.inMilliseconds}ms '
        't=${sinceStart.elapsedMilliseconds}ms',
      );
    }
  });
}
