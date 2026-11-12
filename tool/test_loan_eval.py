import csv
import json

import loan_eval


def _write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def _ledger(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(json.dumps(row) if row is not None else "not json" for row in rows) + "\n",
                    encoding="utf-8")


def test_cli_metrics_with_synthetic_vault(tmp_path, capsys):
    vault = tmp_path / "vault"
    mentions = vault / "_system/enrich/mentions/daily/2026/11"
    _write_json(mentions / "2026-11-10.json", {
        "mentions": [{"surface": "Alpha", "type": "equipment", "line": 1},
                     {"surface": "Extra", "type": "equipment", "line": 2},
                     {"surface": "Beta", "type": "person", "line": 3}],
        "loans": [{"line": 1}, {"line": 4}],
    })
    _write_json(mentions / "2026-11-11.json", {
        "mentions": [{"surface": "Gamma", "type": "equipment", "line": 1}],
        "loans": [],
    })
    gold_rows = [
        {"note": "daily/2026/11/2026-11-10.typ", "line": 1,
         "mentions": [{"surface": "Alpha", "type": "equipment"}], "loan": True},
        {"note": "daily/2026/11/2026-11-10.typ", "line": 2,
         "mentions": [{"surface": "Missing", "type": "equipment"}], "loan": False},
        {"note": "daily/2026/11/2026-11-10.typ", "line": 3,
         "mentions": [{"surface": "Beta", "type": "person"}], "loan": False},
        {"note": "daily/2026/11/2026-11-10.typ", "line": 4, "mentions": [], "loan": False},
        {"note": "daily/2026/11/2026-11-10.typ", "line": 5, "mentions": [], "loan": True},
        {"note": "daily/2026/11/2026-11-11.typ", "line": 1,
         "mentions": [{"surface": "Gamma", "type": "equipment"}], "loan": False},
    ]
    gold = tmp_path / "gold.jsonl"
    gold.write_text("\n".join(json.dumps(row) for row in gold_rows) + "\n", encoding="utf-8")

    feedback = vault / "_system/enrich/feedback/events.jsonl"
    rows = [
        {"at": "2026-01-05T10:00:00Z", "decision": "accept", "surface": "A", "entity": "TL-1"},
        {"at": "2026-01-06T10:00:00Z", "decision": "reject", "surface": "B", "entity": "TL-2"},
        {"at": "2026-01-12T10:00:00Z", "decision": "accept", "surface": "C", "entity": "TL-3"},
        {"at": "2026-01-19T10:00:00Z", "decision": "reject", "surface": "D", "entity": "TL-4"},
        {"at": "2026-01-19T11:00:00Z", "decision": "accept", "surface": "E", "entity": "tag:foo"},
        {"at": "bad", "decision": "accept", "entity": "TL-5"},
        {"at": "2026-01-05T12:00:00Z", "decision": "shown", "surface": "x", "entity": "loan:track", "note": "n1"},
        {"at": "2026-01-05T12:00:12Z", "decision": "accept", "surface": "x", "entity": "loan:track", "note": "n1"},
        {"at": "2026-01-06T12:00:00Z", "decision": "shown", "surface": "y", "entity": "loan:track", "note": "n2"},
        {"at": "2026-01-06T12:00:40Z", "decision": "accept", "surface": "y", "entity": "loan:track", "note": "n2"},
        None,
    ]
    _ledger(feedback, rows)
    out = tmp_path / "out"
    loan_eval.main(["--vault", str(vault), "--gold", str(gold), "--out", str(out), "--form-seconds", "52"])
    capsys.readouterr()

    def read(name):
        with (out / name).open(encoding="utf-8", newline="") as stream:
            return list(csv.reader(stream))

    assert read("extraction.csv") == [
        ["type", "tp", "fp", "fn", "precision", "recall", "f1"],
        ["equipment", "2", "1", "1", "0.6666666666666666", "0.6666666666666666", "0.6666666666666666"],
        ["person", "1", "0", "0", "1.0", "1.0", "1.0"],
        ["TOTAL", "3", "1", "1", "0.75", "0.75", "0.75"],
        ["loan_detection", "1", "1", "1", "0.5", "0.5", "0.5"],
    ]
    assert read("resolver_weekly.csv") == [
        ["week", "decided", "accepted", "top1", "cumulative_top1"],
        ["2026-W02", "2", "1", "0.5", "0.5"],
        ["2026-W03", "1", "1", "1.0", "0.6666666666666666"],
        ["2026-W04", "1", "0", "0.0", "0.5"],
    ]
    assert read("loan_timing.csv") == [["n", "median_s", "p90_s", "form_s", "speedup"], ["2", "26.0", "40.0", "52.0", "2.0"]]
