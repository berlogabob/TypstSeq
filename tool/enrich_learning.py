"""Is Links learning? Accept rate over time, from the feedback ledgers.

Reads _system/enrich/feedback/*.jsonl (one line per accept/reject decision);
changes nothing. Prints Markdown: totals, accept rate per window of decisions,
and per surface how many decisions it took before the first accept.
"""

import argparse
from collections import defaultdict
import json
from pathlib import Path


def load(vault):
    events = []
    for path in sorted((vault / "_system/enrich/feedback").glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            try:
                event = json.loads(line)
                if event["decision"] in ("accept", "reject") and event["surface"]:
                    events.append(event)
            except (ValueError, KeyError, TypeError):
                continue  # one bad line must not discard the ledger
    return sorted(events, key=lambda e: e.get("at", ""))


def windows(events, size):
    """(first, last, accept rate) per consecutive block of `size` decisions."""
    rows = []
    for start in range(0, len(events) - size + 1, size):
        block = events[start:start + size]
        accepts = sum(e["decision"] == "accept" for e in block)
        rows.append((start + 1, start + size, accepts / size))
    return rows


def first_accept(events):
    """surface -> decisions made on it up to and including its first accept."""
    seen, done = defaultdict(int), {}
    for e in events:
        key = e["surface"].casefold()
        if key in done:
            continue
        seen[key] += 1
        if e["decision"] == "accept":
            done[key] = seen[key]
    return done


def report(events, size=20):
    accepts = sum(e["decision"] == "accept" for e in events)
    lines = ["# Links learning", "",
             f"{len(events)} decisions: {accepts} accepted, "
             f"{len(events) - accepts} rejected "
             f"({len(set(e['surface'].casefold() for e in events))} surfaces)."]
    rows = windows(events, size)
    if rows:
        lines += ["", f"Accept rate per {size} decisions (should rise):", ""]
        lines += [f"- {a}-{b}: {rate:.0%}" for a, b, rate in rows]
    else:
        lines += ["", f"Fewer than {size} decisions: no trend yet."]
    firsts = first_accept(events)
    if firsts:
        one = sum(v == 1 for v in firsts.values())
        lines += ["", f"{one} of {len(firsts)} accepted surfaces were right at the "
                  "first decision (no earlier reject)."]
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True, type=Path)
    parser.add_argument("--window", type=int, default=20)
    args = parser.parse_args(argv)
    print(report(load(args.vault), args.window), end="")


if __name__ == "__main__":
    main()
