import 'dart:typed_data';

/// What can be read cheaply from an audio file's bytes, for the Properties tab.
class AudioInfo {
  const AudioInfo({
    required this.format,
    required this.bytes,
    this.sampleRate,
    this.bitrateKbps,
  });

  final String format;
  final int bytes;
  final int? sampleRate;

  /// Average over the whole file (size / duration), not the encoder setting.
  final int? bitrateKbps;
}

const _adtsRates = [
  96000, 88200, 64000, 48000, 44100, 32000, //
  24000, 22050, 16000, 12000, 11025, 8000,
];

int _u32(Uint8List b, int at) =>
    (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

int? _indexOf(Uint8List b, String tag) {
  final t = tag.codeUnits;
  for (var i = 0; i + 4 <= b.length && i < 4 * 1024 * 1024; i++) {
    if (b[i] == t[0] &&
        b[i + 1] == t[1] &&
        b[i + 2] == t[2] &&
        b[i + 3] == t[3]) {
      return i;
    }
  }
  return null;
}

int? _mp4Rate(Uint8List b) {
  final i = _indexOf(b, 'mdhd');
  if (i == null || i + 24 > b.length) return null;
  final at = i + 4 + 4 + (b[i + 4] == 1 ? 16 : 8);
  return at + 4 <= b.length ? _u32(b, at) : null;
}

int? _mp3Rate(Uint8List b) {
  var i = 0;
  if (b.length > 10 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
    i = 10 + ((b[6] << 21) | (b[7] << 14) | (b[8] << 7) | b[9]);
  }
  for (; i + 4 <= b.length && i < 1024 * 1024; i++) {
    if (b[i] != 0xFF || (b[i + 1] & 0xE0) != 0xE0) continue;
    final version = (b[i + 1] >> 3) & 3; // 3 = MPEG1, 2 = MPEG2, 0 = 2.5
    final idx = (b[i + 2] >> 2) & 3;
    if (version == 1 || idx == 3) continue;
    const base = [44100, 48000, 32000];
    return base[idx] ~/
        (version == 3
            ? 1
            : version == 2
            ? 2
            : 4);
  }
  return null;
}

int? _adtsRate(Uint8List b) {
  for (var i = 0; i + 3 <= b.length && i < 64 * 1024; i++) {
    if (b[i] == 0xFF && (b[i + 1] & 0xF6) == 0xF0) {
      final idx = (b[i + 2] >> 2) & 0xF;
      return idx < _adtsRates.length ? _adtsRates[idx] : null;
    }
  }
  return null;
}

AudioInfo audioInfo(Uint8List b, String extension, int? durationMs) {
  final ext = extension.toLowerCase();
  final (format, rate) = switch (ext) {
    'm4a' || 'mp4' => ('AAC in M4A', _mp4Rate(b)),
    'aac' => ('AAC (ADTS)', _adtsRate(b)),
    'mp3' => ('MP3', _mp3Rate(b)),
    'wav' => (
      'WAV (PCM)',
      b.length >= 28
          ? b[24] | (b[25] << 8) | (b[26] << 16) | (b[27] << 24)
          : null,
    ),
    'ogg' => ('Ogg Vorbis', null),
    'opus' => ('Opus', 48000),
    _ => (ext.toUpperCase(), null),
  };
  return AudioInfo(
    format: format,
    bytes: b.length,
    sampleRate: rate,
    bitrateKbps: durationMs == null || durationMs <= 0
        ? null
        : (b.length * 8 / durationMs).round(),
  );
}
