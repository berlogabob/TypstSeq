#!/usr/bin/env python3
"""Startup trace report for a JSONL sync trace (uv run tool/startup_trace_report.py <file>)."""
import json, sys
from datetime import datetime
EXCLUDED = {"event", "mark", "ms", "timestamp"}
def parse_ts(ts):
    if not isinstance(ts, str):
        return None
    text = ts.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None
def extra_str(obj):
    return " ".join(f"{k}={v}" for k, v in obj.items() if k not in EXCLUDED)
def read_events(path):
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                yield obj
def report(events):
    launches, current = [], None
    for obj in events:
        if not isinstance(obj, dict):
            continue
        ev = obj.get("event")
        if ev == "startup" and obj.get("mark") == "open-start":
            if current is not None:
                launches.append(current)
            current = {"n": None, "open_start_ts": obj.get("timestamp"), "open_dt": parse_ts(obj.get("timestamp")), "marks": [], "indexed": [], "sync_finished": []}
        elif ev == "startup" and current is not None:
            current["marks"].append((obj.get("mark"), obj.get("ms"), extra_str(obj)))
        elif ev == "indexed" and current is not None:
            current["indexed"].append(obj.get("durationMs"))
        elif ev == "finished" and current is not None:
            dt = parse_ts(obj.get("timestamp"))
            if dt is not None:
                current["sync_finished"].append(dt)
    if current is not None:
        launches.append(current)
    for i, launch in enumerate(launches, 1):
        launch["n"] = i
    return launches
def summary(launch):
    if not launch:
        return None
    today = launch["open_dt"].strftime("%H:%M:%S") if launch["open_dt"] else "-"
    idx = next((d for d in launch["indexed"] if d is not None), None)
    search = next((ms for mark, ms, _ in launch["marks"] if isinstance(mark, str) and "search" in mark.lower()), None)
    sync = None
    if launch["open_dt"] and launch["sync_finished"]:
        sync = int((min(launch["sync_finished"]) - launch["open_dt"]).total_seconds() * 1000)
    def s(v):
        return v if v is not None else "-"
    return f"Summary: today={today} index={s(idx)} sync={s(sync)} search={s(search)}"
def last_indexed(events):
    runs = [o for o in events if isinstance(o, dict) and o.get("event") == "indexed"][-5:]
    if not runs:
        return "Last 5 indexed: (none)"
    lines = ["Last 5 indexed:"]
    for obj in runs:
        dur = obj.get("durationMs")
        stages = obj.get("stageMillis") or {}
        top = " ".join(f"{k}={v}" for k, v in sorted(stages.items(), key=lambda kv: kv[1], reverse=True)[:4])
        lines.append(f"  dur={dur} ms  stages: {top}")
    return "\n".join(lines)
def main(argv):
    if len(argv) < 2:
        print("usage: uv run tool/startup_trace_report.py <sync_trace.jsonl>", file=sys.stderr)
        return 2
    events = list(read_events(argv[1]))
    launches = report(events)
    lines = []
    for launch in launches:
        lines.append(f"launch {launch['n']} {launch['open_start_ts']}")
        for mark, ms, extra in launch["marks"]:
            value = ms if ms is not None else 0
            lines.append(f"  {mark:<18} {value:>7} ms  {extra}")
    lines += ["", (summary(launches[-1]) if launches else "Summary: (no launch)"), "", last_indexed(events)]
    print("\n".join(lines))
    return 0
def _selftest():
    events = [
        {"event": "startup", "mark": "open-start", "ms": 0, "timestamp": "2024-05-01T10:00:00Z"},
        {"event": "startup", "mark": "render", "ms": 200, "extra": "ok", "timestamp": "2024-05-01T10:00:00.2Z"},
        {"event": "startup", "mark": "open-start", "ms": 0, "timestamp": "2024-05-01T11:00:00.500Z"},
        {"event": "startup", "mark": "search-ready", "ms": 900, "timestamp": "2024-05-01T11:00:01.4Z"},
        {"event": "indexed", "durationMs": 1234, "stageMillis": {"a": 500, "b": 300, "c": 150, "d": 50}},
        {"event": "finished", "timestamp": "2024-05-01T11:00:01.5Z"},
        {"event": "bogus"}, "not-json",
    ]
    launches = report(events)
    assert len(launches) == 2
    last = launches[-1]
    assert last["open_dt"].strftime("%H:%M:%S") == "11:00:00"
    assert last["indexed"] == [1234] and last["sync_finished"]
    text = summary(last)
    assert all(t in text for t in ("today=11:00:00", "index=1234", "sync=1000", "search=900"))
    indexed = last_indexed(events)
    assert "dur=1234 ms" in indexed and "a=500" in indexed
    print("selftest ok")
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        _selftest()
    else:
        raise SystemExit(main(sys.argv))
