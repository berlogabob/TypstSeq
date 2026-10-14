import json
import hashlib
import sys
from datetime import datetime, timedelta
from types import SimpleNamespace
from io import BytesIO

import pytest

import transcribe_worker as worker


@pytest.fixture(autouse=True)
def isolated_state(tmp_path, monkeypatch):
    monkeypatch.setattr(worker.Path, "home", lambda: tmp_path)
    monkeypatch.setattr(worker, "KEYS_PATH", tmp_path / ".tylog/keys.json")
    for name in worker.os.environ:
        if name.startswith("TYLOG_KEY_"):
            monkeypatch.delenv(name, raising=False)
    for name in ("TYLOG_LLM_URL", "TYLOG_LLM_KEY", "TYLOG_LLM_MODEL", "TYLOG_LLM_PREFER"):
        monkeypatch.delenv(name, raising=False)


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
        assert (model, lang) == ("large-v3", "pt")
        assert json.loads(job_path.read_text())["status"] == "processing"
        return [(65, "Fixed text")], "pt", ["pt"]

    monkeypatch.setattr(worker, "transcribe", fake_transcribe)
    state_path = tmp_path / "custom-state.json"
    worker.main(["--vault", str(tmp_path), "--once", "--state", str(state_path)])
    assert json.loads(state_path.read_text()) == {}
    job = json.loads(job_path.read_text())
    assert job["status"] == "done"
    assert job["finished_at"]
    assert job["lang"] == "pt"
    assert job["langs"] == ["pt"]
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
        return [(0, "Hello")], "en", ["en", "ru"]

    monkeypatch.setattr(worker, "transcribe", fake)
    worker.run_once(tmp_path)
    job = json.loads(job_path.read_text())
    assert job["lang"] == "en"
    assert job["langs"] == ["en", "ru"]
    assert job["status"] == "done"
    assert job["extra"] == 42
    assert job["requested_at"] == "yesterday"


def test_transcribe_detected_language(monkeypatch):
    calls = []

    class Model:
        def __init__(self, model):
            assert model == "small"
            calls.append("load")

        def transcribe(self, audio, language, multilingual):
            assert (audio, language, multilingual) == ("audio.wav", None, True)
            return iter([SimpleNamespace(start=1, end=4, text=" Hello ")]), SimpleNamespace(language="en")

        def detect_language(self, audio):
            assert audio == range(30 * 16000)
            calls.append("detect")
            return "en", 0.9, []

    def decode(audio, sampling_rate):
        assert (audio, sampling_rate) == ("audio.wav", 16000)
        calls.append("decode")
        return range(30 * 16000)

    monkeypatch.setitem(sys.modules, "faster_whisper", SimpleNamespace(WhisperModel=Model, decode_audio=decode))
    assert worker.transcribe("audio.wav", lang="") == ([(1, "Hello")], "en", ["en"])
    assert calls == ["load", "decode", "detect"]


@pytest.mark.parametrize("fail_detection", [False, True])
def test_transcribe_language_windows_and_threshold(monkeypatch, fail_detection):
    segments = [SimpleNamespace(start=start, end=end, text=" speech ")
                for start, end in [(0, 20), (20, 30), (30, 40), (40, 45),
                                   (90, 105), (120, 134), (150, 166), (180, 190)]]
    # 100 s speech: ru=45%, pt=15%, de=14%, en=16%, dominant fr=10%.
    detections = {0: "ru", 1: "ru", 3: "pt", 4: "de", 5: "en", 6: "fr"}
    calls = []

    class Model:
        def __init__(self, model):
            calls.append("load")

        def transcribe(self, audio, **kwargs):
            assert kwargs == {"language": None, "multilingual": True}
            return iter(segments), SimpleNamespace(language="fr")

        def detect_language(self, audio):
            window = audio.start // (30 * 16000)
            assert audio == range(window * 30 * 16000, (window + 1) * 30 * 16000)
            calls.append(window)
            if fail_detection and window == 3:
                raise RuntimeError("Detection failed")
            return detections[window], 0.9, []

    def decode(audio, sampling_rate):
        assert (audio, sampling_rate) == ("audio.wav", 16000)
        calls.append("decode")
        return range(210 * 16000)

    monkeypatch.setitem(sys.modules, "faster_whisper", SimpleNamespace(WhisperModel=Model, decode_audio=decode))
    texts, dominant, languages = worker.transcribe("audio.wav")
    assert texts == [(segment.start, "speech") for segment in segments]
    assert dominant == "fr"
    assert languages == (["fr"] if fail_detection else ["fr", "ru", "en", "pt"])
    assert calls == ["load", "decode", 0, 1, 3] + ([] if fail_detection else [4, 5, 6])


def test_transcribe_forced_language_skips_detection(monkeypatch):
    class Model:
        def __init__(self, model):
            assert model == "small"

        def transcribe(self, audio, **kwargs):
            assert kwargs == {"language": "pt"}
            return iter([SimpleNamespace(start=1, end=2, text=" Olá ")]), SimpleNamespace(language="pt")

        def detect_language(self, **kwargs):
            pytest.fail("Forced language must skip detection")

    def decode(*args, **kwargs):
        pytest.fail("Forced language must skip decoding")

    monkeypatch.setitem(sys.modules, "faster_whisper", SimpleNamespace(WhisperModel=Model, decode_audio=decode))
    assert worker.transcribe("audio.wav", lang="pt") == ([(1, "Olá")], "pt", ["pt"])


