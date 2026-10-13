import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Captures an audio note in whichever sliceable format the platform can
/// stream, so the editor can always trim it without an ffmpeg-sized dependency.
///
/// - **native**: `aacLc`, which `record` delivers as self-contained ADTS frames
///   (one per chunk). ~16 kB/s, so a take can run ~26 min under the 25MB
///   Storage cap and a shared file stays messenger-sized.
/// - **web**: `pcm16bits` wrapped into WAV on stop — `record_web` refuses every
///   stream encoder but PCM. ~88 kB/s, hence the much shorter web cap.
///
/// Both are trimmable by `trimAudio` in audio_note_edit.dart; nothing
/// downstream branches on platform.
class AudioNoteRecorder {
  AudioNoteRecorder(this._recorder);

  /// What [stop] returns on this platform.
  static String get extension => kIsWeb ? 'wav' : 'aac';
  static String get contentType => kIsWeb ? 'audio/wav' : 'audio/aac';

  final AudioRecorder _recorder;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final List<double> _levels = [];
  StreamSubscription<Uint8List>? _sub;
  StreamSubscription<Amplitude>? _ampSub;
  int _sampleRate = 44100;

  /// Called with the level of each incoming chunk in dBFS (~-90..0).
  void Function(double dbfs)? onLevel;

  bool get isRecording => _sub != null;

  /// Every level of the take so far, for reducing to waveform peaks.
  List<double> get levels => List.unmodifiable(_levels);

  Future<void> start() async {
    if (_sub != null) return;
    _buffer.clear();
    _levels.clear();
    _sampleRate = 44100;
    await _recorder.setOnConfigChanged((config) {
      _sampleRate = config.sampleRate;
    });
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: kIsWeb ? AudioEncoder.pcm16bits : AudioEncoder.aacLc,
        numChannels: 1,
        // An explicit size bypasses AudioRecord.getMinBufferSize on Android and
        // hard-fails init on devices that need more; only web requires it.
        streamBufferSize: kIsWeb ? 4096 : null,
        // Music, not speech: the raw mic rather than a voice-tuned source, so
        // Android doesn't smear a riff. Knob — drop back to defaultSource if a
        // device records too hot. autoGain/echoCancel/noiseSuppress are already
        // off by default and stay off for the same reason.
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.mic,
        ),
      ),
    );
    _sub = stream.listen((chunk) {
      _buffer.add(chunk);
      if (kIsWeb) _publish(_rmsDbfs(chunk));
    });
    if (!kIsWeb) {
      // AAC chunks aren't PCM, so their bytes say nothing about loudness.
      // `record` measures amplitude on the mic buffer before encoding, which is
      // exactly what we want and is encoder-independent.
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((a) => _publish(a.current));
    }
  }

  void _publish(double dbfs) {
    _levels.add(dbfs);
    onLevel?.call(dbfs);
  }

  /// Stops capture and returns the take: raw ADTS on native, WAV on web.
  Future<Uint8List> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _ampSub?.cancel();
    _ampSub = null;
    await _recorder.stop();
    final raw = _buffer.takeBytes();
    // ADTS frames are already a playable stream; PCM needs its container.
    return kIsWeb ? wavFromPcm16(raw, sampleRate: _sampleRate) : raw;
  }

  Future<void> cancel() async {
    await _sub?.cancel();
    _sub = null;
    await _ampSub?.cancel();
    _ampSub = null;
    await _recorder.stop();
    _buffer.clear();
    _levels.clear();
  }

  static double _rmsDbfs(Uint8List chunk) {
    final data = ByteData.sublistView(chunk);
    final samples = chunk.length ~/ 2;
    if (samples == 0) return -90;
    var sum = 0.0;
    for (var offset = 0; offset + 1 < chunk.length; offset += 2) {
      final v = data.getInt16(offset, Endian.little) / 32768.0;
      sum += v * v;
    }
    final rms = math.sqrt(sum / samples);
    if (rms <= 0.00003) return -90;
    return 20 * math.log(rms) / math.ln10;
  }
}

/// Wraps raw little-endian PCM16 in a standard 44-byte RIFF/WAVE header.
Uint8List wavFromPcm16(
  Uint8List pcm, {
  required int sampleRate,
  int channels = 1,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final header = ByteData(44);

  void writeAscii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  header.setUint16(20, 1, Endian.little); // PCM format
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);

  final out = Uint8List(44 + pcm.length)
    ..setRange(0, 44, header.buffer.asUint8List())
    ..setRange(44, 44 + pcm.length, pcm);
  return out;
}
