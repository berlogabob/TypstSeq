#!/usr/bin/env python3
"""Summary of docs/plans/audio-plan-results.jsonl: one line per task."""
import json, os
rows = [json.loads(l) for l in open(os.path.join(os.path.dirname(__file__), "../../docs/plans/audio-plan-results.jsonl"))]
tasks = {}
for r in rows: tasks.setdefault(r["task"], []).append(r)
print(f'{"task":28} {"landed by":10} {"attempts":8} {"min":>5} {"+/-":>9}')
landed = 0
for t, rs in sorted(tasks.items()):
    win = next((r for r in rs if r["pass"]), None); landed += bool(win)
    mins = sum(r["secs"] for r in rs) / 60
    print(f'{t:28} {(win["agent"] if win else "FAILED"):10} {len(rs):<8} {mins:5.1f} {(str(win["added"])+"/"+str(win["deleted"])) if win else "-":>9}')
print(f"landed {landed}/{len(tasks)}; ornith first-try {sum(1 for rs in tasks.values() if rs[0]['agent']=='ornith' and rs[0]['pass'])}/{sum(1 for rs in tasks.values() if rs[0]['agent']=='ornith')}")
