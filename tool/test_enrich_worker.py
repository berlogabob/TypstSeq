import json
import os

import pytest

import enrich_worker as enrich


DAY = """#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "2026-10-22",
  title: "2026-10-22",
  kind: "daily",
  date: "2026-10-22",
  tags: ("journal",),
)

= 2026-10-22

\\- 09:14 в метро. Катя приехала.

== Reading
- Read: Lisbon news

- 09:36 call with André about IADE.
"""


@pytest.fixture(autouse=True)
def isolated(tmp_path, monkeypatch):
    monkeypatch.setattr(enrich.tw.Path, "home", lambda: tmp_path)
    monkeypatch.delenv("TYLOG_LLM_MODEL", raising=False)
    # Fixture days are fixed dates; keep them inside the window whatever today is.
    monkeypatch.setitem(enrich.run_once.__kwdefaults__, "since_days", 36500)


def vault_with(tmp_path, mode="watch"):
    vault = tmp_path / "vault"
    (vault / "daily/2026/10").mkdir(parents=True)
    (vault / "_system/settings").mkdir(parents=True)
    (vault / "_system/settings/ai.json").write_text(json.dumps(
        {"schema": 1, "connections": [], "tasks": {"enrich": {"mode": mode, "time": "03:00"}}}))
    note = vault / "daily/2026/10/2026-10-22.typ"
    note.write_text(DAY, encoding="utf-8")
    os.utime(note, (0, 0))
    return vault, note


def test_body_lines_skip_header_reading_and_auto_block():
    text = DAY + "\n" + enrich.AUTO_MARKER + "\n== Mentions\n- x\n"
    assert [line for _, line in enrich.body_lines(text)] == [
        "\\- 09:14 в метро. Катя приехала.", "- 09:36 call with André about IADE."]
    assert enrich.content_sha(text) == enrich.content_sha(DAY)


def test_parse_reply_drops_hallucinated_surfaces():
    lines = enrich.body_lines(DAY)
    reply = json.dumps({"mentions": [
        {"surface": "Катя", "type": "person", "line": 13, "hints": ["Екатерина", "Katia"]},
        {"surface": "andre", "type": "person", "line": 18},
        {"surface": "Barbara", "type": "person", "line": 13},
        {"surface": "IADE", "type": "university", "line": 18, "entity": "iade"},
    ], "keywords": ["метро", ""]})
    mentions, keywords = enrich.parse_reply("```json\n" + reply + "\n```", lines)
    assert [(m["surface"], m["type"]) for m in mentions] == [
        ("Катя", "person"), ("andre", "person"), ("IADE", "topic")]
    assert mentions[2]["entity"] == "iade"
    assert keywords == ["метро"]


def test_run_once_writes_mentions_and_is_idempotent(tmp_path):
    vault, note = vault_with(tmp_path)
    calls = []

    def chat(messages):
        calls.append(messages)
        return json.dumps({"mentions": [{"surface": "Катя", "type": "person", "line": 13}],
                           "keywords": []}), "m", "c"

    assert enrich.run_once(vault, chat=chat, state_path=tmp_path / "s.json") == 1
    out = json.loads((vault / "_system/enrich/mentions/daily/2026/10/2026-10-22.json").read_text())
    assert out["note"] == "daily/2026/10/2026-10-22.typ"
    assert out["mentions"][0]["surface"] == "Катя"
    # The app's own block must not trigger a re-extraction.
    note.write_text(DAY + enrich.AUTO_MARKER + "\n", encoding="utf-8")
    os.utime(note, (0, 0))
    assert enrich.run_once(vault, chat=chat, state_path=tmp_path / "s.json") == 0
    assert len(calls) == 1


