import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import pytest

import phrase_audio
import phrase_notes
import transcribe_worker as worker

REPO = Path(__file__).resolve().parent.parent
NOW = datetime(2026, 11, 24, 12, 0, tzinfo=timezone.utc)
DAILY = ('#import "/_system/tylog.typ" as tylog\n\n= 2026-11-24\n\n'
         '- 10:05 Fui no médico com meu celular #tylog.tag("pt-audio")\n  - Médico: Bom dia #1\n- other line\n')


def make_vault(tmp_path, age=3600):
    note = tmp_path / "daily/2026/11/2026-11-24.typ"
    note.parent.mkdir(parents=True)
    note.write_text(DAILY, encoding="utf-8")
    os.utime(note, (NOW.timestamp() - age,) * 2)
    return tmp_path, note


def jobs(vault, kind):
    return [json.loads(path.read_text(encoding="utf-8")) for path in (vault / "_system/jobs" / kind).glob("*.json")]


def test_sweep_queues_one_job_per_block_once_a_day(tmp_path):
    vault, note = make_vault(tmp_path)
    state = {}
    assert phrase_notes.sweep(vault, NOW, state) == 1
    job = jobs(vault, "phrases")[0]
    assert job["lines"] == ["Fui no médico com meu celular", "Médico: Bom dia #1"] and job["audio"] is True
    assert phrase_notes.sweep(vault, NOW, state) == 0  # same day: not scanned again
    assert phrase_notes.sweep(vault, NOW, {}, force=True) == 0  # same block: no second job
    assert note.read_text(encoding="utf-8") == DAILY


def test_sweep_skips_a_note_still_being_typed(tmp_path):
    vault, _ = make_vault(tmp_path, age=60)
    assert phrase_notes.sweep(vault, NOW, {}) == 0


def fake_llm(monkeypatch, replies):
    """llm_chat answers the correction prompt from `replies` in order; translate echoes with the target."""
    asked = []

    def chat(messages, json_mode=False):
        asked.append(messages[0]["content"])
        return json.dumps(replies.pop(0), ensure_ascii=False)
    monkeypatch.setattr(worker, "llm_chat", lambda settings, **kwargs: (settings["tasks"]["translate"]["model"], chat))
    monkeypatch.setattr(worker, "translate", lambda texts, source, target, **kwargs: [f"{target}: {t}" for t in texts])
    return asked


def run_phrase_job(tmp_path, monkeypatch, replies):
    vault, note = make_vault(tmp_path)
    phrase_notes.sweep(vault, NOW, {})
    job = jobs(vault, "phrases")[0]
    asked = fake_llm(monkeypatch, ["pt", *replies])
    settings = {"tasks": {"translate": {"model": "ornith"}, "phrases": {"model": "muse"}}}
    phrase_notes.run_job(vault, job, settings)
    return vault, note, job, asked


FIRST = {"lines": {"0": "Fui ao médico com o meu celular", "1": "Médico: Bom dia #1"},
         "changes": [{"from": "no médico", "to": "ao médico", "why": "ir a"}]}


def test_job_writes_note_record_and_audio_job_without_touching_the_daily(tmp_path, monkeypatch):
    vault, note, job, asked = run_phrase_job(
        tmp_path, monkeypatch, [FIRST, {"lines": {"0": "Fui ao médico com o meu telemóvel"}, "changes": []}])
    text = (vault / job["phrase_note"]).read_text(encoding="utf-8")
    assert job["llm"] == "muse" and "brazilian" not in job
    assert "celular" in asked[2]  # the Brazilian line was asked again, naming the form
    assert "== Corrected\n\nFui ao médico com o meu telemóvel\n\nMédico: Bom dia \\#1" in text
    assert "- no médico → ao médico: ir a" in text
    assert "== Translation ru" in text and "== Translation en" in text and "== Translation pt" not in text
    record = json.loads((vault / "_system/modules/my-portuguese.json").read_text(encoding="utf-8"))
    assert list(record["files"]) == [job["phrase_note"]] and record["unit"] == "phrases"
    assert jobs(vault, "phrase-audio")[0]["lines"] == job["portuguese"]
    assert note.read_text(encoding="utf-8") == DAILY


