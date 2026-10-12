#!/usr/bin/env python3
"""Post-process graphify-out/graph.json in place.

Stdlib only. Three hygiene passes:

1. Remove noise nodes whose label is exactly ``_`` or ``()`` (and the
   edges / hyperedges that reference them).
2. Collapse CHANGELOG-flavored communities into one named ``Changelog``:
   any community whose nodes are overwhelmingly (>=80%) sourced from
   CHANGELOG.md is merged into that single ``Changelog`` community. This
   avoids brittle label matching (graphify labels carry trailing version
   text, or live in a ``community_name`` field); all of ``Release Changelog
   Entries``, ``Version Change Log``, ``Release Notes`` etc. collapse
   together once their nodes are >=80% CHANGELOG.md.
3. Print node/link/hyperedge counts before and after.

Run ``python3 tool/graph_hygiene.py --selftest`` to exercise the logic on a
tiny in-memory graph without touching any real file.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

NOISE_LABELS = {"_", "()"}
CHANGELOG_MARKER = "CHANGELOG.md"
MERGED_CHANGES_COMMUNITY = "Changelog"
CHANGELOG_FRACTION = 0.8  # >=80% of a community's nodes from CHANGELOG.md


def _node_label(node: dict) -> str:
    return (node.get("label") or "").strip()


def _source_is_changelog(node: dict) -> bool:
    source = node.get("source_file") or ""
    return CHANGELOG_MARKER in source


def _community_changelog_fraction(members: list[dict]) -> float:
    """Fraction of a community's nodes whose source_file is CHANGELOG.md."""
    total = len(members)
    if total == 0:
        return 0.0
    changelog = sum(1 for m in members if _source_is_changelog(m))
    return changelog / total


def merge_changelog_communities(graph: dict) -> dict:
    """Collapse CHANGELOG-flavored communities into one named ``Changelog``.

    A community is merged when at least ``CHANGELOG_FRACTION`` (default 80%)
    of its nodes come from CHANGELOG.md. This avoids brittle label matching
    (graphify labels carry trailing version text, or live in ``community_name``).

    Returns a ``{old_id: new_id}`` map.
    """
    nodes = graph.get("nodes", [])

    by_community: dict = {}
    for node in nodes:
        comm = node.get("community")
        by_community.setdefault(comm, []).append(node)

    mapping: dict = {}
    for comm_id, members in by_community.items():
        if _community_changelog_fraction(members) >= CHANGELOG_FRACTION:
            mapping[comm_id] = MERGED_CHANGES_COMMUNITY

    if mapping:
        for node in nodes:
            new_id = mapping.get(node.get("community"))
            if new_id is not None:
                node["community"] = new_id

    return mapping


def remove_noise_nodes(graph: dict) -> int:
    """Remove nodes whose label is exactly '_' or '()'. Returns count removed."""
    nodes = graph.setdefault("nodes", [])
    keep = []
    removed_ids: set[str] = set()
    for node in nodes:
        if _node_label(node) in NOISE_LABELS:
            removed_ids.add(node.get("id"))
            continue
        keep.append(node)
    graph["nodes"] = keep

    _prune_edges(graph, removed_ids)
    return len(removed_ids)


def _prune_edges(graph: dict, removed_ids: set[str]) -> None:
    """Drop links / hyperedges that reference any removed node id."""
    if not removed_ids:
        return

    for link in graph.get("links", []):
        src = link.get("source")
        tgt = link.get("target")
        if src in removed_ids or tgt in removed_ids:
            link["_drop"] = True
    graph["links"] = [ln for ln in graph["links"] if not ln.get("_drop")]

    for edge in graph.get("hyperedges", []):
        members = edge.get("nodes", [])
        if any(m in removed_ids for m in members):
            edge["_drop"] = True
    graph["hyperedges"] = [
        ed for ed in graph["hyperedges"] if not ed.get("_drop")
    ]


def hygiene(graph: dict) -> dict:
    """Run all passes in place. Returns a stats dict."""
    before = {
        "nodes": len(graph.get("nodes", [])),
        "links": len(graph.get("links", [])),
        "hyperedges": len(graph.get("hyperedges", [])),
    }

    removed = remove_noise_nodes(graph)
    merge_mapping = merge_changelog_communities(graph)

    after = {
        "nodes": len(graph.get("nodes", [])),
        "links": len(graph.get("links", [])),
        "hyperedges": len(graph.get("hyperedges", [])),
    }

    return {
        "nodes_removed": before["nodes"] - after["nodes"],
        "links_removed": before["links"] - after["links"],
        "hyperedges_removed": before["hyperedges"] - after["hyperedges"],
        "communities_merged": len(merge_mapping),
        "before": before,
        "after": after,
    }


def _print_stats(stats: dict) -> None:
    print("graph hygiene complete")
    print(f"  nodes:  {stats['before']['nodes']} -> {stats['after']['nodes']}  "
          f"(-{stats['nodes_removed']})")
    print(f"  links:  {stats['before']['links']} -> {stats['after']['links']}  "
          f"(-{stats['links_removed']})")
    print(f"  hyperedges: {stats['before']['hyperedges']} -> "
          f"{stats['after']['hyperedges']}  (-{stats['hyperedges_removed']})")
    print(f"  communities merged: {stats['communities_merged']}")


