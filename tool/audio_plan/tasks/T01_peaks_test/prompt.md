Create test/audio_peaks_test.dart (flutter_test) for bucketPeaks in lib/audio/audio_peaks.dart (import package:tylog/audio/audio_peaks.dart).
Signature: List<int> bucketPeaks(int length, int Function(int) maxAbsAt, {int buckets = 200}).
Behaviour: length<=0 -> []. n=min(length,buckets) bars; pixel i goes to bar i*n~/length; a bar keeps the max maxAbsAt of its pixels; bars are scaled so the loudest is 255 (round(v*255/loudest)); all-zero input -> [].
Write 5 tests: empty length; length smaller than buckets gives length bars; 1000 pixels into 200 buckets gives 200 bars and max 255; scaling (values 100,200 -> [128,255]); all zeros -> [].
Context: Flutter app TyLog at the repo root. Read only the files named here. Create ONLY the allowed file(s); do not edit any other file. Finish when the verify command passes.