@pytest.mark.parametrize("existing", [False, True])
@pytest.mark.parametrize("source_langs", [None, ["en", "pt"]])
def test_translation_job(tmp_path, existing, source_langs):
    jobs = tmp_path / "_system/jobs/translations"
    jobs.mkdir(parents=True)
    original = {"audio": "audio.wav", "note": "note.typ", "target": "ru",
                "source_lang": "en", "requested_at": "yesterday", "status": "queued"}
    if source_langs is not None:
        original["source_langs"] = source_langs
    job_path = jobs / (hashlib.sha1(b"audio.wav\nru").hexdigest() + ".json")
    job_path.write_text(json.dumps(original))
    comments = "== Comments\r\nKeep *this* \\# exactly.\r\n\r\n"
    transcript = "== Transcript\r\n\r\n- 00:00 Hello \\#name\\\\\r\n- 61:40 Next\r\n"
    notes = "== Notes\r\nUnchanged\r\n"
    prefix = "= Note\r\n" + comments + transcript
    note = tmp_path / "note.typ"
    note.write_bytes((prefix + ("== Translation ru\nOld\n" if existing else "") + notes).encode())

    def fake(texts, source_lang, target, source_langs):
        assert (texts, source_lang, target) == (["Hello #name\\", "Next"], "en", "ru")
        assert json.loads(job_path.read_text())["status"] == "processing"
        assert source_langs == original.get("source_langs", ["en"])
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
    monkeypatch.setattr(worker, "transcribe", lambda *args, **kwargs: ([(65, "Hello")], "en", ["en"]))

    def fake(texts, source_lang, target, source_langs):
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
@pytest.mark.parametrize("source_langs", [None, ["en", "pt", "ru"]])
def test_translation_backend_batches(tmp_path, monkeypatch, fenced, source_langs):
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
                               {"id": "Qwen3-Coder", "loaded": True},
                               {"id": "ollama/ornith-1.5:35b", "loaded": True}]}
        else:
            assert request.full_url == "https://studio.example/v1/chat/completions"
            payload = json.loads(request.data)
            assert payload["model"] == "ollama/ornith-1.5:35b"
            assert payload["temperature"] == 0
            prompt = payload["messages"][0]["content"]
            assert "Translate faithfully into ru" in prompt
            assert "Segments that are already in the target language must be returned unchanged" in prompt
            assert "The source may mix these languages: " + ", ".join(source_langs or ["en"]) in prompt
            batch = json.loads(payload["messages"][1]["content"])
            batches.append(batch)
            reply = json.dumps(["ru " + text for text in batch])
            if fenced:
                reply = "```json\n" + reply + "\n```"
            result = {"choices": [{"message": {"content": reply}}]}
        return BytesIO(json.dumps(result).encode())

    monkeypatch.setattr(worker, "urlopen", fake)
    texts = [f"segment {index}" for index in range(81)]
    assert worker.translate(texts, "en", "ru", source_langs) == ["ru " + text for text in texts]
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
        result = ({"data": [{"id": "Ornith", "loaded": True}]}
                  if request.full_url.endswith("/models") else
                  {"choices": [{"message": {"content": '["Привет"]'}}]})
        return BytesIO(json.dumps(result).encode())

    monkeypatch.setattr(worker, "urlopen", fake)
    assert worker.translate(["Hello"], "en", "ru") == ["Привет"]


@pytest.mark.parametrize("prefer, loaded, expected", [
    ("ollama/ornith-1.5:35b", ["Qwen3-Coder", "ORNITH-other", "ollama/ornith-1.5:35b"],
     "ollama/ornith-1.5:35b"),
    ("custom-translator", ["Qwen3-Coder", "Ornith", "custom-translator"], "custom-translator"),
    ("ollama/ornith-1.5:35b", ["Qwen3-Coder", "OLLAMA/ORNITH-other"], "OLLAMA/ORNITH-other"),
])
def test_ensure_model_loaded_preference(prefer, loaded, expected):
    def request(route, payload=None):
        assert (route, payload) == ("/models", None)
        return {"data": [{"id": model, "loaded": True} for model in loaded]}

    assert worker.ensure_model("https://studio.example/v1", "key", prefer, request) == expected


def test_translation_loads_preferred_model(monkeypatch):
    monkeypatch.setenv("TYLOG_LLM_URL", "https://studio.example/v1/")
    monkeypatch.setenv("TYLOG_LLM_KEY", "test-key")
    monkeypatch.setenv("TYLOG_LLM_PREFER", "custom-translator")
    calls = []
    polls = 0
    sleeps = []
    monkeypatch.setattr(worker.time, "sleep", sleeps.append)

    def fake(request, timeout):
        nonlocal polls
        assert request.get_header("Authorization") == "Bearer test-key"
        calls.append(request.full_url)
        if request.full_url.endswith("/models"):
            polls += 1
            result = {"data": [{"id": "Qwen3-Coder", "loaded": True},
                               {"id": "custom-translator", "loaded": polls >= 3}]}
        elif request.full_url == "https://studio.example/api/models/local":
            result = {"models": [{"id": "studio-reference", "model_id": "custom-translator"}]}
        elif request.full_url == "https://studio.example/v1/load":
            assert request.get_method() == "POST"
            assert timeout == 900
            assert json.loads(request.data) == {"model_path": "studio-reference", "max_seq_length": 65536}
            result = {"success": True}
        else:
            assert request.full_url == "https://studio.example/v1/chat/completions"
            assert json.loads(request.data)["model"] == "custom-translator"
            result = {"choices": [{"message": {"content": '["Привет"]'}}]}
        return BytesIO(json.dumps(result).encode())

    monkeypatch.setattr(worker, "urlopen", fake)
    assert worker.translate(["Hello"], "en", "ru") == ["Привет"]
    assert worker.translate.last_model == "custom-translator"
    assert calls == ["https://studio.example/v1/models", "https://studio.example/api/models/local",
                     "https://studio.example/v1/load", "https://studio.example/v1/models",
                     "https://studio.example/v1/models", "https://studio.example/v1/chat/completions"]
    assert sleeps == [5]


