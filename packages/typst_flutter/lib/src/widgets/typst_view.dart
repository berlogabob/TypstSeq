import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:typst_flutter/src/document.dart';
import 'package:typst_flutter/src/exceptions.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;

/// How the Typst document should be rendered.
enum TypstRenderMode {
  /// Render as a scalable vector graphic (SVG). Crisp at any zoom.
  svg,

  /// Render as a rasterized pixel image.
  raster,
}

/// Whether raw RGBA pixels contain content beyond white or transparent pixels.
bool svgRasterHasContent(Uint8List rgba, {int threshold = 12}) {
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final alpha = rgba[i + 3];
    if (alpha > threshold &&
        (rgba[i] < 255 - threshold ||
            rgba[i + 1] < 255 - threshold ||
            rgba[i + 2] < 255 - threshold ||
            alpha < 255 - threshold)) {
      return true;
    }
  }
  return false;
}

/// A widget that renders a single page of an already-compiled Typst document.
///
/// Compilation is the caller's job — use [TypstDocumentViewer] for a widget
/// that owns a compiler.
class TypstView extends StatefulWidget {
  /// Creates a [TypstView] from an already-compiled [TypstDocument].
  const TypstView({
    required this.document,
    super.key,
    this.pageIndex = 0,
    this.renderMode = TypstRenderMode.svg,
    this.pixelsPerPt = 2.0,
    this.fit = BoxFit.contain,
    this.loadingBuilder,
    this.errorBuilder,
  });

  /// The compiled document to render.
  final TypstDocument document;

  /// The 0-based index of the page to render.
  final int pageIndex;

  /// The rendering mode (SVG or Raster).
  final TypstRenderMode renderMode;

  /// Pixel density for raster rendering.
  final double pixelsPerPt;

  /// How the image/SVG should be inscribed into the available space.
  final BoxFit fit;

  /// Builder for the loading state.
  final WidgetBuilder? loadingBuilder;

  /// Builder for the error state.
  ///
  /// Receives the [BuildContext] and the [TypstException] that caused the
  /// failure. Inspect the concrete type to distinguish between compile
  /// errors ([TypstCompileException]) and render errors
  /// ([TypstRenderException]).
  final Widget Function(BuildContext context, TypstException error)?
  errorBuilder;

  @override
  State<TypstView> createState() => _TypstViewState();
}

class _TypstViewState extends State<TypstView> {
  ui.Image? _image;
  String? _svgString;
  api.PageInfo? _pageInfo;
  final _svgContentCache = <int, bool>{};
  TypstDocument? _svgCacheDocument;

  bool _loading = true;
  TypstException? _error;

  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      unawaited(_prepareAndRender());
    }
  }

  @override
  void didUpdateWidget(TypstView old) {
    super.didUpdateWidget(old);
    if (widget.document != old.document ||
        widget.pageIndex != old.pageIndex ||
        widget.renderMode != old.renderMode ||
        widget.pixelsPerPt != old.pixelsPerPt) {
      unawaited(_prepareAndRender());
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _prepareAndRender() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final doc = widget.document;

      if (widget.pageIndex >= doc.pageCount) {
        throw const TypstCompileException('Page index out of bounds');
      }

      final pageInfo = doc.pageInfo(widget.pageIndex);
      if (!mounted) return;
      setState(() {
        _pageInfo = pageInfo;
      });

      if (widget.renderMode == TypstRenderMode.svg) {
        if (!identical(_svgCacheDocument, doc)) {
          _svgCacheDocument = doc;
          _svgContentCache.clear();
        }

        String? svg;
        Object? fallbackReason;
        try {
          svg = await doc.renderSvg(widget.pageIndex);
          if (!mounted) return;
          if (!await _svgRendersNonBlank(svg)) {
            fallbackReason = 'SVG was blank or could not be decoded';
          }
        } on Object catch (e) {
          fallbackReason = e;
        }
        if (!mounted) return;
        if (fallbackReason == null) {
          setState(() {
            _svgString = svg;
            _image?.dispose();
            _image = null;
            _loading = false;
          });
        } else {
          debugPrint(
            'TypstView: SVG render failed; falling back to raster: '
            '$fallbackReason',
          );
          final result = await doc.renderRaster(
            pageIndex: widget.pageIndex,
            pixelsPerPt: widget.pixelsPerPt,
          );
          final image = await result.toImage();
          if (!mounted) {
            image.dispose();
            return;
          }
          setState(() {
            _image?.dispose();
            _image = image;
            _svgString = null;
            _loading = false;
          });
        }
      } else {
        final result = await doc.renderRaster(
          pageIndex: widget.pageIndex,
          pixelsPerPt: widget.pixelsPerPt,
        );
        final image = await result.toImage();
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
          _svgString = null;
          _loading = false;
        });
      }
    } on TypstException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TypstRenderException(e.toString());
        _loading = false;
      });
    }
  }

  Future<bool> _svgRendersNonBlank(String svg) async {
    final cacheKey = svg.hashCode;
    final cached = _svgContentCache[cacheKey];
    if (cached != null) return cached;

    PictureInfo? info;
    ui.Picture? scaledPicture;
    ui.Image? image;
    var hasContent = false;
    try {
      info = await vg.loadPicture(SvgStringLoader(svg), context);
      if (info.size.isEmpty ||
          !info.size.width.isFinite ||
          !info.size.height.isFinite) {
        throw const FormatException('SVG has invalid dimensions');
      }

      final longestSide = math.max(info.size.width, info.size.height);
      final scale = math.min(1.0, 96 / longestSide);
      final width = math.min(96, math.max(1, (info.size.width * scale).ceil()));
      final height = math.min(
        96,
        math.max(1, (info.size.height * scale).ceil()),
      );
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..scale(scale)
        ..drawPicture(info.picture);
      scaledPicture = recorder.endRecording();
      image = await scaledPicture.toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      hasContent =
          data != null &&
          svgRasterHasContent(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
    } on Object {
      hasContent = false;
    } finally {
      image?.dispose();
      scaledPicture?.dispose();
      info?.picture.dispose();
    }

    if (_svgContentCache.length >= 100) _svgContentCache.clear();
    _svgContentCache[cacheKey] = hasContent;
    return hasContent;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _image == null && _svgString == null) {
      return _buildWrapper(
        child:
            widget.loadingBuilder?.call(context) ??
            const Center(child: CircularProgressIndicator()),
      );
    }

    final error = _error;
    if (error != null && _image == null && _svgString == null) {
      return _buildWrapper(
        child:
            widget.errorBuilder?.call(context, error) ??
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error.toString(),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
      );
    }

    return _buildWrapper(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.renderMode == TypstRenderMode.svg && _svgString != null)
            SvgPicture.string(_svgString!, fit: widget.fit)
          else if (_image != null)
            RawImage(image: _image, fit: widget.fit),
          if (_loading)
            const Positioned(
              right: 8,
              bottom: 8,
              child: _SmallLoadingIndicator(),
            ),
          if (error != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.red.withValues(alpha: 0.9),
                padding: const EdgeInsets.all(8),
                child: Text(
                  error.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWrapper({required Widget child}) {
    if (_pageInfo != null) {
      return AspectRatio(
        aspectRatio: _pageInfo!.widthPt / _pageInfo!.heightPt,
        child: child,
      );
    }
    return SizedBox(height: 400, child: child);
  }
}

class _SmallLoadingIndicator extends StatelessWidget {
  const _SmallLoadingIndicator();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(4),
    ),
    child: const SizedBox(
      width: 12,
      height: 12,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    ),
  );
}
