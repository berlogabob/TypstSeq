/// Pure editing helpers for audio notes: WAV trimming, waveform peaks and the
/// timestamp comments parsed out of a recording entry's body.
///
/// Deliberately plugin-free — no recorder, no player, no Firebase — so every
/// branch that can silently corrupt a recording is unit-testable.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_note_recorder.dart' show wavFromPcm16;

/// Where the samples live inside a RIFF/WAVE buffer, plus the format needed to
/// convert between byte offsets and milliseconds.
typedef WavInfo = ({
  int offset,
  int length,
  int sampleRate,
  int channels,
  int bytesPerSample,
});

/// Locates the `fmt `/`data` chunks of a PCM WAV.
///
/// Walks the chunk list rather than assuming the 44-byte header our own
/// [wavFromPcm16] writes: files picked with "Attach file" routinely carry
/// `LIST`/`fact` chunks before `data`, and slicing at a hardcoded 44 would cut
/// into metadata. Returns null for anything that isn't uncompressed PCM.
WavInfo? parseWav(Uint8List wav) {
  if (wav.length < 12) return null;
  final data = ByteData.sublistView(wav);
  String ascii(int offset) =>
      String.fromCharCodes(wav.sublist(offset, offset + 4));
  if (ascii(0) != 'RIFF' || ascii(8) != 'WAVE') return null;

  int? sampleRate;
  int? channels;
  int? bitsPerSample;
  var pos = 12;
  while (pos + 8 <= wav.length) {
    final id = ascii(pos);
    final size = data.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ' && body + 16 <= wav.length) {
      if (data.getUint16(body, Endian.little) != 1) return null; // PCM only
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (sampleRate == null || channels == null || bitsPerSample == null) {
        return null;
      }
      // A truncated recording can declare more bytes than it carries.
      final length = math.min(size, wav.length - body);
      if (length <= 0) return null;
      return (
        offset: body,
        length: length,
        sampleRate: sampleRate,
        channels: channels,
        bytesPerSample: bitsPerSample ~/ 8,
      );
    }
    // Chunks are word-aligned: odd sizes carry a pad byte.
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

/// Duration of a PCM WAV in milliseconds, or null if [wav] isn't one.
int? wavDurationMs(Uint8List wav) {
  final info = parseWav(wav);
  if (info == null) return null;
  return _msFromBytes(info.length, info);
}

/// Returns [wav] cut down to `[startMs, endMs)`, or null if [wav] isn't PCM
/// WAV (an m4a take, say — byte-slicing an MPEG-4 container yields garbage).
///
/// Offsets snap to frame boundaries; slicing mid-frame shifts the sample phase
/// and turns the whole recording into noise on stereo or 24-bit sources.
Uint8List? trimWav(Uint8List wav, {required int startMs, required int endMs}) {
  final info = parseWav(wav);
  if (info == null) return null;
  final frame = info.channels * info.bytesPerSample;
  final totalMs = _msFromBytes(info.length, info);

  final from = _snap(_bytesFromMs(startMs.clamp(0, totalMs), info), frame);
  final to = _snap(_bytesFromMs(endMs.clamp(0, totalMs), info), frame);
  if (to <= from) return null;

  final pcm = Uint8List.sublistView(
    wav,
    info.offset + from,
    info.offset + math.min(to, info.length),
  );
  return wavFromPcm16(
    Uint8List.fromList(pcm),
    sampleRate: info.sampleRate,
    channels: info.channels,
  );
}

// --- ADTS AAC (the native capture format) --------------------------------

/// `sampling_frequency_index` -> Hz, per ISO/IEC 13818-7.
const _adtsSampleRates = [
  96000, 88200, 64000, 48000, 44100, 32000,
  24000, 22050, 16000, 12000, 11025, 8000, 7350,
];

/// Every AAC-LC frame carries exactly this many samples per channel.
const adtsSamplesPerFrame = 1024;

/// ADTS `profile` for AAC-LC. Note this is *not* the MPEG-4 AudioObjectType,
/// which is one higher — see `AdtsConfig.profile`.
const adtsProfileAacLc = 1;

/// A frame's position, total size, and how much of that is header. Trimming
/// only needs the first two; remuxing into MP4 needs the third, because MP4
/// stores bare access units with the ADTS header stripped off.
typedef AdtsFrame = ({int offset, int length, int headerLength});

/// The stream-wide format, read off the first frame.
///
/// `profile` is the raw 2-bit ADTS field (`1` = AAC-LC). The MPEG-4
/// AudioObjectType written into an MP4's AudioSpecificConfig is `profile + 1`;
/// conflating the two writes "AAC Main" into the container, which iOS often
/// still plays and Android's MediaCodec does not.
typedef AdtsConfig = ({
  int sampleRate,
  int freqIndex,
  int channels,
  int profile,
});

/// Reads one ADTS header, or null if [offset] isn't on a valid frame.
///
/// `record` emits `0xF1` (MPEG-4) on iOS/macOS and `0xF9` (MPEG-2) on Android;
/// both are 7-byte, CRC-less headers. A 9-byte CRC header parses too — the
/// frame length field means the same thing either way, only the payload starts
/// two bytes later.
({int length, int headerLength, AdtsConfig config})? _adtsHeader(
  Uint8List aac,
  int offset,
) {
  if (offset + 7 > aac.length) return null;
  if (aac[offset] != 0xFF || (aac[offset + 1] & 0xF0) != 0xF0) return null;
  if ((aac[offset + 1] & 0x06) != 0) return null; // layer must be 00
  final freqIdx = (aac[offset + 2] >> 2) & 0x0F;
  if (freqIdx >= _adtsSampleRates.length) return null;
  final length =
      ((aac[offset + 3] & 0x03) << 11) |
      (aac[offset + 4] << 3) |
      ((aac[offset + 5] >> 5) & 0x07);
  // The CRC belongs to the header, so protection changes where audio starts.
  final headerLength = (aac[offset + 1] & 0x01) == 1 ? 7 : 9;
  // A frame must at least contain its own header, and must not overrun.
  if (length < headerLength || offset + length > aac.length) return null;
  // Anything other than one raw data block per frame isn't 1024 samples, which
  // every duration and sample table here assumes.
  if ((aac[offset + 6] & 0x03) != 0) return null;
  return (
    length: length,
    headerLength: headerLength,
    config: (
      sampleRate: _adtsSampleRates[freqIdx],
      freqIndex: freqIdx,
      channels: ((aac[offset + 2] & 0x01) << 2) | ((aac[offset + 3] >> 6) & 0x03),
      profile: (aac[offset + 2] >> 6) & 0x03,
    ),
  );
}

/// Walks a raw ADTS stream into frames. Null if [aac] doesn't start on one.
///
/// Frames are self-contained, which is the whole reason native capture can be
/// compressed and still trimmable: cutting on a frame boundary needs no
/// decoding, only whole-frame arithmetic.
List<AdtsFrame>? parseAdtsFrames(Uint8List aac) {
  if (_adtsHeader(aac, 0) == null) return null;
  final frames = <AdtsFrame>[];
  var offset = 0;
  while (offset < aac.length) {
    final header = _adtsHeader(aac, offset);
    // A truncated tail frame ends the stream rather than failing the file.
    if (header == null) break;
    frames.add((
      offset: offset,
      length: header.length,
      headerLength: header.headerLength,
    ));
    offset += header.length;
  }
  return frames.isEmpty ? null : frames;
}

/// Format of an ADTS stream, or null if [aac] isn't one.
AdtsConfig? adtsConfig(Uint8List aac) => _adtsHeader(aac, 0)?.config;

/// Duration of an ADTS stream: frames x 1024 / sampleRate.
int? adtsDurationMs(Uint8List aac) {
  final frames = parseAdtsFrames(aac);
  final config = adtsConfig(aac);
  if (frames == null || config == null) return null;
  return frames.length * adtsSamplesPerFrame * 1000 ~/ config.sampleRate;
}

/// Returns [aac] cut to `[startMs, endMs)`, snapped outward to whole frames.
///
/// Granularity is one frame — 23.2ms at 44.1kHz — which is finer than anyone
/// can place a trim handle.
Uint8List? trimAdts(Uint8List aac, {required int startMs, required int endMs}) {
  final frames = parseAdtsFrames(aac);
  final config = adtsConfig(aac);
  if (frames == null || config == null || endMs <= startMs) return null;

  final msPerFrame = adtsSamplesPerFrame * 1000 / config.sampleRate;
  final first = (startMs / msPerFrame).floor().clamp(0, frames.length - 1);
  final last = (endMs / msPerFrame).ceil().clamp(first + 1, frames.length);

  final from = frames[first].offset;
  final to = frames[last - 1].offset + frames[last - 1].length;
  return Uint8List.fromList(Uint8List.sublistView(aac, from, to));
}

// --- format-agnostic entry points ----------------------------------------

/// Trims whichever capture format this take is in — WAV on web, ADTS AAC on
/// native. Null for anything else (legacy m4a, an imported mp3), which is what
/// disables the trim UI.
Uint8List? trimAudio(
  Uint8List bytes, {
  required int startMs,
  required int endMs,
}) =>
    _isAdts(bytes)
    ? trimAdts(bytes, startMs: startMs, endMs: endMs)
    : trimWav(bytes, startMs: startMs, endMs: endMs);

/// Duration of a WAV or ADTS take, or null if it's neither.
int? audioDurationMs(Uint8List bytes) =>
    _isAdts(bytes) ? adtsDurationMs(bytes) : wavDurationMs(bytes);

/// True when the buffer opens with an ADTS syncword rather than `RIFF`.
bool _isAdts(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xF0) == 0xF0;

/// File extensions this app can trim, matched against the Storage object name.
const trimmableExtensions = {'wav', 'aac'};

int _msFromBytes(int bytes, WavInfo info) =>
    bytes * 1000 ~/ (info.sampleRate * info.channels * info.bytesPerSample);

int _bytesFromMs(int ms, WavInfo info) =>
    ms * info.sampleRate * info.channels * info.bytesPerSample ~/ 1000;

int _snap(int bytes, int frame) => bytes - (bytes % frame);

/// Number of bars stored per recording. ~800 bytes on the Firestore doc, which
/// is what lets the editor draw a waveform without downloading the audio.
const waveformPeakCount = 200;

/// Reduces a recording's dBFS level stream to [buckets] bars in 0..255.
///
/// Same -60dB floor as the live recording bars, so a take looks the same while
/// recording and afterwards.
List<int> peaksFromLevels(List<double> dbfs, {int buckets = waveformPeakCount}) {
  if (dbfs.isEmpty || buckets <= 0) return const [];
  final out = List<int>.filled(math.min(buckets, dbfs.length), 0);
  for (var i = 0; i < out.length; i++) {
    final start = i * dbfs.length ~/ out.length;
    final end = math.max(start + 1, (i + 1) * dbfs.length ~/ out.length);
    var peak = -60.0;
    for (var j = start; j < end; j++) {
      if (dbfs[j] > peak) peak = dbfs[j];
    }
    out[i] = (((peak + 60) / 60).clamp(0.0, 1.0) * 255).round();
  }
  return out;
}

/// Derives waveform peaks from the audio itself, for takes recorded before
/// peaks were captured at record time.
///
/// WAV only: PCM samples can be read directly, whereas AAC would need decoding.
/// Strides rather than reading every sample — at 25MB that's 13M samples, and
/// a bar only needs the loudest thing near it, not all of it.
List<int>? peaksFromWav(Uint8List wav, {int buckets = waveformPeakCount}) {
  final info = parseWav(wav);
  if (info == null || info.bytesPerSample != 2 || buckets <= 0) return null;
  final frame = info.channels * info.bytesPerSample;
  final frames = info.length ~/ frame;
  if (frames <= 0) return null;

  final data = ByteData.sublistView(wav);
  final out = List<int>.filled(math.min(buckets, frames), 0);
  // Cap the work per bar; a few hundred samples is plenty to find a peak.
  const maxReadsPerBucket = 256;
  for (var i = 0; i < out.length; i++) {
    final start = i * frames ~/ out.length;
    final end = math.max(start + 1, (i + 1) * frames ~/ out.length);
    final step = math.max(1, (end - start) ~/ maxReadsPerBucket);
    var peak = 0;
    for (var f = start; f < end; f += step) {
      // First channel only: the second says nearly the same thing about level.
      final v = data.getInt16(info.offset + f * frame, Endian.little).abs();
      if (v > peak) peak = v;
    }
    out[i] = (peak * 255 / 32768).round().clamp(0, 255);
  }
  return out;
}

/// Reslices a stored peak array to the same window a trim applied to the audio,
/// so committing a trim doesn't need the bytes re-downloaded to redraw.
List<int> trimPeaks(List<int> peaks, double startFrac, double endFrac) {
  if (peaks.isEmpty) return const [];
  final from = (startFrac.clamp(0.0, 1.0) * peaks.length).floor();
  final to = (endFrac.clamp(0.0, 1.0) * peaks.length).ceil();
  if (to <= from) return const [];
  return peaks.sublist(math.min(from, peaks.length - 1), math.min(to, peaks.length));
}

/// One timestamped comment on a recording.
typedef AudioMarker = ({int ms, String text});

final _markerLine = RegExp(r'^\s*(\d{1,2}):([0-5]\d)\s+(.+?)\s*$');

/// Parses `00:42 good chorus entry` lines out of an entry body.
///
/// ponytail: markers ARE the body text — no new model, no new collection, and
/// they still export and read as plain notes. Lines that don't match are kept
/// out of the marker list and preserved by [formatMarkers] callers only if they
/// re-add them; in practice the whole body is markers.
List<AudioMarker> parseMarkers(String? body) {
  if (body == null || body.isEmpty) return const [];
  final out = <AudioMarker>[];
  for (final line in body.split('\n')) {
    final m = _markerLine.firstMatch(line);
    if (m == null) continue;
    final ms =
        (int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 1000;
    out.add((ms: ms, text: m.group(3)!));
  }
  out.sort((a, b) => a.ms.compareTo(b.ms));
  return out;
}

/// Renders markers back to the `MM:SS text` body format.
String formatMarkers(List<AudioMarker> markers) {
  final sorted = [...markers]..sort((a, b) => a.ms.compareTo(b.ms));
  return sorted.map((m) => '${formatTimestamp(m.ms)} ${m.text}').join('\n');
}

/// `M:SS` for playback readouts, zero-padded `MM:SS` in marker lines.
String formatTimestamp(int ms, {bool padMinutes = true}) {
  final total = ms ~/ 1000;
  final minutes = (total ~/ 60).toString();
  final seconds = (total % 60).toString().padLeft(2, '0');
  return '${padMinutes ? minutes.padLeft(2, '0') : minutes}:$seconds';
}

/// Rebases markers onto a trimmed recording: everything moves back by
/// [startMs], and anything now outside the take is dropped.
///
/// Easy to forget, and forgetting it silently desynchronises every comment.
List<AudioMarker> shiftMarkers(
  List<AudioMarker> markers, {
  required int startMs,
  required int durationMs,
}) => [
  for (final m in markers)
    if (m.ms >= startMs && m.ms - startMs <= durationMs)
      (ms: m.ms - startMs, text: m.text),
];

/// Inserts [marker], replacing any existing one at the same second.
List<AudioMarker> upsertMarker(List<AudioMarker> markers, AudioMarker marker) {
  final second = marker.ms ~/ 1000;
  return [
    for (final m in markers)
      if (m.ms ~/ 1000 != second) m,
    marker,
  ]..sort((a, b) => a.ms.compareTo(b.ms));
}

/// Index of the marker the playhead is currently inside, or -1.
int activeMarkerIndex(List<AudioMarker> markers, int positionMs) {
  var active = -1;
  for (var i = 0; i < markers.length; i++) {
    if (markers[i].ms <= positionMs) {
      active = i;
    } else {
      break;
    }
  }
  return active;
}