@pytest.mark.parametrize("failure", ["http", "rejected", "timeout"])
def test_ensure_model_load_failure_has_no_fallback(monkeypatch, failure):
    now = [0]
    monkeypatch.setattr(worker.time, "monotonic", lambda: now[0])
    monkeypatch.setattr(worker.time, "sleep", lambda seconds: now.__setitem__(0, now[0] + seconds))
    calls = []

    def request(route, payload=None):
        calls.append(route)
        if route == "/models":
            return {"data": [{"id": "Qwen3-Coder", "loaded": True}]}
        if route.endswith("/api/models/local"):
            return {"models": []}
        assert route == "https://studio.example/v1/load"
        assert payload == {"model_path": "ollama/ornith-1.5:35b", "max_seq_length": 65536}
        if failure == "http":
            raise OSError("load unavailable")
        return {"success": failure != "rejected"}

    with pytest.raises(ValueError, match="preferred translation model ollama/ornith-1.5:35b"):
        worker.ensure_model("https://studio.example/v1", "key", "ollama/ornith-1.5:35b", request)
    assert "https://studio.example/v1/load" in calls
    if failure == "timeout":
        assert now[0] == 900


def test_translation_override_wins_and_job_records_llm(tmp_path, monkeypatch):
    monkeypatch.setenv("TYLOG_LLM_URL", "https://studio.example/v1")
    monkeypatch.setenv("TYLOG_LLM_MODEL", "exact/custom-model")
    monkeypatch.setenv("TYLOG_LLM_PREFER", "ollama/ornith-1.5:35b")
    jobs = tmp_path / "_system/jobs/translations"
    jobs.mkdir(parents=True)
    job_path = jobs / "job.json"
    job_path.write_text(json.dumps({"status": "queued", "audio": "audio.wav",
                                    "note": "note.typ", "source_lang": "en", "target": "ru"}))
    (tmp_path / "note.typ").write_text("== Transcript\n- 00:00 Hello\n")

    def fake(request, timeout):
        assert request.full_url == "https://studio.example/v1/chat/completions"
        assert json.loads(request.data)["model"] == "exact/custom-model"
        return BytesIO(json.dumps({"choices": [{"message": {"content": '["Привет"]'}}]}).encode())

    monkeypatch.setattr(worker, "urlopen", fake)
    worker.run_once(tmp_path)
    job = json.loads(job_path.read_text())
    assert job["status"] == "done"
    assert job["llm"] == "exact/custom-model"


@pytest.fixture
def sweep_vault(tmp_path, monkeypatch):
    settings_path = tmp_path / "_system/settings/processing.json"
    settings_path.parent.mkdir(parents=True)
    (tmp_path / "notes").mkdir()
    (tmp_path / "assets/audio").mkdir(parents=True)
    monkeypatch.setattr(worker, "transcribe", lambda *args, **kwargs: ([(0, "Hello")], "en", ["en"]))
    return tmp_path


def set_audio_settings(vault, **overrides):
    audio = {"transcribe": True, "on_the_fly": False, "scheduled": False,
             "time": "03:00", "translate_to": []}
    audio.update(overrides)
    (vault / "_system/settings/processing.json").write_text(json.dumps({"schema": 1, "audio": audio}))


def add_audio_note(vault, name="take.wav", kind="audio", body="", exists=True, attachment=None):
    audio = "assets/audio/" + name
    if exists:
        (vault / audio).write_bytes(b"fake audio")
    note = vault / "notes" / ("Audio " + name + ".typ")
    note.write_text(f'#show: tylog.note.with(id: "take", kind: "{kind}")\n'
                    f'\n= Audio\n#tylog.attachment("{attachment or audio}", kind: "audio")\n' + body)
    return audio, note


def job_path(vault, kind, key):
    return vault / "_system/jobs" / kind / (hashlib.sha1(key.encode()).hexdigest() + ".json")


def write_job(vault, kind, key, **fields):
    path = job_path(vault, kind, key)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(fields))
    return path


NOW = datetime(2026, 10, 14, 9)


@pytest.mark.parametrize("settings", [None, {}, {"transcribe": False, "on_the_fly": True},
                                      {"transcribe": False, "scheduled": True}])
def test_sweep_closed(sweep_vault, settings):
    vault = sweep_vault
    add_audio_note(vault)
    if settings is not None:
        set_audio_settings(vault, **settings)
    state = {}
    assert worker.sweep(vault, NOW, state) == 0
    assert not list((vault / "_system/jobs").rglob("*.json"))
    assert state == {}


def test_on_the_fly_processes_then_translates_next_sweep(sweep_vault):
    vault = sweep_vault
    set_audio_settings(vault, on_the_fly=True, translate_to=["ru", "en", "pt"])
    audio, note = add_audio_note(vault)
    state_path = vault / "state.json"
    worker.run_once(vault, now=NOW, state_path=state_path)
    job = json.loads(job_path(vault, "transcripts", audio).read_text())
    assert job["status"] == "done"
    assert job["auto"] is True
    assert job["note"] == note.relative_to(vault).as_posix()
    assert job["requested_at"] == NOW.astimezone(worker.timezone.utc).isoformat()
    assert "== Transcript" in note.read_text()
    assert not list((vault / "_system/jobs/translations").glob("*.json"))

    calls = []

    def fake_translate(texts, source_lang, target, source_langs):
        calls.append((texts, source_lang, target))
        return [target + " Hello"]

    worker.run_once(vault, now=NOW, state_path=state_path, translate=fake_translate)
    assert sorted(calls) == [(["Hello"], "en", "pt"), (["Hello"], "en", "ru")]
    assert worker.sweep(vault, NOW, {}) == 0


