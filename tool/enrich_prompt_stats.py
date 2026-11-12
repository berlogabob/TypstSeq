"""Read-only comparison of legacy and retrieve-then-extract enrich prompts."""
import argparse
from datetime import date, datetime, timedelta
import json
from pathlib import Path
import re
import statistics

import enrich_worker as enrich


def _truth(note, vault, index):
    names = enrich._entity_name_map(index)
    relative = note.relative_to(vault)
    sidecar = vault / "_system/enrich/mentions" / relative.with_suffix(".json")
    data = enrich.tw._read_json(sidecar)
    found = {item.get("entity") for item in data.get("mentions", []) if isinstance(item, dict)}
    text = note.read_text(encoding="utf-8")
    found.update(names[name] for name in re.findall(r'#tylog\.ref-note\("([^"\\]+)"\)', text) if name in names)
    return {entity_id for entity_id in found if entity_id in {e["id"] for e in enrich.known_entities(index)}}


def collect(vault, days=30):
    vault = Path(vault).resolve()
    index = enrich.read_index(vault)
    entities = enrich.known_entities(index)
    markers = enrich.load_markers(vault, {}, index)
    today = date.today()
    rows = []
    for note in sorted((vault / "daily").glob("*/*/*.typ"), key=lambda p: p.stem, reverse=True):
        try:
            note_day = date.fromisoformat(note.stem)
        except ValueError:
            continue
        if not (today - timedelta(days=days - 1) <= note_day <= today):
            continue
        lines = enrich.body_lines(note.read_text(encoding="utf-8"))
        if not lines:
            continue
        candidates = enrich.select_candidates(lines, entities,
                        enrich.recent_entity_ids(vault, index, note.stem))
        old, new = enrich.build_messages_legacy(lines, enrich.legacy_known_entities(index), markers), \
                   enrich.build_messages(lines, candidates, markers)
        old_chars = sum(len(m["content"]) for m in old)
        new_chars = sum(len(m["content"]) for m in new)
        truth = _truth(note, vault, index)
        hits = len(truth & {entity["id"] for entity in candidates})
        rows.append({"date": note.stem, "old_tokens": old_chars / 3, "new_tokens": new_chars / 3,
                     "candidates": len(candidates), "truth": len(truth), "hits": hits})
    return rows


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True, type=Path)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--csv", type=Path)
    args = parser.parse_args(argv)
    rows = collect(args.vault, args.days)
    old = [row["old_tokens"] for row in rows]
    new = [row["new_tokens"] for row in rows]
    old_total, new_total = sum(old), sum(new)
    truth_total, hits_total = sum(r["truth"] for r in rows), sum(r["hits"] for r in rows)
    recall_days = sum(bool(r["truth"]) for r in rows)
    summary = {"days_measured": len(rows), "median_tokens_old": statistics.median(old) if old else 0,
               "median_tokens_new": statistics.median(new) if new else 0,
               "total_tokens_old": old_total, "total_tokens_new": new_total,
               "reduction_percent": (100 * (old_total - new_total) / old_total) if old_total else 0,
               "mean_candidates": statistics.mean(r["candidates"] for r in rows) if rows else 0,
               "recall_at_30_micro": hits_total / truth_total if truth_total else 0,
               "recall_days_counted": recall_days}
    print("metric                 legacy       retrieve/extract")
    print(f"days measured          {summary['days_measured']}")
    print(f"median tokens          {summary['median_tokens_old']:.1f}        {summary['median_tokens_new']:.1f}")
    print(f"total tokens           {old_total:.1f}        {new_total:.1f}")
    print(f"reduction              {summary['reduction_percent']:.1f}%")
    print(f"mean candidates        {summary['mean_candidates']:.2f}")
    print(f"recall@30 micro        {hits_total}/{truth_total} = {summary['recall_at_30_micro']:.3f}; days counted {recall_days}")
    if args.csv:
        import csv
        with args.csv.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=rows[0].keys() if rows else
                                    ("date", "old_tokens", "new_tokens", "candidates", "truth", "hits"))
            writer.writeheader()
            writer.writerows(rows)
    return summary


if __name__ == "__main__":
    main()
