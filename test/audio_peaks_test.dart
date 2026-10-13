import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/audio/audio_peaks.dart';

void main() {
  group('bucketPeaks', () {
    test('length <= 0 returns an empty list', () {
      expect(bucketPeaks(0, (i) => 0), isEmpty);
      expect(bucketPeaks(-5, (i) => 0), isEmpty);
    });

    test('length smaller than buckets gives one bar per pixel', () {
      final peaks = bucketPeaks(3, (i) => i + 1);
      expect(peaks, hasLength(3));
    });

    test('1000 pixels into 200 buckets gives 200 bars with max 255', () {
      final peaks = bucketPeaks(1000, (i) => 1);
      expect(peaks, hasLength(200));
      expect(peaks.reduce((a, b) => a > b ? a : b), 255);
    });

    test('scaling maps 100,200 to [128,255]', () {
      final peaks = bucketPeaks(2, (i) => i == 0 ? 100 : 200);
      expect(peaks, [128, 255]);
    });

    test('all-zero input returns an empty list', () {
      expect(bucketPeaks(10, (i) => 0), isEmpty);
    });
  });
}
