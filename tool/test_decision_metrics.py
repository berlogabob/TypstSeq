import json
from datetime import datetime, timezone

import decision_metrics as dm


def test_attention_mapping():
    # explicit attention always wins over status
    assert dm.attention("screenshot", "archived", "kept") == "kept"

    # screenshot: inbox / missing status -> new, otherwise keeps its status
    assert dm.attention("screenshot", "inbox", None) == "new"
    assert dm.attention("screenshot", None, None) == "new"
    assert dm.attention("screenshot", "kept", None) == "kept"
    assert dm.attention("screenshot", "acted", None) == "acted"
    assert dm.attention("screenshot", "archived", None) == "archived"
    # an unrecognised screenshot status is not triaged
    assert dm.attention("screenshot", "deleted", None) is None

    # idea: new / missing -> new, approved -> kept, archived -> archived
    assert dm.attention("idea", "new", None) == "new"
    assert dm.attention("idea", None, None) == "new"
    assert dm.attention("idea", "approved", None) == "kept"
    assert dm.attention("idea", "archived", None) == "archived"
    assert dm.attention("idea", "rejected", None) is None

    # audio is always new; other kinds are not triaged
    assert dm.attention("audio", "inbox", None) == "new"
    assert dm.attention("note", "inbox", None) is None
    assert dm.attention(None, None, None) is None


def test_parse_decisions_skips_malformed_lines():
    good = {"at": "2026-10-01T09:00:00Z", "device": "phone", "item": "i1",
            "source": "screenshot", "action": "accepted"}
    text = "\n".join([
        "not json at all",
        "",
        json.dumps({"at": "2026-10-01T09:00:00Z", "item": "i1"}),  # missing fields
        json.dumps(["array", "not", "object"]),  # not an object
        json.dumps({"at": "", "device": "d", "item": "i2", "source": "s", "action": "x"}),  # empty at
        json.dumps(good),
        json.dumps(good | {"target": "n1", "context": "surf"}),  # optional fields kept
    ])
    rows = dm.parse_decisions(text)
    assert len(rows) == 2
    assert rows[0]["item"] == "i1"
    assert rows[0]["target"] is None
    assert rows[1]["target"] == "n1"
    assert rows[1]["context"] == "surf"


def _item(**kw):
    base = {
        "path": "screenshots/a.typ",
        "id": "i1",
        "kind": "screenshot",
        "date": "2026-01-01",
        "attention": None,
        "status": None,
        "captured_at": "2026-01-01T00:00:00Z",
    }
    base.update(kw)
    return base


def test_ignore_rate_on_three_items():
    now = datetime(2026, 2, 1, tzinfo=timezone.utc)
    items = [
        _item(id="old-new", date="2026-01-01", captured_at="2026-01-01T00:00:00Z"),
        _item(id="old-decided", date="2026-01-02", captured_at="2026-01-02T00:00:00Z"),
        _item(id="recent-new", date="2026-01-30", captured_at="2026-01-30T00:00:00Z"),
    ]
    decisions = [
        {"at": "2026-01-05T00:00:00Z", "device": "phone", "item": "old-decided",
         "source": "screenshot", "action": "accepted"},
    ]
    results = dm.metrics(items, decisions, now, days=7)
    by_source = {r["source"]: r for r in results}

    # Two old triaged items (old-new, old-decided); recent-new is too fresh.
    # One undecided of the two -> 1/2 ignored.
    row = by_source["screenshot"]
    assert row["items_new"] == 1
    assert row["decided"] == 1
    assert row["ignore_rate"] == 0.5

    # An untriaged item does not count against the ignore rate.
    no_triage = [
        _item(id="note-1", kind="note", date="2026-01-01"),
    ]
    assert dm.metrics(no_triage, [], now, 7) == []


def test_latency_median():
    now = datetime(2026, 2, 1, tzinfo=timezone.utc)
    items = [
        _item(id="fast", kind="screenshot", date="2026-01-01",
              captured_at="2026-01-01T00:00:00Z"),
        _item(id="slow", kind="screenshot", date="2026-01-01",
              captured_at="2026-01-01T12:00:00Z"),
    ]
    decisions = [
        {"at": "2026-01-01T06:00:00Z", "device": "phone", "item": "fast",
         "source": "screenshot", "action": "accepted"},
        {"at": "2026-01-04T12:00:00Z", "device": "phone", "item": "slow",
         "source": "screenshot", "action": "rejected"},
    ]
    row = {r["source"]: r for r in dm.metrics(items, decisions, now, 7)}["screenshot"]
    # fast: 6h, slow: 72h -> median 39h
    assert row["median_latency_hours"] == 39.0


def test_item_from_text_reads_header():
    # The real header: plain keys, then quoted keys inside properties.
    text = '''#show: tylog.note.with(
  id: "abc-123",
  kind: "screenshot",
  date: "2026-03-04",
  properties: ("status": "kept", "captured_at": "2026-03-04T08:15:00Z", "attention": "kept", ),
)
'''
    item = dm.item_from_text("screenshots/abc.typ", text)
    assert item["id"] == "abc-123"
    assert item["kind"] == "screenshot"
    assert item["date"] == "2026-03-04"
    assert item["attention"] == "kept"
    assert item["status"] == "kept"
    assert item["captured_at"] == "2026-03-04T08:15:00Z"
    # explicit attention wins in the mapping
    assert dm.attention(item["kind"], item["status"], item["attention"]) == "kept"


def test_actions_and_external_sources_counted():
    now = datetime(2026, 2, 1, tzinfo=timezone.utc)
    items = [_item(id="i1", date="2026-01-01", captured_at="2026-01-01T00:00:00Z")]
    decisions = [
        {"at": "2026-01-02T00:00:00Z", "device": "web", "item": "i1",
         "source": "enrich", "action": "seen"},
        {"at": "2026-01-03T00:00:00Z", "device": "web", "item": "other",
         "source": "enrich", "action": "accepted"},
    ]
    by_source = {r["source"]: r for r in dm.metrics(items, decisions, now, 7)}
    # i1 is decided under its kind; the enrich-source actions are counted there.
    assert by_source["screenshot"]["decided"] == 1
    assert by_source["enrich"]["actions"]["seen"] == 1
    assert by_source["enrich"]["actions"]["accepted"] == 1
