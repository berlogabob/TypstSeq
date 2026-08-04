import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tylog_core/tylog_core.dart';

import 'graph.dart' show colorForSlot;
import 'widgets/graph_label.dart';

/// A cell's children are revealed once its on-screen area exceeds this square
/// (per-cell semantic zoom — big communities open earlier than small ones).
const kRevealPx = 180.0;

/// Above this many cells the tessellation runs in a background isolate
/// (mirrors the force layout's threshold in graph.dart).
const _isolateThreshold = 400;

/// Zoomable Voronoi treemap of the vault: community → tag → note cells packed
/// into a screen-filling rectangle, deeper levels revealed by zooming. Tap a
/// cell to dive into it; tap a note cell to open the note.
class VoronoiView extends StatefulWidget {
  const VoronoiView({
    super.key,
    required this.index,
    required this.communities,
    required this.onOpenPath,
    required this.indexRevision,
  });

  final VaultIndex index;

  /// Null while the community pass hasn't landed yet ⇒ placeholder.
  final CommunityMap? communities;
  final ValueChanged<String> onOpenPath;

  /// Cache key: cells are retessellated only when this changes (or the
  /// viewport size does).
  final int indexRevision;

  @override
  State<VoronoiView> createState() => _VoronoiViewState();
}

class _Cell {
  _Cell({
    required this.id,
    required this.label,
    required this.parent,
    required this.depth,
    required this.colorSlot,
    required this.count,
    required this.pts,
  }) : path = Path()..addPolygon(pts, true),
       bbox = _bboxOf(pts),
       area = _areaOf(pts),
       centroid = _centroidOf(pts);

  final String id;
  final String label;
  final int parent;
  final int depth;
  final int colorSlot;
  final int count;
  final List<Offset> pts;
  final Path path;
  final Rect bbox;
  final double area;
  final Offset centroid;
  final List<int> children = [];
}

Rect _bboxOf(List<Offset> pts) {
  if (pts.isEmpty) return Rect.zero;
  var r = Rect.fromPoints(pts.first, pts.first);
  for (final p in pts.skip(1)) {
    r = r.expandToInclude(Rect.fromPoints(p, p));
  }
  return r;
}

double _areaOf(List<Offset> pts) {
  var sum = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2;
}

Offset _centroidOf(List<Offset> pts) {
  final (x, y) = polygonCentroid([for (final p in pts) (p.dx, p.dy)]);
  return Offset(x, y);
}

bool _containsPoint(List<Offset> pts, Offset p) =>
    containsConvex([for (final v in pts) (v.dx, v.dy)], (p.dx, p.dy));

/// Whether [cell]'s children are shown at the current zoom [scale].
bool _isOpen(_Cell cell, double scale) =>
    cell.children.isNotEmpty && cell.area * scale * scale > kRevealPx * kRevealPx;

