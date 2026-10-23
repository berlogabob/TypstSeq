"""What the day-log mentions say across the whole vault, as Markdown.

Reads _system/enrich/mentions/** (written by enrich_worker.py) and the vault
index; changes nothing. Names are grouped across case forms and nicknames
when they share a hint starting the same way ("Рома", "Ромой" -> "Роман").
"""

import argparse
from collections import Counter, defaultdict
from itertools import combinations
import json
from pathlib import Path
import re

import enrich_worker as enrich

PEOPLE_LIKE = ("person", "place", "organization", "project", "event")


def key(text):
    return re.sub(r"\W", "", enrich._fold(text))


def load(vault):
    mentions = []
    for path in sorted((vault / "_system/enrich/mentions").rglob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            continue
        if data.get("schema") == 1:
            mentions.append(data)
    return mentions


def group_names(days):
    """Union of surfaces that share a key or a hint key -> one name group."""
    parent = {}

    def find(x):
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for day in days:
        for m in day["mentions"]:
            if m["type"] not in PEOPLE_LIKE:
                continue
            surface = key(m["surface"])
            if len(surface) < 2:
                continue
            find(surface)
            # Hints are the model's guesses (it hinted "Катя" with a known
            # surname): merge only forms of the same word, i.e. same start.
            for hint in map(key, m.get("hints", [])):
                if len(hint) >= 3 and hint[:3] == surface[:3]:
                    parent[find(surface)] = find(hint)
    return find


def report(vault):
    days = load(vault)
    index = enrich.read_index(vault)
    pages = {key(name): note["title"] for note in enrich.known_entities(index, limit=10**6)
             for name in [note["title"], *note["aliases"]]}
    total_days = sum(1 for n in index.get("notes", []) if n.get("kind") == "daily")
    find = group_names(days)

    groups = defaultdict(lambda: {"forms": Counter(), "days": set(), "pages": set(), "type": Counter()})
    keywords = defaultdict(Counter)
    for day in days:
        daily = day["note"].startswith("daily/")
        date = Path(day["note"]).stem
        seen = set()
        for m in day["mentions"]:
            if m["type"] not in PEOPLE_LIKE or len(key(m["surface"])) < 2:
                continue
            g = find(key(m["surface"]))
            groups[g]["forms"][m["surface"]] += 1
            groups[g]["days" if daily else "pages"].add(date)
            groups[g]["type"][m["type"]] += 1
            seen.add(g)
        day["groups"] = seen
        if daily:
            keywords[date[:7]].update(day.get("keywords", []))

    def label(g):
        return groups[g]["forms"].most_common(1)[0][0]

    def page(g):
        return next((pages[key(f)] for f in groups[g]["forms"] if key(f) in pages), None)

    ranked = sorted(groups, key=lambda g: -len(groups[g]["days"]) - len(groups[g]["pages"]))
    read_days = sum(day["note"].startswith("daily/") for day in days)
    out = [f"# Day-log discoveries\n",
           f"{read_days} of {total_days} days and {len(days) - read_days} pages read; "
           f"{len(groups)} distinct names.\n"]
    for kind in PEOPLE_LIKE:
        rows = [g for g in ranked if groups[g]["type"].most_common(1)[0][0] == kind][:15]
        if not rows:
            continue
        out.append(f"\n## Most mentioned: {kind}\n\n| Name | Days | Pages | First | Last | Page | Other forms |\n|---|---|---|---|---|---|---|")
        for g in rows:
            d = sorted(groups[g]["days"]) or ["—"]
            forms = ", ".join(f for f, _ in groups[g]["forms"].most_common(4)[1:])
            out.append(f"| {label(g)} | {len(groups[g]['days'])} | {len(groups[g]['pages'])} | "
                       f"{d[0]} | {d[-1]} | {page(g) or '—'} | {forms} |")
    missing = [g for g in ranked if not page(g)
               and len(groups[g]["days"]) + len(groups[g]["pages"]) >= 3][:20]
    if missing:
        out.append("\n## Recurring, no page yet\n")
        out += [f"- {label(g)} ({groups[g]['type'].most_common(1)[0][0]}, "
                f"{len(groups[g]['days'])} days, {len(groups[g]['pages'])} pages)" for g in missing]
    pairs = Counter()
    for day in days:
        pairs.update(combinations(sorted(day["groups"]), 2))
    strong = [(p, n) for p, n in pairs.most_common(20) if n >= 3]
    if strong:
        out.append("\n## Often together (same day)\n")
        out += [f"- {label(a)} + {label(b)}: {n} days" for (a, b), n in strong]
    out.append("\n## Topics by month\n")
    for month in sorted(keywords):
        out.append(f"- {month}: " + ", ".join(w for w, _ in keywords[month].most_common(6)))
    return "\n".join(out) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True, type=Path)
    print(report(parser.parse_args(argv).vault.resolve()), end="")


if __name__ == "__main__":
    main()
