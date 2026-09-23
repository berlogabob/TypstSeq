import 'dart:ui';

/// Stage budget violations and frame latency are different measurements:
/// https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html
Map<String, num> editorFrameMetrics(
  List<FrameTiming> timings, {
  required double refreshRate,
}) {
  if (timings.isEmpty || !refreshRate.isFinite || refreshRate <= 0) {
    throw ArgumentError(
      'Frame samples and a positive refresh rate are required',
    );
  }
  final budgetUs = 1000000 / refreshRate;
  final build = timings.map((t) => t.buildDuration.inMicroseconds).toList()
    ..sort();
  final raster = timings.map((t) => t.rasterDuration.inMicroseconds).toList()
    ..sort();
  final span = timings.map((t) => t.totalSpan.inMicroseconds).toList()..sort();
  double p95(List<int> samples) =>
      samples[(samples.length * 0.95).ceil() - 1] / 1000;
  final overBudget = timings
      .where(
        (t) =>
            t.buildDuration.inMicroseconds > budgetUs ||
            t.rasterDuration.inMicroseconds > budgetUs,
      )
      .length;
  return {
    'refresh_hz': refreshRate,
    'budget_ms': budgetUs / 1000,
    'frames': timings.length,
    'over_budget': overBudget,
    'over_budget_pct': overBudget * 100 / timings.length,
    'build_over_budget': build.where((us) => us > budgetUs).length,
    'raster_over_budget': raster.where((us) => us > budgetUs).length,
    'span_over_budget': span.where((us) => us > budgetUs).length,
    'build_p95_ms': p95(build),
    'raster_p95_ms': p95(raster),
    'span_p95_ms': p95(span),
    'build_max_ms': build.last / 1000,
    'raster_max_ms': raster.last / 1000,
    'span_max_ms': span.last / 1000,
  };
}
