#!/usr/bin/env python3
import argparse
import hashlib
import json
import sys
import time
from pathlib import Path
import numpy as np


def top_k(query, vectors, k=20):
    q = np.asarray(query, dtype=np.float32)
    norm = np.linalg.norm(q)
    if q.ndim != 1 or q.size != vectors.shape[1] or not np.isfinite(norm) or norm == 0:
        raise ValueError("invalid_query")
    if not 1 <= k <= len(vectors):
        raise ValueError("invalid_k")
    scores = vectors @ (q / norm)
    return np.lexsort((np.arange(len(scores)), -scores))[:k]


def generate(path, count, seed=0, dimension=384):
    if count < 1 or dimension != 384:
        raise ValueError("invalid_fixture")
    rng = np.random.default_rng(seed)
    values = np.lib.format.open_memmap(
        path, mode="w+", dtype=np.float32, shape=(count, dimension)
    )
    for start in range(0, count, 4096):
        batch = rng.standard_normal((min(4096, count - start), dimension)).astype(
            np.float32
        )
        batch /= np.linalg.norm(batch, axis=1, keepdims=True).astype(np.float32)
        values[start : start + len(batch)] = batch
    values.flush()


def benchmark(path, warm_count=30, seed=0):
    if warm_count < 1:
        raise ValueError("invalid_warm_count")
    vectors = np.load(path, mmap_mode="r")
    if (
        vectors.ndim != 2
        or vectors.shape[1] != 384
        or vectors.dtype != np.float32
        or len(vectors) < 20
    ):
        raise ValueError("invalid_vectors")
    rng = np.random.default_rng(seed)
    queries = rng.standard_normal((warm_count + 1, 384)).astype(np.float32)
    timings = []
    for query in queries:
        start = time.perf_counter()
        top_k(query, vectors)
        timings.append((time.perf_counter() - start) * 1000)
    warm = np.asarray(timings[1:])
    return {
        "count": int(len(vectors)),
        "dimension": 384,
        "seed": seed,
        "cold_ms": round(timings[0], 3),
        "p50_ms": round(float(np.percentile(warm, 50)), 3),
        "p95_ms": round(float(np.percentile(warm, 95)), 3),
        "max_ms": round(float(warm.max()), 3),
        "queries_per_sec": round(1000 / float(warm.mean()), 3),
        "sha256": file_sha256(path),
    }


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="mode", required=True)
    gen = sub.add_parser("generate")
    gen.add_argument("output", type=Path)
    gen.add_argument("count", type=int)
    gen.add_argument("--seed", type=int, default=0)
    run = sub.add_parser("benchmark")
    run.add_argument("input", type=Path)
    run.add_argument("--seed", type=int, default=0)
    run.add_argument("--warm", type=int, default=30)
    args = parser.parse_args(argv)
    try:
        if args.mode == "generate":
            generate(args.output, args.count, args.seed)
        else:
            if args.warm < 1:
                raise ValueError("invalid_warm_count")
            result = benchmark(args.input, args.warm, args.seed)
            print(json.dumps(result, sort_keys=True))
    except (OSError, ValueError):
        print("error: invalid_input", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
