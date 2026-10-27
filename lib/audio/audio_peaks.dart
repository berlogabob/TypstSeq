import 'dart:io';

import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';

/// Reduces [length] pixels (each [maxAbsAt] -> 0..32768) to [buckets] bars
/// scaled so the loudest bar is 255. Pure, so it is tested without a codec.
List<int> bucketPeaks(
  int length,
  int Function(int) maxAbsAt, {
  int buckets = 200,
}) {
  if (length <= 0) return const [];
  final n = length < buckets ? length : buckets;
  final bars = List<int>.filled(n, 0);
  for (var i = 0; i < length; i++) {
    final b = i * n ~/ length;
    final v = maxAbsAt(i);
    if (v > bars[b]) bars[b] = v;
  }
  final loudest = bars.reduce((a, b) => a > b ? a : b);
  if (loudest == 0) return const [];
  return [for (final v in bars) (v * 255 / loudest).round()];
}

/// Peaks for any file the platform codec can read (mp3, m4a, aac, wav, ogg
/// where the OS supports it), via MediaCodec on Android and AVFoundation on
/// iOS/macOS. Empty on any failure: the screen then draws a flat placeholder.
Future<List<int>> peaksFromAudioFile(File audio, {int buckets = 200}) async {
  final dir = await getTemporaryDirectory().then(
    (d) => d.create(recursive: true),
  );
  final out = File(
    '${dir.path}/peaks-${DateTime.now().microsecondsSinceEpoch}.wave',
  );
  try {
    Waveform? waveform;
    await for (final p in JustWaveform.extract(
      audioInFile: audio,
      waveOutFile: out,
      zoom: const WaveformZoom.pixelsPerSecond(20),
    )) {
      waveform = p.waveform ?? waveform;
    }
    final w = waveform;
    if (w == null) return const [];
    return bucketPeaks(
      w.length,
      (i) => w.getPixelMax(i).abs() > w.getPixelMin(i).abs()
          ? w.getPixelMax(i).abs()
          : w.getPixelMin(i).abs(),
      buckets: buckets,
    );
  } catch (_) {
    return const [];
  } finally {
    if (await out.exists()) await out.delete();
  }
}