def test_brazilian_form_that_stays_is_flagged(tmp_path, monkeypatch):
    vault, _, job, _ = run_phrase_job(tmp_path, monkeypatch, [FIRST, {"lines": {"0": "Fui com o celular"}, "changes": []}])
    assert job["brazilian"] == ["celular"]
    assert "Not checked as European Portuguese: celular" in (vault / job["phrase_note"]).read_text(encoding="utf-8")


def test_audio_job_attaches_clip_and_note_compiles(tmp_path, monkeypatch):
    vault, _, job, _ = run_phrase_job(
        tmp_path, monkeypatch, [FIRST, {"lines": {"0": "Fui ao médico com o meu telemóvel"}, "changes": []}])
    audio = jobs(vault, "phrase-audio")[0]
    built = []
    monkeypatch.setattr(phrase_audio, "build", lambda lines, voices: built.append(lines) or b"mp3")
    monkeypatch.setattr(phrase_audio, "transcribe", lambda mp3: "nada" if len(built) == 1 else "Fui ao médico com o meu telemóvel bom dia")
    monkeypatch.setattr(phrase_audio, "peaks_hex", lambda mp3: "00ff")
    phrase_audio.run_job(vault, audio, {"voices": ["a", "b"]})
    assert len(built) == 2 and audio["score"] >= 0.9  # the first clip failed the check and was made again
    assert built[0][1] == ("Médico", "Bom dia #1")
    text = (vault / job["phrase_note"]).read_text(encoding="utf-8")
    assert f'== Corrected\n\n#tylog.attachment("{audio["audio"]}", kind: "audio")[Audio]\n' in text
    record = json.loads((vault / "_system/modules/my-portuguese.json").read_text(encoding="utf-8"))
    assert set(record["files"]) == {job["phrase_note"], audio["audio"], audio["audio"] + ".peaks"}
    typst = shutil.which("typst")
    if not typst:
        pytest.skip("typst is not installed")
    shutil.copytree(REPO / "typst/vault", vault / "_system", dirs_exist_ok=True)
    shutil.copytree(REPO / "typst/tylog", vault / "_system/packages/tylog/0.1.0")
    result = subprocess.run([typst, "compile", "--root", str(vault), str(vault / job["phrase_note"]),
                             str(tmp_path / "out.pdf")], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def test_settings_keep_the_phrases_task(tmp_path):
    path = tmp_path / "_system/settings/ai.json"
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps({"schema": 1, "tasks": {"phrases": {"model": "muse", "connection": "studio"}}}))
    settings = worker.load_ai_settings(tmp_path)
    assert phrase_notes.phrase_settings(settings)["tasks"]["translate"] == {"model": "muse", "connection": "studio"}


def test_typed_hashtag_is_a_tag():
    text = "- 14:28 other\n\nContext line.\nOlá Andrea, como estás? \\#pt\n\n- 15:00 A: Olá. \\#pt-audio\n  - B: Bom dia.\n- \\#ptx no\n"
    assert phrase_notes.tagged_blocks(text) == [(["Olá Andrea, como estás?"], False), (["A: Olá.", "B: Bom dia."], True)]


def test_tagged_recording_stands_for_its_transcript(tmp_path):
    text = '#tylog.attachment("/assets/audio/2026/11/rec1.m4a", kind: "audio")[rec1.m4a]\\#pt-audio\n'
    assert phrase_notes.tagged_blocks(text, tmp_path) == []  # no transcript yet: wait
    (tmp_path / "notes").mkdir()
    (tmp_path / "notes/Audio rec1.typ").write_text("= Audio\n\n== Summary ru\n\n- 00:00 x\n\n== Transcript\n\n"
                                                   "- 00:03 Привет, Андрей.\n- 00:06 Давно не видел.\n", encoding="utf-8")
    assert phrase_notes.tagged_blocks(text, tmp_path) == [(["Привет, Андрей.", "Давно не видел."], True)]
