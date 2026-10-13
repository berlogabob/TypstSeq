import 'dart:convert';
import 'dart:typed_data';

import 'package:tylog_audio/src/m4a_muxer.dart';
import 'package:flutter_test/flutter_test.dart';

const _freqIdx48k = 3;
const _freqIdx44k = 4;

/// One synthesised ADTS frame. Only the 7 header bytes need to be real — the
/// payload is opaque to the muxer, which copies it verbatim.
Uint8List _adtsFrame({
  int payload = 100,
  int freqIdx = _freqIdx44k,
  int channels = 1,
  int profile = 1, // AAC-LC
  int rawBlocks = 0,
  int fill = 0xAB,
}) {
  final length = 7 + payload;
  final f = Uint8List(length)..fillRange(7, length, fill);
  f[0] = 0xFF;
  f[1] = 0xF1; // sync + MPEG-4 + layer 00 + protection_absent
  f[2] = (profile << 6) | (freqIdx << 2) | ((channels >> 2) & 0x01);
  f[3] = ((channels & 0x03) << 6) | ((length >> 11) & 0x03);
  f[4] = (length >> 3) & 0xFF;
  f[5] = ((length & 0x07) << 5) | 0x1F;
  f[6] = 0xFC | (rawBlocks & 0x03);
  return f;
}

Uint8List _adts(
  int count, {
  int payload = 100,
  int freqIdx = _freqIdx44k,
  int channels = 1,
  int profile = 1,
  int rawBlocks = 0,
}) {
  final out = BytesBuilder();
  for (var i = 0; i < count; i++) {
    out.add(
      _adtsFrame(
        payload: payload,
        freqIdx: freqIdx,
        channels: channels,
        profile: profile,
        rawBlocks: rawBlocks,
        fill: 0xA0 + i,
      ),
    );
  }
  return out.toBytes();
}

/// Minimal ISO-BMFF walker: returns every box at [start]..[end] as
/// type -> (offset of the box, its total length).
Map<String, (int, int)> _boxes(Uint8List b, int start, int end) {
  final out = <String, (int, int)>{};
  var pos = start;
  while (pos + 8 <= end) {
    final size = ByteData.sublistView(b).getUint32(pos);
    final type = String.fromCharCodes(b.sublist(pos + 4, pos + 8));
    if (size < 8) break;
    out[type] = (pos, size);
    pos += size;
  }
  return out;
}

/// Finds a box by its path, e.g. `moov/trak/mdia/mdhd`. Containers are walked
/// from their first child; FullBox containers need their 4 version/flags bytes
/// skipped, which [skip] supplies per level.
(int, int) _find(Uint8List b, String path, {Map<String, int> skip = const {}}) {
  var start = 0;
  var end = b.length;
  late (int, int) hit;
  for (final name in path.split('/')) {
    final found = _boxes(b, start, end)[name];
    expect(found, isNotNull, reason: 'missing box $name in $path');
    hit = found!;
    start = hit.$1 + 8 + (skip[name] ?? 0);
    end = hit.$1 + hit.$2;
  }
  return hit;
}

int _u32At(Uint8List b, int offset) =>
    ByteData.sublistView(b).getUint32(offset);

/// Bytes 12..50 of the `esds` Apple writes for 48kHz mono AAC-LC, i.e. the
/// whole descriptor tree. Read out of AVFCore's record_start.m4a. The two
/// bitrate fields (indices 15..22 of this slice) are computed by us and are
/// excluded by the test that uses this.
const _appleEsdsDescriptors = [
  0x03, 0x80, 0x80, 0x80, 0x22, // ES_Descriptor, len 34
  0x00, 0x00, // ES_ID
  0x00, // flags
  0x04, 0x80, 0x80, 0x80, 0x14, // DecoderConfigDescriptor, len 20
  0x40, // objectTypeIndication: MPEG-4 Audio
  0x15, // streamType 6 (audio) << 2 | 0 | 1
  0x00, 0x18, 0x00, // bufferSizeDB 6144       (indices 15..17)
  0x00, 0x00, 0x00, 0x00, // maxBitrate  <- ours differs (18..21)
  0x00, 0x00, 0xFA, 0x00, // avgBitrate  <- ours differs (22..25)
  0x05, 0x80, 0x80, 0x80, 0x02, // DecoderSpecificInfo, len 2
  0x11, 0x88, // AudioSpecificConfig: AOT 2, freqIdx 3, chCfg 1
  0x06, 0x80, 0x80, 0x80, 0x01, // SLConfigDescriptor, len 1
  0x02, // predefined: MP4
];

