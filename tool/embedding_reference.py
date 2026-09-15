#!/usr/bin/env python3
"""Offline multilingual-e5 reference embedding and exact cosine search."""

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import numpy as np


def mean_pool(token_embeddings, attention_mask):
    values = np.asarray(token_embeddings, dtype=np.float32)
    mask = np.asarray(attention_mask, dtype=np.float32)[..., None]
    denominator = mask.sum(axis=1)
    if np.any(denominator <= 0):
        raise ValueError("zero_attention")
    return (values * mask).sum(axis=1) / denominator


def normalize(vectors):
    values = np.asarray(vectors, dtype=np.float32)
    if not np.isfinite(values).all():
        raise ValueError("nonfinite_vector")
    norms = np.linalg.norm(values, axis=1, keepdims=True)
    if np.any(~np.isfinite(norms)) or np.any(norms == 0):
        raise ValueError("zero_or_nonfinite_norm")
    return (values / norms).astype(np.float32)


def ensure_embedding_dimension(vectors):
    values = np.asarray(vectors)
    if values.ndim != 2 or values.shape[1] != 384:
        raise ValueError("invalid_embedding_dimension")
    return values


def exact_cosine_top_k(query, vectors, k=20):
    if not isinstance(k, int) or isinstance(k, bool) or not 1 <= k <= len(vectors):
        raise ValueError("invalid_k")
    q = normalize(np.asarray(query, dtype=np.float32).reshape(1, -1))[0]
    matrix = normalize(vectors)
    if matrix.shape[1] != q.shape[0]:
        raise ValueError("dimension_mismatch")
    scores = matrix @ q
    # Stable descending score, then ascending row index for deterministic ties.
    order = np.lexsort((np.arange(len(scores)), -scores))[:k]
    return [(int(i), float(scores[i])) for i in order]


def embed_texts(texts, kind, tokenizer, session):
    if kind not in ("query", "passage"):
        raise ValueError("invalid_kind")
    prefixed = [f"{kind}: {text}" for text in texts]
    inputs = tokenizer(
        prefixed, padding=True, truncation=True, max_length=512, return_tensors="np"
    )
    names = {x.name for x in session.get_inputs()}
    feed = {name: np.asarray(value) for name, value in inputs.items() if name in names}
    if "token_type_ids" in names and "token_type_ids" not in feed:
        feed["token_type_ids"] = np.zeros_like(feed["input_ids"], dtype=np.int64)
    output = session.run(None, feed)[0]
    return normalize(mean_pool(output, feed["attention_mask"]))


def run(input_path, model_path, tokenizer_path, output_path):
    try:
        import onnxruntime as ort
        from transformers import AutoTokenizer

        records = [
            json.loads(line)
            for line in Path(input_path).read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        if not records:
            raise ValueError("empty_input")
        if any(
            not isinstance(r, dict)
            or not isinstance(r.get("id"), str)
            or not isinstance(r.get("text"), str)
            or r.get("kind") not in ("query", "passage")
            for r in records
        ):
            raise ValueError("invalid_record")
        tokenizer = AutoTokenizer.from_pretrained(
            str(tokenizer_path), local_files_only=True
        )
        session = ort.InferenceSession(
            str(model_path), providers=["CPUExecutionProvider"]
        )
        start = time.perf_counter()
        # ponytail: per-record inference is intentionally simple; batch once P05.3 measures a need.
        vectors = np.concatenate(
            [embed_texts([r["text"]], r["kind"], tokenizer, session) for r in records]
        )
        ensure_embedding_dimension(vectors)
        np.savez_compressed(
            output_path, ids=np.asarray([r["id"] for r in records]), vectors=vectors
        )
        return {
            "records": len(records),
            "dimension": int(vectors.shape[1]),
            "elapsed_ms": round((time.perf_counter() - start) * 1000, 3),
            "sha256": hashlib.sha256(Path(output_path).read_bytes()).hexdigest(),
        }
    except ValueError:
        raise
    except Exception:
        raise RuntimeError("runtime_failure") from None


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("model", type=Path)
    parser.add_argument("tokenizer", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args(argv)
    try:
        print(
            json.dumps(
                run(args.input, args.model, args.tokenizer, args.output), sort_keys=True
            )
        )
    except (ValueError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
