import 'package:flutter/material.dart';

/// A [CircularProgressIndicator], optionally boxed to a fixed [size].
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key, this.size, this.strokeWidth});

  final double? size;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final indicator = CircularProgressIndicator(strokeWidth: strokeWidth ?? 4);
    return size == null
        ? indicator
        : SizedBox.square(dimension: size, child: indicator);
  }
}