class _VoronoiViewState extends State<VoronoiView>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _zoomCtl;
  Animation<Matrix4>? _zoomAnim;

  List<_Cell>? _cells;
  List<int> _roots = const [];
  int _rootCount = 1;
  Size? _builtSize;
  bool _computing = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _zoomCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
        final anim = _zoomAnim;
        if (anim != null) _transform.value = anim.value;
      });
  }

  @override
  void dispose() {
    _zoomCtl.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VoronoiView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.indexRevision != oldWidget.indexRevision ||
        !identical(widget.communities, oldWidget.communities)) {
      _token++;
      _cells = null;
      _builtSize = null;
      _computing = false;
    }
  }

  /// Tessellates (or re-tessellates) for [viewport]: small vaults synchronously,
  /// large ones on an isolate guarded by [_token] (the `_layoutToken` pattern
  /// from graph.dart).
  void _ensureCells(Size viewport) {
    final communities = widget.communities;
    if (communities == null || _computing) return;
    if (_cells != null && _builtSize == viewport) return;
    final req = buildVoronoiRequest(
      widget.index,
      communities,
      viewport.width,
      viewport.height,
    );
    if (req.ids.length <= _isolateThreshold) {
      _apply(req, computeVoronoiTreemap(req), viewport);
      return;
    }
    _computing = true;
    final token = _token;
    compute(computeVoronoiTreemap, req).then((result) {
      if (!mounted || token != _token) return;
      setState(() {
        _computing = false;
        _apply(req, result, viewport);
      });
    });
  }

  void _apply(VoronoiRequest req, VoronoiResult result, Size viewport) {
    final cells = <_Cell>[
      for (var i = 0; i < req.ids.length; i++)
        _Cell(
          id: req.ids[i],
          label: req.labels[i],
          parent: req.parent[i],
          depth: req.depth[i],
          colorSlot: req.colorSlot[i],
          count: req.weight[i].round(),
          pts: [
            for (var v = result.cellStart[i]; v < result.cellStart[i + 1]; v += 2)
              Offset(result.verts[v], result.verts[v + 1]),
          ],
        ),
    ];
    final roots = <int>[];
    for (var i = 0; i < cells.length; i++) {
      if (cells[i].pts.length < 3) continue; // vanished cell: don't render
      if (cells[i].parent == -1) {
        roots.add(i);
      } else {
        cells[cells[i].parent].children.add(i);
      }
    }
    _cells = cells;
    _roots = roots;
    _rootCount = math.max(1, voronoiRootCount(req));
    _builtSize = viewport;
    _transform.value = Matrix4.identity();
  }

  void _onTap(Offset point, Size viewport) {
    final cells = _cells;
    if (cells == null) return;
    final scale = _transform.value.getMaxScaleOnAxis();
    // Descend from the root to the deepest currently-visible cell under the tap.
    _Cell? hit;
    var level = _roots;
    while (true) {
      _Cell? found;
      for (final i in level) {
        if (cells[i].bbox.contains(point) && _containsPoint(cells[i].pts, point)) {
          found = cells[i];
          break;
        }
      }
      if (found == null) break;
      hit = found;
      if (!_isOpen(found, scale)) break;
      level = found.children;
    }
    if (hit == null) return;
    if (hit.children.isEmpty) {
      widget.onOpenPath(hit.id);
    } else {
      _animateTo(viewport, hit.bbox);
    }
  }

  /// Animates the view to frame [target] (canvas coords), zooming far enough
  /// in that the target cell opens into its children.
  void _animateTo(Size viewport, Rect target) {
    final fit = math.min(
      viewport.width / target.width,
      viewport.height / target.height,
    );
    final scale = (fit * 0.9).clamp(1.0, 8.0);
    final end = Matrix4.identity()
      ..translateByDouble(
        viewport.width / 2 - target.center.dx * scale,
        viewport.height / 2 - target.center.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
    _zoomAnim = Matrix4Tween(begin: _transform.value.clone(), end: end).animate(
      CurvedAnimation(parent: _zoomCtl, curve: Curves.easeInOut),
    );
    _zoomCtl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.communities == null) {
      return const Center(child: Text('Analyzing communities…'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _ensureCells(viewport);
        final cells = _cells;
        if (cells == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_roots.isEmpty) {
          return const Center(child: Text('Nothing to map yet'));
        }
        return Stack(
          children: [
            InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: 0.5,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(80),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _onTap(details.localPosition, viewport),
                child: CustomPaint(
                  size: viewport,
                  painter: _VoronoiPainter(
                    cells: cells,
                    roots: _roots,
                    rootCount: _rootCount,
                    colorScheme: scheme,
                    viewport: viewport,
                    transform: _transform,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                key: const Key('voronoi-fit'),
                tooltip: 'Fit map',
                onPressed: () =>
                    _animateTo(viewport, Offset.zero & (_builtSize ?? viewport)),
                icon: const Icon(Icons.fit_screen),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VoronoiPainter extends CustomPainter {
  _VoronoiPainter({
    required this.cells,
    required this.roots,
    required this.rootCount,
    required this.colorScheme,
    required this.viewport,
    required this.transform,
  }) : super(repaint: transform);

  final List<_Cell> cells;
  final List<int> roots;
  final int rootCount;
  final ColorScheme colorScheme;
  final Size viewport;

  /// Live view transform (also the repaint signal) — read each frame for the
  /// per-cell reveal test, constant-size labels, and culling.
  final TransformationController transform;

  /// Visible region in canvas coords (translate+scale only, no rotation).
  Rect _cullRect(double scale) {
    final m = transform.value;
    if (scale <= 0) return Rect.largest;
    final tx = m.storage[12], ty = m.storage[13];
    return Rect.fromLTRB(
      (0 - tx) / scale,
      (0 - ty) / scale,
      (viewport.width - tx) / scale,
      (viewport.height - ty) / scale,
    ).inflate(40);
  }

  Color _fillFor(_Cell cell, int siblingIndex) {
    final base = colorForSlot(cell.colorSlot, rootCount, colorScheme);
    // Deeper levels fade toward the surface; alternate siblings a notch so
    // adjacent cells of one parent still separate without borders doing all
    // the work.
    final t = (0.18 * cell.depth + (siblingIndex.isOdd ? 0.07 : 0.0))
        .clamp(0.0, 0.6);
    return Color.lerp(base, colorScheme.surface, 0.35 + t)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = transform.value.getMaxScaleOnAxis();
    final cull = _cullRect(scale);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = colorScheme.surface
      ..strokeWidth = 1.2 / scale;
    final labels = <(_Cell, int)>[]; // cell + sibling index, drawn last

    void draw(int index, int siblingIndex) {
      final cell = cells[index];
      if (!cell.bbox.overlaps(cull)) return;
      if (_isOpen(cell, scale)) {
        var child = 0;
        for (final c in cell.children) {
          draw(c, child++);
        }
        // Parent outline on top of its children, heavier for higher levels.
        canvas.drawPath(
          cell.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = colorScheme.surface
            ..strokeWidth = (3.0 - cell.depth) * 1.2 / scale,
        );
        return;
      }
      canvas.drawPath(cell.path, Paint()..color = _fillFor(cell, siblingIndex));
      canvas.drawPath(cell.path, border);
      labels.add((cell, siblingIndex));
    }

    var sibling = 0;
    for (final r in roots) {
      draw(r, sibling++);
    }

    for (final (cell, _) in labels) {
      final spec = graphLabelSpec(
        Size(cell.bbox.width * scale, cell.bbox.height * scale),
      );
      if (spec == null) continue;
      final hasCount = cell.children.isNotEmpty;
      final name = hasCount ? prettyGraphLabel(cell.label) : cell.label;
      final nameSize = spec.fontSize / scale;
      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: nameSize,
            height: 1.2,
            fontWeight: switch (cell.depth) {
              0 => FontWeight.w600,
              1 => FontWeight.w500,
              _ => FontWeight.w400,
            },
          ),
          children: [
            if (hasCount && spec.showCount)
              TextSpan(
                text: '\n${cell.count}',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(
                    alpha: kGraphCountAlpha,
                  ),
                  fontSize: nameSize * kGraphCountScale,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: spec.maxLines + (hasCount && spec.showCount ? 1 : 0),
        ellipsis: '…',
      )..layout(maxWidth: cell.bbox.width * 0.85);
      if (tp.height > cell.bbox.height * 0.9) continue;
      // Center on the centroid, but keep the text inside the cell bounds so
      // it never crosses a border into a neighbor.
      final inner = cell.bbox.deflate(4 / scale);
      final wanted = cell.centroid - Offset(tp.width / 2, tp.height / 2);
      tp.paint(
        canvas,
        Offset(
          wanted.dx.clamp(
            inner.left,
            math.max(inner.left, inner.right - tp.width),
          ),
          wanted.dy.clamp(
            inner.top,
            math.max(inner.top, inner.bottom - tp.height),
          ),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoronoiPainter oldDelegate) =>
      oldDelegate.cells != cells || oldDelegate.colorScheme != colorScheme;
}