def _selftest() -> None:
    graph = {
        "directed": False,
        "multigraph": False,
        "graph": {},
        "nodes": [
            {"id": "a", "label": "_", "community": 0, "source_file": "x.md"},
            {"id": "b", "label": "ok node", "community": 1, "source_file": "x.md"},
            {"id": "c", "label": "Release Changelog Entries 0.4",
             "community": 2, "source_file": "CHANGELOG.md"},
            {"id": "d", "label": "Release Changelog Entries 0.5",
             "community": 3, "source_file": "CHANGELOG.md"},
            {"id": "e", "label": "Version 0.4 Fix",
             "community": 4, "source_file": "CHANGELOG.md"},
            {"id": "f", "label": "Version 0.5 Change",
             "community": 5, "source_file": "CHANGELOG.md"},
            {"id": "g", "label": "Version 0.6 Fix",
             "community": 6, "source_file": "README.md"},
            {"id": "h", "label": "()", "community": 7, "source_file": "x.md"},
        ],
        "links": [
            {"source": "a", "target": "b", "relation": "x"},
            {"source": "b", "target": "c", "relation": "x"},
            {"source": "c", "target": "d", "relation": "x"},
            {"source": "e", "target": "f", "relation": "x"},
            {"source": "g", "target": "b", "relation": "x"},
        ],
        "hyperedges": [
            {"id": "he1", "nodes": ["a", "c"], "relation": "participate_in"},
            {"id": "he2", "nodes": ["c", "d"], "relation": "participate_in"},
        ],
    }

    stats = hygiene(graph)

    # Noise removal.
    assert stats["nodes_removed"] == 2, stats
    assert stats["links_removed"] == 1, stats  # a-b dropped
    assert stats["hyperedges_removed"] == 1, stats  # he1 (a) dropped

    ids = {n["id"] for n in graph["nodes"]}
    assert "a" not in ids and "h" not in ids, ids
    assert {"b", "c", "d", "e", "f", "g"} <= ids, ids

    # Community merges: everything >80% CHANGELOG.md collapses to 'Changelog'.
    by_id = {n["id"]: n["community"] for n in graph["nodes"]}
    assert by_id["c"] == by_id["d"] == "Changelog", by_id
    assert by_id["e"] == by_id["f"] == "Changelog", by_id
    # g's label is Version+Fix but from README.md, so it stays its own community.
    assert by_id["g"] != by_id["c"], by_id
    # b stays distinct from both the merged community and from g.
    assert by_id["b"] != by_id["c"], by_id
    assert by_id["b"] != by_id["g"], by_id

    _selftest_fraction()

    # Clean hyperedge survives.
    assert [e["id"] for e in graph["hyperedges"]] == ["he2"], graph["hyperedges"]

    print("selftest passed")


def _selftest_fraction() -> None:
    """Communities are classified by CHANGELOG.md fraction (>=80%), not labels."""
    graph = {
        "nodes": [
            # 3 of 4 nodes from CHANGELOG.md -> 75%, must NOT merge.
            {"id": "n1", "label": "Release Changelog Entries 0.4",
             "community": 0, "source_file": "CHANGELOG.md"},
            {"id": "n2", "label": "Release Changelog Entries 0.4",
             "community": 0, "source_file": "CHANGELOG.md"},
            {"id": "n3", "label": "Release Changelog Entries 0.4",
             "community": 0, "source_file": "CHANGELOG.md"},
            {"id": "n4", "label": "Feature X", "community": 0, "source_file": "src.py"},
            # 5 of 5 from CHANGELOG.md -> 100%, merge (the ~25-community case).
            {"id": "c1", "label": "Release Changelog Entries 1.0",
             "community": 1, "source_file": "CHANGELOG.md"},
            {"id": "c2", "label": "Release Changelog Entries 1.1",
             "community": 2, "source_file": "CHANGELOG.md"},
            {"id": "c3", "label": "Version Change Log 1.2",
             "community": 3, "source_file": "CHANGELOG.md"},
            {"id": "c4", "label": "Release Notes 1.3",
             "community": 4, "source_file": "CHANGELOG.md"},
            {"id": "c5", "label": "Release Changelog Entries 1.4",
             "community": 5, "source_file": "CHANGELOG.md"},
        ],
        "links": [],
        "hyperedges": [],
    }

    stats = hygiene(graph)
    assert stats["communities_merged"] == 5, stats
    assert stats["nodes_removed"] == 0, stats

    by_id = {n["id"]: n["community"] for n in graph["nodes"]}
    # All five changelog communities collapse to a single 'Changelog'.
    assert by_id["c1"] == by_id["c2"] == by_id["c3"] == by_id["c4"] == by_id["c5"] == "Changelog", by_id
    # The 75% community stays separate.
    assert by_id["n1"] != "Changelog", by_id
    # The non-changelog node stays separate too.
    assert by_id["n4"] != "Changelog", by_id

    print("selftest_fraction passed")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "path",
        nargs="?",
        default="graphify-out/graph.json",
        help="path to graphify graph.json (default: graphify-out/graph.json)",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="run the in-memory self-check and exit",
    )
    args = parser.parse_args(argv)

    if args.selftest:
        _selftest()
        _selftest_fraction()
        return 0

    path = Path(args.path)
    if not path.exists():
        print(f"error: {path} does not exist", file=sys.stderr)
        return 1

    original = path.read_text(encoding="utf-8")
    graph = json.loads(original)

    # Preserve formatting/indentation style from the original file.
    indent = 2
    if '\n' in original:
        # Detect indentation from the first indented line.
        for line in original.splitlines()[1:]:
            if line and line[0] in " \t":
                indent = len(line) - len(line.lstrip())
                break

    stats = hygiene(graph)
    _print_stats(stats)

    path.write_text(json.dumps(graph, indent=indent, ensure_ascii=False),
                    encoding="utf-8")
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
