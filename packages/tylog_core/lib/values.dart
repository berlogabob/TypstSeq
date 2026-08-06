/// Typst value rendering, shared with the app.
///
/// [typstString] is public because it kept being copied instead: the app had a
/// byte-identical duplicate in `lib/controlled_editor.dart` and a weaker
/// variant in `lib/vault.dart` that escaped `"` but not `\`. Anything writing a
/// Typst string literal must use this one — getting it wrong produces a note
/// that cannot compile, and the scanner's fallback parser reads the result back
/// as valid, so nothing complains.
///
/// `stringList` stays package-internal; it is a JSON-decoding helper with no
/// business outside `src/`.
library;

export 'src/values.dart' show escapeMarkup, typstString;
