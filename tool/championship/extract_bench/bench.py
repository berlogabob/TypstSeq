#!/usr/bin/env python3
"""Which Studio model extracts mentions best for the enrich worker.

    python3 tool/championship/extract_bench/bench.py --freeze --vault <vault> [--limit N]   # inputs.jsonl from the gold labels
    python3 tool/championship/extract_bench/bench.py <model id> [<model id> ...]            # appends to results.jsonl
    python3 tool/championship/extract_bench/bench.py --report

Gold labels (note, surface, type, entity) are in DATA/gold-all-draft.jsonl. The journal text is private, so the
frozen inputs and the results stay in DATA (~/Documents/tylog-gold/extract-bench), outside the repo.
Each model gets the worker's own prompt and reply check (enrich_worker.build_messages / parse_reply):
- found   = share of gold surfaces among the model's mentions (one contains the other, case and accents folded);
- type    = share of the found ones with the gold type;
- linked  = gold has an entity: share linked to it; false link = gold has none: share linked to something;
- per note: mentions kept, mentions dropped by the reply check (not in the line: invented), failures, seconds.
The gold names one or two surfaces per note, so "mentions per note" shows over-extraction, not precision.
"""
import hashlib, json, os, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
import enrich_worker as enrich  # noqa: E402
import transcribe_worker as worker  # noqa: E402

DATA = Path(os.environ.get("EXTRACT_BENCH_DATA", Path.home() / "Documents/tylog-gold"))
INPUTS, RESULTS = DATA / "extract-bench/inputs.jsonl", DATA / "extract-bench/results.jsonl"


def freeze(vault, limit):
    """One row per gold note: numbered lines and the prompt, built once so every model reads the same input."""
    gold = {}
    for line in (DATA / "gold-all-draft.jsonl").read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        gold.setdefault(row["note"], []).append({key: row[key] for key in ("surface", "type", "entity")})
    index = enrich.read_index(vault)
    entities = enrich.known_entities(index, enrich.base_kinds(vault))
    notes = sorted(gold, key=lambda note: hashlib.sha1(note.encode()).hexdigest())  # fixed, mixed order
    rows = []
    for note in notes:
        path = vault / note
        lines = enrich.body_lines(path.read_text(encoding="utf-8")) if path.is_file() else []
        if not lines:
            continue
        candidates = enrich.select_candidates(lines, entities, enrich.recent_entity_ids(vault, index, path.stem))
        rows.append({"note": note, "gold": gold[note], "lines": lines,
                     "messages": enrich.build_messages(lines, candidates)})
        if len(rows) == limit:
            break
    INPUTS.parent.mkdir(parents=True, exist_ok=True)
    INPUTS.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
    print(len(rows), "notes ->", INPUTS)


def matches(gold, mention):
    a, b = enrich._fold(gold.strip()), enrich._fold(mention.strip())
    return bool(a and b) and (a in b or b in a)


def score(gold, mentions):
    """Per gold label: found, type right, link right (None when it does not apply)."""
    out = []
    for label in gold:
        hit = next((m for m in mentions if matches(label["surface"], m["surface"])), None)
        has_entity = label["entity"] != "none"
        out.append({"found": hit is not None,
                    "type": None if hit is None else hit["type"] == label["type"],
                    "linked": None if hit is None or not has_entity else hit.get("entity") == label["entity"],
                    "false_link": None if hit is None or has_entity else "entity" in hit})
    return out


def run_model(model, rows):
    started = time.monotonic()
    load = subprocess.run([sys.executable, str(HERE.parent / "model_bench/studio_load.py"), model,
                           str(worker.LLM_CONTEXT)], capture_output=True, text=True, timeout=1200)
    meta = {"model": model, "load_s": round(time.monotonic() - started, 1)}
    if load.returncode != 0:
        return [{**meta, "load_error": (load.stderr or load.stdout).strip()[:300]}]
    chat = enrich.make_chat({"model": model}, [])
    out = [meta]
    for number, row in enumerate(rows, 1):
        lines = [tuple(line) for line in row["lines"]]
        started = time.monotonic()
        result = {"model": model, "note": row["note"]}
        try:
            reply = chat(row["messages"])[0]
            mentions = enrich.parse_reply(reply, lines)[0]
            try:
                raw = len(json.loads(reply).get("mentions") or [])
            except ValueError:
                raw = len(mentions)  # fenced reply: parse_reply read it
            result.update(mentions=mentions, dropped=max(0, raw - len(mentions)), labels=score(row["gold"], mentions))
        except Exception as error:
            result["error"] = str(error)[:200]
        result["sec"] = round(time.monotonic() - started, 1)
        out.append(result)
        print(model, number, "/", len(rows), result.get("error", ""), flush=True)
    return out


def share(values):
    values = [value for value in values if value is not None]
    return f"{sum(values) / len(values):.2f}" if values else "-"


def report():
    rows = [json.loads(line) for line in RESULTS.read_text(encoding="utf-8").splitlines()]
    print("| model | found | type | linked | false link | mentions/note | dropped/note | failed | s/note | load s |"
          "\n|---|---|---|---|---|---|---|---|---|---|")
    for model in dict.fromkeys(row["model"] for row in rows):
        mine = [row for row in rows if row["model"] == model]
        meta = next(row for row in mine if "load_s" in row)
        if "load_error" in meta:
            print(f"| {model} | load failed: {meta['load_error'][:80]} |")
            continue
        notes = [row for row in mine if "note" in row]
        good = [row for row in notes if "error" not in row]
        labels = [label for row in good for label in row["labels"]]
        # A failed note counts as not found: its labels are missing from `labels`.
        missed = sum(1 for row in notes if "error" in row)
        found = [label["found"] for label in labels] + [False] * missed
        print(f"| {model} | {share(found)} | {share(l['type'] for l in labels)} | {share(l['linked'] for l in labels)} "
              f"| {share(l['false_link'] for l in labels)} | {share(len(r['mentions']) for r in good)} "
              f"| {share(r['dropped'] for r in good)} | {missed} | {share(r['sec'] for r in notes)} | {meta['load_s']} |")


def selfcheck():
    gold = [{"surface": "Конимбрига", "type": "place", "entity": "p1"}, {"surface": "Typst", "type": "project", "entity": "none"}]
    mentions = [{"surface": "конимбригу", "type": "place"}, {"surface": "Typst app", "type": "topic", "entity": "x"},
                {"surface": "Конимбрига", "type": "place", "entity": "p1"}]
    assert score(gold, mentions[1:]) == [{"found": True, "type": True, "linked": True, "false_link": None},
                                         {"found": True, "type": False, "linked": None, "false_link": True}]
    assert score(gold[:1], mentions[:1])[0]["found"] is False  # a different word form is not a match


if __name__ == "__main__":
    selfcheck()
    args = sys.argv[1:]
    limit = int(args.pop(args.index("--limit") + 1)) if "--limit" in args else None
    if "--freeze" in args:
        freeze(Path(args[args.index("--vault") + 1]).expanduser().resolve(), limit)
    elif args == ["--report"]:
        report()
    else:
        rows = [json.loads(line) for line in INPUTS.read_text(encoding="utf-8").splitlines()]
        for model in [arg for arg in args if arg != "--limit"]:
            with RESULTS.open("a", encoding="utf-8") as stream:
                stream.writelines(json.dumps(row, ensure_ascii=False) + "\n" for row in run_model(model, rows))
