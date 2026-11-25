"""Connection priority (A, B, C): the first connection that answers wins."""
import json

import pytest

import enrich_worker as enrich
import transcribe_worker as worker

CONNECTIONS = [{"id": "studio", "kind": "openai-compatible", "url": "http://studio.invalid/v1"},
               {"id": "chatgpt", "kind": "codex-cli", "url": "cli:codex", "cloud": True},
               {"id": "claude", "kind": "claude-cli", "url": "cli:claude", "cloud": True}]
PRIORITY = ["studio", "chatgpt", "claude"]


def test_settings_keep_priority_and_reject_unknown(tmp_path):
    path = tmp_path / "_system/settings/ai.json"
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps({"schema": 1, "connections": CONNECTIONS,
                                "tasks": {"translate": {"priority": PRIORITY}}}))
    settings = worker.load_ai_settings(tmp_path)
    assert [entry["id"] for entry in worker.task_connections(settings, settings["tasks"]["translate"])] == PRIORITY
    assert worker.translate_connection(settings)["id"] == "studio"
    with pytest.raises(ValueError, match="Unknown translation connection: gone"):
        worker.task_connections(settings, {"priority": ["gone"]})
    assert worker.task_connections(settings, {}) == [None]


def test_translate_chat_falls_to_the_next_and_skips_a_dead_one(monkeypatch):
    calls = []

    def server(settings, connection, **options):
        calls.append("start " + connection["id"])
        raise ValueError("server is off")

    def cli(kind, messages, seconds=None):
        calls.append(kind)
        if kind == "codex-cli":
            raise ValueError("usage limit")
        return "from claude"

    monkeypatch.setattr(worker, "_server_chat", server)
    monkeypatch.setattr(worker, "cli_chat", cli)
    settings = {"connections": CONNECTIONS, "tasks": {"translate": {"priority": PRIORITY, "model": "m"}}}
    _, chat = worker.llm_chat(settings)
    assert chat([{"role": "user", "content": "x"}]) == "from claude"
    assert chat([{"role": "user", "content": "y"}]) == "from claude"
    assert calls == ["start studio", "codex-cli", "claude-cli", "codex-cli", "claude-cli"]  # studio started once

    monkeypatch.setattr(worker, "cli_chat", lambda *a, **k: (_ for _ in ()).throw(ValueError("down")))
    with pytest.raises(ValueError, match="studio: server is off; chatgpt: down; claude: down"):
        worker.llm_chat(settings)[1]([{"role": "user", "content": "x"}])


def test_enrich_chat_uses_priority(monkeypatch):
    monkeypatch.setattr(enrich.tw, "probe_connection", lambda base, key: (_ for _ in ()).throw(OSError("off")))
    monkeypatch.setattr(enrich.tw, "cli_chat", lambda kind, messages: {"claude-cli": "{}"}[kind])
    chat = enrich.make_chat({"priority": ["studio", "claude"], "model": "m"}, CONNECTIONS)
    assert chat([{"role": "user", "content": "x"}]) == ("{}", "claude-cli", "claude")


def test_cli_reply_is_read_from_the_out_file(monkeypatch):
    monkeypatch.setitem(worker.CLI, "claude-cli", 'printf \'```json\\n{"a": 1}\\n```\' > "$OUT"; cat >/dev/null')
    assert worker.cli_chat("claude-cli", [{"role": "user", "content": "x"}]) == '{"a": 1}'
    monkeypatch.setitem(worker.CLI, "claude-cli", "cat >/dev/null; echo limit >&2; exit 1")
    with pytest.raises(ValueError, match="claude-cli: limit"):
        worker.cli_chat("claude-cli", [{"role": "user", "content": "x"}])
