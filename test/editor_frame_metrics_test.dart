import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/editor_frame_metrics.dart';

FrameTiming frame(int buildUs, int rasterUs, {int waitUs = 0}) => FrameTiming(
  vsyncStart: 0,
  buildStart: 0,
  buildFinish: buildUs,
  rasterStart: buildUs + waitUs,
  rasterFinish: buildUs + waitUs + rasterUs,
  rasterFinishWallTime: buildUs + waitUs + rasterUs,
);

void main() {
  test('pipeline latency does not count as a stage budget violation', () {
    final report = editorFrameMetrics([
      frame(9000, 9000),
      frame(2000, 2000, waitUs: 20000),
    ], refreshRate: 60);
    expect(report['over_budget'], 0);
    expect(report['span_over_budget'], 2);
    expect(report['span_p95_ms'], 24);
  });

  test('counts each slow frame once, even when both stages exceed budget', () {
    final report = editorFrameMetrics([
      frame(18000, 2000),
      frame(2000, 18000),
      frame(34000, 34000),
    ], refreshRate: 60);
    expect(report['over_budget'], 3);
    expect(report['build_over_budget'], 2);
    expect(report['raster_over_budget'], 2);
    expect(report['over_budget_pct'], 100);
  });

  test('uses device refresh rate and a strict exceeding-budget boundary', () {
    final frames = [frame(10000, 10000), frame(10001, 1)];
    expect(editorFrameMetrics(frames, refreshRate: 60)['over_budget'], 0);
    expect(editorFrameMetrics(frames, refreshRate: 100)['over_budget'], 1);
    expect(editorFrameMetrics(frames, refreshRate: 120)['over_budget'], 2);
  });

  test(
    'missing samples or invalid display data cannot yield a passing report',
    () {
      expect(
        () => editorFrameMetrics([], refreshRate: 60),
        throwsArgumentError,
      );
      for (final rate in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => editorFrameMetrics([frame(1, 1)], refreshRate: rate),
          throwsArgumentError,
        );
      }
    },
  );
}
