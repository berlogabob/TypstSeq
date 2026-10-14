import json
import hashlib
import sys
from types import SimpleNamespace
from io import BytesIO

import pytest

import transcribe_worker as worker


def test_escape_markup():
    assert worker.escape_markup("\\#[]$*_@ plain") == "\\\\\\#\\[\\]\\$\\*\\_\\@ plain"


@pytest.mark.parametrize("seconds, expected", [(0, "00:00"), (65, "01:05"), (3700, "61:40")])
def test_format_ts(seconds, expected):
    assert worker.format_ts(seconds) == expected


def test_render_section():
    assert worker.render_section([(0, "Hello #world"), (65, "Next")]) == (
        "== Transcript\n\n- 00:00 Hello \\#world\n- 01:05 Next\n"
    )


def test_apply_transcript_append():
    note = "= Note\n\n== Comments\nKeep *this*."
    assert worker.apply_transcript(note, [(65, "Hello")]) == (
        note + "\n\n== Transcript\n\n- 01:05 Hello\n"
    )


def test_apply_transcript_replace_keeps_comments():
    prefix = "= Note\r\n\r\n"
    comments = "== Comments\r\nKeep *this*.\r\n\r\n== Other\r\nLast"
    note = prefix + "== Transcript\r\n\r\n- 00:00 Old\r\n" + comments
    assert worker.apply_transcript(note, [(65, "Hello")]) == (
        prefix + "== Transcript\n\n- 01:05 Hello\n" + comments
    )


def test_apply_transcript_replace_at_eof():
    assert worker.apply_transcript("= Note\n== Transcript\nOld", []) == (
        "= Note\n== Transcript\n\n"
    )


def test_cli_core(tmp_path, monkeypatch):
    jobs = tmp_path / "_system/jobs/transcripts"
    jobs.mkdir(parents=True)
    job_path = jobs / "job.json"
    job_path.write_text(json.dumps({"status": "queued", "audio": "audio.wav", "note": "note.typ", "lang": "pt"}))
    note = tmp_path / "note.typ"
    note.write_bytes(b"= Note\r\n== Comments\r\nKeep me\r\n")

    def fake_transcribe(audio, model, lang):
        assert audio == tmp_path / "audio.wav"
        assert (model, lang) == ("small", "pt")
        assert json.loads(job_path.read_text())["status"] == "processing"
        return [(65, "Fixed text")], "pt"

    monkeypatch.setattr(worker, "transcribe", fake_transcribe)
    worker.main(["--vault", str(tmp_path), "--once"])
    job = json.loads(job_path.read_text())
    assert job["status"] == "done"
    assert job["finished_at"]
    assert job["lang"] == "pt"
    assert note.read_bytes() == (
        b"= Note\r\n== Comments\r\nKeep me\r\n\n== Transcript\n\n- 01:05 Fixed text\n"
    )


def test_failed_transcription_keeps_note(tmp_path, monkeypatch):
    jobs = tmp_path / "_system/jobs/transcripts"
    jobs.mkdir(parents=True)
    job_path = jobs / "job.json"
    job_path.write_text(json.dumps({"status": "queued", "audio": "audio.wav", "note": "note.typ"}))
    note = tmp_path / "note.typ"
    note.write_bytes(b"Original\r\n")

    def fail(*args, **kwargs):
        raise RuntimeError("Transcription failed")

    monkeypatch.setattr(worker, "transcribe", fail)
    worker.run_once(tmp_path)
    job = json.loads(job_path.read_text())
    assert job["status"] == "failed"
    assert job["error"] == "Transcription failed"
    assert note.read_bytes() == b"Original\r\n"


@pytest.mark.parametrize("requested", [None, "", "ru"])
def test_job_language(tmp_path, monkeypatch, requested):
    jobs = tmp_path / "_system/jobs/transcripts"
    jobs.mkdir(parents=True)
    original = {"status": "queued", "audio": "audio.wav", "note": "note.typ",
                "lang": requested, "requested_at": "yesterday", "extra": 42}
    job_path = jobs / "job.json"
    job_path.write_text(json.dumps(original))
    (tmp_path / "note.typ").write_text("= Note\n")

    def fake(audio, model, lang):
        assert lang == (requested or None)
        return [(0, "Hello")], "en"

    monkeypatch.setattr(worker, "transcribe", fake)
    worker.run_once(tmp_path)
    job = json.loads(job_path.read_text())
    assert job["lang"] == "en"
    assert job["status"] == "done"
    assert job["extra"] == 42
    assert job["requested_at"] == "yesterday"


