import 'dart:typed_data';

import 'package:tylog_audio/src/audio_note_edit.dart';
import 'package:tylog_audio/src/audio_note_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

const _rate = 8000; // small enough to keep fixtures readable
const _bytesPerMs = _rate * 2 ~/ 1000; // mono 16-bit -> 16 bytes/ms

/// Mono 16-bit PCM ramp of [ms] milliseconds, wrapped as WAV.
Uint8List _wav(int ms) => wavFromPcm16(
  Uint8List.fromList(List.generate(ms * _bytesPerMs, (i) => i % 256)),
  sampleRate: _rate,
);

/// The same audio, but with a LIST chunk sitting between `fmt ` and `data` —
/// what a WAV exported by another tool and attached here looks like.
Uint8List _wavWithListChunk(int ms) {
  final plain = _wav(ms);
  final info = parseWav(plain)!;
  const listBody = 'INFOISFT'; // 8 bytes, even, no pad needed
  final out = BytesBuilder()
    ..add(plain.sublist(0, info.offset - 8)) // through the fmt chunk
    ..add('LIST'.codeUnits)
    ..add(
      (ByteData(4)..setUint32(0, listBody.length, Endian.little))
          .buffer
          .asUint8List(),
    )
    ..add(listBody.codeUnits)
    ..add(plain.sublist(info.offset - 8)); // data header + samples
  final bytes = out.toBytes();
  // Fix the RIFF size so the file stays well-formed.
  ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);
  return bytes;
}

/// Index into the ADTS sample-rate table: 4 = 44100, 7 = 22050.
const _freqIdx44k = 4;

/// One synthesised ADTS frame. The payload is opaque to every function under
/// test, so no encoder is needed — only the 7 header bytes have to be real.
/// [mpeg2] picks Android's 0xF9 over iOS/macOS's 0xF1.
Uint8List _adtsFrame({
  int payload = 100,
  int freqIdx = _freqIdx44k,
  bool mpeg2 = false,
}) {
  final length = 7 + payload;
  final f = Uint8List(length);
  f[0] = 0xFF;
  f[1] = mpeg2 ? 0xF9 : 0xF1; // sync + id + layer 00 + protection_absent
  f[2] = (1 << 6) | (freqIdx << 2); // AAC-LC profile, channel cfg high bit 0
  f[3] = (1 << 6) | ((length >> 11) & 0x03); // channel cfg 1 (mono) + len hi
  f[4] = (length >> 3) & 0xFF;
  f[5] = ((length & 0x07) << 5) | 0x1F; // len lo + buffer fullness
  f[6] = 0xFC; // 1 frame per block
  return f;
}

/// [count] identical frames concatenated, as `record` delivers them.
Uint8List _adts(int count, {int freqIdx = _freqIdx44k, bool mpeg2 = false}) {
  final out = BytesBuilder();
  for (var i = 0; i < count; i++) {
    out.add(_adtsFrame(freqIdx: freqIdx, mpeg2: mpeg2));
  }
  return out.toBytes();
}

/// 1024 samples at 44.1kHz.
const _frameMs = 1024 * 1000 / 44100; // 23.219...

