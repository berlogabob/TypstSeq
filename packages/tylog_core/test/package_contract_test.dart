import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/src/scanner.dart';

/// The guard that was missing when the app started writing `clocked:` as a
/// named argument the Typst package had never declared.
///
/// That single mismatch cost 167 notes: every one carrying the field stopped
/// compiling, and nothing complained, because the fallback parser reads a
/// broken call back as a perfectly good note. It was found by compiling the
/// vault by hand, days later. Worse, the corrected shape then landed on one
/// device before the other, so the two disagreed and sync raised conflicts on
/// every affected note — which is how a format slip turns into a data problem.
///
/// The rule this pins: **TyLog may only write field names the shipped package
/// declares.** Adding a writer for a new field now fails here until the field
/// exists in `typst/tylog/lib.typ`.
///
/// This is a source-level check on purpose. `make test-typst` compiles a
/// fixture of hand-written call shapes, and `writer_compiles_test.dart`
/// compiles each writer's output — both only cover shapes someone remembered
/// to exercise. This one cannot be forgotten: it derives the package's side
/// from the package itself.
void main() {
  final packagePath = File('../../typst/tylog/lib.typ');

  /// Parameter names declared by `#let <name>(...)` in the Typst package.
  Set<String> declaredParameters(String source, String function) {
    final start = source.indexOf('#let $function('.replaceAll(r'$function', function));
    expect(start, isNot(-1), reason: 'no #let $function( in lib.typ');
    final body = source.substring(start, source.indexOf(') = [', start));
    return {
      for (final line in body.split('\n'))
        if (RegExp(r'^\s{2}([a-z][a-z0-9-]*):').firstMatch(line)
            case final match?)
          match.group(1)!,
    };
  }

  test('every field TyLog writes is declared by the Typst package', () {
    expect(
      packagePath.existsSync(),
      isTrue,
      reason: 'run from packages/tylog_core; expected ${packagePath.path}',
    );
    final source = packagePath.readAsStringSync();

    final task = declaredParameters(source, 'task');
    final note = declaredParameters(source, 'note');

    // Sanity: the parse found a real signature, not an empty set that would
    // make every assertion below vacuous.
    expect(task, contains('id'), reason: 'task signature parsed');
    expect(note, contains('title'), reason: 'note signature parsed');

    expect(
      writableTaskFields.difference(task),
      isEmpty,
      reason:
          'these task fields are written by TyLog but not declared in '
          'typst/tylog/lib.typ — a note carrying one will not compile',
    );
    expect(
      writableNoteFields.difference(note),
      isEmpty,
      reason:
          'these note-header fields are written by TyLog but not declared in '
          'typst/tylog/lib.typ',
    );
  });

  test('the check would catch an undeclared field', () {
    final source = packagePath.readAsStringSync();
    final task = declaredParameters(source, 'task');

    // `clocked` is exactly what was wrongly written as a named argument. It
    // must not be declared — the fix moved that data into `properties`.
    expect(
      task,
      isNot(contains('clocked')),
      reason: 'time tracking lives in properties, not as its own argument',
    );
    expect(
      {'clocked'}.difference(task),
      isNotEmpty,
      reason: 'so adding it to writableTaskFields would fail the test above',
    );
  });
}
