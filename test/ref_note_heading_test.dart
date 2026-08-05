import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';

void main() {
  test('refNoteHeading extracts and unescapes the optional heading', () {
    expect(
      refNoteHeading(
        r'#tylog.ref-note("target", heading: "Deep \"dive\"")[link]',
      ),
      'Deep "dive"',
    );
    expect(refNoteHeading(r'#tylog.ref-note("target")[link]'), isNull);
  });
}
