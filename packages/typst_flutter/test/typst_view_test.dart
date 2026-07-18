import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/src/widgets/typst_view.dart';

void main() {
  test('all-white opaque SVG raster has no content', () {
    final rgba = Uint8List.fromList([255, 255, 255, 255]);

    expect(svgRasterHasContent(rgba), isFalse);
  });

  test('all-transparent SVG raster has no content', () {
    final rgba = Uint8List.fromList([0, 0, 0, 0]);

    expect(svgRasterHasContent(rgba), isFalse);
  });

  test('SVG raster with a dark pixel has content', () {
    final rgba = Uint8List.fromList([255, 255, 255, 255, 0, 0, 0, 255]);

    expect(svgRasterHasContent(rgba), isTrue);
  });
}