def test_transcribe_detected_language(monkeypatch):
    class Model:
        def __init__(self, model):
            assert model == "small"

        def transcribe(self, audio, language):
            assert (audio, language) == ("audio.wav", None)
            return iter([SimpleNamespace(start=1, text=" Hello ")]), SimpleNamespace(language="en")

    monkeypatch.setitem(sys.modules, "faster_whisper", SimpleNamespace(WhisperModel=Model))
    assert worker.transcribe("audio.wav", lang="") == ([(1, "Hello")], "en")


@pytest.mark.parametrize("existing", [False, True])
def test_translation_job(tmp_path, existing):
    jobs = tmp_path / "_system/jobs/translations"
    jobs.mkdir(parents=True)
    original = {"audio": "audio.wav", "note": "note.typ", "target": "ru",
                "source_lang": "en", "requested_at": "yesterday", "status": "queued"}
    job_path = jobs / (hashlib.sha1(b"audio.wav\nru").hexdigest() + ".json")
    job_path.write_text(json.dumps(original))
    comments = "== Comments\r\nKeep *this* \\# exactly.\r\n\r\n"
    transcript = "== Transcript\r\n\r\n- 00:00 Hello \\#name\\\\\r\n- 61:40 Next\r\n"
    notes = "== Notes\r\nUnchanged\r\n"
    prefix = "= Note\r\n" + comments + transcript
    note = tmp_path / "note.typ"
    note.write_bytes((prefix + ("== Translation ru\nOld\n" if existing else "") + notes).encode())

    def fake(texts, source_lang, target):
        assert (texts, source_lang, target) == (["Hello #name\\", "Next"], "en", "ru")
        assert json.loads(job_path.read_text())["status"] == "processing"
        return ["Привет \\#[]$*_@", "Далее"]

    expected = (prefix + "== Translation ru\n\n- 00:00 " +
                worker.escape_markup("Привет \\#[]$*_@") + "\n- 61:40 Далее\n" + notes).encode()
    for _ in range(2):
        job_path.write_text(json.dumps(original))
        worker.run_once(tmp_path, translate=fake)
        assert note.read_bytes() == expected
        job = json.loads(job_path.read_text())
        assert job["status"] == "done"
        assert job["finished_at"]
        assert all(job[key] == value for key, value in original.items() if key != "status")


def test_translation_missing_transcript(tmp_path):
    jobs = tmp_path / "_system/jobs/translations"
    jobs.mkdir(parents=True)
    job_path = jobs / "job.json"
    job_path.write_text(json.dumps({"status": "queued", "audio": "audio.wav",
                                    "note": "note.typ", "source_lang": "en", "target": "ru"}))
    note = tmp_path / "note.typ"
    note.write_bytes(b"== Comments\r\nOriginal")

    def unexpected(*args):
        pytest.fail("Translation must not run without a transcript")

    worker.run_once(tmp_path, translate=unexpected)
    job = json.loads(job_path.read_text())
    assert job["status"] == "failed"
    assert "no Transcript" in job["error"]
    assert note.read_bytes() == b"== Comments\r\nOriginal"


def test_transcription_before_translation(tmp_path, monkeypatch):
    for kind in ("transcripts", "translations"):
        jobs = tmp_path / "_system/jobs" / kind
        jobs.mkdir(parents=True)
        job = {"status": "queued", "audio": "audio.wav", "note": "note.typ"}
        if kind == "translations":
            job.update(source_lang="en", target="ru")
        (jobs / "job.json").write_text(json.dumps(job))
    note = tmp_path / "note.typ"
    note.write_text("= Note\n")
    monkeypatch.setattr(worker, "transcribe", lambda *args, **kwargs: ([(65, "Hello")], "en"))

    def fake(texts, source_lang, target):
        assert texts == ["Hello"]
        return ["Привет"]

    worker.run_once(tmp_path, translate=fake)
    assert note.read_text() == (
        "= Note\n\n== Transcript\n\n- 01:05 Hello\n"
        "== Translation ru\n\n- 01:05 Привет\n"
    )