def test_scheduled_catch_up_once_per_local_day(sweep_vault):
    vault = sweep_vault
    set_audio_settings(vault, scheduled=True)
    first, _ = add_audio_note(vault)
    state_path = vault / "state.json"
    worker.run_once(vault, now=NOW.replace(hour=2, minute=59), state_path=state_path)
    assert not job_path(vault, "transcripts", first).exists()
    worker.run_once(vault, now=NOW, state_path=state_path)
    assert job_path(vault, "transcripts", first).exists()
    # The scheduled run stays open until a sweep finds nothing left to do.
    assert "last_scheduled_date" not in json.loads(state_path.read_text())
    worker.run_once(vault, now=NOW, state_path=state_path)
    assert json.loads(state_path.read_text())["last_scheduled_date"] == "2026-10-14"
    second, _ = add_audio_note(vault, "second.wav")
    worker.run_once(vault, now=NOW, state_path=state_path)
    assert not job_path(vault, "transcripts", second).exists()
    worker.run_once(vault, now=NOW + timedelta(days=1), state_path=state_path)
    assert job_path(vault, "transcripts", second).exists()
    worker.run_once(vault, now=NOW + timedelta(days=1), state_path=state_path)
    assert json.loads(state_path.read_text())["last_scheduled_date"] == "2026-10-15"


def test_schedule_at_exact_time_and_empty_sweep(sweep_vault):
    set_audio_settings(sweep_vault, scheduled=True)
    state = {}
    assert worker.sweep(sweep_vault, NOW.replace(hour=3, minute=0), state) == 0
    assert state == {"last_scheduled_date": "2026-10-14"}


def test_process_now_forces_once_per_request(sweep_vault):
    vault = sweep_vault
    set_audio_settings(vault, scheduled=True)
    first, _ = add_audio_note(vault)
    request = vault / "_system/jobs/process-now.json"
    request.parent.mkdir(parents=True)
    request.write_text(json.dumps({"requested_at": "2026-10-14T01:00:00Z"}))
    state_path = vault / "state.json"
    before = NOW.replace(hour=1)
    worker.run_once(vault, now=before, state_path=state_path)
    assert job_path(vault, "transcripts", first).exists()
    assert json.loads(state_path.read_text()) == {"last_process_now": "2026-10-14T01:00:00Z"}
    second, _ = add_audio_note(vault, "second.wav")
    worker.run_once(vault, now=before, state_path=state_path)
    assert not job_path(vault, "transcripts", second).exists()
    request.write_text(json.dumps({"requested_at": "2026-10-14T01:01:00Z"}))
    worker.run_once(vault, now=before, state_path=state_path)
    assert job_path(vault, "transcripts", second).exists()
    assert request.exists()
    assert json.loads(state_path.read_text())["last_process_now"] == "2026-10-14T01:01:00Z"


def test_force_respects_both_features_disabled(sweep_vault):
    set_audio_settings(sweep_vault, transcribe=False, translate=False, translate_to=["ru"])
    audio, _ = add_audio_note(sweep_vault, body="== Transcript\n- 00:00 Hello\n")
    write_job(sweep_vault, "transcripts", audio, lang="en", status="done")
    assert worker.sweep(sweep_vault, NOW, {}, force=True) == 0
    assert not list((sweep_vault / "_system/jobs/translations").glob("*.json"))


@pytest.mark.parametrize("status", ["queued", "processing", "done", "failed"])
def test_existing_jobs_block_recreation(sweep_vault, status):
    vault = sweep_vault
    set_audio_settings(vault, on_the_fly=True, translate_to=["ru"])
    missing, _ = add_audio_note(vault, body="== Transcript\n \n== Comments\nKeep\n")
    complete, _ = add_audio_note(vault, "complete.wav", body="== Transcript\n- 00:00 Hello\n")
    transcript = write_job(vault, "transcripts", missing, status=status)
    write_job(vault, "transcripts", complete, status="done", lang="en")
    translation = write_job(vault, "translations", complete + "\nru", status=status)
    originals = [path.read_bytes() for path in (transcript, translation)]
    assert worker.sweep(vault, NOW, {}) == 0
    assert [path.read_bytes() for path in (transcript, translation)] == originals


def test_translation_only_missing_targets(sweep_vault):
    vault = sweep_vault
    set_audio_settings(vault, on_the_fly=True, translate_to=["ru", "en", "pt", "de"])
    audio, _ = add_audio_note(vault, body="== Transcript\n- 00:00 Hello\n== Translation ru\n\n")
    write_job(vault, "transcripts", audio, lang="en", status="done")
    write_job(vault, "translations", audio + "\nde", status="failed")
    assert worker.sweep(vault, NOW, {}) == 1
    job = json.loads(job_path(vault, "translations", audio + "\npt").read_text())
    assert (job["target"], job["source_lang"], job["status"], job["auto"]) == ("pt", "en", "queued", True)
    assert job["source_langs"] == ["en"]
    assert not job_path(vault, "translations", audio + "\nen").exists()
    assert not job_path(vault, "translations", audio + "\nru").exists()


@pytest.mark.parametrize("flag, targets, expected", [
    (None, ["ru"], 1), (None, [], 0),
    (False, ["ru"], 0), (True, ["ru"], 1), (True, [], 0),
])
def test_translate_setting_independent_of_transcribe(sweep_vault, flag, targets, expected):
    settings = {"transcribe": False, "on_the_fly": True, "translate_to": targets}
    if flag is not None:
        settings["translate"] = flag
    set_audio_settings(sweep_vault, **settings)
    audio, _ = add_audio_note(sweep_vault, body="== Transcript\n- 00:00 Hello\n")
    add_audio_note(sweep_vault, "untranscribed.wav")
    transcript_job = write_job(sweep_vault, "transcripts", audio, lang="en", status="done")
    original = transcript_job.read_bytes()
    assert worker.sweep(sweep_vault, NOW, {}) == expected
    assert list((sweep_vault / "_system/jobs/transcripts").glob("*.json")) == [transcript_job]
    assert transcript_job.read_bytes() == original
    assert len(list((sweep_vault / "_system/jobs/translations").glob("*.json"))) == expected


