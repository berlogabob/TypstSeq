/// Small value helpers shared by several `lib/src` files. Deliberately not
/// re-exported from `tylog_core.dart`: these are package-internal, and each
/// used to exist as a byte-identical private copy in every file that needed it.
library;

/// Coerces a decoded-JSON value into a list of strings, treating a missing or
/// non-list value as empty.
List<String> stringList(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();

/// Renders [value] as a Typst string literal.
String typstString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
