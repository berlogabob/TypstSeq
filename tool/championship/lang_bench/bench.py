#!/usr/bin/env python3
"""Which Studio model writes the best European Portuguese for phrase notes.

    python3 tool/championship/lang_bench/bench.py <model id> [<model id> ...] [--limit N]   # appends to results.jsonl
    python3 tool/championship/lang_bench/bench.py --report                                  # table from results.jsonl

Each model is loaded at the worker's context (tool/championship/model_bench/studio_load.py) and runs data.jsonl through the
worker's own calls: phrase_notes.to_portuguese / correct and transcribe_worker.translate. Scores are automatic:
- to_pt   sim = word similarity to the course line; must = share of expected pt-PT forms present;
          br = Brazilian forms found (fixed list below).
- fix     fixed = share of planted errors corrected; kept = similarity to the correct line (over-editing lowers it).
- from_pt sim to the reference translation (characters for ru, words for en).
A window whose reply is not usable JSON is counted (bad) and its lines are asked again one by one.
"""
import difflib, json, re, subprocess, sys, time, unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
import phrase_notes  # noqa: E402
import transcribe_worker as worker  # noqa: E402

RESULTS = HERE / "results.jsonl"
WINDOW = 10
BRAZILIAN = phrase_notes.BRAZILIAN


def words(text):
    return re.findall(r"[\w'-]+", unicodedata.normalize("NFC", text.lower()))


def sim(a, b, chars=False):
    a, b = (" ".join(words(a)), " ".join(words(b))) if chars else (words(a), words(b))
    return round(difflib.SequenceMatcher(None, a, b).ratio(), 3)


def has(term, text):
    return f" {' '.join(words(term))} " in f" {' '.join(words(text))} "


def score(item, out):
    if item["task"] == "to_pt":
        must = item["must"]
        return {"sim": sim(out, item["ref"]), "br": len(BRAZILIAN.findall(out.lower())),
                "must": round(sum(has(term, out) for term in must) / len(must), 3) if must else None}
    if item["task"] == "fix":
        errors = item["errors"]
        return {"kept": sim(out, item["ref"]), "br": len(BRAZILIAN.findall(out.lower())),
                "fixed": round(sum(has(right, out) and not has(wrong, out) for wrong, right in errors) / len(errors), 3)
                if errors else None}
    return {"sim": sim(out, item["ref"], chars=item["target"] == "ru")}


def run_window(call, items):
    """[(item, output or None, seconds per line, error)]; a failed window is retried line by line."""
    started = time.monotonic()
    try:
        outs = call([item["src"] for item in items])
        each = (time.monotonic() - started) / len(items)
        return [(item, out, each, None) for item, out in zip(items, outs)], 0
    except (ValueError, OSError, KeyError) as error:
        if len(items) == 1:
            return [(items[0], None, time.monotonic() - started, str(error)[:200])], 1
    rows = []
    for item in items:
        rows += run_window(call, [item])[0]
    return rows, 1


def run_model(model, data):
    started = time.monotonic()
    load = subprocess.run([sys.executable, str(HERE.parent / "model_bench/studio_load.py"), model,
                           str(worker.LLM_CONTEXT)], capture_output=True, text=True, timeout=1200)
    meta = {"model": model, "load_s": round(time.monotonic() - started, 1), "bad_windows": 0}
    if load.returncode != 0:
        return [{**meta, "load_error": (load.stderr or load.stdout).strip()[:300]}]
    settings = {"tasks": {"translate": {"model": model}}}
    _, chat = worker.llm_chat(settings)
    groups = {}
    for item in data:
        groups.setdefault((item["task"], item.get("src_lang") or item.get("target")), []).append(item)
    rows = []
    for (task, lang), items in groups.items():
        call = {"to_pt": lambda lines: phrase_notes.to_portuguese(lines, lang, chat),
                "fix": lambda lines: phrase_notes.correct(lines, chat)[0],
                "from_pt": lambda lines: worker.translate(lines, "pt", lang, settings=settings)}[task]
        for first in range(0, len(items), WINDOW):
            done, bad = run_window(call, items[first:first + WINDOW])
            meta["bad_windows"] += bad
            for item, out, seconds, error in done:
                failed = out is None or out == worker.FAILED_TRANSLATION
                rows.append({"model": model, "id": item["id"], "task": task, "lang": lang, "out": out,
                             "sec": round(seconds, 2), "error": error or ("failed" if failed else None),
                             **({} if failed else score(item, out))})
            print(model, task, lang, first + len(done), "/", len(items), flush=True)
    return [meta] + rows