def test_transcribe_enabled_translate_disabled(sweep_vault):
    set_audio_settings(sweep_vault, on_the_fly=True, translate=False, translate_to=["ru"])
    missing, _ = add_audio_note(sweep_vault)
    complete, _ = add_audio_note(sweep_vault, "complete.wav", body="== Transcript\n- 00:00 Hello\n")
    write_job(sweep_vault, "transcripts", complete, lang="en", status="done")
    assert worker.sweep(sweep_vault, NOW, {}) == 1
    assert job_path(sweep_vault, "transcripts", missing).exists()
    assert not list((sweep_vault / "_system/jobs/translations").glob("*.json"))


@pytest.mark.parametrize("langs, expected", [(["pt"], ["ru", "en"]),
                                            (["pt", "ru"], ["ru", "en", "pt"])])
def test_translation_targets_for_monolingual_and_mixed_transcripts(sweep_vault, langs, expected):
    set_audio_settings(sweep_vault, on_the_fly=True, translate_to=["ru", "en", "pt"])
    second = "Привет" if len(langs) > 1 else "Olá novamente"
    audio, note = add_audio_note(sweep_vault, body=f"== Transcript\n- 00:00 Olá\n- 00:30 {second}\n")
    write_job(sweep_vault, "transcripts", audio, lang="pt", langs=langs, status="done")
    assert worker.sweep(sweep_vault, NOW, {}) == len(expected)
    for target in expected:
        job = json.loads(job_path(sweep_vault, "translations", audio + "\n" + target).read_text())
        assert job["source_lang"] == "pt"
        assert job["source_langs"] == langs
        assert job["target"] == target
    calls = []

    def fake(texts, source_lang, target, source_langs):
        assert texts == ["Olá", second]
        assert (source_lang, source_langs) == ("pt", langs)
        calls.append(target)
        return [target + " first", target + " second"]

    worker.run_once(sweep_vault, now=NOW, translate=fake)
    assert sorted(calls) == sorted(expected)
    for target in expected:
        assert f"== Translation {target}\n\n- 00:00 {target} first\n- 00:30 {target} second\n" in note.read_text()
    assert worker.sweep(sweep_vault, NOW, {}) == 0


@pytest.mark.parametrize("gate", ["closed", "on_the_fly", "scheduled", "force"])
def test_translation_only_preserves_sweep_gate(sweep_vault, gate):
    set_audio_settings(sweep_vault, transcribe=False, translate=True, translate_to=["ru"],
                       on_the_fly=gate == "on_the_fly", scheduled=gate == "scheduled")
    audio, _ = add_audio_note(sweep_vault, body="== Transcript\n- 00:00 Hello\n")
    write_job(sweep_vault, "transcripts", audio, lang="en", status="done")
    assert worker.sweep(sweep_vault, NOW, {}, force=gate == "force") == (0 if gate == "closed" else 1)


def test_translate_enabled_without_targets_completes_scheduled_sweep(sweep_vault):
    set_audio_settings(sweep_vault, transcribe=False, translate=True, translate_to=[], scheduled=True)
    add_audio_note(sweep_vault)
    state = {}
    assert worker.sweep(sweep_vault, NOW, state) == 0
    assert state == {"last_scheduled_date": "2026-10-14"}
    assert not list((sweep_vault / "_system/jobs").rglob("*.json"))


@pytest.mark.parametrize("lang", [None, ""])
def test_transcript_without_language_does_not_translate(sweep_vault, lang):
    set_audio_settings(sweep_vault, on_the_fly=True, translate_to=["ru"])
    audio, _ = add_audio_note(sweep_vault, body="== Transcript\nHello\n")
    write_job(sweep_vault, "transcripts", audio, lang=lang, status="done")
    assert worker.sweep(sweep_vault, NOW, {}) == 0


def test_sweep_skips_invalid_notes_and_audio(sweep_vault):
    vault = sweep_vault
    set_audio_settings(vault, on_the_fly=True)
    add_audio_note(vault, "other.wav", kind="note")
    add_audio_note(vault, "missing.wav", exists=False)
    _, no_attachment = add_audio_note(vault, "no-attachment.wav")
    no_attachment.write_text('#show: tylog.note.with(kind: "audio")\n')
    _, no_header = add_audio_note(vault, "no-header.wav")
    no_header.write_text('#tylog.attachment("assets/audio/no-header.wav", kind: "audio")\n')
    add_audio_note(vault, "outside.wav", attachment="../outside.wav")
    (vault.parent / "outside.wav").write_bytes(b"outside")
    assert worker.sweep(vault, NOW, {}) == 0


def test_attachment_unescaping_and_leading_slash(sweep_vault):
    set_audio_settings(sweep_vault, on_the_fly=True)
    audio, _ = add_audio_note(sweep_vault, 'a"b\\c.wav', attachment=r'/assets/audio/a\"b\\c.wav')
    assert worker.sweep(sweep_vault, NOW, {}) == 1
    assert json.loads(job_path(sweep_vault, "transcripts", audio).read_text())["audio"] == audio


