/// Wraps raw ADTS AAC frames in a minimal MP4/M4A container, losslessly.
///
/// Messengers decide whether an attachment is playable audio or a generic
/// document from its container: Telegram's audio player takes `.mp3` and
/// `.m4a`, and explicitly tells you to send `.aac` as a File. Our capture
/// format is raw ADTS because that's what makes trimming a frame-slice, so the
/// bytes get re-wrapped on their way out — same frames, different box, no
/// re-encoding and no dependency.
///
/// Layout and constants were checked byte-for-byte against an Apple-authored
/// `.m4a` (AVFCore's `record_start.m4a`) and FFmpeg's `movenc.c`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'audio_note_edit.dart';

/// Wraps [aac] — a raw ADTS AAC-LC stream — in an MP4 container.
///
/// Returns null for anything that can't be represented faithfully, so callers
/// fall back to sharing the original bytes. A note that arrives as a document
/// beats one that arrives corrupt.
///
/// [title] and [artist] become iTunes-style metadata, which is what a player
/// shows instead of the filename. Both null skips the `udta` subtree entirely.
Uint8List? m4aFromAdts(Uint8List aac, {String? title, String? artist}) {
  final frames = parseAdtsFrames(aac);
  final config = adtsConfig(aac);
  if (frames == null || config == null || frames.isEmpty) return null;

  // AudioSpecificConfig is only 2 bytes, which can't express an explicit
  // sample rate (freqIndex 15) or a channel layout that lives in a PCE
  // (channels 0). And the AudioObjectType below is hardcoded to AAC-LC.
  if (config.profile != adtsProfileAacLc) return null;
  if (config.freqIndex > 12) return null;
  if (config.channels < 1 || config.channels > 7) return null;

  final sizes = [
    for (final f in frames) f.length - f.headerLength,
  ];
  if (sizes.any((s) => s <= 0)) return null;
  final payloadLength = sizes.reduce((a, b) => a + b);

  final ftyp = _ftyp();
  final moov = _moov(
    config: config,
    sampleSizes: sizes,
    payloadLength: payloadLength,
    title: title,
    artist: artist,
  );
  final mdatPayloadOffset = ftyp.length + moov.bytes.length + 8;
  // 32-bit chunk offsets and box sizes; co64 would be needed beyond this, and
  // a 25MB Storage cap means we never get close.
  if (mdatPayloadOffset + payloadLength > 0xFFFFFFFF) return null;

  // stco entries are fixed-width, so moov's length can't depend on the value
  // written here — which is what makes patching it after the fact sound.
  ByteData.sublistView(moov.bytes)
      .setUint32(moov.stcoEntryIndex, mdatPayloadOffset);

  final out = BytesBuilder()
    ..add(ftyp)
    ..add(moov.bytes)
    ..add(_boxHeader('mdat', payloadLength));
  // MP4 stores bare access units: the ADTS header is transport framing and has
  // no place inside mdat. Leaving it in yields a file that looks structurally
  // fine and plays noise.
  for (var i = 0; i < frames.length; i++) {
    final f = frames[i];
    out.add(
      Uint8List.sublistView(aac, f.offset + f.headerLength, f.offset + f.length),
    );
  }
  return out.toBytes();
}

// --- box primitives -------------------------------------------------------

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v);

Uint8List _u16(int v) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, v);

/// Four-character box type. ASCII only — the `©` iTunes types must go through
/// [_boxRaw] instead, never through here.
Uint8List _fourcc(String type) => Uint8List.fromList(ascii.encode(type));

Uint8List _boxHeader(String type, int payloadLength) =>
    Uint8List.fromList([..._u32(payloadLength + 8), ..._fourcc(type)]);

/// `size + type + payload`.
Uint8List _box(String type, List<int> payload) =>
    Uint8List.fromList([..._u32(payload.length + 8), ..._fourcc(type), ...payload]);

/// A box whose type isn't ASCII — the iTunes tags start with `©` (0xA9).
///
/// Deliberately takes bytes rather than a String: `utf8.encode('©nam')` returns
/// *five* bytes, which would corrupt the box type and shift every size after it.
Uint8List _boxRaw(List<int> type, List<int> payload) =>
    Uint8List.fromList([..._u32(payload.length + 8), ...type, ...payload]);

/// A FullBox: `size + type + version + flags + payload`.
Uint8List _fullBox(String type, int flags, List<int> payload) =>
    _box(type, [0, (flags >> 16) & 0xFF, (flags >> 8) & 0xFF, flags & 0xFF, ...payload]);

