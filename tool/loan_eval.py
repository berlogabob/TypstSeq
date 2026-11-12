"""Evaluate natural-language loan extraction and resolver feedback."""

import argparse
import csv
from datetime import datetime
import json
import math
from pathlib import Path
import re
import statistics

import enrich_worker as enrich


def _jsonl(path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            value = json.loads(line)
            if isinstance(value, dict):
                rows.append(value)
        except (ValueError, TypeError):
            continue
    return rows


def _load_gold(path):
    rows = []
    for value in _jsonl(path):
        if isinstance(value.get("note"), str) and isinstance(value.get("line"), int):
            rows.append(value)
    return rows


def _sidecar(vault, note):
    path = vault / "_system/enrich/mentions" / Path(note).with_suffix("").with_suffix(".json")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError):
        return {}


def _prf(tp, fp, fn):
    precision = tp / (tp + fp) if tp + fp else ""
    recall = tp / (tp + fn) if tp + fn else ""
    f1 = 2 * precision * recall / (precision + recall) if precision != "" and recall != "" and precision + recall else ""
    return precision, recall, f1


def extraction(vault, gold):
    by_line = {}
    kinds = set()
    for row in gold:
        key = row["note"], row["line"]
        by_line.setdefault(key, []).append(row)
        kinds.update(m.get("type") for m in row.get("mentions", []) if isinstance(m, dict) and isinstance(m.get("type"), str))
    counts = {kind: [0, 0, 0] for kind in sorted(kinds)}
    loans = [0, 0, 0]
    sidecars = {note: _sidecar(vault, note) for note, _ in by_line}
    for (note, line), rows in by_line.items():
        actual = {(m.get("type"), enrich._fold(m.get("surface", ""))) for m in sidecars[note].get("mentions", [])
                  if isinstance(m, dict) and m.get("line") == line and isinstance(m.get("surface"), str)}
        expected = {(m.get("type"), enrich._fold(m.get("surface", ""))) for row in rows
                    for m in row.get("mentions", []) if isinstance(m, dict) and isinstance(m.get("surface"), str)}
        for kind in kinds:
            e, a = {x for x in expected if x[0] == kind}, {x for x in actual if x[0] == kind}
            c = counts[kind]
            c[0] += len(e & a); c[1] += len(a - e); c[2] += len(e - a)
        expected_loan = any(row.get("loan") is True for row in rows)
        actual_loan = any(isinstance(item, dict) and item.get("line") == line for item in sidecars[note].get("loans", []))
        loans[0] += expected_loan and actual_loan
        loans[1] += not expected_loan and actual_loan
        loans[2] += expected_loan and not actual_loan
    total = [sum(c[i] for c in counts.values()) for i in range(3)]
    rows = []
    for kind, (tp, fp, fn) in [*((k, counts[k]) for k in sorted(counts)), ("TOTAL", total), ("loan_detection", loans)]:
        rows.append((kind, tp, fp, fn, *_prf(tp, fp, fn)))
    return rows


def _events(vault):
    for path in sorted((vault / "_system/enrich/feedback").glob("*.jsonl")):
        for row in _jsonl(path):
            yield row


def resolver_weekly(vault, entity_regex):
    pattern = re.compile(entity_regex)
    weeks = {}
    for row in _events(vault):
        entity, decision = row.get("entity", ""), row.get("decision")
        if decision not in ("accept", "reject") or not isinstance(entity, str) or not pattern.search(entity):
            continue
        if entity.startswith(("tag:", "marker:", "mention:ignore", "loan:track")):
            continue
        try:
            at = datetime.fromisoformat(row["at"].replace("Z", "+00:00"))
        except (KeyError, ValueError, TypeError):
            continue
        iso = at.isocalendar()
        week = f"{iso.year}-W{iso.week:02d}"
        values = weeks.setdefault(week, [0, 0])
        values[0] += 1
        values[1] += decision == "accept"
    rows, decided_total, accepted_total = [], 0, 0
    for week, (decided, accepted) in sorted(weeks.items()):
        decided_total += decided; accepted_total += accepted
        rows.append((week, decided, accepted, accepted / decided, accepted_total / decided_total))
    return rows


def loan_timing(vault, form_seconds=None):
    events = [e for e in _events(vault) if e.get("entity") == "loan:track" and e.get("decision") in ("shown", "accept")]
    shown, deltas = {}, []
    for row in sorted(events, key=lambda e: e.get("at", "")):
        key = (row.get("note"), row.get("surface"))
        try:
            at = datetime.fromisoformat(row["at"].replace("Z", "+00:00"))
        except (KeyError, ValueError, TypeError):
            continue
        if row["decision"] == "shown":
            shown.setdefault(key, at)
        elif key in shown:
            delta = (at - shown[key]).total_seconds()
            if 0 <= delta <= 86400:
                deltas.append(delta)
    median = statistics.median(deltas) if deltas else ""
    p90 = sorted(deltas)[math.ceil(0.9 * len(deltas)) - 1] if deltas else ""
    row = [len(deltas), median, p90]
    if form_seconds is not None:
        row += [form_seconds, form_seconds / median if median else ""]
    return row


def _write(path, header, rows):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(header)
        writer.writerows(rows)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True, type=Path)
    parser.add_argument("--gold", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--form-seconds", type=float)
    parser.add_argument("--entity-regex", default=r"^TL-|^[A-Z]{1,3}-\d+$")
    args = parser.parse_args(argv)
    args.out.mkdir(parents=True, exist_ok=True)
    ext = extraction(args.vault, _load_gold(args.gold))
    weekly = resolver_weekly(args.vault, args.entity_regex)
    timing = loan_timing(args.vault, args.form_seconds)
    _write(args.out / "extraction.csv", ["type", "tp", "fp", "fn", "precision", "recall", "f1"], ext)
    _write(args.out / "resolver_weekly.csv", ["week", "decided", "accepted", "top1", "cumulative_top1"], weekly)
    _write(args.out / "loan_timing.csv", ["n", "median_s", "p90_s"] + (["form_s", "speedup"] if args.form_seconds is not None else []), [timing])
    print("extraction.csv\n" + "\n".join(",".join(map(str, row)) for row in ext))
    print("resolver_weekly.csv\n" + "\n".join(",".join(map(str, row)) for row in weekly))
    print("loan_timing.csv\n" + ",".join(map(str, timing)))


if __name__ == "__main__":
    main()
