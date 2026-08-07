import 'package:test/test.dart';
import 'package:tylog_core/src/image_identity.dart';

/// Builds a minimal but structurally valid JPEG.
///
/// `exif` becomes the APP1 payload (metadata — must be ignored), `pixels`
/// becomes the entropy-coded scan (image data — must not be).
List<int> _jpeg({required List<int> exif, required List<int> pixels}) => [
  0xFF, 0xD8, // SOI
  0xFF, 0xE1, ..._be16(exif.length + 2), ...exif, // APP1
  0xFF, 0xDB, ..._be16(6), 0x00, 0x01, 0x02, 0x03, // DQT
  0xFF, 0xDA, ..._be16(4), 0x01, 0x00, ...pixels, // SOS + scan
  0xFF, 0xD9, // EOI
];

List<int> _be16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

void main() {
  group('sameJpegIgnoringMetadata', () {
    // The real case: Android hands the app a GPS-redacted copy of a photo whose
    // bytes on disk are intact. Same length, same pixels, zeroed coordinates.
    // Verified against the real pair from the vault — 3,257,635 bytes, 49
    // differing, all inside EXIF.
    test('a redacted copy is the same picture', () {
      final onDisk = _jpeg(
        exif: [0x45, 0x78, 0x69, 0x66, 0x4E, 0x57], // …N, W
        pixels: [1, 2, 3, 4, 5, 6, 7, 8],
      );
      final asRead = _jpeg(
        exif: [0x45, 0x78, 0x69, 0x66, 0x00, 0x00], // coordinates stripped
        pixels: [1, 2, 3, 4, 5, 6, 7, 8],
      );

      expect(onDisk.length, asRead.length);
      expect(onDisk, isNot(asRead));
      expect(sameJpegIgnoringMetadata(onDisk, asRead), isTrue);
    });

    // The guard that keeps this honest. If this ever returns true, the sync
    // would silently discard one of two genuinely different photos.
    test('a different picture is not the same picture', () {
      final a = _jpeg(exif: [1, 2, 3, 4], pixels: [1, 2, 3, 4, 5, 6, 7, 8]);
      final b = _jpeg(exif: [1, 2, 3, 4], pixels: [1, 2, 3, 4, 5, 6, 7, 9]);

      expect(a.length, b.length, reason: 'same length, different pixels');
      expect(sameJpegIgnoringMetadata(a, b), isFalse);
    });

    test('differing scan length is not the same picture', () {
      final a = _jpeg(exif: [1, 2], pixels: [1, 2, 3, 4]);
      final b = _jpeg(exif: [1, 2], pixels: [1, 2, 3, 4, 5]);

      expect(sameJpegIgnoringMetadata(a, b), isFalse);
    });

    test('a differing quantisation table is not the same picture', () {
      final a = _jpeg(exif: const [], pixels: [9, 9]);
      final b = List<int>.from(a);
      // Corrupt one DQT byte — image data, not metadata.
      b[b.indexOf(0xDB) + 4] = 0x7F;

      expect(sameJpegIgnoringMetadata(a, b), isFalse);
    });

    // "No opinion" for anything unparseable, so a caller falls through to its
    // ordinary byte comparison rather than trusting a guess.
    test('non-JPEG input yields no opinion', () {
      final png = [0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4];

      expect(sameJpegIgnoringMetadata(png, png), isFalse);
      expect(sameJpegIgnoringMetadata(const [], const []), isFalse);
      expect(sameJpegIgnoringMetadata(const [0xFF, 0xD8], const [0xFF, 0xD8]),
          isFalse);
    });

    test('a truncated segment yields no opinion rather than a crash', () {
      final good = _jpeg(exif: [1, 2, 3, 4], pixels: [5, 6]);
      final truncated = good.sublist(0, 8);

      expect(
        () => sameJpegIgnoringMetadata(good, truncated),
        returnsNormally,
      );
      expect(sameJpegIgnoringMetadata(good, truncated), isFalse);
    });
  });
}
