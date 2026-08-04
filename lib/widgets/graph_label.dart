import 'dart:math' as math;
import 'dart:ui';

/// Display-only transform for tag/community slugs on the graph surfaces:
/// `large-language-models` → `Large language models`. The raw slug stays
/// authoritative everywhere else (chips, editor, index).
String prettyGraphLabel(String slug) {
  if (slug.isEmpty) return slug;
  final words = slug.replaceAll('-', ' ');
  return words[0].toUpperCase() + words.substring(1);
}

/// What a treemap cell label is allowed to be, decided from geometry alone.
class GraphLabelSpec {
  const GraphLabelSpec({
    required this.fontSize,
    required this.showCount,
    required this.maxLines,
  });

  /// Name font size in *screen* pixels (divide by canvas scale when painting).
  final double fontSize;

  /// Whether the count line fits under the name.
  final bool showCount;

  /// Lines allowed for the name.
  final int maxLines;
}

/// Count line size and ink, relative to the name (value is secondary to name).
const kGraphCountScale = 0.78;
const kGraphCountAlpha = 0.65;

/// Fit ladder for a cell of [sizePx] (screen pixels): name size scales with
/// cell area so type hierarchy mirrors data hierarchy, then content degrades
/// stepwise — drop the count line, then wrap less — and returns null when not
/// even one min-size line fits. Line height budgeted at 1.2× font size within
/// 80% of the cell height.
GraphLabelSpec? graphLabelSpec(Size sizePx) {
  if (sizePx.width < 40 || sizePx.height < 26) return null;
  final fontSize = (0.09 * math.sqrt(sizePx.width * sizePx.height)).clamp(
    10.0,
    22.0,
  );
  final budget = sizePx.height * 0.8;
  final nameLine = fontSize * 1.2;
  final countLine = fontSize * kGraphCountScale * 1.2;
  GraphLabelSpec spec(bool count, int lines) => GraphLabelSpec(
    fontSize: fontSize,
    showCount: count,
    maxLines: lines,
  );
  if (2 * nameLine + countLine <= budget) return spec(true, 2);
  if (nameLine + countLine <= budget) return spec(true, 1);
  if (2 * nameLine <= budget) return spec(false, 2);
  if (nameLine <= budget) return spec(false, 1);
  return null;
}