@pytest.mark.parametrize("contents", ["broken JSON", "[]", "null"])
def test_corrupt_state_is_empty(sweep_vault, contents):
    set_audio_settings(sweep_vault, scheduled=True)
    audio, _ = add_audio_note(sweep_vault)
    state_path = sweep_vault / "state.json"
    state_path.write_text(contents)
    worker.run_once(sweep_vault, now=NOW, state_path=state_path)
    assert job_path(sweep_vault, "transcripts", audio).exists()
    worker.run_once(sweep_vault, now=NOW, state_path=state_path)
    assert json.loads(state_path.read_text())["last_scheduled_date"] == "2026-10-14"


def test_multiline_header_with_parentheses_in_title(sweep_vault):
    set_audio_settings(sweep_vault, on_the_fly=True)
    audio, note = add_audio_note(sweep_vault)
    note.write_text('#show: tylog.note.with(\n  title: "Audio (take)",\n  kind: "audio",\n)\n'
                    f'#tylog.attachment("{audio}", kind: "audio")\n')
    assert worker.sweep(sweep_vault, NOW, {}) == 1


def test_on_the_fly_continues_after_scheduled_sweep(sweep_vault):
    set_audio_settings(sweep_vault, on_the_fly=True, scheduled=True)
    add_audio_note(sweep_vault)
    state = {}
    assert worker.sweep(sweep_vault, NOW, state) == 1
    assert "last_scheduled_date" not in state  # job still queued
    for job in (sweep_vault / "_system/jobs/transcripts").glob("*.json"):
        job.write_text(json.dumps({"status": "done", "lang": "en"}))
    assert worker.sweep(sweep_vault, NOW, state) == 0
    assert state["last_scheduled_date"] == "2026-10-14"
    add_audio_note(sweep_vault, "next.wav")
    assert worker.sweep(sweep_vault, NOW, state) == 1


def test_empty_translation_targets(sweep_vault):
    set_audio_settings(sweep_vault, on_the_fly=True, translate_to=[])
    audio, _ = add_audio_note(sweep_vault, body="== Transcript\n- 00:00 Hello\n")
    write_job(sweep_vault, "transcripts", audio, status="done", lang="en")
    assert worker.sweep(sweep_vault, NOW, {}) == 0


def test_scheduled_run_stays_open_until_translations_exist(sweep_vault):
    """Overnight: transcripts first, translations on a later sweep, same night."""
    vault = sweep_vault
    set_audio_settings(vault, scheduled=True, translate_to=["ru", "pt"])
    audio, note = add_audio_note(vault)
    state_path = vault / "state.json"
    translated = []

    def fake_translate(texts, source_lang, target, source_langs):
        translated.append(target)
        return [target] * len(texts)

    for _ in range(4):  # the worker runs once a minute
        worker.run_once(vault, now=NOW, state_path=state_path, translate=fake_translate)
    text = note.read_text()
    assert "== Transcript" in text
    assert "== Translation ru" in text and "== Translation pt" in text
    assert sorted(translated) == ["pt", "ru"]
    assert json.loads(state_path.read_text())["last_scheduled_date"] == "2026-10-14"


def write_ai(vault, **fields):
    path = vault / "_system/settings/ai.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"schema": 1, **fields}))


@pytest.mark.parametrize("contents", [None, "broken", "[]", "null", '{"schema": 2}',
                                      '{"unknown": true}'])
def test_load_ai_settings_missing_corrupt_unknown(tmp_path, contents):
    if contents is not None:
        path = tmp_path / "_system/settings/ai.json"
        path.parent.mkdir(parents=True)
        path.write_text(contents)
    assert worker.load_ai_settings(tmp_path) == {}


@pytest.mark.parametrize("quality, expected", [("fast", "small"), ("balanced", "large-v3-turbo"),
                                               ("best", "large-v3"), ("unknown", "large-v3")])
def test_whisper_precedence(tmp_path, quality, expected):
    write_ai(tmp_path, tasks={"transcribe": {"quality": quality, "model": None}})
    settings = worker.load_ai_settings(tmp_path)
    assert worker.resolve_whisper_model(settings, None) == expected
    settings["tasks"]["transcribe"]["model"] = "explicit"
    assert worker.resolve_whisper_model(settings, None) == "explicit"
    assert worker.resolve_whisper_model(settings, "cli") == "cli"
    assert worker.resolve_whisper_model({}, None) == "large-v3"


def test_run_resolves_settings_each_time(sweep_vault, monkeypatch):
    set_audio_settings(sweep_vault, on_the_fly=True)
    calls = []
    monkeypatch.setattr(worker, "transcribe", lambda audio, model, lang:
                        (calls.append(model) or [], "en", ["en"]))
    for index, (task, cli, expected) in enumerate([
        ({"quality": "fast"}, None, "small"),
        ({"quality": "best", "model": "explicit"}, None, "explicit"),
        ({"model": "explicit"}, "cli", "cli"),
    ]):
        write_ai(sweep_vault, tasks={"transcribe": task})
        add_audio_note(sweep_vault, f"{index}.wav")
        worker.run_once(sweep_vault, model=cli, now=NOW)
        assert calls[-1] == expected