def mean(values):
    values = [value for value in values if value is not None]
    return f"{sum(values) / len(values):.2f}" if values else "-"


def report():
    rows = [json.loads(line) for line in RESULTS.read_text(encoding="utf-8").splitlines()]
    print("| model | to_pt sim | pt-PT forms | Brazilian | errors fixed | fix kept | ->ru | ->en | failed | bad windows "
          "| s/line | load s |\n|---|---|---|---|---|---|---|---|---|---|---|---|")
    for model in dict.fromkeys(row["model"] for row in rows):
        mine = [row for row in rows if row["model"] == model]
        meta = next(row for row in mine if "load_s" in row)
        if "load_error" in meta:
            print(f"| {model} | load failed: {meta['load_error'][:80]} |")
            continue
        items = [row for row in mine if "id" in row]
        pick = lambda task, key, lang=None: mean(row.get(key) for row in items  # noqa: E731
                                                 if row["task"] == task and lang in (None, row["lang"]))
        print(f"| {model} | {pick('to_pt', 'sim')} | {pick('to_pt', 'must')} "
              f"| {sum(row.get('br') or 0 for row in items)} | {pick('fix', 'fixed')} | {pick('fix', 'kept')} "
              f"| {pick('from_pt', 'sim', 'ru')} | {pick('from_pt', 'sim', 'en')} "
              f"| {sum(row['error'] is not None for row in items)} | {meta['bad_windows']} "
              f"| {mean(row['sec'] for row in items)} | {meta['load_s']} |")


def selfcheck():
    item = {"task": "to_pt", "ref": "Estou a trabalhar num projeto novo.", "must": ["a trabalhar"]}
    assert score(item, item["ref"]) == {"sim": 1.0, "br": 0, "must": 1.0}
    assert score(item, "Estou trabalhando em um projeto novo.")["br"] == 1
    assert score(item, "Estou trabalhando em um projeto novo.")["must"] == 0.0
    assert score({"task": "to_pt", "ref": "x", "must": []}, "Me chamo Alex. Você tem um celular?")["br"] == 3
    fix = {"task": "fix", "ref": "Vim à aula.", "errors": [["a aula", "à aula"]]}
    assert score(fix, "Vim à aula.")["fixed"] == 1.0 and score(fix, "Vim a aula.")["fixed"] == 0.0
    assert score({"task": "from_pt", "target": "ru", "ref": "Хочу, но не могу."}, "Хочу, но не могу")["sim"] == 1.0


if __name__ == "__main__":
    selfcheck()
    args = sys.argv[1:]
    if args == ["--report"]:
        report()
        sys.exit(0)
    limit = int(args.pop(args.index("--limit") + 1)) if "--limit" in args else None
    args = [arg for arg in args if arg != "--limit"]
    data = [json.loads(line) for line in (HERE / "data.jsonl").read_text(encoding="utf-8").splitlines()]
    if limit:  # smoke run: the first N items of each task
        seen = {}
        data = [item for item in data if seen.setdefault(item["task"], []).append(1) or len(seen[item["task"]]) <= limit]
    for model in args:
        rows = run_model(model, data)
        with RESULTS.open("a", encoding="utf-8") as stream:
            stream.writelines(json.dumps(row, ensure_ascii=False) + "\n" for row in rows)
