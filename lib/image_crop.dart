import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tylog_core/storage.dart';

Rect cropMove(Rect rect, Rect bounds, Offset delta) => rect.shift(
  Offset(
    delta.dx.clamp(bounds.left - rect.left, bounds.right - rect.right),
    delta.dy.clamp(bounds.top - rect.top, bounds.bottom - rect.bottom),
  ),
);

Rect cropPreset(Rect rect, Rect bounds, double ratio) {
  final maxWidth = math.min(bounds.width, bounds.height * ratio);
  final minWidth = math.min(maxWidth, math.max(32.0, 32 * ratio));
  final width = math
      .min(rect.width, rect.height * ratio)
      .clamp(minWidth, maxWidth);
  final next = Rect.fromCenter(
    center: rect.center,
    width: width,
    height: width / ratio,
  );
  return cropMove(next, bounds, Offset.zero);
}

/// Corner order: top left, top right, bottom right, bottom left.
Rect cropResize(
  Rect rect,
  Rect bounds,
  int corner,
  Offset delta,
  double? ratio,
) {
  final left = corner == 0 || corner == 3;
  final top = corner < 2;
  final anchor = Offset(
    left ? rect.right : rect.left,
    top ? rect.bottom : rect.top,
  );
  final maxWidth = left ? anchor.dx - bounds.left : bounds.right - anchor.dx;
  final maxHeight = top ? anchor.dy - bounds.top : bounds.bottom - anchor.dy;
  var width = rect.width + (left ? -delta.dx : delta.dx);
  var height = rect.height + (top ? -delta.dy : delta.dy);
  if (ratio == null) {
    width = width.clamp(math.min(32.0, maxWidth), maxWidth);
    height = height.clamp(math.min(32.0, maxHeight), maxHeight);
  } else {
    final max = math.min(maxWidth, maxHeight * ratio);
    final min = math.min(max, math.max(32.0, 32 * ratio));
    width = ((width + height * ratio) / 2).clamp(min, max);
    height = width / ratio;
  }
  return Rect.fromLTWH(
    left ? anchor.dx - width : anchor.dx,
    top ? anchor.dy - height : anchor.dy,
    width,
    height,
  );
}

/// Map the fitted (possibly letterboxed) image to whole source pixels.
Rect cropPixels(Rect rect, Rect imageBounds, Size pixels) {
  final clipped = rect.intersect(imageBounds);
  final left =
      ((clipped.left - imageBounds.left) / imageBounds.width * pixels.width)
          .round()
          .clamp(0, pixels.width.toInt() - 1);
  final top =
      ((clipped.top - imageBounds.top) / imageBounds.height * pixels.height)
          .round()
          .clamp(0, pixels.height.toInt() - 1);
  final right =
      ((clipped.right - imageBounds.left) / imageBounds.width * pixels.width)
          .round()
          .clamp(left + 1, pixels.width.toInt());
  final bottom =
      ((clipped.bottom - imageBounds.top) / imageBounds.height * pixels.height)
          .round()
          .clamp(top + 1, pixels.height.toInt());
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right.toDouble(),
    bottom.toDouble(),
  );
}

Future<ui.Image> decodeCropImage(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final longSide = math.max(descriptor.width, descriptor.height);
    // ponytail: cap decoded images at 4096 px; tiled decoding if larger crops are needed.
    final scale = math.min(1.0, 4096 / longSide);
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<Uint8List> encodeImageCrop(ui.Image image, Rect pixels) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    pixels,
    Rect.fromLTWH(0, 0, pixels.width, pixels.height),
    Paint()..filterQuality = FilterQuality.none,
  );
  final picture = recorder.endRecording();
  ui.Image? cropped;
  try {
    cropped = await picture.toImage(
      pixels.width.toInt(),
      pixels.height.toInt(),
    );
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode cropped image');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    cropped?.dispose();
    picture.dispose();
  }
}

Future<String> saveImageCrop(
  VaultStorage storage,
  String original,
  Uint8List bytes,
) async {
  final relative = original.replaceFirst(RegExp(r'^/+'), '');
  final slash = relative.lastIndexOf('/');
  final dot = relative.lastIndexOf('.');
  final stem = dot > slash ? relative.substring(0, dot) : relative;
  final hash = sha256.convert(bytes).toString().substring(0, 8);
  final path = '$stem-crop-$hash.png';
  if (await storage.exists(path)) {
    if (!listEquals(await storage.readBytes(path), bytes)) {
      throw StateError('Cropped asset name already contains different bytes');
    }
  } else {
    await storage.writeBytes(path, bytes);
  }
  return original.startsWith('/') ? '/$path' : path;
}

class ImageCropPage extends StatefulWidget {
  const ImageCropPage({
    super.key,
    required this.bytes,
    required this.onDone,
    required this.onError,
  });