def test_translation_backend_failure_keeps_note(tmp_path):
    jobs = tmp_path / "_system/jobs/translations"
    jobs.mkdir(parents=True)
    job_path = jobs / "job.json"
    job_path.write_text(json.dumps({"status": "queued", "audio": "audio.wav",
                                    "note": "note.typ", "source_lang": "en", "target": "ru"}))
    note = tmp_path / "note.typ"
    original = b"== Transcript\r\n- 00:00 Hello\r\n== Translation ru\r\nOld\r\n"
    note.write_bytes(original)

    def fail(*args):
        raise RuntimeError("Backend unavailable")

    worker.run_once(tmp_path, translate=fail)
    job = json.loads(job_path.read_text())
    assert job["status"] == "failed"
    assert job["error"] == "Backend unavailable"
    assert note.read_bytes() == original


@pytest.mark.parametrize("fenced", [False, True])
def test_translation_backend_batches(tmp_path, monkeypatch, fenced):
    monkeypatch.setenv("TYLOG_LLM_URL", "https://studio.example/v1/")
    monkeypatch.setenv("TYLOG_LLM_KEY", "test-key")
    monkeypatch.delenv("TYLOG_LLM_MODEL", raising=False)
    batches = []

    def fake(request, timeout):
        assert request.get_header("Authorization") == "Bearer test-key"
        assert timeout == 120
        if request.full_url.endswith("/models"):
            assert request.get_method() == "GET"
            result = {"data": [{"id": "unloaded", "loaded": False},
                               {"id": "translator", "loaded": True}]}
        else:
            assert request.full_url == "https://studio.example/v1/chat/completions"
            payload = json.loads(request.data)
            assert payload["model"] == "translator"
            assert payload["temperature"] == 0
            batch = json.loads(payload["messages"][1]["content"])
            batches.append(batch)
            reply = json.dumps(["ru " + text for text in batch])
            if fenced:
                reply = "```json\n" + reply + "\n```"
            result = {"choices": [{"message": {"content": reply}}]}
        return BytesIO(json.dumps(result).encode())

    monkeypatch.setattr(worker, "urlopen", fake)
    texts = [f"segment {index}" for index in range(81)]
    assert worker.translate(texts, "en", "ru") == ["ru " + text for text in texts]
    assert [len(batch) for batch in batches] == [40, 40, 1]


@pytest.mark.parametrize("reply", ['[]', '{}', '[1]', 'not JSON'])
def test_translation_backend_invalid_reply(monkeypatch, reply):
    monkeypatch.setenv("TYLOG_LLM_URL", "https://studio.example/v1")
    monkeypatch.setenv("TYLOG_LLM_KEY", "test-key")
    monkeypatch.setenv("TYLOG_LLM_MODEL", "translator")
    monkeypatch.setattr(worker, "urlopen", lambda *args, **kwargs: BytesIO(json.dumps(
        {"choices": [{"message": {"content": reply}}]}
    ).encode()))
    with pytest.raises(ValueError):
        worker.translate(["Hello"], "en", "ru")


def test_translation_backend_studio_fallback(tmp_path, monkeypatch):
    for name in ("TYLOG_LLM_URL", "TYLOG_LLM_KEY", "TYLOG_LLM_MODEL"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setattr(worker.Path, "home", lambda: tmp_path)
    config = tmp_path / ".pi/agent/models.json"
    config.parent.mkdir(parents=True)
    config.write_text(json.dumps({"providers": {"studio": {
        "baseUrl": "https://studio.example/v1", "apiKey": "studio-key"}}}))

    def fake(request, timeout):
        assert request.get_header("Authorization") == "Bearer studio-key"
        result = ({"data": [{"id": "model", "loaded": True}]}
                  if request.full_url.endswith("/models") else
                  {"choices": [{"message": {"content": '["Привет"]'}}]})
        return BytesIO(json.dumps(result).encode())

    monkeypatch.setattr(worker, "urlopen", fake)
    assert worker.translate(["Hello"], "en", "ru") == ["Привет"]
