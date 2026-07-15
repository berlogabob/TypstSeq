import 'package:typst_flutter/src/rust/api/markdown_import.dart' as api;
import 'package:typst_flutter/src/rust/frb_generated.dart';

/// Converts CommonMark/GFM into editable Typst using the bundled native bridge.
Future<api.MarkdownTypstResult> convertMarkdown({
  required String markdown,
  required String title,
  String? baseUrl,
}) async {
  try {
    await RustLib.init();
    // A compiler or earlier import may already have initialised the bridge.
    // ignore: avoid_catching_errors
  } on StateError catch (error) {
    if (!error.message.contains('twice')) rethrow;
  }
  return api.convertMarkdown(
    markdown: markdown,
    title: title,
    baseUrl: baseUrl,
  );
}
