# P05.2 result — numerical reference runner

Accepted 2026-09-15.

- Dependencies are pinned for Python 3.12 and ONNX Runtime 1.30.0.
- Local-only inference applies the E5 query/passage prefixes, masked mean pooling, Float32 L2 normalization, and a strict 384-dimension check.
- Exact cosine search has deterministic tie ordering and rejects invalid dimensions, vectors, and bounds.
- Private inputs, IDs, paths, and vectors remain outside logs and Git.

Validation: 6 focused unit tests pass. Repeated offline Mac runs over four synthetic EN/PT/RU records produced the same output SHA-256; the accepted pinned environment completed inference in 13.6 ms after model load. This is a compatibility smoke test, not the P05.3 scale benchmark.
