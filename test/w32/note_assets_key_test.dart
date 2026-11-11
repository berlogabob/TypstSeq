import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';

void main() {
  test('typing prose does not change the referenced-asset key', () {
    const base = 'Intro #image("assets/a.png") and #image("/assets/b.JPG")';
    final key = referencedAssetKey(base);
    for (var i = 0; i < 10; i++) {
      expect(referencedAssetKey('$base${'x' * i}'), key);
    }
  });

  test(
    'adding, removing or reordering assets changes only when the set does',
    () {
      const a = '"assets/a.png"';
      const b = '"assets/b.png"';
      expect(referencedAssetKey('$a $b'), referencedAssetKey('$b $a $a'));
      expect(referencedAssetKey('$a $b'), isNot(referencedAssetKey(a)));
      expect(referencedAssetKey('no images'), '');
    },
  );

  test('only image files under assets/ count', () {
    expect(
      referencedAssetPaths('"assets/x.pdf" "other/y.png" "assets/z.webp"'),
      {'assets/z.webp'},
    );
  });
}
