/// JPEG identity that ignores metadata segments.
///
/// Public because the sync layer needs it: on Android a geotagged photo reads
/// back with its GPS EXIF zeroed, so byte comparison reports a change that does
/// not exist on disk. See `src/image_identity.dart` for the full account.
library;

export 'src/image_identity.dart' show sameJpegIgnoringMetadata;
