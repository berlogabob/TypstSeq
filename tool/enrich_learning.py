"""Is Links learning? Accept rate over time, from the feedback ledgers.

Reads accept/reject events from _system/enrich/feedback/*.jsonl and displays
from _system/enrich/shown/*.jsonl;
changes nothing. Prints Markdown: totals, accept rate per window of decisions,
and per surface how many decisions it took before the first accept.
"""

import argparse
from collections import defaultdict
import json
from pathlib import Path


def load(vault, include_shown=False):
    events = []
    ledgers = [("feedback", ("accept", "reject"))]
    if include_shown:
        ledgers.append(("shown", ("shown",)))
    for folder, decisions in ledgers:
        for path in sorted((vault / "_system/enrich" / folder).glob("*.jsonl")):
            for line in path.read_text(encoding="utf-8").splitlines():
                try:
                    event = json.loads(line)
                    if event["decision"] in decisions and event["surface"]:
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


def exposure_counts(events):
    """Unique offers and those decided after display; proposals match any entity."""
    shown, decided = set(), set()
    for e in sorted(events, key=lambda e: e.get("at", "")):
        key = (e.get("note", ""), e["surface"], e.get("entity", ""))
        if e["decision"] == "shown":
            shown.add(key)
        elif e["decision"] in ("accept", "reject"):
            for offer in (key, (*key[:2], "")):
                if offer in shown:
                    decided.add(offer)
    return len(shown), len(decided), len(shown - decided)


def report(events, size=20):
    shown, decided, ignored = exposure_counts(events)
    events = [e for e in events if e["decision"] in ("accept", "reject")]
    accepts = sum(e["decision"] == "accept" for e in events)
    lines = ["# Links learning", "",
             f"{len(events)} decisions: {accepts} accepted, "
             f"{len(events) - accepts} rejected "
             f"({len(set(e['surface'].casefold() for e in events))} surfaces)."]
    rate = f"{ignored / shown:.0%}" if shown else "n/a"
    lines += ["", f"{shown} shown, {decided} decided, {ignored} ignored "
              f"(ignore rate: {rate})."]
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
    print(report(load(args.vault, include_shown=True), args.window), end="")


if __name__ == "__main__":
    main()