void main() {
  group('parseWav', () {
    test('finds the data chunk of a plain 44-byte-header WAV', () {
      final info = parseWav(_wav(100))!;
      expect(info.offset, 44);
      expect(info.length, 100 * _bytesPerMs);
      expect(info.sampleRate, _rate);
      expect(info.channels, 1);
      expect(info.bytesPerSample, 2);
    });

    test('skips a LIST chunk instead of assuming byte 44', () {
      final info = parseWav(_wavWithListChunk(100))!;
      expect(info.offset, greaterThan(44), reason: 'data moved past LIST');
      expect(info.length, 100 * _bytesPerMs);
    });

    test('returns null for non-RIFF bytes (m4a guard)', () {
      final m4a = Uint8List.fromList([
        0, 0, 0, 32, ...'ftypM4A '.codeUnits, 0, 0, 0, 0,
      ]);
      expect(parseWav(m4a), isNull);
    });

    test('returns null for a truncated header', () {
      expect(parseWav(Uint8List(8)), isNull);
    });

    test('clamps a data size that overruns the buffer', () {
      final wav = _wav(50);
      // Claim twice as many sample bytes as are actually present.
      ByteData.sublistView(wav).setUint32(40, 50 * _bytesPerMs * 2, Endian.little);
      expect(parseWav(wav)!.length, 50 * _bytesPerMs);
    });
  });

  group('wavDurationMs', () {
    test('round-trips the fixture duration', () {
      expect(wavDurationMs(_wav(2500)), 2500);
    });

    test('is null for non-WAV', () {
      expect(wavDurationMs(Uint8List.fromList('not audio'.codeUnits)), isNull);
    });
  });

  group('trimWav', () {
    test('keeps only the requested window', () {
      final trimmed = trimWav(_wav(1000), startMs: 200, endMs: 700)!;
      expect(wavDurationMs(trimmed), 500);
    });

    test('rewrites the RIFF and data sizes to match', () {
      final trimmed = trimWav(_wav(1000), startMs: 0, endMs: 250)!;
      final view = ByteData.sublistView(trimmed);
      final dataSize = view.getUint32(40, Endian.little);
      expect(dataSize, 250 * _bytesPerMs);
      expect(view.getUint32(4, Endian.little), 36 + dataSize);
      expect(trimmed.length, 44 + dataSize);
    });

    test('copies the right samples out of the source', () {
      final source = _wav(1000);
      final info = parseWav(source)!;
      final trimmed = trimWav(source, startMs: 200, endMs: 700)!;
      final expectedFirst = source[info.offset + 200 * _bytesPerMs];
      expect(trimmed[44], expectedFirst);
    });

    test('trims a WAV whose data chunk is not at byte 44', () {
      final trimmed = trimWav(_wavWithListChunk(1000), startMs: 100, endMs: 400)!;
      expect(wavDurationMs(trimmed), 300);
      // Slicing at a hardcoded 44 would have started inside the LIST chunk.
      final source = _wavWithListChunk(1000);
      final info = parseWav(source)!;
      expect(trimmed[44], source[info.offset + 100 * _bytesPerMs]);
    });

    test('snaps offsets to frame boundaries on stereo sources', () {
      final stereo = wavFromPcm16(
        Uint8List(1000 * _bytesPerMs * 2),
        sampleRate: _rate,
        channels: 2,
      );
      // 3ms at 8kHz stereo = 96 bytes, but pick a start that lands off-frame
      // for a 4-byte frame if snapping were skipped.
      final trimmed = trimWav(stereo, startMs: 7, endMs: 500)!;
      final info = parseWav(trimmed)!;
      expect(info.channels, 2);
      expect(info.length % 4, 0, reason: 'sliced on a whole stereo frame');
    });

    test('returns null for m4a bytes', () {
      final m4a = Uint8List.fromList([
        0, 0, 0, 32, ...'ftypM4A '.codeUnits, 0, 0, 0, 0,
      ]);
      expect(trimWav(m4a, startMs: 0, endMs: 100), isNull);
    });

    test('returns null for an empty or inverted window', () {
      expect(trimWav(_wav(1000), startMs: 500, endMs: 500), isNull);
      expect(trimWav(_wav(1000), startMs: 700, endMs: 200), isNull);
    });

    test('clamps an end past the recording instead of overrunning', () {
      final trimmed = trimWav(_wav(500), startMs: 100, endMs: 9999)!;
      expect(wavDurationMs(trimmed), 400);
    });

    test('is exact at 44.1kHz across a full-length 4-minute take', () {
      // The real capture format. Byte offsets here run to ~2.1e10, past 32-bit
      // — and on web Dart ints are doubles, so this is where sloppy math would
      // start dropping samples.
      const totalMs = 240000;
      final wav = wavFromPcm16(
        Uint8List(totalMs * 44100 * 2 ~/ 1000),
        sampleRate: 44100,
      );
      expect(wavDurationMs(wav), totalMs);
      final trimmed = trimWav(wav, startMs: 1500, endMs: 238500)!;
      expect(wavDurationMs(trimmed), 237000);
      expect(parseWav(trimmed)!.sampleRate, 44100);
    });
  });

  group('parseAdtsFrames', () {
    test('walks every frame of a multi-frame stream', () {
      final frames = parseAdtsFrames(_adts(10))!;
      expect(frames.length, 10);
      expect(frames.first.offset, 0);
      expect(frames.first.length, 107);
      expect(frames.last.offset, 9 * 107);
    });

    test('parses Android 0xF9 and iOS 0xF1 headers identically', () {
      final mpeg4 = parseAdtsFrames(_adts(5))!;
      final mpeg2 = parseAdtsFrames(_adts(5, mpeg2: true))!;
      expect(mpeg2.length, mpeg4.length);
      expect(mpeg2.map((f) => f.length), mpeg4.map((f) => f.length));
    });

    test('rejects a bad syncword', () {
      final bytes = _adts(3);
      bytes[1] = 0x0F;
      expect(parseAdtsFrames(bytes), isNull);
    });

    test('rejects a non-zero layer field', () {
      final bytes = _adts(3);
      bytes[1] = 0xF7; // layer = 11
      expect(parseAdtsFrames(bytes), isNull);
    });

    test('rejects WAV and m4a', () {
      expect(parseAdtsFrames(_wav(100)), isNull);
      expect(
        parseAdtsFrames(
          Uint8List.fromList([0, 0, 0, 32, ...'ftypM4A '.codeUnits]),
        ),
        isNull,
      );
    });

    test('stops at a truncated tail frame instead of failing the stream', () {
      final full = _adts(4);
      final truncated = Uint8List.sublistView(full, 0, full.length - 40);
      expect(parseAdtsFrames(Uint8List.fromList(truncated))!.length, 3);
    });
  });

  group('adtsDurationMs', () {
    test('is frames x 1024 / sampleRate', () {
      expect(adtsDurationMs(_adts(43)), (43 * _frameMs).floor());
      expect(adtsConfig(_adts(1))!.sampleRate, 44100);
    });

    test('reads the rate out of the frequency index', () {
      expect(adtsConfig(_adts(1, freqIdx: 7))!.sampleRate, 22050);
      // Half the rate, so the same frame count is twice the wall time.
      expect(adtsDurationMs(_adts(10, freqIdx: 7)), 10 * 1024 * 1000 ~/ 22050);
    });

    test('is null for non-ADTS', () {
      expect(adtsDurationMs(_wav(100)), isNull);
    });
  });

  group('trimAdts', () {
    test('keeps the frames covering the window', () {
      // 100 frames ~= 2322ms. Ask for 500..1500ms.
      final trimmed = trimAdts(_adts(100), startMs: 500, endMs: 1500)!;
      final kept = parseAdtsFrames(trimmed)!;
      expect(kept.length, (1500 / _frameMs).ceil() - (500 / _frameMs).floor());
      expect(adtsDurationMs(trimmed), greaterThanOrEqualTo(1000));
    });

    test('never splits a frame', () {
      final trimmed = trimAdts(_adts(50), startMs: 111, endMs: 777)!;
      expect(trimmed.length % 107, 0, reason: 'whole 107-byte frames only');
      expect(parseAdtsFrames(trimmed), isNotNull);
    });

    test('copies the right frames out of the source', () {
      final source = _adts(20);
      final first = (300 / _frameMs).floor();
      final trimmed = trimAdts(source, startMs: 300, endMs: 900)!;
      // Payload bytes are zero in the fixture, so compare the whole header run.
      expect(
        trimmed.sublist(0, 7),
        source.sublist(first * 107, first * 107 + 7),
      );
    });

    test('clamps an end past the stream', () {
      final trimmed = trimAdts(_adts(10), startMs: 0, endMs: 999999)!;
      expect(parseAdtsFrames(trimmed)!.length, 10);
    });

    test('returns null for an inverted window or non-ADTS input', () {
      expect(trimAdts(_adts(10), startMs: 500, endMs: 100), isNull);
      expect(trimAdts(_wav(100), startMs: 0, endMs: 50), isNull);
    });
  });

  group('trimAudio / audioDurationMs dispatch', () {
    test('routes RIFF to the WAV path', () {
      final trimmed = trimAudio(_wav(1000), startMs: 200, endMs: 700)!;
      expect(wavDurationMs(trimmed), 500);
      expect(audioDurationMs(_wav(2500)), 2500);
    });

    test('routes an ADTS syncword to the AAC path', () {
      final trimmed = trimAudio(_adts(100), startMs: 500, endMs: 1500)!;
      expect(parseAdtsFrames(trimmed), isNotNull);
      expect(wavDurationMs(trimmed), isNull, reason: 'still AAC, not WAV');
      expect(audioDurationMs(_adts(43)), (43 * _frameMs).floor());
    });

    test('refuses m4a and returns null duration', () {
      final m4a = Uint8List.fromList([
        0, 0, 0, 32, ...'ftypM4A '.codeUnits, 0, 0, 0, 0,
      ]);
      expect(trimAudio(m4a, startMs: 0, endMs: 100), isNull);
      expect(audioDurationMs(m4a), isNull);
    });
  });

  group('peaksFromLevels', () {
    test('reduces to the bucket count and takes the loudest per bucket', () {
      final levels = [
        for (var i = 0; i < 1000; i++) i.isEven ? -60.0 : -30.0,
      ];
      final peaks = peaksFromLevels(levels, buckets: 10);
      expect(peaks.length, 10);
      expect(peaks.every((p) => p == 128), isTrue, reason: '-30dB -> mid scale');
    });

    test('maps the floor to 0 and 0dBFS to 255', () {
      expect(peaksFromLevels([-60], buckets: 1), [0]);
      expect(peaksFromLevels([0], buckets: 1), [255]);
      expect(peaksFromLevels([-90], buckets: 1), [0], reason: 'below the floor');
    });

    test('never pads past the sample count', () {
      expect(peaksFromLevels([-10, -20]).length, 2);
    });

    test('is empty for no input', () {
      expect(peaksFromLevels(const []), isEmpty);
    });
  });

  group('peaksFromWav', () {
    /// A WAV whose samples ramp 0 -> full scale across [ms].
    Uint8List rampWav(int ms) {
      final frames = ms * _rate ~/ 1000;
      final pcm = Uint8List(frames * 2);
      final view = ByteData.sublistView(pcm);
      for (var i = 0; i < frames; i++) {
        view.setInt16(i * 2, (32767 * i / frames).round(), Endian.little);
      }
      return wavFromPcm16(pcm, sampleRate: _rate);
    }

    test('rises with the audio it describes', () {
      final peaks = peaksFromWav(rampWav(2000), buckets: 20)!;
      expect(peaks.length, 20);
      expect(peaks.first, lessThan(peaks.last));
      expect(peaks, orderedEquals(List.of(peaks)..sort()));
      expect(peaks.last, greaterThan(240), reason: 'full scale -> near 255');
    });

    test('maps silence to zero', () {
      final silent = wavFromPcm16(Uint8List(1000 * _bytesPerMs), sampleRate: _rate);
      expect(peaksFromWav(silent, buckets: 8), everyElement(0));
    });

    test('is null for non-WAV and for an empty data chunk', () {
      expect(peaksFromWav(Uint8List.fromList('not audio!!!'.codeUnits)), isNull);
      expect(peaksFromWav(wavFromPcm16(Uint8List(0), sampleRate: _rate)), isNull);
    });

    test('never returns more bars than there are frames', () {
      expect(peaksFromWav(rampWav(2))!.length, lessThanOrEqualTo(16));
    });

    test('handles a full-length take without reading every sample', () {
      // 4 minutes at 44.1kHz is ~10.6M frames; striding keeps this instant.
      final wav = wavFromPcm16(
        Uint8List(240000 * 44100 * 2 ~/ 1000),
        sampleRate: 44100,
      );
      final peaks = peaksFromWav(wav)!;
      expect(peaks.length, waveformPeakCount);
    });

    test('reads the first channel of a stereo source', () {
      const frames = 400;
      final pcm = Uint8List(frames * 4);
      final view = ByteData.sublistView(pcm);
      for (var i = 0; i < frames; i++) {
        view.setInt16(i * 4, 16384, Endian.little); // left: half scale
        view.setInt16(i * 4 + 2, 0, Endian.little); // right: silent
      }
      final peaks = peaksFromWav(
        wavFromPcm16(pcm, sampleRate: _rate, channels: 2),
        buckets: 4,
      )!;
      expect(peaks, everyElement(greaterThan(120)));
    });
  });

  group('trimPeaks', () {
    test('reslices proportionally', () {
      final peaks = List.generate(100, (i) => i);
      final out = trimPeaks(peaks, 0.25, 0.75);
      expect(out.first, 25);
      expect(out.last, 74);
    });

    test('handles the full range and empties', () {
      expect(trimPeaks(List.generate(10, (i) => i), 0, 1).length, 10);
      expect(trimPeaks(const [], 0, 1), isEmpty);
      expect(trimPeaks(List.generate(10, (i) => i), 0.5, 0.5), isEmpty);
    });
  });

  group('markers', () {
    test('parses MM:SS and M:SS lines, sorted', () {
      final markers = parseMarkers('01:15 tempo drops\n0:42 good chorus entry');
      expect(markers.map((m) => m.ms), [42000, 75000]);
      expect(markers.first.text, 'good chorus entry');
    });

    test('ignores prose lines and bad timestamps', () {
      final markers = parseMarkers(
        'just a note\n00:42 real one\n99 nope\n01:75 bad seconds\n',
      );
      expect(markers.length, 1);
      expect(markers.single.text, 'real one');
    });

    test('is empty for null or blank bodies', () {
      expect(parseMarkers(null), isEmpty);
      expect(parseMarkers(''), isEmpty);
    });

    test('formatMarkers round-trips parseMarkers', () {
      const body = '00:42 good chorus entry\n01:15 tempo drops';
      expect(formatMarkers(parseMarkers(body)), body);
    });

    test('formatTimestamp pads minutes for lines, not for readouts', () {
      expect(formatTimestamp(42000), '00:42');
      expect(formatTimestamp(42000, padMinutes: false), '0:42');
      expect(formatTimestamp(605000), '10:05');
    });
  });

  group('shiftMarkers', () {
    test('rebases onto the trimmed window and drops what fell outside', () {
      final markers = parseMarkers('00:05 head\n00:20 keep\n01:00 tail');
      final shifted = shiftMarkers(markers, startMs: 10000, durationMs: 30000);
      expect(shifted.map((m) => m.text), ['keep']);
      expect(shifted.single.ms, 10000, reason: '20s - 10s trimmed off the head');
    });

    test('keeps a marker landing exactly on either edge', () {
      final markers = [(ms: 10000, text: 'start'), (ms: 40000, text: 'end')];
      final shifted = shiftMarkers(markers, startMs: 10000, durationMs: 30000);
      expect(shifted.map((m) => m.ms), [0, 30000]);
    });
  });

  group('upsertMarker / activeMarkerIndex', () {
    test('replaces a marker on the same second', () {
      final markers = [(ms: 42000, text: 'old'), (ms: 75000, text: 'other')];
      final out = upsertMarker(markers, (ms: 42400, text: 'new'));
      expect(out.length, 2);
      expect(out.first.text, 'new');
    });

    test('inserts sorted', () {
      final out = upsertMarker(
        [(ms: 75000, text: 'late')],
        (ms: 42000, text: 'early'),
      );
      expect(out.map((m) => m.text), ['early', 'late']);
    });

    test('activeMarkerIndex tracks the playhead', () {
      final markers = [(ms: 0, text: 'a'), (ms: 10000, text: 'b')];
      expect(activeMarkerIndex(markers, 0), 0);
      expect(activeMarkerIndex(markers, 9999), 0);
      expect(activeMarkerIndex(markers, 10000), 1);
      expect(activeMarkerIndex(const [], 5000), -1);
    });

    test('activeMarkerIndex is -1 before the first marker', () {
      expect(activeMarkerIndex([(ms: 5000, text: 'a')], 100), -1);
    });
  });
}