@pytest.mark.parametrize("quality, explicit, env_model, prefer, expected, automatic", [
    ("fast", None, None, None, "ollama/ornith-1.5:9b", True),
    ("balanced", None, None, None, "ollama/ornith-1.5:35b", True),
    ("best", None, None, None, "ollama/ornith-1.5:35b", True),
    (None, None, None, None, "ollama/ornith-1.5:35b", True),
    ("fast", "explicit", None, None, "explicit", False),
    ("fast", "explicit", "env", "preferred", "env", False),
    ("fast", None, None, "preferred", "preferred", True),
])
def test_translation_ai_precedence(tmp_path, monkeypatch, quality, explicit, env_model,
                                   prefer, expected, automatic):
    write_ai(tmp_path, connections=[{"id": "studio", "url": "https://configured/v1"}],
             tasks={"translate": {"connection": "studio", "quality": quality, "model": explicit}})
    providers = tmp_path / ".pi/agent/models.json"
    providers.parent.mkdir(parents=True)
    providers.write_text(json.dumps({"providers": {"studio": {"apiKey": "local-key"}}}))
    monkeypatch.setenv("TYLOG_LLM_URL", "https://other/v1")
    if env_model:
        monkeypatch.setenv("TYLOG_LLM_MODEL", env_model)
    if prefer:
        monkeypatch.setenv("TYLOG_LLM_PREFER", prefer)
    calls = []

    def ensure(base, key, preferred, request):
        assert (base, key, preferred) == ("https://configured/v1", "local-key", expected)
        calls.append(preferred)
        return preferred

    def http(request, timeout):
        assert request.full_url == "https://configured/v1/chat/completions"
        assert request.get_header("Authorization") == "Bearer local-key"
        assert json.loads(request.data)["model"] == expected
        return BytesIO(b'{"choices": [{"message": {"content": "[\\"translated\\"]"}}]}')

    monkeypatch.setattr(worker, "ensure_model", ensure)
    monkeypatch.setattr(worker, "urlopen", http)
    assert worker.translate(["hello"], "en", "ru", settings=worker.load_ai_settings(tmp_path)) == ["translated"]
    assert calls == ([expected] if automatic else [])


def test_connection_credentials_match_only_selected_provider(tmp_path, monkeypatch):
    path = tmp_path / ".pi/agent/models.json"
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps({"providers": {"studio": {"baseUrl": "studio-url", "apiKey": "studio-key"},
                                              "other": {"apiKey": "other-key"}}}))
    assert worker.connection_credentials() == ("studio-url", "studio-key")
    assert worker.connection_credentials({"id": "other", "url": "other-url"}) == ("other-url", "other-key")
    assert worker.connection_credentials({"id": "unknown", "url": "url"}) == ("url", None)
    monkeypatch.setenv("TYLOG_LLM_KEY", "env-key")
    assert worker.connection_credentials({"id": "other", "url": "url"}) == ("url", "env-key")
    with pytest.raises(ValueError, match="Unknown translation connection"):
        worker.translate([], "en", "ru", settings={"tasks": {"translate": {"connection": "missing"}}})


@pytest.mark.parametrize("global_key, connection_key, file_key, expected", [
    ("global-secret", "connection-secret", "file-secret", "global-secret"),
    ("", "connection-secret", "file-secret", "connection-secret"),
    ("", "", "file-secret", "file-secret"),
    ("", "", "", "provider-secret"),
])
def test_connection_key_precedence(tmp_path, monkeypatch, global_key, connection_key,
                                   file_key, expected):
    monkeypatch.setenv("TYLOG_LLM_KEY", global_key)
    monkeypatch.setenv("TYLOG_KEY_MY_SERVER", connection_key)
    worker.KEYS_PATH.parent.mkdir(parents=True)
    worker.KEYS_PATH.write_text(json.dumps({"my-server": file_key, "other": "other-secret"}))
    providers = tmp_path / ".pi/agent/models.json"
    providers.parent.mkdir(parents=True)
    providers.write_text(json.dumps({"providers": {"my-server": {"apiKey": "provider-secret"}}}))
    connection = {"id": "my-server", "url": "https://server/v1"}
    assert worker.connection_credentials(connection) == (connection["url"], expected)
    assert worker.connection_credentials({"id": "unknown", "url": "url"}) == (
        "url", global_key or None)


@pytest.mark.parametrize("contents", [None, "broken JSON", "[]", "null",
                                      '{"my-server": 42}', '{"my-server": ""}'])
def test_missing_or_corrupt_keys_file(tmp_path, contents):
    if contents is not None:
        worker.KEYS_PATH.parent.mkdir(parents=True)
        worker.KEYS_PATH.write_text(contents)
    providers = tmp_path / ".pi/agent/models.json"
    providers.parent.mkdir(parents=True)
    providers.write_text(json.dumps({"providers": {"my-server": {"apiKey": "fallback"}}}))
    assert worker.connection_credentials({"id": "my-server", "url": "url"}) == ("url", "fallback")


@pytest.mark.parametrize("source", ["global", "connection", "file", "provider"])
@pytest.mark.parametrize("failed", [False, True])
def test_translation_and_heartbeat_use_key_without_writing_it(tmp_path, monkeypatch, capsys,
                                                            source, failed):
    secret = "private-api-key-123"
    if source == "global":
        monkeypatch.setenv("TYLOG_LLM_KEY", secret)
    elif source == "connection":
        monkeypatch.setenv("TYLOG_KEY_MY_SERVER", secret)
    elif source == "file":
        worker.KEYS_PATH.parent.mkdir(parents=True)
        worker.KEYS_PATH.write_text(json.dumps({"my-server": secret}))
    else:
        providers = tmp_path / ".pi/agent/models.json"
        providers.parent.mkdir(parents=True)
        providers.write_text(json.dumps({"providers": {"my-server": {"apiKey": secret}}}))
    write_ai(tmp_path, connections=[{"id": "my-server", "url": "https://server/v1"}],
             tasks={"translate": {"connection": "my-server", "model": "translator"}})
    path = write_job(tmp_path, "translations", "audio\nru", status="queued",
                     note="note.typ", source_lang="en", target="ru")
    (tmp_path / "note.typ").write_text("== Transcript\n- 00:00 Hello\n")
    calls = []

    def http(request, timeout):
        assert request.get_header("Authorization") == "Bearer " + secret
        calls.append(request.full_url)
        if failed and request.full_url.endswith("/chat/completions"):
            raise OSError("Backend rejected key " + secret)
        result = ({"data": [{"id": "translator"}]} if request.full_url.endswith("/models") else
                  {"choices": [{"message": {"content": '["translated"]'}}]})
        return BytesIO(json.dumps(result).encode())

    monkeypatch.setattr(worker, "urlopen", http)
    state_path = tmp_path / "state.json"
    worker.run_once(tmp_path, state_path=state_path, hostname=lambda: "test-host", now=NOW)
    job = json.loads(path.read_text())
    assert job["status"] == ("failed" if failed else "done")
    if failed:
        assert job["error"] == "Backend rejected key [redacted]"
    heartbeat = tmp_path / "_system/workers/test-host.json"
    assert json.loads(heartbeat.read_text())["connections"]["my-server"]["reachable"] is True
    assert calls == ["https://server/v1/chat/completions", "https://server/v1/models"]
    written = [state_path, *(tmp_path / "_system/jobs").rglob("*.json"),
               *(tmp_path / "_system/workers").glob("*.json")]
    assert all(secret not in file.read_text() for file in written)
    captured = capsys.readouterr()
    assert secret not in captured.out + captured.err


