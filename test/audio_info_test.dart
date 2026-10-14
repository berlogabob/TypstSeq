import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/audio/audio_info.dart';

void main() {
  test('mp3 header gives the sample rate and an average bitrate', () {
    // MPEG1 Layer III, 128 kbps, 44.1 kHz frame header.
    final b = Uint8List.fromList([
      0xFF,
      0xFB,
      0x90,
      0x00,
      ...List.filled(1996, 0),
    ]);
    final info = audioInfo(b, 'mp3', 1000);
    expect(info.format, 'MP3');
    expect(info.sampleRate, 44100);
    expect(info.bitrateKbps, 16); // 2000 B in 1 s
  });

  test('wav and adts sample rates', () {
    final wav = Uint8List(44)
      ..[24] = 0x44
      ..[25] = 0xAC; // 44100
    expect(audioInfo(wav, 'wav', null).sampleRate, 44100);
    final adts = Uint8List.fromList([0xFF, 0xF1, 0x50, 0x80, 0, 0, 0]); // idx 4
    expect(audioInfo(adts, 'aac', null).sampleRate, 44100);
  });

  test('m4a mdhd timescale', () {
    final b = Uint8List.fromList([
      ...'mdhd'.codeUnits, 0, 0, 0, 0, // version 0 + flags
      0, 0, 0, 0, 0, 0, 0, 0, // created, modified
      0, 0, 0xBB, 0x80, // timescale 48000
      ...List.filled(8, 0),
    ]);
    expect(audioInfo(b, 'm4a', 1000).sampleRate, 48000);
  });

  test('a real vault m4a, when present', () {
    final f = File(
      '${Platform.environment['HOME']}/Nextcloud/TyLogVault/assets/audio/2026/10/20261014-081648.m4a',
    );
    if (!f.existsSync()) return;
    final info = audioInfo(f.readAsBytesSync(), 'm4a', 11000);
    expect(info.sampleRate, anyOf(16000, 22050, 24000, 32000, 44100, 48000));
  });
}
