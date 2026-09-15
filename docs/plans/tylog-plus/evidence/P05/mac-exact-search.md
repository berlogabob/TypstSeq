# P05.3 result — Mac exact-cosine search

Accepted 2026-09-15 with NumPy 2.4.4 over normalized Float32 vectors of dimension 384. Fixtures and raw output remain outside Git.

| Vectors | Cold | Warm p50 | Warm p95 | Warm max | Queries/s | Peak RSS |
|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | 3.851 ms | 0.918 ms | 1.266 ms | 1.849 ms | 1,009.096 | 53,624,832 B |
| 250,000 | 38.805 ms | 18.026 ms | 18.115 ms | 18.129 ms | 55.532 | 427,720,704 B |

Both sizes pass the 3 s warm-p95 and 6 s cold gates. The benchmark memory maps the vector file, generates fixtures in bounded batches, streams SHA-256, and never logs vectors or paths. Four focused tests cover determinism, exact ordering, bounds, metrics, and CLI privacy.