def test_run_once_respects_off_and_settling(tmp_path):
    vault, note = vault_with(tmp_path, mode="off")
    chat = lambda messages: pytest.fail("must not call the model")
    assert enrich.run_once(vault, chat=chat, state_path=tmp_path / "s.json") == 0
    vault2, note2 = vault_with(tmp_path / "b")
    os.utime(note2)  # just edited
    assert enrich.run_once(vault2, chat=chat, state_path=tmp_path / "s2.json") == 0


def test_failed_note_waits_for_a_change_or_tomorrow(tmp_path):
    vault, note = vault_with(tmp_path)
    calls = []

    def chat(messages):
        calls.append(1)
        raise ValueError("down")

    enrich.run_once(vault, chat=chat, state_path=tmp_path / "s.json")
    enrich.run_once(vault, chat=chat, state_path=tmp_path / "s.json")
    assert len(calls) == 1
    note.write_text(DAY + "- more\n", encoding="utf-8")
    os.utime(note, (0, 0))
    enrich.run_once(vault, chat=chat, state_path=tmp_path / "s.json")
    assert len(calls) == 2
    tomorrow = enrich.datetime.now(enrich.timezone.utc) + enrich.timedelta(days=1)
    enrich.run_once(vault, chat=chat, state_path=tmp_path / "s.json", now=tomorrow)
    assert len(calls) == 3


def test_old_days_wait_for_process_now(tmp_path):
    vault, note = vault_with(tmp_path)
    calls = []

    def chat(messages):
        calls.append(1)
        return json.dumps({"mentions": [], "keywords": []}), "m", "c"

    later = enrich.datetime(2027, 6, 1, tzinfo=enrich.timezone.utc)
    assert enrich.run_once(vault, chat=chat, now=later, state_path=tmp_path / "s.json",
                           since_days=90) == 0
    (vault / "_system/enrich").mkdir(parents=True, exist_ok=True)
    (vault / "_system/enrich/run-request.json").write_text(json.dumps({"requested_at": "x"}))
    assert enrich.run_once(vault, chat=chat, now=later, state_path=tmp_path / "s.json",
                           since_days=90) == 1
    assert len(calls) == 1


def test_content_sha_ignores_trailing_blanks_like_the_app():
    body = "= Day\n\nв точку . \n\n\n"
    with_block = "= Day\n\nв точку .\n\n" + enrich.AUTO_MARKER + "\n"
    assert enrich.content_sha(body) == enrich.content_sha(with_block)
    # Pinned in packages/tylog_core/test/enrich_test.dart too.
    assert enrich.content_sha(body) == "98e4ab71821ed482817f51df3f49becd38aea18e74b37327571cc5b29397e91a"


def test_second_worker_exits_while_one_runs(tmp_path, monkeypatch):
    import fcntl
    calls = []
    monkeypatch.setattr(enrich, "run_once", lambda *a, **k: calls.append(1))
    with open(tmp_path / ".tylog-enrich.lock", "w") as held:
        fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
        enrich.main(["--vault", str(tmp_path), "--once"])
    assert calls == []
    enrich.main(["--vault", str(tmp_path), "--once"])
    assert calls == [1]


def test_notes_only_with_include_notes(tmp_path):
    vault, _ = vault_with(tmp_path)
    page = vault / "notes/Logseq page.typ"
    page.parent.mkdir(parents=True)
    page.write_text("= Page\n\nmet André\n", encoding="utf-8")
    os.utime(page, (0, 0))
    chat = lambda messages: (json.dumps({"mentions": [], "keywords": []}), "m", "c")
    assert enrich.run_once(vault, chat=chat, state_path=tmp_path / "s.json") == 1
    assert enrich.run_once(vault, chat=chat, state_path=tmp_path / "s.json", include_notes=True) == 1
    assert (vault / "_system/enrich/mentions/notes/Logseq page.json").exists()


def test_long_pages_are_cut_to_fit_the_context():
    lines = [(i, "x" * 1000) for i in range(1, 100)]
    content = enrich.build_messages(lines, [])[1]["content"]
    assert len(content) < enrich.MAX_CHARS + 1000
