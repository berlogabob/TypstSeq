"""How well do we triage decisions? Per-source ignore rate and latency.

Reads decision rows from V/_system/decisions/*.jsonl and the vault items they
act on (the *.typ files under V/screenshots, V/notes, V/daily). Changes nothing.
Prints, per source, how many items are still new (undecided), how many were
decided, the ignore rate among old items, and the median latency to a decision.

The attention mapping here mirrors packages/tylog_core/lib/src/attention.dart so
"new" means the same thing in the report as in the app.
"""

import argparse
from collections import Counter, defaultdict
import json
import re
import statistics
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Mirrors attentionStates in the app; an item is triaged only when it maps to
# one of these states.
ATTENTION_STATES = ("new", "kept", "acted", "archived")

ITEM_ROOTS = ("screenshots", "notes", "daily")


def attention(kind, status, explicit):
    """Map a raw (kind, status, explicit attention) to a triaged state or None.

    Explicit attention always wins. Otherwise the mapping falls back to status
    per kind, matching the app exactly.
    """
    if explicit in ATTENTION_STATES:
        return explicit
    if kind == "screenshot":
        if status is None or status == "inbox":
            return "new"
        if status in ("kept", "acted", "archived"):
            return status
    elif kind == "idea":
        if status is None or status == "new":
            return "new"
        if status == "approved":
            return "kept"
        if status == "archived":
            return "archived"
    elif kind == "audio":
        return "new"
    return None


def parse_decisions(text):
    """Parse a decisions ledger into rows, skipping malformed lines.

    A line is kept only when it is a JSON object carrying the five required
    scalar fields (at, device, item, source, action). target/context are optional.
    """
    rows = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if not isinstance(obj, dict):
            continue
        at = obj.get("at")
        device = obj.get("device")
        item = obj.get("item")
        source = obj.get("source")
        action = obj.get("action")
        if not all(isinstance(x, str) and x for x in (at, device, item, source, action)):
            continue
        rows.append({
            "at": at,
            "device": device,
            "item": item,
            "source": source,
            "action": action,
            "target": obj.get("target"),
            "context": obj.get("context"),
        })
    return rows


_ITEM_RE = {
    key: re.compile(rf"(?<![a-z0-9_]){key}\"?:\s*\"([^\"]*)\"", re.IGNORECASE)
    for key in ("id", "kind", "date", "attention", "status", "captured_at")
}


def item_from_text(path, text):
    """Pull an item's header fields out of a .typ file's first 2000 chars."""
    head = text[:2000]

    def find(key):
        match = _ITEM_RE[key].search(head)
        return match.group(1) if match else None

    return {
        "path": str(path),
        "id": find("id"),
        "kind": find("kind"),
        "date": find("date"),
        "attention": find("attention"),
        "status": find("status"),
        "captured_at": find("captured_at"),
    }


def _parse_dt(value):
    """Parse an ISO-8601 timestamp (or a bare date) into a tz-aware datetime."""
    if not value:
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        try:
            dt = datetime.strptime(text[:10], "%Y-%m-%d")
        except ValueError:
            return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def _earliest_latency(item, decisions):
    """Hours from the item's capture time to its earliest decision, or None."""
    times = [d for d in (_parse_dt(x["at"]) for x in decisions) if d is not None]
    if not times:
        return None
    when = min(times)
    captured = _parse_dt(item.get("captured_at"))
    if captured is None:
        day = _parse_dt(item.get("date"))
        if day is None:
            return None
        captured = datetime(day.year, day.month, day.day, tzinfo=timezone.utc)
    return (when - captured).total_seconds() / 3600.0


def metrics(items, decisions, now, days):
    """Aggregate per-source triage metrics over triaged items older than `days`.

    Returns a list of source dicts: source, items_new, decided, ignore_rate
    (0..1 or None), median_latency_hours (or None), and a Counter of actions.
    """
    now_day = now.date()
    cutoff = now_day - timedelta(days=days)

    by_item = defaultdict(list)
    for decision in decisions:
        by_item[decision["item"]].append(decision)
    decided_ids = set(by_item)

    sources = defaultdict(lambda: {
        "items_new": 0,
        "decided": 0,
        "latencies": [],
        "actions": Counter(),
    })
    for decision in decisions:
        sources[decision["source"]]["actions"][decision["action"]] += 1

    for item in items:
        if not item.get("id"):
            continue
        if attention(item.get("kind"), item.get("status"), item.get("attention")) is None:
            continue
        item_day = _parse_dt(item.get("date"))
        if item_day is None or item_day.date() >= cutoff:
            continue

        source = item.get("kind") or "unknown"
        agg = sources[source]
        is_decided = item["id"] in decided_ids
        if is_decided:
            agg["decided"] += 1
            latency = _earliest_latency(item, by_item[item["id"]])
            if latency is not None:
                agg["latencies"].append(latency)
        else:
            agg["items_new"] += 1

    results = []
    for source, agg in sources.items():
        total = agg["items_new"] + agg["decided"]
        ignore_rate = (agg["items_new"] / total) if total else None
        results.append({
            "source": source,
            "items_new": agg["items_new"],
            "decided": agg["decided"],
            "ignore_rate": ignore_rate,
            "median_latency_hours": (
                statistics.median(agg["latencies"]) if agg["latencies"] else None
            ),
            "actions": agg["actions"],
        })
    results.sort(key=lambda row: row["source"])
    return results


def render(results):
    """Render the per-source metrics as an aligned text table."""
    header = ["source", "items_new", "decided", "ignore_rate", "median_latency_h", "actions"]
    rows = [header]
    for row in results:
        rows.append([
            row["source"],
            str(row["items_new"]),
            str(row["decided"]),
            f"{row['ignore_rate'] * 100:.0f}%" if row["ignore_rate"] is not None else "n/a",
            f"{row['median_latency_hours']:.1f}"
            if row["median_latency_hours"] is not None else "n/a",
            " ".join(f"{action}={count}" for action, count in sorted(row["actions"].items())),
        ])
    widths = [max(len(r[i]) for r in rows) for i in range(len(header))]
    lines = ["\t".join(h.ljust(widths[i]) for i, h in enumerate(header))]
    lines.append("\t".join("-" * widths[i] for i in range(len(header))))
    lines.extend("\t".join(r[i].ljust(widths[i]) for i in range(len(header))) for r in rows[1:])
    return "\n".join(lines) + "\n"


def load(vault):
    """Load decisions and vault items from a vault directory."""
    decisions = []
    decisions_dir = vault / "_system" / "decisions"
    if decisions_dir.is_dir():
        for path in sorted(decisions_dir.glob("*.jsonl")):
            try:
                decisions.extend(parse_decisions(path.read_text(encoding="utf-8")))
            except OSError:
                continue

    items = []
    for root in ITEM_ROOTS:
        root_dir = vault / root
        if not root_dir.is_dir():
            continue
        for path in sorted(root_dir.rglob("*.typ")):
            try:
                text = path.read_text(encoding="utf-8")
            except OSError:
                continue
            items.append(item_from_text(path, text))
    return items, decisions


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True, type=Path)
    parser.add_argument("--days", type=int, default=7)
    args = parser.parse_args(argv)

    items, decisions = load(args.vault)
    results = metrics(items, decisions, datetime.now(timezone.utc), args.days)
    sys.stdout.write(render(results))


if __name__ == "__main__":
    main()
