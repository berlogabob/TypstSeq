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


def test_shown_is_excluded_from_learning_but_reported(tmp_path, capsys):
    ledger = tmp_path / "_system/enrich/feedback"
    ledger.mkdir(parents=True)
    events = [ev(1, "shown"), ev(2, "reject"), ev(3, "shown", "Рома")]
    (ledger / "a.jsonl").write_text(
        json.dumps(events[1]), encoding="utf-8")
    shown = tmp_path / "_system/enrich/shown"
    shown.mkdir(parents=True)
    (shown / "a.jsonl").write_text(
        "\n".join(map(json.dumps, [events[0], events[2], ev(4, "accept")])),
        encoding="utf-8")
    assert learning.load(tmp_path) == [events[1]]
    assert learning.load(tmp_path, include_shown=True) == events
    learning.main(["--vault", str(tmp_path), "--window", "1"])
    report = capsys.readouterr().out
    assert "1 decisions: 0 accepted, 1 rejected" in report
    assert "2 shown, 1 decided, 1 ignored (ignore rate: 50%)" in report
    assert "- 1-1: 0%" in report


def test_exposures_match_note_surface_entity_and_later_decisions():
    def offer(n, decision, note="day", entity="a", surface="Name"):
        return dict(ev(n, decision, surface), note=note, entity=entity)

    events = [
        offer(1, "accept"),  # predates display
        offer(2, "shown"),
        offer(3, "shown"),  # duplicate across devices
        offer(4, "accept", note="other"),
        offer(5, "reject", entity="b"),
        offer(6, "accept", surface="Other"),
        offer(7, "shown", entity=""),  # proposal
        offer(8, "accept", entity="new-page"),
    ]
    assert learning.exposure_counts(list(reversed(events))) == (2, 1, 1)
    events += [offer(9, "reject"), offer(10, "accept")]
    assert learning.exposure_counts(events) == (2, 2, 0)
    assert "0 shown, 0 decided, 0 ignored (ignore rate: n/a)" in learning.report([])
