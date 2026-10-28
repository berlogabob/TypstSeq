import json

import enrich_learning as learning


def ev(n, decision, surface="Катя"):
    return {"at": f"2026-10-{n:02d}", "decision": decision, "surface": surface}


def test_windows_and_first_accept(tmp_path):
    events = [ev(1, "reject"), ev(2, "accept"), ev(3, "accept", "Рома"), ev(4, "accept")]
    assert learning.windows(events, 2) == [(1, 2, 0.5), (3, 4, 1.0)]
    assert learning.first_accept(events) == {"катя": 2, "рома": 1}


def test_load_skips_bad_lines(tmp_path):
    ledger = tmp_path / "_system/enrich/feedback"
    ledger.mkdir(parents=True)
    (ledger / "a.jsonl").write_text(
        json.dumps(ev(2, "accept")) + "\nnot json\n" + json.dumps(ev(1, "reject")) + "\n",
        encoding="utf-8")
    events = learning.load(tmp_path)
    assert [e["decision"] for e in events] == ["reject", "accept"]
    assert "2 decisions: 1 accepted, 1 rejected" in learning.report(events)