  final Uint8List bytes;
  final Future<void> Function(Uint8List bytes) onDone;
  final ValueChanged<Object> onError;

  @override
  State<ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<ImageCropPage> {
  ui.Image? _image;
  Rect _selection = const Rect.fromLTWH(0, 0, 1, 1);
  double? _ratio;
  bool _busy = false;
  int? _corner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final image = await decodeCropImage(widget.bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (error) {
      if (!mounted) return;
      widget.onError(error);
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Rect _screenRect(Rect bounds) => Rect.fromLTWH(
    bounds.left + _selection.left * bounds.width,
    bounds.top + _selection.top * bounds.height,
    _selection.width * bounds.width,
    _selection.height * bounds.height,
  );

  void _select(Rect rect, Rect bounds) => setState(() {
    _selection = Rect.fromLTWH(
      (rect.left - bounds.left) / bounds.width,
      (rect.top - bounds.top) / bounds.height,
      rect.width / bounds.width,
      rect.height / bounds.height,
    );
  });

  Future<void> _done() async {
    final image = _image!;
    final pixels = cropPixels(
      _selection,
      const Rect.fromLTWH(0, 0, 1, 1),
      Size(image.width.toDouble(), image.height.toDouble()),
    );
    if (pixels ==
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    // dart:ui image encoding needs the main isolate; keep input blocked until saved.
    await WidgetsBinding.instance.endOfFrame;
    try {
      final bytes = await encodeImageCrop(image, pixels);
      await widget.onDone(bytes);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      widget.onError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Crop image'),
        leadingWidth: 80,
        leading: TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _ratio = null;
                    _selection = const Rect.fromLTWH(0, 0, 1, 1);
                  }),
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: _busy || _image == null ? null : _done,
            child: const Text('Done'),
          ),
        ],
      ),
      body: SafeArea(
        child: _image == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final image = _image!;
                      final size = Size(
                        image.width.toDouble(),
                        image.height.toDouble(),
                      );
                      final fitted = applyBoxFit(
                        BoxFit.contain,
                        size,
                        Size(
                          constraints.maxWidth,
                          math.max(1, constraints.maxHeight - 56),
                        ),
                      );
                      final bounds = Alignment.center.inscribe(
                        fitted.destination,
                        Rect.fromLTWH(
                          0,
                          0,
                          constraints.maxWidth,
                          math.max(1, constraints.maxHeight - 56),
                        ),
                      );
                      final rect = _screenRect(bounds);
                      final corners = [
                        rect.topLeft,
                        rect.topRight,
                        rect.bottomRight,
                        rect.bottomLeft,
                      ];
                      return Column(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              key: const Key('crop-surface'),
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) {
                                _corner = null;
                                for (var i = 0; i < corners.length; i++) {
                                  if ((details.localPosition - corners[i])
                                          .distance <=
                                      24) {
                                    _corner = i;
                                    break;
                                  }
                                }
                                if (_corner == null &&
                                    !rect.contains(details.localPosition)) {
                                  _corner = -1;
                                }
                              },
                              onPanUpdate: (details) {
                                if (_busy || _corner == -1) return;
                                final current = _screenRect(bounds);
                                _select(
                                  _corner == null
                                      ? cropMove(current, bounds, details.delta)
                                      : cropResize(
                                          current,
                                          bounds,
                                          _corner!,
                                          details.delta,
                                          _ratio,
                                        ),
                                  bounds,
                                );
                              },
                              child: Semantics(
                                label:
                                    'Crop selection. Drag corners to resize or inside to move.',
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: _CropPainter(image, bounds, rect),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 56,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                for (final (label, ratio)
                                    in <(String, double?)>[
                                      ('Free', null),
                                      ('1:1', 1),
                                      ('4:3', 4 / 3),
                                      ('16:9', 16 / 9),
                                    ])
                                  ChoiceChip(
                                    label: Text(label),
                                    selected: _ratio == ratio,
                                    onSelected: _busy
                                        ? null
                                        : (_) {
                                            setState(() => _ratio = ratio);
                                            if (ratio != null) {
                                              _select(
                                                cropPreset(rect, bounds, ratio),
                                                bounds,
                                              );
                                            }
                                          },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (_busy)
                    Positioned.fill(
                      child: Stack(
                        children: [
                          ModalBarrier(
                            dismissible: false,
                            color: Colors.black.withValues(alpha: 0.54),
                          ),
                          const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.bounds, this.rect);
  final ui.Image image;
  final Rect bounds;
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      bounds,
      Paint(),
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds)
        ..addRect(rect),
      Paint()..color = Colors.black.withValues(alpha: 0.54),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]) {
      canvas.drawCircle(corner, 7, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.bounds != bounds ||
      oldDelegate.rect != rect;
}
