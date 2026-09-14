#!/usr/bin/env python3
"""Generate deterministic, synthetic TyLog+ scale fixtures."""

import argparse
import hashlib
import json
import random
from pathlib import Path


DEFAULTS = {"nodes": 100_000, "edges": 1_000_000, "chunks": 250_000, "seed": 20260914}
LANGUAGES = ("en", "pt", "ru")
NODE_TYPES = ("note", "task", "article")
TEXT = {
    "en": ("measure", "observe", "workspace", "reference", "decision", "routine", "search", "graph"),
    "pt": ("medida", "observar", "espaço", "referência", "decisão", "rotina", "pesquisa", "grafo"),
    "ru": ("мера", "наблюдение", "пространство", "ссылка", "решение", "привычка", "поиск", "граф"),
}


def _record(stream, value):
    stream.write(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    stream.write("\n")


def _id(prefix, number):
    return "%s-%08d" % (prefix, number)


def _language(index):
    return LANGUAGES[index % len(LANGUAGES)]


def _node_type(index):
    return NODE_TYPES[(index // len(LANGUAGES)) % len(NODE_TYPES)]


def _tier(seed, index):
    bucket = hashlib.sha256(("%d:%d" % (seed, index)).encode()).digest()[0]
    if bucket < 179:
        return "short", 500 + bucket * 1501 // 179
    if bucket < 243:
        return "medium", 2_000 + (bucket - 179) * 8_001 // 64
    return "long", 40_000 + (bucket - 243) * 10_001 // 13


def _node_record(seed, index):
    language = _language(index)
    node_type = _node_type(index)
    tier, target = _tier(seed, index)
    words = TEXT[language]
    rng = random.Random(seed * 1_000_003 + index)
    parts = ["%s %s %d" % (language.upper(), node_type, index)]
    length = len(parts[0])
    while length < target:
        part = "%s-%d" % (words[rng.randrange(len(words))], rng.randrange(10_000))
        parts.append(part)
        length += len(part) + 1
    content = " ".join(parts)[:target]
    return {"id": _id("node", index), "type": node_type, "language": language,
            "title": "%s %s %d" % (language.upper(), node_type, index), "tier": tier,
            "content": content, "source_version": "synthetic-node-v1",
            "content_sha256": hashlib.sha256(content.encode()).hexdigest()}


def generate(output_dir, nodes=DEFAULTS["nodes"], edges=DEFAULTS["edges"], chunks=DEFAULTS["chunks"], seed=DEFAULTS["seed"]):
    """Write a synthetic fixture and return its manifest."""
    values = {"nodes": nodes, "edges": edges, "chunks": chunks}
    if any(not isinstance(value, int) or isinstance(value, bool) or value < 0 for value in values.values()):
        raise ValueError("nodes, edges, and chunks must be non-negative integers")
    if nodes == 0 and (edges or chunks):
        raise ValueError("edges and chunks must be zero when nodes is zero")
    destination = Path(output_dir)
    if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        raise FileExistsError("output directory must be missing or empty: %s" % destination)
    destination.mkdir(parents=True, exist_ok=True)
    rng = random.Random(seed)
    paths = {name: destination / (name + ".jsonl") for name in ("nodes", "edges", "chunks")}

    with paths["nodes"].open("w", encoding="utf-8", newline="\n") as stream:
        for index in range(nodes):
            _record(stream, _node_record(seed, index))

    with paths["edges"].open("w", encoding="utf-8", newline="\n") as stream:
        # A small deterministic hub set makes degree distribution meaningfully skewed.
        hubs = max(1, min(nodes, nodes // 100))
        for index in range(edges):
            source = rng.randrange(nodes)
            if index % 10 < 7:
                target = rng.randrange(hubs)
            else:
                target = rng.randrange(nodes)
            _record(stream, {"id": _id("edge", index), "from": _id("node", source), "to": _id("node", target),
                             "kind": "reference"})

    with paths["chunks"].open("w", encoding="utf-8", newline="\n") as stream:
        for index in range(chunks):
            node_index = index % nodes
            parent = _node_record(seed, node_index)
            size = 800 + hashlib.sha256(("chunk:%d:%d" % (seed, index)).encode()).digest()[0] * 801 // 255
            offset = (index * 7919 + seed) % max(1, len(parent["content"]) - size + 1)
            text = parent["content"][offset:offset + size]
            _record(stream, {"id": _id("chunk", index), "node_id": parent["id"], "language": parent["language"],
                             "offset": offset, "text": text, "source_version": parent["source_version"],
                             "source_content_sha256": parent["content_sha256"]})

    files = {}
    for name, path in paths.items():
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        files[name] = {"path": path.name, "bytes": path.stat().st_size, "sha256": digest.hexdigest()}
    distribution = {"tiers": {tier: sum(_tier(seed, i)[0] == tier for i in range(nodes)) for tier in ("short", "medium", "long")},
                    "languages": {language: sum(_language(i) == language for i in range(nodes)) for language in LANGUAGES},
                    "types": {node_type: sum(_node_type(i) == node_type for i in range(nodes)) for node_type in NODE_TYPES}}
    manifest = {"schema_version": 1, "dataset": "synthetic", "seed": seed, "counts": values,
                "distribution": distribution, "files": files}
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default="tylog-scale-fixture")
    for name in ("nodes", "edges", "chunks", "seed"):
        parser.add_argument("--" + name, type=int, default=DEFAULTS[name])
    args = parser.parse_args(argv)
    try:
        manifest = generate(args.output_dir, args.nodes, args.edges, args.chunks, args.seed)
    except (ValueError, FileExistsError, OSError) as error:
        parser.error(str(error))
    print(json.dumps(manifest, sort_keys=True))


if __name__ == "__main__":
    main()