def test_heartbeat_content_and_probe_throttling(tmp_path):
    write_ai(tmp_path, connections=[{"id": "studio", "url": "https://studio/v1"},
                                    {"id": "offline", "url": "https://offline/v1"}])
    hub = tmp_path / ".cache/huggingface/hub"
    for model in ("small", "large-v3"):
        (hub / ("models--Systran--faster-whisper-" + model)).mkdir(parents=True)
    (hub / "models--Other--model").mkdir()
    calls = []

    def probe(base, key):
        calls.append(base)
        if "offline" in base:
            raise OSError("offline")
        return {"reachable": True, "loaded": ["ornith"]}

    now = NOW.replace(tzinfo=worker.timezone.utc)
    kwargs = {"hostname": lambda: "host/unsafe", "probe": probe, "clock": lambda: now}
    worker.run_once(tmp_path, **kwargs)
    heartbeat_path = tmp_path / "_system/workers/host_unsafe.json"
    assert json.loads(heartbeat_path.read_text()) == {
        "host": "host/unsafe", "last_seen": now.isoformat(), "whisper_models": ["large-v3", "small"],
        "connections": {"studio": {"reachable": True, "loaded": ["ornith"]},
                        "offline": {"reachable": False, "loaded": []}}}
    worker.run_once(tmp_path, **{**kwargs, "clock": lambda: now + timedelta(seconds=299)})
    assert len(calls) == 2
    assert json.loads(heartbeat_path.read_text())["last_seen"] == (now + timedelta(seconds=299)).isoformat()
    worker.run_once(tmp_path, **{**kwargs, "clock": lambda: now + timedelta(seconds=300)})
    assert len(calls) == 4
    state = json.loads((tmp_path / ".tylog-transcribe-state.json").read_text())
    assert state["connection_probes"]["studio"]["result"]["loaded"] == ["ornith"]


def test_probe_http_contract(monkeypatch):
    def http(request, timeout):
        assert (request.full_url, request.get_method(), timeout) == ("https://studio/v1/models", "GET", 3)
        assert request.get_header("Authorization") == "Bearer secret"
        return BytesIO(b'{"data": [{"id": "loaded", "loaded": true}, {"id": "off", "loaded": false}, {"id": "openai"}]}')
    monkeypatch.setattr(worker, "urlopen", http)
    assert worker.probe_connection("https://studio/v1/", "secret") == {
        "reachable": True, "loaded": ["loaded", "openai"]}


def test_heartbeat_write_failure_ignored(sweep_vault):
    set_audio_settings(sweep_vault, on_the_fly=True)
    audio, note = add_audio_note(sweep_vault)
    (sweep_vault / "_system/workers").write_text("blocks directory")
    worker.run_once(sweep_vault, now=NOW)
    assert json.loads(job_path(sweep_vault, "transcripts", audio).read_text())["status"] == "done"
    assert "== Transcript" in note.read_text()


@pytest.mark.parametrize("tasks, connections", [(None, None), ([], {}),
    ({"transcribe": [], "translate": {"model": 42, "quality": {}}}, [None, {"id": []}])])
def test_malformed_ai_fields_are_ignored(tmp_path, tasks, connections):
    write_ai(tmp_path, tasks=tasks, connections=connections)
    settings = worker.load_ai_settings(tmp_path)
    assert worker.resolve_whisper_model(settings) == "large-v3"
    assert settings["connections"] == []


def test_run_translation_uses_ai_and_records_model(tmp_path, monkeypatch):
    write_ai(tmp_path, connections=[{"id": "studio", "url": "https://studio/v1"}],
             tasks={"translate": {"connection": "studio", "quality": "fast"}})
    path = write_job(tmp_path, "translations", "audio\nru", status="queued",
                     note="note.typ", source_lang="en", target="ru")
    (tmp_path / "note.typ").write_text("== Transcript\n- 00:00 Hello\n")

    def ensure(base, key, prefer, request):
        assert (base, prefer) == ("https://studio/v1", "ollama/ornith-1.5:9b")
        return prefer

    monkeypatch.setattr(worker, "ensure_model", ensure)
    monkeypatch.setattr(worker, "urlopen", lambda request, timeout:
                        BytesIO(b'{"choices": [{"message": {"content": "[\\"translated\\"]"}}]}'))
    worker.run_once(tmp_path, probe=lambda base, key: {"reachable": True, "loaded": []})
    job = json.loads(path.read_text())
    assert job["status"] == "done"
    assert job["llm"] == "ollama/ornith-1.5:9b"
