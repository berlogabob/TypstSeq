"""Small-model arm: an off-the-shelf zero-shot NER model (GLiNER) against the
mentions the enrich worker's LLM extracted. Agreement, not accuracy: the LLM
output is the reference, nobody labelled the text.

  prepare --vault V --gold G.jsonl --out in.jsonl    (Mac; notes named in G)
  run in.jsonl out.jsonl                             (Studio, CPU; needs gliner)
  score in.jsonl out.jsonl [--gold G.jsonl]          (Mac)
"""
import argparse
import json
import sys
import time
from pathlib import Path

LABELS = ["person", "place", "organization", "project", "event", "equipment", "topic"]
MODEL = "urchade/gliner_multi-v2.1"


def prepare(vault, gold, out):
    sys.path.insert(0, str(Path(__file__).parent))
    import enrich_worker as enrich
    vault = Path(vault)
    notes = dict.fromkeys(json.loads(line)["note"] for line in open(gold, encoding="utf-8") if line.strip())
    with open(out, "w", encoding="utf-8") as handle:
        for note in notes:
            mentions = json.loads(enrich.mentions_path(vault, vault / note).read_text(encoding="utf-8"))
            lines = enrich.body_lines((vault / note).read_text(encoding="utf-8"))
            handle.write(json.dumps({"note": note, "lines": lines, "llm": mentions["mentions"]},
                                    ensure_ascii=False) + "\n")
    print(f"{len(notes)} notes -> {out}")


def run(source, out):
    from gliner import GLiNER
    model = GLiNER.from_pretrained(MODEL)
    with open(out, "w", encoding="utf-8") as handle:
        for raw in open(source, encoding="utf-8"):
            row = json.loads(raw)
            started, found = time.time(), []
            for number, text in row["lines"]:
                # The model reads a few hundred tokens; long OCR lines go in pieces.
                for start in range(0, len(text), 800):
                    for entity in model.predict_entities(text[start:start + 800], LABELS, threshold=0.5):
                        found.append({"surface": entity["text"], "type": entity["label"], "line": number,
                                      "score": round(float(entity["score"]), 3)})
            handle.write(json.dumps({"note": row["note"], "seconds": round(time.time() - started, 3),
                                     "mentions": found}, ensure_ascii=False) + "\n")
            handle.flush()


def _same(a, b):
    a, b = a.casefold().strip(), b.casefold().strip()
    return bool(a and b) and (a in b or b in a)


def score(source, out, gold=None):
    small = {json.loads(line)["note"]: json.loads(line) for line in open(out, encoding="utf-8")}
    rows = [json.loads(line) for line in open(source, encoding="utf-8")]
    total = found = typed = extra = 0
    seconds = []
    for row in rows:
        got = small[row["note"]]
        seconds.append(got["seconds"])
        used = set()
        for mention in row["llm"]:
            total += 1
            hits = [(i, m) for i, m in enumerate(got["mentions"])
                    if m["line"] == mention["line"] and _same(m["surface"], mention["surface"])]
            if hits:
                found += 1
                used.update(i for i, _ in hits)
                typed += any(m["type"] == mention["type"] for _, m in hits)
        extra += len(got["mentions"]) - len(used)
    print(f"notes {len(rows)}; LLM mentions {total}; GLiNER found {found} ({found / total:.0%}); "
          f"same type {typed} ({typed / total:.0%}); GLiNER-only spans {extra}")
    seconds.sort()
    print(f"seconds per note on CPU: median {seconds[len(seconds) // 2]:.2f}, max {seconds[-1]:.2f}, "
          f"total {sum(seconds):.1f}")
    if gold:
        sampled = [json.loads(line) for line in open(gold, encoding="utf-8") if line.strip()]
        hit = sum(any(_same(m["surface"], g["surface"]) for m in small[g["note"]]["mentions"]) for g in sampled)
        linked = [g for g in sampled if g["entity"] not in (None, "none")]
        hit_linked = sum(any(_same(m["surface"], g["surface"]) for m in small[g["note"]]["mentions"]) for g in linked)
        print(f"gold rows {len(sampled)}: GLiNER found {hit}; of the {len(linked)} with a real entity: {hit_linked}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    p = commands.add_parser("prepare"); p.add_argument("--vault", required=True); p.add_argument("--gold", required=True); p.add_argument("--out", required=True)
    p = commands.add_parser("run"); p.add_argument("source"); p.add_argument("out")
    p = commands.add_parser("score"); p.add_argument("source"); p.add_argument("out"); p.add_argument("--gold")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.vault, args.gold, args.out)
    elif args.command == "run":
        run(args.source, args.out)
    else:
        score(args.source, args.out, args.gold)
