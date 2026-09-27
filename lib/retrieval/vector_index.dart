import 'dart:math' as math;
import 'dart:typed_data';

import 'cosine_search.dart';

/// Compact, normalized in-memory copy of stored chunk vectors.
///
/// Holding Float32 vectors plus the ONNX model broke the 750 MB A24 budget
/// (250k × 384 × 4 B = 384 MB); an fp16 copy still missed it by ~80 MB. Each
/// vector is stored as int8 with a per-vector scale (a quarter of Float32).
/// It only ranks candidates: callers rerank the top
/// [CompactVectorIndex.top] hits with the exact Float32 vectors from SQLite,
/// so returned scores stay exact.
class CompactVectorIndex {
  CompactVectorIndex._(this.ids, this._data, this._scales, this.dimension);

  final List<String> ids;
  final Int8List _data;
  final Float32List _scales;
  final int dimension;

  int get length => ids.length;

  /// Approximate cosine top [limit]; ties break by id like [topCosineHits].
  List<VectorHit> top(List<double> query, int limit) {
    if (query.length != dimension || limit <= 0 || ids.isEmpty) return const [];
    var norm = 0.0;
    for (final value in query) {
      if (!value.isFinite) return const [];
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm == 0) return const [];
    final q = Float32List(dimension);
    for (var i = 0; i < dimension; i++) {
      q[i] = query[i] / norm;
    }
    // Bounded, sorted best-first; a candidate below the current floor is
    // skipped without an insert, which is the common case after warm-up.
    final best = <VectorHit>[];
    var floor = double.negativeInfinity;
    for (var row = 0, base = 0; row < ids.length; row++, base += dimension) {
      var sum = 0.0;
      for (var j = 0; j < dimension; j++) {
        sum += _data[base + j] * q[j];
      }
      final dot = sum * _scales[row];
      if (best.length >= limit && dot < floor) continue;
      final hit = VectorHit(id: ids[row], score: dot);
      var at = best.length;
      while (at > 0 && _before(hit, best[at - 1])) {
        at--;
      }
      if (at >= limit) continue;
      best.insert(at, hit);
      if (best.length > limit) best.removeLast();
      if (best.length >= limit) floor = best.last.score;
    }
    return best;
  }
}

bool _before(VectorHit a, VectorHit b) =>
    a.score > b.score || (a.score == b.score && a.id.compareTo(b.id) < 0);

/// Builds an index of known [capacity] one vector at a time, so callers can
/// stream rows (from SQLite pages or a generator) without a Float32 copy.
class CompactVectorIndexBuilder {
  CompactVectorIndexBuilder(int capacity, this.dimension)
    : _data = Int8List(capacity * dimension),
      _scales = Float32List(capacity),
      _ids = <String>[];

  final int dimension;
  final Int8List _data;
  final Float32List _scales;
  final List<String> _ids;

  bool get isFull => _ids.length * dimension >= _data.length;

  /// Adds a Float32 vector (raw bytes or a list); invalid rows are skipped.
  void add(String id, List<double> vector) {
    if (vector.length != dimension) return;
    if (_ids.length * dimension >= _data.length) {
      throw StateError('CompactVectorIndexBuilder capacity exceeded');
    }
    var norm = 0.0;
    for (final value in vector) {
      if (!value.isFinite) return;
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm == 0) return;
    var peak = 0.0;
    for (final value in vector) {
      peak = math.max(peak, value.abs());
    }
    // value/norm ≈ q * scale, with q in [-127, 127].
    final scale = peak / norm / 127;
    final base = _ids.length * dimension;
    for (var j = 0; j < dimension; j++) {
      _data[base + j] = (vector[j] / norm / scale).round().clamp(-127, 127);
    }
    _scales[_ids.length] = scale;
    _ids.add(id);
  }

  void addBytes(String id, Uint8List bytes) {
    if (bytes.lengthInBytes != dimension * 4) return;
    add(id, bytes.buffer.asFloat32List(bytes.offsetInBytes, dimension));
  }

  CompactVectorIndex build() => CompactVectorIndex._(
    List.unmodifiable(_ids),
    _ids.length * dimension == _data.length
        ? _data
        : Int8List.sublistView(_data, 0, _ids.length * dimension),
    _scales.length == _ids.length
        ? _scales
        : Float32List.sublistView(_scales, 0, _ids.length),
    dimension,
  );
}
