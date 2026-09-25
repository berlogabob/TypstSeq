#!/usr/bin/env python3
"""Score a private judged pack against reference embedding vectors."""

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "pack_validator", ROOT / "tool/validate_embedding_benchmark.py"
)
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def evaluate(records, ids, vectors):
    ids = np.asarray(ids)
    vectors = np.asarray(vectors)
    if ids.ndim != 1 or ids.dtype.kind not in "US" or len(set(ids.tolist())) != len(ids):
        raise ValueError("invalid_vectors")
    ids = ids.astype(str)
    if vectors.ndim != 2 or vectors.shape != (len(ids), 384):
        raise ValueError("invalid_vectors")
    if not np.isfinite(vectors).all():
        raise ValueError("invalid_vectors")
    norms = np.linalg.norm(vectors, axis=1)
    if not np.isfinite(norms).all() or np.any(norms == 0):
        raise ValueError("invalid_vectors")
    vectors = vectors / norms[:, None]

    rows = {value: index for index, value in enumerate(ids)}
    query_ids = {record["query_id"] for record in records}
    if not query_ids.issubset(rows):
        raise ValueError("missing_query_vectors")
    candidate_rows = [index for index, value in enumerate(ids) if value not in query_ids]
    if len(candidate_rows) < 10:
        raise ValueError("insufficient_candidates")
    candidate_ids = ids[candidate_rows]
    candidate_vectors = vectors[candidate_rows]
    groups = {lang: [0, 0] for lang in validator.LANGS}
    cross = [0, 0]
    hits = 0
    for record in records:
        query_index = rows[record["query_id"]]
        relevant = {passage["chunk_id"] for passage in record["relevant"]}
        if not relevant.issubset(rows):
            raise ValueError("missing_relevant_vectors")
        scores = candidate_vectors @ vectors[query_index]
        top = np.lexsort((candidate_ids, -scores))[:10]
        hit = bool(relevant.intersection(candidate_ids[top].tolist()))
        hits += hit
        language = record["query_language"]
        groups[language][0] += hit
        groups[language][1] += 1
        if any(passage["language"] != language for passage in record["relevant"]):
            cross[0] += hit
            cross[1] += 1

    def recall(pair):
        return round(pair[0] / pair[1], 4) if pair[1] else 0.0

    by_language = {
        lang: {"queries": pair[1], "hits": pair[0], "recall_at_10": recall(pair)}
        for lang, pair in groups.items()
    }
    cross_result = {
        "queries": cross[1], "hits": cross[0], "recall_at_10": recall(cross)
    }
    passed = (
        hits / len(records) >= 0.85
        and all(pair[0] / pair[1] >= 0.80 for pair in groups.values())
        and cross[1] > 0
        and cross[0] / cross[1] >= 0.80
    )
    return {
        "status": "PASS" if passed else "FAIL",
        "queries": len(records),
        "hits": hits,
        "recall_at_10": recall((hits, len(records))),
        "by_language": by_language,
        "cross_language": cross_result,
    }


def run(pack_path, vectors_path):
    validator.validate(pack_path)
    records = [
        json.loads(line)
        for line in pack_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    with np.load(vectors_path, allow_pickle=False) as artifact:
        result = evaluate(records, artifact["ids"], artifact["vectors"])
    result["pack_sha256"] = digest(pack_path)
    result["vectors_sha256"] = digest(vectors_path)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path)
    parser.add_argument("vectors", type=Path, help="npz from embedding_reference.py")
    args = parser.parse_args(argv)
    try:
        result = run(args.pack, args.vectors)
    except Exception:
        print("error: invalid_or_unavailable_input", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
