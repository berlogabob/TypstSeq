/// Whether two JPEGs are the same picture, ignoring their metadata segments.
///
/// Android redacts GPS EXIF from images an app reads out of shared storage: the
/// bytes on disk keep the coordinates, the bytes the app receives have them
/// zeroed. Nothing in the app can opt out — the redaction decision is made from
/// the identity of the DocumentsProvider serving the read, not the app's, so
/// `ACCESS_MEDIA_LOCATION` does not reach it.
///
/// The consequence for sync is that a geotagged photo looks changed on the
/// device forever. It conflicts, and resolving does not help because the next
/// read is redacted again. Worse, "keep this device version" uploads the
/// redacted copy and destroys the coordinates on the server — the one
/// irreversible outcome, offered as the default.
///
/// Measured on a real vault: 3,257,635-byte photo, 49 bytes differing, all
/// inside the EXIF GPS block; every byte of image data identical. 248 JPEGs in
/// the vault, exactly 2 carry GPS, and exactly those 2 conflicted.
///
/// So: compare the compressed image data and skip the metadata. Same pixels
/// means the same picture, whatever the reader was allowed to see.
library;

/// True when [a] and [b] are JPEGs whose non-metadata segments are identical.
///
/// Returns false for anything that is not a parseable JPEG, so a caller can
/// treat false as "no opinion" and fall through to its normal comparison.
bool sameJpegIgnoringMetadata(List<int> a, List<int> b) {
  final left = _payloadSegments(a);
  final right = _payloadSegments(b);
  if (left == null || right == null) return false;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    final x = left[i];
    final y = right[i];
    if (x.marker != y.marker || x.length != y.length) return false;
    for (var k = 0; k < x.length; k++) {
      if (a[x.start + k] != b[y.start + k]) return false;
    }
  }
  return true;
}

/// Metadata markers, skipped by [sameJpegIgnoringMetadata]:
/// APP0–APP15 (`0xE0`–`0xEF`, which covers JFIF and the EXIF APP1 block) and
/// COM (`0xFE`). Everything else — quantisation tables, Huffman tables, frame
/// headers and the entropy-coded scan — is image data and must match.
bool _isMetadata(int marker) =>
    (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE;

class _Segment {
  const _Segment(this.marker, this.start, this.length);
  final int marker;
  final int start;
  final int length;
}

/// Walks the JPEG segment structure, returning the non-metadata segments, or
/// null if the bytes are not a JPEG we can parse confidently.
List<_Segment>? _payloadSegments(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  final segments = <_Segment>[];
  var i = 2;
  while (i + 1 < bytes.length) {
    if (bytes[i] != 0xFF) return null;
    var marker = bytes[i + 1];
    // Fill bytes: any number of 0xFF may pad before the marker.
    var cursor = i + 1;
    while (marker == 0xFF && cursor + 1 < bytes.length) {
      cursor++;
      marker = bytes[cursor];
    }
    if (marker == 0xD9) break; // EOI
    // Start of scan: the entropy-coded data runs to the end. Compare it whole
    // rather than trying to parse it.
    if (marker == 0xDA) {
      segments.add(_Segment(marker, cursor + 1, bytes.length - cursor - 1));
      break;
    }
    if (cursor + 3 >= bytes.length) return null;
    final length = (bytes[cursor + 1] << 8) | bytes[cursor + 2];
    if (length < 2) return null;
    final start = cursor + 3;
    final payload = length - 2;
    if (start + payload > bytes.length) return null;
    if (!_isMetadata(marker)) {
      segments.add(_Segment(marker, start, payload));
    }
    i = start + payload;
  }
  return segments.isEmpty ? null : segments;
}