void main() {
  group('container shape', () {
    test('writes ftyp, moov and mdat in that order', () {
      final m4a = m4aFromAdts(_adts(10))!;
      final top = _boxes(m4a, 0, m4a.length);
      expect(top.keys, ['ftyp', 'moov', 'mdat']);
      expect(top['ftyp']!.$1, 0, reason: 'ftyp must come first');
      // moov before mdat, so a streaming player can start without the whole file
      expect(top['moov']!.$1, lessThan(top['mdat']!.$1));
    });

    test('declares the brands Apple does', () {
      final m4a = m4aFromAdts(_adts(3))!;
      expect(
        m4a.sublist(0, 28),
        [
          0, 0, 0, 28, ...ascii.encode('ftyp'),
          ...ascii.encode('M4A '), 0, 0, 0, 0,
          ...ascii.encode('M4A '), ...ascii.encode('mp42'), ...ascii.encode('isom'),
        ],
      );
    });

    test('nests the full audio track', () {
      final m4a = m4aFromAdts(_adts(3))!;
      const skip = {'stsd': 8}; // FullBox version/flags + entry_count
      for (final path in [
        'moov/mvhd',
        'moov/trak/tkhd',
        'moov/trak/mdia/mdhd',
        'moov/trak/mdia/hdlr',
        'moov/trak/mdia/minf/smhd',
        'moov/trak/mdia/minf/dinf/dref',
        'moov/trak/mdia/minf/stbl/stsd',
        'moov/trak/mdia/minf/stbl/stts',
        'moov/trak/mdia/minf/stbl/stsc',
        'moov/trak/mdia/minf/stbl/stsz',
        'moov/trak/mdia/minf/stbl/stco',
        'moov/trak/mdia/minf/stbl/stsd/mp4a',
      ]) {
        expect(() => _find(m4a, path, skip: skip), returnsNormally, reason: path);
      }
    });

    test('handler is soun', () {
      final m4a = m4aFromAdts(_adts(3))!;
      final (offset, _) = _find(m4a, 'moov/trak/mdia/hdlr');
      expect(String.fromCharCodes(m4a.sublist(offset + 16, offset + 20)), 'soun');
    });
  });

  group('descriptors', () {
    test('esds matches Apple byte-for-byte apart from the bitrates', () {
      // Same parameters as the reference file: 48kHz, mono, AAC-LC.
      final m4a = m4aFromAdts(_adts(14, freqIdx: _freqIdx48k))!;
      final (offset, size) = _find(
        m4a,
        'moov/trak/mdia/minf/stbl/stsd/mp4a/esds',
        skip: {'stsd': 8, 'mp4a': 28},
      );
      expect(size, 51, reason: "Apple's esds is exactly 51 bytes");
      final descriptors = m4a.sublist(offset + 12, offset + size);
      for (var i = 0; i < _appleEsdsDescriptors.length; i++) {
        if (i >= 18 && i < 26) continue; // max/avg bitrate: ours is computed
        expect(
          descriptors[i],
          _appleEsdsDescriptors[i],
          reason: 'esds descriptor byte $i',
        );
      }
    });

    test('stsd and mp4a come out at the reference sizes', () {
      final m4a = m4aFromAdts(_adts(5, freqIdx: _freqIdx48k))!;
      expect(_find(m4a, 'moov/trak/mdia/minf/stbl/stsd').$2, 103);
      expect(
        _find(m4a, 'moov/trak/mdia/minf/stbl/stsd/mp4a', skip: {'stsd': 8}).$2,
        87,
      );
    });

    test('AudioObjectType is the ADTS profile plus one', () {
      // ADTS profile 1 (LC) must become AOT 2. Writing 1 would say "AAC Main"
      // and Android's decoder would reject it.
      final m4a = m4aFromAdts(_adts(4))!; // the fixture defaults to 44.1kHz
      final (offset, size) = _find(
        m4a,
        'moov/trak/mdia/minf/stbl/stsd/mp4a/esds',
        skip: {'stsd': 8, 'mp4a': 28},
      );
      final asc = m4a.sublist(offset + size - 8, offset + size - 6);
      expect(asc[0] >> 3, 2, reason: 'AOT');
      expect(((asc[0] & 0x07) << 1) | (asc[1] >> 7), _freqIdx44k);
      expect((asc[1] >> 3) & 0x0F, 1, reason: 'channel config');
    });

    test('AudioSpecificConfig tracks rate and channels', () {
      for (final (freqIdx, channels) in [(3, 1), (4, 2), (8, 2), (11, 1)]) {
        final m4a = m4aFromAdts(_adts(3, freqIdx: freqIdx, channels: channels))!;
        final (offset, size) = _find(
          m4a,
          'moov/trak/mdia/minf/stbl/stsd/mp4a/esds',
          skip: {'stsd': 8, 'mp4a': 28},
        );
        final asc = m4a.sublist(offset + size - 8, offset + size - 6);
        expect(((asc[0] & 0x07) << 1) | (asc[1] >> 7), freqIdx);
        expect((asc[1] >> 3) & 0x0F, channels);
      }
    });
  });

  group('sample tables', () {
    test('stts is one entry of 1024-sample frames', () {
      final m4a = m4aFromAdts(_adts(14))!;
      final (offset, _) = _find(m4a, 'moov/trak/mdia/minf/stbl/stts');
      expect(_u32At(m4a, offset + 12), 1, reason: 'entry_count');
      expect(_u32At(m4a, offset + 16), 14, reason: 'sample_count');
      expect(_u32At(m4a, offset + 20), 1024, reason: 'sample_delta');
    });

    test('stsc puts every sample in one chunk', () {
      final m4a = m4aFromAdts(_adts(14))!;
      final (offset, _) = _find(m4a, 'moov/trak/mdia/minf/stbl/stsc');
      expect(_u32At(m4a, offset + 12), 1, reason: 'entry_count');
      expect(_u32At(m4a, offset + 16), 1, reason: 'first_chunk');
      expect(_u32At(m4a, offset + 20), 14, reason: 'samples_per_chunk');
    });

    test('stsz sizes sum to the mdat payload', () {
      final m4a = m4aFromAdts(_adts(9, payload: 137))!;
      final (offset, _) = _find(m4a, 'moov/trak/mdia/minf/stbl/stsz');
      expect(_u32At(m4a, offset + 12), 0, reason: 'per-sample table follows');
      expect(_u32At(m4a, offset + 16), 9);
      var total = 0;
      for (var i = 0; i < 9; i++) {
        final size = _u32At(m4a, offset + 20 + i * 4);
        expect(size, 137, reason: 'payload only, header stripped');
        total += size;
      }
      final (_, mdatSize) = _find(m4a, 'mdat');
      expect(total, mdatSize - 8);
    });

    test('stco points at the mdat payload, not the box header', () {
      final m4a = m4aFromAdts(_adts(6))!;
      final (offset, _) = _find(m4a, 'moov/trak/mdia/minf/stbl/stco');
      expect(_u32At(m4a, offset + 12), 1, reason: 'entry_count');
      final chunkOffset = _u32At(m4a, offset + 16);
      final (mdatOffset, _) = _find(m4a, 'mdat');
      expect(
        chunkOffset,
        mdatOffset + 8,
        reason: 'past the 8-byte mdat header, or playback is noise',
      );
      final (_, ftypSize) = _find(m4a, 'ftyp');
      final (_, moovSize) = _find(m4a, 'moov');
      expect(chunkOffset, ftypSize + moovSize + 8);
    });
  });

  group('durations', () {
    test('all three durations agree, in one timescale', () {
      final m4a = m4aFromAdts(_adts(20))!; // the fixture defaults to 44.1kHz
      const expected = 20 * 1024;
      final (mvhd, _) = _find(m4a, 'moov/mvhd');
      final (tkhd, _) = _find(m4a, 'moov/trak/tkhd');
      final (mdhd, _) = _find(m4a, 'moov/trak/mdia/mdhd');
      expect(_u32At(m4a, mvhd + 20), 44100, reason: 'mvhd timescale');
      expect(_u32At(m4a, mvhd + 24), expected, reason: 'mvhd duration');
      expect(_u32At(m4a, tkhd + 28), expected, reason: 'tkhd duration');
      expect(_u32At(m4a, mdhd + 20), 44100, reason: 'mdhd timescale');
      expect(_u32At(m4a, mdhd + 24), expected, reason: 'mdhd duration');
    });

    test('language is the packed und marker', () {
      final m4a = m4aFromAdts(_adts(3))!;
      final (mdhd, _) = _find(m4a, 'moov/trak/mdia/mdhd');
      expect(ByteData.sublistView(m4a).getUint16(mdhd + 28), 0x55C4);
    });
  });

  group('mdat', () {
    test('holds bare access units with no ADTS syncword', () {
      final m4a = m4aFromAdts(_adts(8))!;
      final (offset, size) = _find(m4a, 'mdat');
      final payload = m4a.sublist(offset + 8, offset + size);
      for (var i = 0; i + 1 < payload.length; i++) {
        expect(
          payload[i] == 0xFF && (payload[i + 1] & 0xF0) == 0xF0,
          isFalse,
          reason: 'ADTS header survived into mdat at $i',
        );
      }
    });

    test('first sample is the first frame payload, header removed', () {
      final aac = _adts(4, payload: 64);
      final m4a = m4aFromAdts(aac)!;
      final (offset, _) = _find(m4a, 'mdat');
      expect(m4a.sublist(offset + 8, offset + 8 + 64), aac.sublist(7, 7 + 64));
    });
  });

  group('metadata', () {
    test('carries the title and artist', () {
      final m4a = m4aFromAdts(_adts(3), title: 'Bridge riff', artist: 'FlowGroove')!;
      expect(() => _find(m4a, 'moov/udta/meta/ilst', skip: {'meta': 4}),
          returnsNormally);
      expect(String.fromCharCodes(m4a), contains('Bridge riff'));
      expect(String.fromCharCodes(m4a), contains('FlowGroove'));
    });

    test('the copyright fourcc is one byte, not UTF-8 encoded', () {
      // utf8.encode('©nam') is FIVE bytes; that would corrupt the box type and
      // shift every size after it.
      final m4a = m4aFromAdts(_adts(3), title: 'x')!;
      final (ilst, _) = _find(m4a, 'moov/udta/meta/ilst', skip: {'meta': 4});
      expect(m4a.sublist(ilst + 12, ilst + 16), [0xA9, 0x6E, 0x61, 0x6D]);
      expect(m4a.sublist(ilst + 12, ilst + 16), isNot(utf8.encode('©nam')));
    });

    test('meta is a FullBox, so version/flags precede its children', () {
      final m4a = m4aFromAdts(_adts(3), title: 'x')!;
      final (meta, _) = _find(m4a, 'moov/udta/meta');
      expect(m4a.sublist(meta + 8, meta + 12), [0, 0, 0, 0]);
      // The first child starts after those four bytes, not immediately.
      expect(String.fromCharCodes(m4a.sublist(meta + 16, meta + 20)), 'hdlr');
    });

    test('omits udta entirely when there is nothing to say', () {
      final m4a = m4aFromAdts(_adts(3))!;
      expect(_boxes(m4a, 0, m4a.length).containsKey('moov'), isTrue);
      final (moov, moovSize) = _find(m4a, 'moov');
      expect(_boxes(m4a, moov + 8, moov + moovSize).keys, ['mvhd', 'trak']);
    });
  });

  group('refuses what it cannot represent', () {
    test('non-ADTS input', () {
      expect(m4aFromAdts(Uint8List.fromList('RIFFxxxxWAVE'.codeUnits)), isNull);
      expect(m4aFromAdts(Uint8List(0)), isNull);
    });

    test('a profile other than AAC-LC', () {
      // Profile 0 is Main; its AOT is 1, which this muxer does not write.
      expect(m4aFromAdts(_adts(4, profile: 0)), isNull);
      expect(m4aFromAdts(_adts(4, profile: 3)), isNull);
    });

    test('a channel configuration that lives in a PCE', () {
      expect(m4aFromAdts(_adts(4, channels: 0)), isNull);
    });

    test('a reserved or escape frequency index', () {
      for (final freqIdx in [13, 14, 15]) {
        expect(m4aFromAdts(_adts(4, freqIdx: freqIdx)), isNull, reason: '$freqIdx');
      }
    });

    test('frames carrying more than one raw data block', () {
      // Those are 2048+ samples, so a 1024 sample_delta would be a lie.
      expect(m4aFromAdts(_adts(4, rawBlocks: 1)), isNull);
    });
  });

  test('round-trips the sample count of a real-length take', () {
      // ~15s at 44.1kHz is 646 frames, the size the device test produces.
    final m4a = m4aFromAdts(_adts(646, payload: 380))!;
    final (stsz, _) = _find(m4a, 'moov/trak/mdia/minf/stbl/stsz');
    expect(_u32At(m4a, stsz + 16), 646);
    final (mdat, mdatSize) = _find(m4a, 'mdat');
    expect(mdatSize - 8, 646 * 380);
    expect(_u32At(m4a, _find(m4a, 'moov/trak/mdia/minf/stbl/stco').$1 + 16),
        mdat + 8);
  });
}