/// MPEG-4 descriptor with the 4-byte length form Apple and FFmpeg both emit.
/// Fixed-width headers keep the size arithmetic constant.
Uint8List _descriptor(int tag, List<int> payload) => Uint8List.fromList([
  tag,
  0x80 | ((payload.length >> 21) & 0x7F),
  0x80 | ((payload.length >> 14) & 0x7F),
  0x80 | ((payload.length >> 7) & 0x7F),
  payload.length & 0x7F,
  ...payload,
]);

// --- the tree -------------------------------------------------------------

Uint8List _ftyp() => _box('ftyp', [
  ..._fourcc('M4A '), // major brand
  ..._u32(0), // minor version
  ..._fourcc('M4A '), ..._fourcc('mp42'), ..._fourcc('isom'),
]);

/// The unity display matrix. The bottom-right term is 1.0 in 2.30 fixed point,
/// not 16.16 like the others.
List<int> get _unityMatrix => [
  ..._u32(0x00010000), ..._u32(0), ..._u32(0),
  ..._u32(0), ..._u32(0x00010000), ..._u32(0),
  ..._u32(0), ..._u32(0), ..._u32(0x40000000),
];

({Uint8List bytes, int stcoEntryIndex}) _moov({
  required AdtsConfig config,
  required List<int> sampleSizes,
  required int payloadLength,
  String? title,
  String? artist,
}) {
  final sampleCount = sampleSizes.length;
  // Both timescales are the sample rate, so mvhd/tkhd/mdhd durations are the
  // same integer. Mixing a 1000 movie timescale with the media rate is the
  // classic way to end up with a track that reports the wrong length.
  final duration = sampleCount * adtsSamplesPerFrame;
  final timescale = config.sampleRate;

  final stbl = _stbl(
    config: config,
    sampleSizes: sampleSizes,
    payloadLength: payloadLength,
    duration: duration,
  );

  final minf = _box('minf', [
    ..._fullBox('smhd', 0, [..._u16(0), ..._u16(0)]), // balance, reserved
    ..._box('dinf', [
      ..._fullBox('dref', 0, [
        ..._u32(1),
        ..._fullBox('url ', 1, []), // flags 1: media is in this same file
      ]),
    ]),
    ...stbl.bytes,
  ]);

  final mdia = _box('mdia', [
    ..._fullBox('mdhd', 0, [
      ..._u32(0), ..._u32(0), // creation, modification
      ..._u32(timescale), ..._u32(duration),
      ..._u16(0x55C4), // packed ISO-639-2 'und'
      ..._u16(0),
    ]),
    ..._fullBox('hdlr', 0, [
      ..._u32(0), // pre_defined; QuickTime's component type, 0 under MP4
      ..._fourcc('soun'),
      ..._u32(0), ..._u32(0), ..._u32(0), // reserved
      ...ascii.encode('SoundHandler'), 0, // null-terminated, not Pascal
    ]),
    ...minf,
  ]);

  final trak = _box('trak', [
    ..._fullBox('tkhd', 0x000003, [
      // enabled | in_movie
      ..._u32(0), ..._u32(0), // creation, modification
      ..._u32(1), // track_id
      ..._u32(0), // reserved
      ..._u32(duration),
      ..._u32(0), ..._u32(0), // reserved
      ..._u16(0), // layer
      ..._u16(0), // alternate_group
      ..._u16(0x0100), // volume 1.0
      ..._u16(0), // reserved
      ..._unityMatrix,
      ..._u32(0), ..._u32(0), // width, height — audio has none
    ]),
    ...mdia,
  ]);

  final mvhd = _fullBox('mvhd', 0, [
    ..._u32(0), ..._u32(0), // creation, modification
    ..._u32(timescale), ..._u32(duration),
    ..._u32(0x00010000), // rate 1.0
    ..._u16(0x0100), // volume 1.0
    ..._u16(0), ..._u32(0), ..._u32(0), // reserved
    ..._unityMatrix,
    ..._u32(0), ..._u32(0), ..._u32(0),
    ..._u32(0), ..._u32(0), ..._u32(0), // pre_defined[6]
    ..._u32(2), // next_track_id
  ]);

  final udta = _udta(title: title, artist: artist);
  final moov = _box('moov', [...mvhd, ...trak, ...udta]);

  // Offset of the stco entry within moov. stbl is the last thing in trak, so
  // everything before it is just `trak.length - stbl.length`; add moov's own
  // header and mvhd in front, and stbl's internal offset behind.
  final stcoEntryIndex =
      8 + mvhd.length + (trak.length - stbl.bytes.length) + stbl.stcoEntryIndex;
  return (bytes: moov, stcoEntryIndex: stcoEntryIndex);
}

