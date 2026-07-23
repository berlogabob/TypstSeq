import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';

void main() {
  // Must match the private _autoRelatedMarker in app_mobile.dart.
  const marker = '// tylog:auto-related';
  const body = '#import "x"\n\n= Title\n\nBody text.';

  test('stripAutoRelated removes an appended block and is idempotent', () {
    final withBlock =
        '$body\n\n$marker\n== Related\n#tylog.ref-note("a")[A]\n';
    final stripped = stripAutoRelated(withBlock);
    expect(stripped, body, reason: 'block and its trailing whitespace removed');

    // Stripping the clean body again is a no-op.
    expect(stripAutoRelated(stripped), body);

    // Re-appending a *different* block then stripping returns to the same body —
    // this is what makes a repeated "Relink vault" idempotent, not duplicating.
    final reAppended =
        '$stripped\n\n$marker\n== Related\n#tylog.ref-note("b")[B]\n';
    expect(stripAutoRelated(reAppended), body);
  });

  test('stripAutoRelated leaves marker-free source untouched', () {
    const plain = '= Note\n\nNo related block here.';
    expect(stripAutoRelated(plain), plain);
  });
}
