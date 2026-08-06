/// Small value helpers shared by several `lib/src` files.
///
/// Each of these used to exist as a byte-identical private copy in every file
/// that needed it. `typstString` is now re-exported from `values.dart` for the
/// app too, because copies kept reappearing there — one of them subtly wrong.
/// `stringList` stays internal.
library;

/// Coerces a decoded-JSON value into a list of strings, treating a missing or
/// non-list value as empty.
List<String> stringList(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();

/// Renders [value] as a Typst string literal.
String typstString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// Escapes Typst's markup-mode special characters so [value] renders as literal
/// text.
///
/// The inverse of `unescapeMarkup`, which lives beside the importer that needs
/// it. Anything interpolating user text into markup — a heading, a chip label,
/// a list item — has to go through this, or a title containing `#` or `[`
/// silently produces a note that will not compile.
String escapeMarkup(String value) => value.replaceAllMapped(
  RegExp(r'[\\#\[\]\$*_@]'),
  (match) => '\\${match.group(0)}',
);