({Uint8List bytes, int stcoEntryIndex}) _stbl({
  required AdtsConfig config,
  required List<int> sampleSizes,
  required int payloadLength,
  required int duration,
}) {
  final sampleCount = sampleSizes.length;
  final stsd = _stsd(config: config, payloadLength: payloadLength, duration: duration);

  final head = <int>[
    ...stsd,
    ..._fullBox('stts', 0, [
      ..._u32(1),
      ..._u32(sampleCount), ..._u32(adtsSamplesPerFrame),
    ]),
    ..._fullBox('stsc', 0, [
      ..._u32(1),
      ..._u32(1), ..._u32(sampleCount), ..._u32(1), // one chunk holds them all
    ]),
    ..._fullBox('stsz', 0, [
      ..._u32(0), // 0 = per-sample sizes follow
      ..._u32(sampleCount),
      for (final s in sampleSizes) ..._u32(s),
    ]),
  ];
  // Patched later to point at the mdat *payload*, past its 8-byte header.
  final stco = _fullBox('stco', 0, [..._u32(1), ..._u32(0)]);
  final bytes = _box('stbl', [...head, ...stco]);
  return (bytes: bytes, stcoEntryIndex: 8 + head.length + stco.length - 4);
}

Uint8List _stsd({
  required AdtsConfig config,
  required int payloadLength,
  required int duration,
}) {
  final bitrate = duration == 0
      ? 0
      : payloadLength * 8 * config.sampleRate ~/ duration;

  // AudioSpecificConfig: AOT(5) | freqIndex(4) | channels(4) | three 0 bits.
  // AOT is the ADTS profile PLUS ONE — AAC-LC is profile 1, AOT 2.
  const audioObjectTypeAacLc = 2;
  final asc = [
    (audioObjectTypeAacLc << 3) | (config.freqIndex >> 1),
    ((config.freqIndex & 1) << 7) | (config.channels << 3),
  ];

  final esds = _fullBox('esds', 0, [
    ..._descriptor(0x03, [
      ..._u16(0), // ES_ID
      0, // no dependency, no URL, priority 0
      ..._descriptor(0x04, [
        0x40, // objectTypeIndication: MPEG-4 Audio
        0x15, // (streamType 6 << 2) | (upstream 0 << 1) | reserved 1
        ...[0x00, 0x18, 0x00], // bufferSizeDB 6144
        ..._u32(bitrate), // maxBitrate
        ..._u32(bitrate), // avgBitrate
        ..._descriptor(0x05, asc),
      ]),
      ..._descriptor(0x06, [0x02]), // SLConfig: predefined for MP4
    ]),
  ]);

  // The 16.16 field can't hold rates above 65535; the authoritative rate is the
  // one in the AudioSpecificConfig, so halve until it fits (as FFmpeg does).
  var entryRate = config.sampleRate;
  while (entryRate > 0xFFFF) {
    entryRate >>= 1;
  }

  final mp4a = _box('mp4a', [
    0, 0, 0, 0, 0, 0, // reserved
    ..._u16(1), // data_reference_index
    ..._u32(0), ..._u32(0), // QuickTime version/revision/vendor
    ..._u16(config.channels),
    ..._u16(16), // sample size
    ..._u16(0), // pre_defined
    ..._u16(0), // reserved
    ..._u16(entryRate), ..._u16(0), // 16.16 fixed point
    ...esds,
  ]);

  return _fullBox('stsd', 0, [..._u32(1), ...mp4a]);
}

/// iTunes-style metadata, so a player shows the note's title rather than the
/// filename. Empty when there's nothing to say.
Uint8List _udta({String? title, String? artist}) {
  final items = <int>[
    if (title != null && title.isNotEmpty)
      ..._boxRaw(const [0xA9, 0x6E, 0x61, 0x6D], _dataBox(title)), // ©nam
    if (artist != null && artist.isNotEmpty)
      ..._boxRaw(const [0xA9, 0x41, 0x52, 0x54], _dataBox(artist)), // ©ART
  ];
  if (items.isEmpty) return Uint8List(0);

  return _box('udta', [
    // Under an ISO brand `meta` is a FullBox; QuickTime's variant has no
    // version/flags, and a parser that guesses wrong drops the whole subtree.
    ..._fullBox('meta', 0, [
      ..._fullBox('hdlr', 0, [
        ..._u32(0),
        ..._fourcc('mdir'),
        ..._fourcc('appl'), // component manufacturer, in reserved[0]
        ..._u32(0), ..._u32(0),
        0, // empty name
      ]),
      ..._box('ilst', items),
    ]),
  ]);
}

/// `data` box: type indicator 1 (UTF-8), locale 0, then the raw text.
List<int> _dataBox(String value) =>
    _box('data', [..._u32(1), ..._u32(0), ...utf8.encode(value)]);
