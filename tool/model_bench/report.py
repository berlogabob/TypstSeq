#!/usr/bin/env python3
import json, collections, pathlib
rows = [json.loads(l) for l in (pathlib.Path(__file__).parent / "results.jsonl").read_text().splitlines() if l.strip()]
g = collections.defaultdict(list)
for r in rows: g[(r["model"], r["task"])].append(r)
print(f'{"model":44} {"task":20} {"pass":>5} {"silent":>6} {"stray":>5} {"+":>5} {"-":>5} {"min":>5}')
tot = collections.defaultdict(lambda: [0, 0, 0])
for (m, t), rs in sorted(g.items()):
    n = len(rs); p = sum(r["pass"] for r in rs); s = sum(r["visible"] and not r["pass"] for r in rs)
    avg = lambda k: sum(r[k] for r in rs) / n
    print(f'{m[-44:]:44} {t:20} {p}/{n:<3} {s:>6} {avg("stray"):>5.1f} {avg("added"):>5.0f} {avg("deleted"):>5.0f} {avg("secs")/60:>5.1f}')
    tot[m][0] += p; tot[m][1] += n; tot[m][2] += s
print()
for m, (p, n, s) in sorted(tot.items(), key=lambda x: -x[1][0] / x[1][1]):
    print(f'{m[-44:]:44} pass {p}/{n} ({100*p//n}%)  silent-wrong {s}')
