import base64
import json
import hashlib
import signal
import sys
import time
from datetime import datetime, timedelta
from email import policy
from email.parser import BytesParser
from types import SimpleNamespace
from io import BytesIO
from urllib.parse import parse_qs
from urllib.error import HTTPError
import wave

import pytest

import audio_v2
import transcribe_worker as worker

real_free_memory_bytes = worker._free_memory_bytes


@pytest.fixture(autouse=True)
def isolated_state(tmp_path, monkeypatch):
    monkeypatch.setattr(worker.Path, "home", lambda: tmp_path)
    monkeypatch.setattr(worker, "KEYS_PATH", tmp_path / ".tylog/keys.json")
    for name in worker.os.environ:
        if name.startswith("TYLOG_KEY_"):
            monkeypatch.delenv(name, raising=False)
    for name in ("TYLOG_LLM_URL", "TYLOG_LLM_KEY", "TYLOG_LLM_MODEL", "TYLOG_LLM_PREFER"):
        monkeypatch.delenv(name, raising=False)
    # Local transcription checks memory and renices: tests get a roomy Mac and no-op nice
    # unless they say otherwise, so results do not depend on the machine running them.
    monkeypatch.setattr(worker, "_free_memory_bytes", lambda: 16 * 1024**3)
    monkeypatch.setattr(worker.os, "nice", lambda increment: None)
    worker.lower_priority.cache_clear()


def test_escape_markup():
    assert worker.escape_markup("\\#[]$*_@ plain") == "\\\\\\#\\[\\]\\$\\*\\_\\@ plain"


@pytest.mark.parametrize("seconds, expected", [(0, "00:00"), (65, "01:05"), (3700, "61:40")])
def test_format_ts(seconds, expected):
    assert worker.format_ts(seconds) == expected


def test_render_section():
    assert worker.render_section([(0, "Hello #world"), (65, "Next")]) == (
        "== Transcript\n\n- 00:00 Hello \\#world\n- 01:05 Next\n"
    )


def test_render_section_speakers():
    assert worker.render_section([(0, "Hello #world", "S1"), (65, "Next", "S2")]) == (
        "== Transcript\n\n- 00:00 [S1] Hello \\#world\n- 01:05 [S2] Next\n"
    )


@pytest.mark.parametrize("vectors, expected", [
    ([[1, 0], [0, 1], [1, 0], [-1, 0]], ["S1", "S2", "S1", "S3"]),
    ([[1, 0], [0.99, 0.01], [1, 0], [1, 0]], None),
])
def test_diarize_clustering(vectors, expected):
    np = pytest.importorskip("numpy")
    pytest.importorskip("sklearn")
    segments = [SimpleNamespace(start=i * 2, end=i * 2 + 2, text=f" text {i} ")
                for i in range(len(vectors))]
    embeddings = iter(vectors)
    result = worker.diarize_segments(np.ones(8 * 16000), segments,
                                     embed=lambda clip: next(embeddings))
    plain = [(s.start, s.text.strip()) for s in segments]
    if expected is None:
        assert result == plain
        assert worker.render_section(result) == worker.render_section(plain)
    else:
        assert result == [(start, text, label) for (start, text), label in zip(plain, expected)]


def test_diarize_short_segments_merge_only_for_embedding():
    np = pytest.importorskip("numpy")
    pytest.importorskip("sklearn")
    segments = [SimpleNamespace(start=start, end=end, text=text)
                for start, end, text in [(0, 0.5, "short"), (1, 3, "long"), (4, 4.5, "last")]]
    samples = np.arange(5 * 16000)
    clips = []

    def embed(clip):
        clips.append(clip)
        return [1, 0]

    result = worker.diarize_segments(samples, segments, embed=embed)
    assert result == [(0, "short"), (1, "long"), (4, "last")]
    np.testing.assert_array_equal(clips[0], np.concatenate([samples[:8000], samples[16000:48000]]))
    np.testing.assert_array_equal(clips[1], samples[16000:48000])
    np.testing.assert_array_equal(clips[2], np.concatenate([samples[16000:48000], samples[64000:72000]]))


@pytest.mark.parametrize("cli, option, enabled", [(False, True, True), (True, False, True),
                                                (False, False, False), (False, "true", False)])
def test_diarize_job_and_cli(tmp_path, monkeypatch, cli, option, enabled):
    jobs = tmp_path / "_system/jobs/transcripts"
    jobs.mkdir(parents=True)
    job_path = jobs / "job.json"
    job_path.write_text(json.dumps({"status": "queued", "audio": "audio.wav", "note": "note.typ",
                                    "diarize": option, "engine": "v1"}))
    note = tmp_path / "note.typ"
    note.write_text("= Note\n")

    def transcribe(audio, model, lang, **kwargs):
        assert kwargs == ({"diarize": True} if enabled else {})
        return [(0, "Hello", "S1"), (2, "Hi", "S2")] if enabled else [(0, "Hello")], "en", ["en"]

    monkeypatch.setattr(worker, "transcribe", transcribe)
    worker.main(["--vault", str(tmp_path), "--once"] + (["--diarize"] if cli else []))
    assert json.loads(job_path.read_text())["status"] == "done"
    assert ("[S1]" in note.read_text()) == enabled


def test_transcribe_diarize_uses_segment_bounds(monkeypatch):
    segments = [SimpleNamespace(start=0, end=2, text=" Hello "),
                SimpleNamespace(start=2, end=4, text=" Hi ")]
    samples = object()
    model = SimpleNamespace(transcribe=lambda *args, **kwargs:
                            (iter(segments), SimpleNamespace(language="en")))
    monkeypatch.setitem(sys.modules, "faster_whisper", SimpleNamespace(
        WhisperModel=lambda name, **options: model,
        decode_audio=lambda path, sampling_rate: samples))

    def diarize(audio, actual_segments):
        assert audio is samples
        assert actual_segments == segments
        return [(0, "Hello", "S1"), (2, "Hi", "S2")]

    monkeypatch.setattr(worker, "diarize_segments", diarize)
    assert worker.transcribe("audio.wav", lang="en", diarize=True) == (
        [(0, "Hello", "S1"), (2, "Hi", "S2")], "en", ["en"])


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
    job_path.write_text(json.dumps({"status": "queued", "audio": "audio.wav", "note": "note.typ", "lang": "pt",
                                    "engine": "v1"}))
    note = tmp_path / "note.typ"
    note.write_bytes(b"= Note\r\n== Comments\r\nKeep me\r\n")

    def fake_transcribe(audio, model, lang):
        assert audio == tmp_path / "audio.wav"
        assert (model, lang) == ("small", "pt")
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
    job_path.write_text(json.dumps({"status": "queued", "audio": "audio.wav", "note": "note.typ", "engine": "v1"}))
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
    original = {"status": "queued", "audio": "audio.wav", "note": "note.typ", "engine": "v1",
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
        def __init__(self, model, **options):
            # int8 on the CPU: float32 large-v3 was 6.6 GB and paged out.
            assert options["compute_type"] == "int8"
            assert model == "small"
            calls.append("load")

        def transcribe(self, audio, language, multilingual):
            assert (audio, language, multilingual) == (range(30 * 16000), None, True)
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
        def __init__(self, model, **options):
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
        def __init__(self, model, **options):
            assert model == "small"

        def transcribe(self, audio, **kwargs):
            assert kwargs == {"language": "pt"}
            return iter([SimpleNamespace(start=1, end=2, text=" Olá ")]), SimpleNamespace(language="pt")

        def detect_language(self, **kwargs):
            pytest.fail("Forced language must skip detection")

    def decode(*args, **kwargs):
        return SimpleNamespace(size=1)  # decoded once up front; detection still skipped

    monkeypatch.setitem(sys.modules, "faster_whisper", SimpleNamespace(WhisperModel=Model, decode_audio=decode))
    assert worker.transcribe("audio.wav", lang="pt") == ([(1, "Olá")], "pt", ["pt"])


@pytest.mark.parametrize("requested", [None, "pt"])
def test_studio_chunks_timestamps_and_language(tmp_path, monkeypatch, requested):
    audio = tmp_path / "audio.wav"
    worker.subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                           "anullsrc=r=8000:cl=stereo", "-t", "65", str(audio)], check=True)
    language = requested or "ru"
    detections = []

    class Model:
        def __init__(self, name, **options):
            assert requested is None
            assert name == "tiny"
            assert options == {"device": "cpu", "compute_type": "int8"}

        def detect_language(self, audio):
            assert audio == range(30 * 16000)
            detections.append(language)
            return language, 0.9, []

    def decode(path, sampling_rate):
        assert (path, sampling_rate) == (str(audio), 16000)
        return range(65 * 16000)

    monkeypatch.setitem(sys.modules, "faster_whisper", SimpleNamespace(
        WhisperModel=Model, decode_audio=decode))
    calls = []

    def post(request, timeout):
        assert (request.full_url, request.get_method(), timeout) == (
            "https://studio/v1/audio/transcriptions", "POST", 120)
        assert request.get_header("Authorization") == "Bearer secret"
        message = BytesParser(policy=policy.default).parsebytes(
            ("Content-Type: " + request.get_header("Content-type") + "\r\n\r\n").encode()
            + request.data)
        parts = {part.get_param("name", header="content-disposition"): part
                 for part in message.iter_parts()}
        assert {name: parts[name].get_content() for name in ("model", "response_format", "language")} == {
            "model": "unsloth/whisper-large-v3-turbo", "response_format": "json", "language": language}
        assert parts["file"].get_filename() == f"out{len(calls):05d}.wav"
        with wave.open(BytesIO(parts["file"].get_payload(decode=True))) as wav:
            assert (wav.getframerate(), wav.getnchannels()) == (16000, 1)
            assert 0 < wav.getnframes() <= 31 * 16000
        calls.append(request)
        return BytesIO(json.dumps({"text": [" First ", " \n ", " Last "][len(calls) - 1]}).encode())

    segments, detected, languages = worker.transcribe_studio(
        audio, "https://studio/v1/", "secret", lang=requested, post=post)
    assert (segments, detected, languages) == ([(0, "First"), (60, "Last")], language, [language])
    assert worker.render_section(segments) == "== Transcript\n\n- 00:00 First\n- 01:00 Last\n"
    assert len(calls) == 3
    assert detections == ([] if requested else [language])


@pytest.mark.parametrize("selected", [None, "studio", "other"])
def test_studio_job_uses_selected_connection(tmp_path, monkeypatch, selected):
    write_ai(tmp_path, connections=[{"id": name, "url": f"https://{name}/v1"}
                                    for name in ("studio", "other")],
             tasks={"transcribe": {"connection": selected, "model": "small"}})
    monkeypatch.setenv("TYLOG_KEY_" + (selected or "studio").upper(), "secret")
    path = write_job(tmp_path, "transcripts", "audio", status="queued", audio="audio.wav",
                     note="note.typ", lang="pt", diarize=True, studio_error="old failure", engine="v1")
    note = tmp_path / "note.typ"
    note.write_text("= Note\n")

    def studio(audio, base, key, lang):
        assert audio == tmp_path / "audio.wav"
        assert (base, key, lang) == (f"https://{selected or 'studio'}/v1", "secret", "pt")
        return [(30, "Olá")], "pt", ["pt"]

    monkeypatch.setattr(worker, "transcribe_studio", studio)
    monkeypatch.setattr(worker, "transcribe", lambda *args, **kwargs: pytest.fail("Local transcription ran"))
    worker.run_once(tmp_path, diarize=True, probe=lambda *args: {"reachable": True, "loaded": []})
    job = json.loads(path.read_text())
    assert (job["status"], job["engine"], job["lang"], job["langs"]) == ("done", "studio", "pt", ["pt"])
    assert "studio_error" not in job
    assert "- 00:30 Olá\n" in note.read_text()


@pytest.mark.parametrize("error", [OSError("Network failed: secret"),
    HTTPError("https://studio/v1", 500, "Rejected secret", {}, None),
    worker.subprocess.CalledProcessError(1, ["ffmpeg", "secret"])])
def test_studio_failure_falls_back_to_local(tmp_path, monkeypatch, error):
    write_ai(tmp_path, connections=[{"id": "studio", "url": "https://studio/v1"}],
             tasks={"transcribe": {"quality": "fast"}})
    monkeypatch.setenv("TYLOG_KEY_STUDIO", "secret")
    path = write_job(tmp_path, "transcripts", "audio", status="queued", audio="audio.wav",
                     note="note.typ", lang="pt", diarize=True, engine="v1")
    note = tmp_path / "note.typ"
    note.write_text("= Note\n")
    calls = []

    def studio(audio, base, key, lang):
        calls.append("studio")
        raise error

    def local(audio, model, lang, **options):
        assert (audio, model, lang, options) == (tmp_path / "audio.wav", "small", "pt", {"diarize": True})
        calls.append("local")
        return [(0, "Fallback")], "pt", ["pt"]

    monkeypatch.setattr(worker, "transcribe_studio", studio)
    monkeypatch.setattr(worker, "transcribe", local)
    monkeypatch.setattr(worker, "_free_memory_bytes", lambda: 16 * 1024**3)
    monkeypatch.setattr(worker.os, "nice", lambda increment: None)
    worker.run_once(tmp_path, probe=lambda *args: {"reachable": False, "loaded": []})
    job = json.loads(path.read_text())
    assert calls == ["studio", "local"]
    assert (job["status"], job["engine"]) == ("done", "local")
    assert job["studio_error"] == str(error).replace("secret", "[redacted]")
    assert "secret" not in path.read_text()
    assert "- 00:00 Fallback\n" in note.read_text()


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

    # merge_section writes the section at the end of the note (the old one is replaced either way)
    expected = (prefix + notes + "\n== Translation ru\n\n- 00:00 " +
                worker.escape_markup("Привет \\#[]$*_@") + "\n- 61:40 Далее\n").encode()
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
        job = {"status": "queued", "audio": "audio.wav", "note": "note.typ", "engine": "v1"}
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
        "\n== Translation ru\n\n- 01:05 Привет\n"
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
        assert timeout == 300
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
            assert payload["chat_template_kwargs"] == {"enable_thinking": False}
            prompt = payload["messages"][0]["content"]
            assert "Translate faithfully into ru" in prompt
            assert "Segments that are already in the target language must be returned unchanged" in prompt
            assert "The source may mix these languages: " + ", ".join(source_langs or ["en"]) in prompt
            batch = json.loads(payload["messages"][1]["content"])
            batches.append(batch)
            reply = json.dumps(["ру " + text for text in batch])
            if fenced:
                reply = "```json\n" + reply + "\n```"
            result = {"choices": [{"message": {"content": reply}}]}
        return BytesIO(json.dumps(result).encode())

    monkeypatch.setattr(worker, "urlopen", fake)
    texts = [f"segment {index}" for index in range(81)]
    assert worker.translate(texts, "en", "ru", source_langs) == ["ру " + text for text in texts]
    assert [len(batch) for batch in batches] == [10] * 8 + [1]


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
            assert json.loads(request.data) == {"model_path": "studio-reference", "max_seq_length": 65536,
                                                "force_cancel_active": True}
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
        assert payload == {"model_path": "ollama/ornith-1.5:35b", "max_seq_length": 65536,
                           "force_cancel_active": True}
        if failure == "http":
            raise OSError("load unavailable")
        return {"success": failure != "rejected"}

    with pytest.raises(ValueError, match="preferred translation model ollama/ornith-1.5:35b"):
        worker.ensure_model("https://studio.example/v1", "key", "ollama/ornith-1.5:35b", request)
    assert "https://studio.example/v1/load" in calls
    if failure == "timeout":
        assert now[0] == 900


def test_load_sends_force_cancel_active(monkeypatch):
    monkeypatch.setattr(worker.time, "sleep", lambda seconds: None)
    loads = []

    def request(route, payload=None):
        if route == "/models":
            return {"data": [{"id": "ollama/ornith-1.5:35b", "loaded": True}] if loads else []}
        if route.endswith("/api/models/local"):
            return {"models": []}
        assert route == "https://studio.example/v1/load"
        loads.append(payload)
        return {"success": True}

    assert worker.ensure_model("https://studio.example/v1", "key", "ollama/ornith-1.5:35b", request) \
        == "ollama/ornith-1.5:35b"
    assert loads == [{"model_path": "ollama/ornith-1.5:35b", "max_seq_length": 65536,
                      "force_cancel_active": True}]


def studio_stub(replies, calls):
    """urlopen stand-in: each chat call takes the next reply. Every request is appended to `calls` as (url, payload)."""
    def fake(request, timeout):
        payload = json.loads(request.data) if request.data else None
        calls.append((request.full_url, payload))
        if request.full_url.endswith("/chat/completions"):
            result = {"choices": [{"message": {"content": next(replies)}}]}
        elif request.full_url.endswith("/api/models/local"):
            result = {"models": []}
        elif request.full_url.endswith("/load"):
            result = {"success": True}
        else:
            result = {"data": [{"id": "ollama/ornith-1.5:35b", "loaded": True}]}
        return BytesIO(json.dumps(result).encode())

    return fake


def test_empty_reply_reloads_at_64k_and_retries_once(monkeypatch):
    monkeypatch.setenv("TYLOG_LLM_URL", "https://studio.example/v1")
    monkeypatch.setenv("TYLOG_LLM_MODEL", "ollama/ornith-1.5:35b")
    monkeypatch.setattr(worker.time, "sleep", lambda seconds: None)
    calls = []
    monkeypatch.setattr(worker, "urlopen", studio_stub(iter(["", '["Привет"]']), calls))

    _, chat = worker.llm_chat({})
    assert chat([{"role": "user", "content": "hi"}]) == '["Привет"]'
    assert [url for url, _ in calls] == [
        "https://studio.example/v1/chat/completions",
        "https://studio.example/api/models/local",
        "https://studio.example/v1/load",
        "https://studio.example/v1/models",
        "https://studio.example/v1/chat/completions",
    ]
    assert calls[2][1] == {"model_path": "ollama/ornith-1.5:35b", "max_seq_length": 65536,
                           "force_cancel_active": True}
    assert calls[4][1] == calls[0][1]


def test_second_empty_reply_raises(monkeypatch):
    monkeypatch.setenv("TYLOG_LLM_URL", "https://studio.example/v1")
    monkeypatch.setenv("TYLOG_LLM_MODEL", "ollama/ornith-1.5:35b")
    monkeypatch.setattr(worker.time, "sleep", lambda seconds: None)
    calls = []
    monkeypatch.setattr(worker, "urlopen", studio_stub(iter(["", ""]), calls))

    _, chat = worker.llm_chat({})
    with pytest.raises(ValueError, match=r"ollama/ornith-1\.5:35b returned an empty reply"):
        chat([{"role": "user", "content": "hi"}])
    urls = [url for url, _ in calls]
    assert urls.count("https://studio.example/v1/load") == 1
    assert urls.count("https://studio.example/v1/chat/completions") == 2


def test_empty_llm_reply_raises_clear_error(monkeypatch):
    monkeypatch.setenv("TYLOG_LLM_URL", "https://studio.example/v1")
    monkeypatch.setenv("TYLOG_LLM_MODEL", "ollama/ornith-1.5:35b")
    monkeypatch.setattr(worker.time, "sleep", lambda seconds: None)
    monkeypatch.setattr(worker, "urlopen", studio_stub(iter(["", ""]), []))

    _, chat = worker.llm_chat({})
    with pytest.raises(ValueError) as error:
        chat([{"role": "user", "content": "hi"}])
    assert str(error.value) == "LLM ollama/ornith-1.5:35b returned an empty reply"


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


class FakeMac:
    """Stands in for audio_v2.MacSTT: every speech chunk is "Hello"; the primary pass only."""
    text = "Hello"

    def __init__(self, model, lang, *, studio_failed=False):
        self.language = lang or "en"

    def __call__(self, wav, engine):
        return self.text if engine == audio_v2.PRIMARY else None


def fake_v2_audio(monkeypatch, mac=FakeMac):
    """VAD, duration, ffmpeg cut and the Mac model replaced: one 4 s speech chunk per recording."""
    monkeypatch.setattr(audio_v2, "speech_regions", lambda audio: [(0.0, 4.0)])
    monkeypatch.setattr(audio_v2, "audio_seconds", lambda audio: 4.0)
    monkeypatch.setattr(audio_v2, "cut_chunk", lambda audio, start, end, out: out.write_bytes(b"wav"))
    monkeypatch.setattr(audio_v2, "MacSTT", mac)


@pytest.fixture
def sweep_vault(tmp_path, monkeypatch):
    settings_path = tmp_path / "_system/settings/processing.json"
    settings_path.parent.mkdir(parents=True)
    (tmp_path / "notes").mkdir()
    (tmp_path / "assets/audio").mkdir(parents=True)
    monkeypatch.setattr(worker, "transcribe", lambda *args, **kwargs: ([(0, "Hello")], "en", ["en"]))
    fake_v2_audio(monkeypatch)
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


@pytest.mark.parametrize("settings, state", [
    (None, {}), ({}, {}), ({"transcribe": False, "on_the_fly": True}, {}),
    ({"transcribe": False, "scheduled": True}, {"last_scheduled_date": "2026-10-14"}),
])
def test_sweep_closed(sweep_vault, settings, state):
    vault = sweep_vault
    add_audio_note(vault)
    if settings is not None:
        set_audio_settings(vault, **settings)
    state_now = {}
    assert worker.sweep(vault, NOW, state_now) == 0
    assert not list((vault / "_system/jobs").rglob("*.json"))
    assert state_now == state


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


def echo_translate(texts, source_lang, target, source_langs):
    return [target] * len(texts)


def test_scheduled_catch_up_once_per_local_day(sweep_vault):
    vault = sweep_vault
    set_audio_settings(vault, scheduled=True)
    first, _ = add_audio_note(vault)
    state_path = vault / "state.json"

    def run(when):
        worker.run_once(vault, now=when, state_path=state_path, translate=echo_translate)

    run(NOW.replace(hour=2, minute=59))
    assert not job_path(vault, "transcripts", first).exists()
    run(NOW)
    assert job_path(vault, "transcripts", first).exists()
    # The scheduled run stays open until a sweep finds nothing left to do: the ru and pt
    # translations of the new transcript are queued by the next sweep, then done.
    assert "last_scheduled_date" not in json.loads(state_path.read_text())
    run(NOW)
    assert "last_scheduled_date" not in json.loads(state_path.read_text())
    run(NOW)
    assert json.loads(state_path.read_text())["last_scheduled_date"] == "2026-10-14"
    second, _ = add_audio_note(vault, "second.wav")
    run(NOW)
    assert not job_path(vault, "transcripts", second).exists()
    run(NOW + timedelta(days=1))
    assert job_path(vault, "transcripts", second).exists()
    run(NOW + timedelta(days=1))
    run(NOW + timedelta(days=1))
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


def test_force_translates_with_both_flags_off(sweep_vault):
    set_audio_settings(sweep_vault, transcribe=False, translate=False, translate_to=["ru"])
    audio, _ = add_audio_note(sweep_vault, body="== Transcript\n- 00:00 Hello\n")
    write_job(sweep_vault, "transcripts", audio, lang="en", status="done")
    assert worker.sweep(sweep_vault, NOW, {}, force=True) == 2
    assert sorted(path.name for path in (sweep_vault / "_system/jobs/translations").glob("*.json")) == sorted(
        [job_path(sweep_vault, "translations", audio + "\n" + lang).name for lang in ("ru", "pt")])


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
    assert worker.sweep(vault, NOW, {}) == 1  # only the missing pt translation of "complete"
    assert [path.read_bytes() for path in (transcript, translation)] == originals
    assert job_path(vault, "translations", complete + "\npt").exists()


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
    (None, ["ru"], ["ru", "pt"]), (None, [], ["ru", "pt"]),
    (False, ["ru"], ["ru", "pt"]), (True, ["de"], ["ru", "pt", "de"]), (True, [], ["ru", "pt"]),
])
def test_translate_flag_is_ignored_and_extra_targets_follow(sweep_vault, flag, targets, expected):
    settings = {"transcribe": False, "on_the_fly": True, "translate_to": targets}
    if flag is not None:
        settings["translate"] = flag
    set_audio_settings(sweep_vault, **settings)
    audio, _ = add_audio_note(sweep_vault, body="== Transcript\n- 00:00 Hello\n")
    add_audio_note(sweep_vault, "untranscribed.wav")
    transcript_job = write_job(sweep_vault, "transcripts", audio, lang="en", status="done")
    original = transcript_job.read_bytes()
    assert worker.sweep(sweep_vault, NOW, {}) == len(expected)
    assert list((sweep_vault / "_system/jobs/transcripts").glob("*.json")) == [transcript_job]
    assert transcript_job.read_bytes() == original
    assert sorted(path.name for path in (sweep_vault / "_system/jobs/translations").glob("*.json")) == sorted(
        job_path(sweep_vault, "translations", audio + "\n" + lang).name for lang in expected)


def test_transcribe_enabled_translate_disabled(sweep_vault):
    set_audio_settings(sweep_vault, on_the_fly=True, translate=False, translate_to=["ru"])
    missing, _ = add_audio_note(sweep_vault)
    complete, _ = add_audio_note(sweep_vault, "complete.wav", body="== Transcript\n- 00:00 Hello\n")
    write_job(sweep_vault, "transcripts", complete, lang="en", status="done")
    assert worker.sweep(sweep_vault, NOW, {}) == 3  # one transcript, then ru and pt for "complete"
    assert job_path(sweep_vault, "transcripts", missing).exists()
    assert job_path(sweep_vault, "translations", complete + "\nru").exists()
    assert job_path(sweep_vault, "translations", complete + "\npt").exists()


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
    assert worker.sweep(sweep_vault, NOW, {}, force=gate == "force") == (0 if gate == "closed" else 2)


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
    worker.run_once(sweep_vault, now=NOW, state_path=state_path, translate=echo_translate)
    assert job_path(sweep_vault, "transcripts", audio).exists()
    for _ in range(2):  # translations come with the next sweep
        worker.run_once(sweep_vault, now=NOW, state_path=state_path, translate=echo_translate)
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


def test_no_extra_targets_still_translates_ru_en_pt(sweep_vault):
    set_audio_settings(sweep_vault, on_the_fly=True, translate_to=[])
    audio, _ = add_audio_note(sweep_vault, body="== Transcript\n- 00:00 Hello\n")
    write_job(sweep_vault, "transcripts", audio, status="done", lang="en")
    assert worker.sweep(sweep_vault, NOW, {}) == 2  # ru and pt; en is the source


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


def test_finished_transcript_requeues_done_translations(sweep_vault):
    """A re-run of an old recording: its finished transcript invalidates the done ru translation.
    The ru job goes back to queued with its other fields kept; the next sweep creates the missing en."""
    vault = sweep_vault
    set_audio_settings(vault, on_the_fly=True)
    audio, note = add_audio_note(vault)
    relative = note.relative_to(vault).as_posix()
    write_job(vault, "transcripts", audio, status="queued", audio=audio, note=relative, lang="pt")
    translation = write_job(vault, "translations", audio + "\nru", status="done", audio=audio, note=relative,
                            target="ru", source_lang="pt", source_langs=["pt"], error="old",
                            finished_at="2026-10-13T10:00:00+00:00")
    worker.run_once(vault, now=NOW, state_path=vault / "state.json")
    assert json.loads(job_path(vault, "transcripts", audio).read_text())["status"] == "done"
    assert json.loads(translation.read_text()) == {
        "audio": audio, "note": relative, "target": "ru", "source_lang": "pt",
        "source_langs": ["pt"], "status": "queued"}
    assert not job_path(vault, "translations", audio + "\nen").exists()
    assert worker.sweep(vault, NOW, {}) == 1  # the missing en; ru already exists
    assert json.loads(job_path(vault, "translations", audio + "\nen").read_text())["status"] == "queued"


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

    class Recording(FakeMac):
        def __init__(self, model, lang, *, studio_failed=False):
            super().__init__(model, lang)
            calls.append(model)

    fake_v2_audio(monkeypatch, mac=Recording)
    for index, (task, cli) in enumerate([
        ({"quality": "fast"}, None),
        ({"quality": "best", "model": "explicit"}, None),
        ({"model": "explicit"}, "cli"),
    ]):
        write_ai(sweep_vault, tasks={"transcribe": task})
        add_audio_note(sweep_vault, f"{index}.wav")
        worker.run_once(sweep_vault, model=cli, now=NOW)
    assert calls == ["small", "explicit", "cli"]  # MacSTT applies the small cap itself


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
        return BytesIO('{"choices": [{"message": {"content": "[\\"переведено\\"]"}}]}'.encode())

    monkeypatch.setattr(worker, "ensure_model", ensure)
    monkeypatch.setattr(worker, "urlopen", http)
    assert worker.translate(["hello"], "en", "ru", settings=worker.load_ai_settings(tmp_path)) == ["переведено"]
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
    path = write_job(tmp_path, "translations", "audio\nru", status="queued", audio="audio",
                     note="note.typ", source_lang="en", target="ru")
    (tmp_path / "note.typ").write_text("== Transcript\n- 00:00 Hello\n")
    calls = []

    def http(request, timeout):
        assert request.get_header("Authorization") == "Bearer " + secret
        calls.append(request.full_url)
        if failed and request.full_url.endswith("/chat/completions"):
            raise OSError("Backend rejected key " + secret)
        result = ({"data": [{"id": "translator"}]} if request.full_url.endswith("/models") else
                  {"choices": [{"message": {"content": '["переведено"]'}}]})
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
    worker.run_once(tmp_path, **{**kwargs, "clock": lambda: now + timedelta(seconds=239)})
    assert len(calls) == 2
    # Unchanged content within 4 min: the synced file is left alone.
    assert json.loads(heartbeat_path.read_text())["last_seen"] == now.isoformat()
    worker.run_once(tmp_path, **{**kwargs, "clock": lambda: now + timedelta(seconds=300)})
    assert len(calls) == 4
    assert json.loads(heartbeat_path.read_text())["last_seen"] == (now + timedelta(seconds=300)).isoformat()
    state = json.loads((tmp_path / ".tylog-transcribe-state.json").read_text())
    assert state["connection_probes"]["studio"]["result"]["loaded"] == ["ornith"]


def test_probe_http_contract(monkeypatch):
    def http(request, timeout):
        assert (request.full_url, request.get_method(), timeout) == ("https://studio/v1/models", "GET", 15)
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
    path = write_job(tmp_path, "translations", "audio\nru", status="queued", audio="audio",
                     note="note.typ", source_lang="en", target="ru")
    (tmp_path / "note.typ").write_text("== Transcript\n- 00:00 Hello\n")

    def ensure(base, key, prefer, request):
        assert (base, prefer) == ("https://studio/v1", "ollama/ornith-1.5:9b")
        return prefer

    monkeypatch.setattr(worker, "ensure_model", ensure)
    monkeypatch.setattr(worker, "urlopen", lambda request, timeout:
                        BytesIO('{"choices": [{"message": {"content": "[\\"переведено\\"]"}}]}'.encode()))
    worker.run_once(tmp_path, probe=lambda base, key: {"reachable": True, "loaded": []})
    job = json.loads(path.read_text())
    assert job["status"] == "done"
    assert job["llm"] == "ollama/ornith-1.5:9b"


def test_abandoned_processing_job_is_taken_again(tmp_path, monkeypatch):
    # The worker hung for 8 hours on a model download and was killed: its job
    # stayed "processing" and nothing would ever pick it up again.
    jobs = tmp_path / "_system/jobs/transcripts"
    jobs.mkdir(parents=True)
    note = tmp_path / "note.typ"
    note.write_text("= Note\n")
    now = datetime(2026, 10, 24, 20, 0, tzinfo=worker.timezone.utc)
    stale = jobs / "stale.json"
    stale.write_text(json.dumps({"status": "processing", "audio": "a.wav", "note": "note.typ", "engine": "v1",
                                 "requested_at": "2026-10-24T10:36:10+00:00"}))
    fresh = jobs / "fresh.json"
    fresh.write_text(json.dumps({"status": "processing", "audio": "b.wav", "note": "note.typ",
                                 "processing_at": "2026-10-24T19:30:00+00:00"}))
    calls = []

    def fake_transcribe(audio, model, lang):
        calls.append(audio.name)
        return [(0, "Hi")], "en", ["en"]

    monkeypatch.setattr(worker, "transcribe", fake_transcribe)
    worker.run_once(tmp_path, now=now, state_path=tmp_path / "s.json",
                    hostname=lambda: "h", probe=lambda *a: {"reachable": False, "loaded": []})
    assert calls == ["a.wav"]  # the 30-minute-old claim is left to its worker
    assert json.loads(stale.read_text())["status"] == "done"
    assert json.loads(fresh.read_text())["status"] == "processing"


def test_decode_nonempty_retries_via_ffmpeg_then_fails(monkeypatch, tmp_path):
    empty, full = SimpleNamespace(size=0), SimpleNamespace(size=5)
    calls = []

    def decode(path, sampling_rate):
        calls.append(path)
        return full if path.endswith(".wav") else empty

    monkeypatch.setattr(worker.subprocess, "run", lambda *a, **k: None)
    assert worker.decode_nonempty("a.aac", decode) is full
    assert calls[0] == "a.aac" and calls[1].endswith(".wav")
    with pytest.raises(ValueError, match="0 seconds"):
        worker.decode_nonempty("a.aac", lambda path, sampling_rate: empty)


@pytest.mark.parametrize("name", ["ai.json", "processing.json"])
def test_settings_path_prefers_whole_local_file(tmp_path, name):
    shared = tmp_path / name
    local = shared.with_suffix(".local.json")
    assert worker._settings_path_for(shared) == shared
    shared.write_text('{"shared": true, "other": 7}')
    local.write_text('{"local": true}')
    assert worker._read_json(worker._settings_path_for(shared)) == {"local": True}
    local.write_text('{bad')
    assert worker._read_json(worker._settings_path_for(shared)) == {}
    local.unlink()
    assert worker._read_json(worker._settings_path_for(shared)) == {"shared": True, "other": 7}


def test_collapse_repeats_keeps_one_copy():
    assert worker.collapse_repeats("Olá. É isso aí! É isso aí! É isso aí! É isso aí! Fim.") == "Olá. É isso aí! … Fim."
    assert worker.collapse_repeats("Sim! Sim! Não.") == "Sim! Sim! Não."


def test_translation_bad_batch_falls_back_to_lines(monkeypatch):
    monkeypatch.setenv("TYLOG_LLM_URL", "https://studio.example/v1")
    monkeypatch.setenv("TYLOG_LLM_MODEL", "translator")

    def fake(request, timeout):
        batch = json.loads(json.loads(request.data)["messages"][1]["content"])
        if len(batch) > 1 or batch == ["loop"]:
            reply = '["unterminated'
        else:
            reply = json.dumps(["ру " + batch[0]])
        return BytesIO(json.dumps({"choices": [{"message": {"content": reply}}]}).encode())

    monkeypatch.setattr(worker, "urlopen", fake)
    assert worker.translate(["a", "loop", "b"], "pt", "ru") == ["ру a", "[sem tradução]", "ру b"]


def test_gap_lines_not_sent_to_model():
    note = "= Note\n\n== Transcript\n\n- 00:00 Hello\n- 00:05 [—]\n- 00:10 World\n"
    sent = []

    def fake(texts, source_lang, target, source_langs):
        sent.append(list(texts))
        return ["Привет", "Мир"]

    updated, _ = worker.apply_translation(note, "en", "ru", fake)
    assert sent == [["Hello", "World"]]
    assert "== Translation ru\n\n- 00:00 Привет\n- 00:05 [—]\n- 00:10 Мир\n" in updated


def test_failed_line_is_marked_not_source(monkeypatch):
    monkeypatch.setenv("TYLOG_LLM_URL", "https://studio.example/v1")
    monkeypatch.setenv("TYLOG_LLM_MODEL", "translator")

    def fake(request, timeout):
        batch = json.loads(json.loads(request.data)["messages"][1]["content"])
        if "loop" in batch:
            reply = '["unterminated'
        else:
            reply = json.dumps(["ру " + text for text in batch])
        return BytesIO(json.dumps({"choices": [{"message": {"content": reply}}]}).encode())

    monkeypatch.setattr(worker, "urlopen", fake)
    note = "= Note\n\n== Transcript\n\n- 00:00 a\n- 00:05 loop\n- 00:10 b\n"
    updated, _ = worker.apply_translation(note, "pt", "ru", worker.translate)
    assert "== Translation ru\n\n- 00:00 ру a\n- 00:05 \\[sem tradução\\]\n- 00:10 ру b\n" in updated


def chat_fake(monkeypatch, reply_for):
    """LLM endpoint stand-in: reply_for(messages) gives the reply text. Returns the messages of every request."""
    sent = []

    def fake(request, timeout):
        messages = json.loads(request.data)["messages"]
        sent.append(messages)
        content = reply_for(messages)
        return BytesIO(json.dumps({"choices": [{"message": {"content": content}}]}).encode())

    monkeypatch.setenv("TYLOG_LLM_URL", "https://studio.example/v1")
    monkeypatch.setenv("TYLOG_LLM_MODEL", "translator")
    monkeypatch.setattr(worker, "urlopen", fake)
    return sent


def is_line_prompt(messages):
    return messages[0]["content"].startswith("Translate this line into")


def test_portuguese_reply_for_ru_is_retried(monkeypatch):
    def reply(messages):
        return "Привет, мир" if is_line_prompt(messages) else json.dumps(["Olá, mundo"])

    sent = chat_fake(monkeypatch, reply)
    assert worker.translate(["Hello, world"], "en", "ru") == ["Привет, мир"]
    assert len(sent) == 2
    assert sent[1] == [
        {"role": "system", "content": "Translate this line into Russian. Reply with the translation only."},
        {"role": "user", "content": "Hello, world"},
    ]


def test_retry_failure_marks_line(monkeypatch):
    def reply(messages):
        if is_line_prompt(messages):
            return "Olá de novo"  # still Portuguese when asked alone
        batch = json.loads(messages[1]["content"])
        return json.dumps(["Olá, mundo" if text == "Hello, world" else "Доброе утро всем" for text in batch])

    sent = chat_fake(monkeypatch, reply)
    assert worker.translate(["Hello, world", "Good morning all"], "en", "ru") == [
        worker.FAILED_TRANSLATION, "Доброе утро всем"]
    assert [is_line_prompt(messages) for messages in sent] == [False, True]


def test_short_identical_line_ok_for_en():
    assert worker.looks_translated("Okay then", "Okay then", "en")
    assert worker.looks_translated("Good morning everyone", "Bom dia a todos", "en")
    assert not worker.looks_translated("Good morning everyone", "Good morning everyone", "en")
    assert not worker.looks_translated("Bom dia a todos", "Bom dia a todos", "pt")
    assert not worker.looks_translated("Hello world", "Olá mundo", "ru")
    assert worker.looks_translated("Hello world", "Привет мир", "ru")
    assert not worker.looks_translated("Hello world", "  ", "en")


def test_ru_needs_one_cyrillic_letter_per_three_words():
    nine = "one two three four five six seven eight nine"
    assert worker.looks_translated(nine, "Раз", "ru")
    assert not worker.looks_translated(nine, "Ра", "ru")
    assert worker.looks_translated("Hi", "Ок", "ru")
    assert worker.looks_translated("123 !!", "Ок", "ru")


def test_translation_line_count_equals_transcript():
    note = ("= Note\n\n== Transcript\n\n- 00:00 Hello\n- 00:05 [—]\n"
            "- 00:10 (?) Maybe\n- 00:20 Bye\n")

    def fake(texts, source_lang, target, source_langs):
        assert texts == ["Hello", "Maybe", "Bye"]
        return ["Привет", "Может быть", "Пока"]

    updated, _ = worker.apply_translation(note, "en", "ru", fake)
    body = updated.split("== Translation ru\n", 1)[1].splitlines()
    assert [line for line in body if line.startswith("- ")] == [
        "- 00:00 Привет", "- 00:05 [—]", "- 00:10 (?) Может быть", "- 00:20 Пока"]


def test_user_edited_translation_line_kept():
    note = "= Note\n\n== Transcript\n\n- 00:00 Hello\n- 00:05 World\n"
    first, state = worker.apply_translation(note, "en", "ru", lambda texts, *_: ["Привет", "Мир"])
    edited = first.replace("- 00:05 Мир", "- 00:05 Земля")
    second, _ = worker.apply_translation(edited, "en", "ru", lambda texts, *_: ["Здравствуй", "Свет"],
                                         previous=state)
    assert "- 00:05 Земля\n" in second and "Свет" not in second
    assert "- 00:00 Здравствуй\n" in second


def test_translation_keeps_edit_made_during_translation(tmp_path):
    write_job(tmp_path, "translations", "audio.wav\nru", status="queued", audio="audio.wav",
              note="note.typ", source_lang="en", target="ru")
    note = tmp_path / "note.typ"
    note.write_text("= Note\n\n== Transcript\n\n- 00:00 Hello\n\n== Comments\nKeep me\n")

    def editing(texts, source_lang, target, source_langs):
        note.write_text(note.read_text().replace("Keep me\n", "Keep me\nAnd this one too\n"))  # the user, mid-call
        return ["Привет"]

    worker.run_once(tmp_path, translate=editing)
    assert json.loads(job_path(tmp_path, "translations", "audio.wav\nru").read_text())["status"] == "done"
    assert note.read_text() == (
        "= Note\n\n== Transcript\n\n- 00:00 Hello\n\n== Comments\nKeep me\nAnd this one too\n"
        "\n== Translation ru\n\n- 00:00 Привет\n")


def test_deadline_interrupts_a_blocking_call():
    with pytest.raises(TimeoutError):
        with worker.deadline(0.2):
            time.sleep(5)


def test_deadline_restores_handler_and_clears_timer():
    previous = signal.getsignal(signal.SIGALRM)
    with worker.deadline(5):
        pass
    assert signal.getsignal(signal.SIGALRM) is previous
    assert signal.getitimer(signal.ITIMER_REAL) == (0.0, 0.0)


def test_studio_post_that_hangs_is_cut_by_deadline(tmp_path, monkeypatch):
    audio = tmp_path / "audio.wav"
    worker.subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                           "anullsrc=r=8000:cl=stereo", "-t", "5", str(audio)], check=True)
    monkeypatch.setattr(worker, "STUDIO_DEADLINE", 0.3)

    def hang(request, timeout):
        time.sleep(10)

    started = time.monotonic()
    with pytest.raises(TimeoutError):
        worker.transcribe_studio(audio, "https://studio/v1", "secret", lang="pt", post=hang)
    assert time.monotonic() - started < 5


def test_mac_fallback_refused_when_memory_low(monkeypatch):
    assert worker.mac_fallback_allowed(free_bytes=2 * 1024**3) is False
    assert worker.mac_fallback_allowed(free_bytes=4 * 1024**3) is True
    assert worker.mac_fallback_allowed(free_bytes=6 * 1024**3) is True
    monkeypatch.setattr(worker, "_free_memory_bytes", lambda: None)
    assert worker.mac_fallback_allowed() is False


def test_vm_stat_free_memory_counts_reclaimable_pages(monkeypatch):
    output = ("Mach Virtual Memory Statistics: (page size of 16384 bytes)\n"
              "Pages free:                 100.\nPages active: 999.\n"
              "Pages inactive:             200.\nPages speculative: 50.\n")
    monkeypatch.setattr(worker.subprocess, "run", lambda *a, **k: SimpleNamespace(stdout=output))
    assert real_free_memory_bytes() == 350 * 16384

    def unavailable(*args, **kwargs):
        raise OSError("vm_stat missing")

    monkeypatch.setattr(worker.subprocess, "run", unavailable)
    assert real_free_memory_bytes() is None


@pytest.mark.parametrize("model, cap, expected", [
    ("large-v3", "small", "small"), ("unsloth/whisper-large-v3-turbo", "small", "small"),
    ("tiny", "small", "tiny"), ("small", "small", "small"), ("custom-model", "small", "small"),
])
def test_min_model_never_exceeds_cap(model, cap, expected):
    assert worker.min_model(model, cap) == expected


def test_fallback_refused_when_memory_low(tmp_path, monkeypatch):
    write_ai(tmp_path, connections=[{"id": "studio", "url": "https://studio/v1"}])
    monkeypatch.setenv("TYLOG_KEY_STUDIO", "secret")
    path = write_job(tmp_path, "transcripts", "audio", status="queued", audio="audio.wav",
                     note="note.typ", engine="v1")
    note = tmp_path / "note.typ"
    note.write_text("= Note\n")

    def studio(audio, base, key, lang):
        raise OSError("Studio down")

    monkeypatch.setattr(worker, "transcribe_studio", studio)
    monkeypatch.setattr(worker, "transcribe", lambda *args, **kwargs: pytest.fail("Local transcription ran"))
    monkeypatch.setattr(worker, "_free_memory_bytes", lambda: 2 * 1024**3)
    worker.run_once(tmp_path, probe=lambda *args: {"reachable": False, "loaded": []})
    job = json.loads(path.read_text())
    assert job["status"] == "failed"
    assert job["error"] == "Studio unreachable; Mac fallback refused (low memory)"
    assert job["studio_error"] == "Studio down"
    assert note.read_text() == "= Note\n"


def test_local_fallback_caps_model_at_small(tmp_path, monkeypatch):
    write_ai(tmp_path, connections=[{"id": "studio", "url": "https://studio/v1"}],
             tasks={"transcribe": {"model": "large-v3"}})
    monkeypatch.setenv("TYLOG_KEY_STUDIO", "secret")
    path = write_job(tmp_path, "transcripts", "audio", status="queued", audio="audio.wav",
                     note="note.typ", engine="v1")
    note = tmp_path / "note.typ"
    note.write_text("= Note\n")
    calls, nice = [], []

    def studio(audio, base, key, lang):
        raise OSError("Studio down")

    def local(audio, model, lang, **options):
        calls.append(model)
        return [(0, "Fallback")], "pt", ["pt"]

    monkeypatch.setattr(worker, "transcribe_studio", studio)
    monkeypatch.setattr(worker, "transcribe", local)
    monkeypatch.setattr(worker, "_free_memory_bytes", lambda: 16 * 1024**3)
    monkeypatch.setattr(worker.os, "nice", nice.append)
    worker.lower_priority.cache_clear()
    worker.run_once(tmp_path, probe=lambda *args: {"reachable": False, "loaded": []})
    job = json.loads(path.read_text())
    assert calls == ["small"]
    assert nice == [19]
    assert (job["status"], job["engine"]) == ("done", "local")


def test_local_transcription_without_studio_is_capped_and_niced(tmp_path, monkeypatch):
    write_ai(tmp_path, tasks={"transcribe": {"model": "large-v3"}})
    path = write_job(tmp_path, "transcripts", "audio", status="queued", audio="audio.wav",
                     note="note.typ", engine="v1")
    (tmp_path / "note.typ").write_text("= Note\n")
    calls, nice = [], []

    def local(audio, model, lang, **options):
        calls.append(model)
        return [(0, "Hello")], "en", ["en"]

    monkeypatch.setattr(worker, "transcribe", local)
    monkeypatch.setattr(worker.os, "nice", nice.append)
    worker.lower_priority.cache_clear()
    worker.run_once(tmp_path)
    assert calls == ["small"]
    assert nice == [19]
    assert json.loads(path.read_text())["status"] == "done"


def test_local_transcription_without_studio_refused_when_memory_low(tmp_path, monkeypatch):
    write_ai(tmp_path, tasks={"transcribe": {"model": "large-v3"}})
    path = write_job(tmp_path, "transcripts", "audio", status="queued", audio="audio.wav",
                     note="note.typ", engine="v1")
    note = tmp_path / "note.typ"
    note.write_text("= Note\n")
    monkeypatch.setattr(worker, "_free_memory_bytes", lambda: 2 * 1024**3)
    monkeypatch.setattr(worker, "transcribe", lambda *args, **kwargs: pytest.fail("Local transcription ran"))
    worker.run_once(tmp_path)
    job = json.loads(path.read_text())
    assert job["status"] == "failed"
    assert job["error"] == "Mac fallback refused (low memory)"
    assert note.read_text() == "= Note\n"


# Task 7: v2 transcript jobs. Studio is replaced by FakeStudio; no test reaches the network or loads a model.

LOOP = "É isso aí! " * 40
PRIMARY, SECONDARY = audio_v2.PRIMARY, audio_v2.SECONDARY


class FakeStudio:
    """In-memory Studio STT on the routes tool/asr_bakeoff.py uses. Text depends on the chunk start only."""

    def __init__(self, texts=None, fail_on=()):
        self.texts = texts or {}
        self.fail_on = set(fail_on)  # 1-based transcribe attempts that raise
        self.calls = []              # (method, route) in order, status polls included
        self.bodies = []             # transcribe request bodies
        self.uploads = []            # (engine, chunk start) per transcribe attempt
        self.loaded = {}             # engine -> model

    def __call__(self, root, key, method, path, body=None, *, seconds):
        route, _, query = path.partition("?")
        self.calls.append((method, route))
        if route == "/api/inference/audio/stt/status":
            return {engine: {"downloaded_models": [model], "loaded_model": self.loaded.get(engine),
                             "loading": False}
                    for engine, model in (("transformers", "large-v3-turbo"), ("mtmd", "qwen3-asr-1.7b"))}
        if route == "/api/inference/audio/stt/load":
            assert body["device"] == "gpu"
            self.loaded[body["engine"]] = body["model"]
            return {}
        if route == "/api/inference/audio/stt/unload":
            params = parse_qs(query)
            assert params["wait"] == ["true"]
            self.loaded.pop(params["engine"][0], None)
            return {}
        if route == "/api/inference/audio/transcribe":
            assert body["device"] == "gpu"
            assert self.loaded.get(body["engine"]) == body["model"], "transcribe on a model that is not resident"
            self.bodies.append(body)
            start = float(base64.b64decode(body["audio"]))
            self.uploads.append((body["engine"], start))
            if len(self.uploads) in self.fail_on:
                raise OSError("Studio dropped")
            return {"text": self.texts.get(start, "Olá."), "language": "pt"}
        raise AssertionError(f"unexpected {method} {route}")


def v2_media(tmp_path, monkeypatch, regions, seconds):
    """A recording with the given VAD regions. The ffmpeg cut writes its start time, so a fake
    engine can tell which chunk it was sent."""
    (tmp_path / "audio.wav").write_bytes(b"recording")
    monkeypatch.setattr(audio_v2, "speech_regions", lambda audio: list(regions))
    monkeypatch.setattr(audio_v2, "audio_seconds", lambda audio: seconds)
    monkeypatch.setattr(audio_v2, "cut_chunk",
                        lambda audio, start, end, out: out.write_bytes(str(float(start)).encode()))


def v2_job(tmp_path, **fields):
    if not (tmp_path / "note.typ").exists():
        (tmp_path / "note.typ").write_text("= Note\n")
    return write_job(tmp_path, "transcripts", "audio.wav",
                     **{"status": "queued", "audio": "audio.wav", "note": "note.typ", **fields})


def scripted_mac(monkeypatch, texts=None):
    """audio_v2.MacSTT stand-in: primary text by chunk start (default "Olá."), nothing for the secondary."""
    class Scripted:
        def __init__(self, model, lang, *, studio_failed=False):
            self.language = lang or "pt"

        def __call__(self, wav, engine):
            if engine != PRIMARY:
                return None
            return (texts or {}).get(float(wav.read_bytes()), "Olá.")

    monkeypatch.setattr(audio_v2, "MacSTT", Scripted)


def studio_connection(tmp_path, monkeypatch):
    write_ai(tmp_path, connections=[{"id": "studio", "url": "http://studio.test:8888/v1"}])
    monkeypatch.setenv("TYLOG_KEY_STUDIO", "secret")


def quiet_probe(*args):
    return {"reachable": True, "loaded": []}


def read_job(tmp_path, key="audio.wav"):
    return json.loads(job_path(tmp_path, "transcripts", key).read_text())


def test_v2_marks_music_chunks_and_keeps_speech(tmp_path, monkeypatch):
    v2_media(tmp_path, monkeypatch, [(0, 10), (30, 40), (60, 70)], seconds=80)
    texts = {0.0: "Olá tudo bem com você?", 30.0: "Nasci no seio de uma família.", 60.0: LOOP}

    def stt(wav, engine):
        return texts.get(float(wav.read_bytes()), "") if engine == PRIMARY else ""

    lines = audio_v2.transcribe_v2(tmp_path / "audio.wav", audio_v2.sidecar_path(tmp_path, "audio.wav"),
                                   stt, engines=(PRIMARY,))
    assert [(line["start"], line["kind"], line["text"]) for line in lines] == [
        (0.0, "speech", "Olá tudo bem com você?"), (10.0, "gap", ""),
        (30.0, "speech", "Nasci no seio de uma família."), (40.0, "gap", ""),
        (60.0, "gap", ""), (70.0, "gap", ""),
    ]


def test_v2_resumes_from_sidecar_without_resending(tmp_path, monkeypatch):
    monkeypatch.setattr(audio_v2, "speech_regions", lambda audio: pytest.fail("VAD ran again"))
    sidecar = audio_v2.sidecar_path(tmp_path, "audio.wav")
    chunks = [{"start": s, "end": s + 4, "kind": "speech", "asr": f"Texto {s}."} for s in (0, 10, 20)]
    chunks += [{"start": s, "end": s + 4, "kind": "speech"} for s in (30, 40)]
    audio_v2.save_sidecar(sidecar, {"chunks": chunks, "lines": [], "stages": {}})
    monkeypatch.setattr(audio_v2, "cut_chunk",
                        lambda audio, start, end, out: out.write_bytes(str(float(start)).encode()))
    sent = []

    def stt(wav, engine):
        sent.append(float(wav.read_bytes()))
        return "Novo."

    audio_v2.transcribe_v2(tmp_path / "audio.wav", sidecar, stt, engines=(PRIMARY,))
    assert sent == [30.0, 40.0]


def test_v2_all_music_recording_is_done_not_failed(tmp_path, monkeypatch):
    v2_media(tmp_path, monkeypatch, [(0, 10), (20, 30)], seconds=30)
    scripted_mac(monkeypatch, {0.0: LOOP, 20.0: LOOP})
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    job = read_job(tmp_path)
    assert (job["status"], job["lang"]) == ("done", "pt")
    assert "error" not in job
    assert (tmp_path / "note.typ").read_text() == (
        "= Note\n\n== Transcript\n\n- 00:00 [—]\n- 00:10 [—]\n- 00:20 [—]\n")


def test_no_speech_at_all_is_one_gap_line(tmp_path, monkeypatch):
    v2_media(tmp_path, monkeypatch, [], seconds=300)
    scripted_mac(monkeypatch, {})
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    assert read_job(tmp_path)["status"] == "done"
    assert (tmp_path / "note.typ").read_text() == "= Note\n\n== Transcript\n\n- 00:00 [—]\n"


def test_v2_secondary_engine_text_stored_as_asr_alt(tmp_path, monkeypatch):
    v2_media(tmp_path, monkeypatch, [(0, 4), (10, 14)], seconds=20)
    order = []

    def stt(wav, engine):
        order.append(engine)
        return "Olá." if engine == PRIMARY else "Ola!"

    sidecar = audio_v2.sidecar_path(tmp_path, "audio.wav")
    lines = audio_v2.transcribe_v2(tmp_path / "audio.wav", sidecar, stt)
    assert order == [PRIMARY, PRIMARY, SECONDARY, SECONDARY]  # one pass per engine, not interleaved
    speech = [chunk for chunk in audio_v2.load_sidecar(sidecar)["chunks"] if chunk["kind"] == "speech"]
    assert [(chunk["asr"], chunk["asr_alt"]) for chunk in speech] == [("Olá.", "Ola!"), ("Olá.", "Ola!")]
    assert [line["text"] for line in lines if line["kind"] == "speech"] == ["Olá.", "Olá."]


def test_note_reread_before_write_keeps_midrun_edit(tmp_path, monkeypatch):
    v2_media(tmp_path, monkeypatch, [(0, 4)], seconds=10)
    scripted_mac(monkeypatch, {0.0: "Olá tudo bem."})
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    note = tmp_path / "note.typ"
    assert "- 00:00 Olá tudo bem.\n" in note.read_text()

    # Re-process: the ASR runs again, and the user corrects the line while it does.
    sidecar = audio_v2.sidecar_path(tmp_path, "audio.wav")
    data = audio_v2.load_sidecar(sidecar)
    for chunk in data["chunks"]:
        chunk.pop("asr", None)
    audio_v2.save_sidecar(sidecar, data)

    class Editing:
        def __init__(self, model, lang, *, studio_failed=False):
            self.language = "pt"

        def __call__(self, wav, engine):
            if engine == PRIMARY:
                note.write_text(note.read_text().replace("Olá tudo bem.", "Olá, tudo bem com você."))
                return "Olá tudo bem."
            return None

    monkeypatch.setattr(audio_v2, "MacSTT", Editing)
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    assert read_job(tmp_path)["status"] == "done"
    assert note.read_text() == "= Note\n\n== Transcript\n\n- 00:00 Olá, tudo bem com você.\n- 00:04 [—]\n"


def test_rerun_replaces_machine_line_that_became_a_gap(tmp_path, monkeypatch):
    v2_media(tmp_path, monkeypatch, [(0, 4), (30, 34)], seconds=34)
    scripted_mac(monkeypatch, {0.0: "Olá tudo bem.", 30.0: "Até amanhã."})
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    assert "- 00:30 Até amanhã.\n" in (tmp_path / "note.typ").read_text()

    sidecar = audio_v2.sidecar_path(tmp_path, "audio.wav")
    data = audio_v2.load_sidecar(sidecar)
    for chunk in data["chunks"]:
        chunk.pop("asr", None)
    audio_v2.save_sidecar(sidecar, data)
    scripted_mac(monkeypatch, {0.0: "Olá tudo bem.", 30.0: LOOP})
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    assert (tmp_path / "note.typ").read_text() == (
        "= Note\n\n== Transcript\n\n- 00:00 Olá tudo bem.\n- 00:04 [—]\n- 00:30 [—]\n")


def test_legacy_note_backed_up_then_replaced(tmp_path, monkeypatch):
    v2_media(tmp_path, monkeypatch, [(0, 4)], seconds=10)
    scripted_mac(monkeypatch, {0.0: "Olá tudo bem."})
    legacy = "= Note\n\n== Transcript\n\n- 00:00 Old thirty second blob\n- 00:30 Old two\n\n== Comments\nKeep me\n"
    (tmp_path / "note.typ").write_text(legacy)
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    sidecar = audio_v2.sidecar_path(tmp_path, "audio.wav")
    assert sidecar.with_name(sidecar.stem + ".v1.typ").read_text() == legacy
    assert (tmp_path / "note.typ").read_text() == (
        "= Note\n\n== Transcript\n\n- 00:00 Olá tudo bem.\n- 00:04 [—]\n\n== Comments\nKeep me\n")


def test_legacy_backup_kept_when_v1_translation_already_wrote_a_sidecar(tmp_path, monkeypatch):
    v2_media(tmp_path, monkeypatch, [(0, 4)], seconds=10)
    scripted_mac(monkeypatch, {0.0: "Olá tudo bem."})
    legacy = "= Note\n\n== Transcript\n\n- 00:00 Old blob\n"
    (tmp_path / "note.typ").write_text(legacy)
    audio_v2.save_sidecar(audio_v2.sidecar_path(tmp_path, "audio.wav"),
                          {"lines": [], "stages": {}, "translations": {"ru": []}})
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    sidecar = audio_v2.sidecar_path(tmp_path, "audio.wav")
    assert sidecar.with_name(sidecar.stem + ".v1.typ").read_text() == legacy
    assert read_job(tmp_path)["status"] == "done"


def test_legacy_translation_lines_cleared_after_backup(tmp_path, monkeypatch):
    v2_media(tmp_path, monkeypatch, [(0, 4)], seconds=10)
    scripted_mac(monkeypatch, {0.0: "Olá tudo bem."})
    legacy = ("= Note\n\n== Transcript\n\n- 00:00 Old blob\n\n"
              "== Translation ru\n\n- 00:00 Старый блоб\n\n== Comments\nKeep me\n")
    (tmp_path / "note.typ").write_text(legacy)
    # v1 kept the translation's lines in the sidecar too; a later translation must not merge them back.
    audio_v2.save_sidecar(audio_v2.sidecar_path(tmp_path, "audio.wav"), {
        "lines": [], "stages": {}, "translations": {"ru": [
            {"start": 0.0, "kind": "speech", "text": "Старый блоб", "status": "ok",
             "rendered": {"Translation ru": "- 00:00 Старый блоб"}}]}})
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    sidecar = audio_v2.sidecar_path(tmp_path, "audio.wav")
    assert sidecar.with_name(sidecar.stem + ".v1.typ").read_text() == legacy
    assert (tmp_path / "note.typ").read_text() == (
        "= Note\n\n== Transcript\n\n- 00:00 Olá tudo bem.\n- 00:04 [—]\n\n== Comments\nKeep me\n")

    write_job(tmp_path, "translations", "audio.wav\nru", status="queued", audio="audio.wav",
              note="note.typ", source_lang="pt", target="ru")
    worker.run_once(tmp_path, translate=lambda texts, *_: ["Новый перевод."] * len(texts))
    assert json.loads(job_path(tmp_path, "translations", "audio.wav\nru").read_text())["status"] == "done"
    assert (tmp_path / "note.typ").read_text() == (
        "= Note\n\n== Transcript\n\n- 00:00 Olá tudo bem.\n- 00:04 [—]\n\n== Comments\nKeep me\n"
        "\n== Translation ru\n\n- 00:00 Новый перевод.\n- 00:04 [—]\n")


def test_studio_run_uses_passes_and_unloads_after_each(tmp_path, monkeypatch):
    studio_connection(tmp_path, monkeypatch)
    v2_media(tmp_path, monkeypatch, [(0, 4), (10, 14)], seconds=20)
    v2_job(tmp_path)  # no language: Studio's detection becomes the job language
    studio = FakeStudio({0.0: "Olá tudo bem.", 10.0: "Até amanhã."})
    monkeypatch.setattr(audio_v2, "_studio_request", studio)
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    job = read_job(tmp_path)
    assert (job["status"], job["engine"], job["lang"], job["langs"]) == ("done", "studio", "pt", ["pt"])
    assert "studio_error" not in job
    assert studio.uploads == [("transformers", 0.0), ("transformers", 10.0),
                              ("mtmd", 0.0), ("mtmd", 10.0)]
    assert studio.loaded == {}
    assert (tmp_path / "note.typ").read_text() == (
        "= Note\n\n== Transcript\n\n- 00:00 Olá tudo bem.\n- 00:04 [—]\n- 00:10 Até amanhã.\n- 00:14 [—]\n")


def test_studio_request_shape(tmp_path, monkeypatch):
    studio = FakeStudio({0.0: "Olá."})
    monkeypatch.setattr(audio_v2, "_studio_request", studio)
    wav = tmp_path / "chunk.wav"
    wav.write_bytes(b"0.0")
    stt = audio_v2.StudioSTT("http://desktop-vdsrh2e:8888/", "secret", "pt")
    assert stt(wav, PRIMARY) == "Olá."
    stt(wav, SECONDARY)
    stt.close()
    status, load = ("GET", "/api/inference/audio/stt/status"), ("POST", "/api/inference/audio/stt/load")
    transcribe, unload = ("POST", "/api/inference/audio/transcribe"), ("POST", "/api/inference/audio/stt/unload")
    assert studio.calls == [
        status, load, status, transcribe,  # downloaded check, load, poll until resident, transcribe
        unload,                            # switching to the secondary unloads the primary
        status, load, status, transcribe,
        unload,                            # close() after the call
    ]
    assert studio.bodies[0] == {"audio": base64.b64encode(b"0.0").decode("ascii"), "engine": "transformers",
                                "model": "large-v3-turbo", "language": "pt", "device": "gpu"}
    assert studio.bodies[1]["engine"] == "mtmd" and studio.bodies[1]["model"] == "qwen3-asr-1.7b"


def test_studio_failure_keeps_sidecar_and_next_run_resumes(tmp_path, monkeypatch):
    studio_connection(tmp_path, monkeypatch)
    v2_media(tmp_path, monkeypatch, [(0, 4), (10, 14), (20, 24)], seconds=30)
    v2_job(tmp_path, lang="pt")
    studio = FakeStudio({0.0: "Um.", 10.0: "Dois.", 20.0: "Três."}, fail_on={2})
    monkeypatch.setattr(audio_v2, "_studio_request", studio)
    monkeypatch.setattr(worker, "_free_memory_bytes", lambda: 2 * 1024**3)
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    job = read_job(tmp_path)
    assert job["status"] == "failed"
    assert job["error"] == "Studio unreachable; Mac fallback refused (low memory)"
    assert job["studio_error"] == "Studio dropped"
    assert (tmp_path / "note.typ").read_text() == "= Note\n"
    saved = [chunk.get("asr") for chunk in audio_v2.load_sidecar(
        audio_v2.sidecar_path(tmp_path, "audio.wav"))["chunks"] if chunk["kind"] == "speech"]
    assert saved == ["Um.", None, None]
    assert studio.loaded == {}  # unloaded even though the pass failed

    studio.fail_on = set()
    studio.uploads.clear()
    monkeypatch.setattr(worker, "_free_memory_bytes", lambda: 16 * 1024**3)
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    job = read_job(tmp_path)
    assert (job["status"], job["engine"]) == ("done", "studio")
    assert "studio_error" not in job
    assert [start for engine, start in studio.uploads if engine == "transformers"] == [10.0, 20.0]
    assert (tmp_path / "note.typ").read_text() == (
        "= Note\n\n== Transcript\n\n- 00:00 Um.\n- 00:04 [—]\n- 00:10 Dois.\n- 00:14 [—]\n"
        "- 00:20 Três.\n- 00:24 [—]\n")


def test_studio_failure_falls_back_to_mac_when_memory_allows(tmp_path, monkeypatch):
    studio_connection(tmp_path, monkeypatch)
    v2_media(tmp_path, monkeypatch, [(0, 4), (10, 14), (20, 24)], seconds=30)
    scripted_mac(monkeypatch, {10.0: "Mac dois.", 20.0: "Mac três."})
    v2_job(tmp_path, lang="pt")
    studio = FakeStudio({0.0: "Um."}, fail_on={2})
    monkeypatch.setattr(audio_v2, "_studio_request", studio)
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    job = read_job(tmp_path)
    assert (job["status"], job["engine"], job["studio_error"]) == ("done", "local", "Studio dropped")
    assert (tmp_path / "note.typ").read_text() == (
        "= Note\n\n== Transcript\n\n- 00:00 Um.\n- 00:04 [—]\n- 00:10 Mac dois.\n- 00:14 [—]\n"
        "- 00:20 Mac três.\n- 00:24 [—]\n")


def test_studio_call_is_cut_by_deadline(monkeypatch):
    def hang(request, timeout):
        time.sleep(10)

    monkeypatch.setattr(audio_v2, "urlopen", hang)
    started = time.monotonic()
    with pytest.raises(TimeoutError):
        audio_v2._studio_request("http://studio.test", "secret", "GET", "/p", seconds=0.3)
    assert time.monotonic() - started < 5


def test_mac_fallback_refused_when_memory_low_and_never_loads(tmp_path, monkeypatch):
    monkeypatch.setitem(sys.modules, "faster_whisper", SimpleNamespace(
        WhisperModel=lambda *args, **options: pytest.fail("model loaded under low memory")))
    monkeypatch.setattr(worker, "_free_memory_bytes", lambda: 2 * 1024**3)
    mac = audio_v2.MacSTT("large-v3", "pt", studio_failed=True)
    with pytest.raises(RuntimeError, match=r"^Studio unreachable; Mac fallback refused \(low memory\)$"):
        mac(tmp_path / "chunk.wav", PRIMARY)
    assert mac(tmp_path / "chunk.wav", SECONDARY) is None


def test_mac_fallback_loads_small_once_for_all_chunks(tmp_path, monkeypatch):
    loads = []

    class Model:
        def __init__(self, name, **options):
            loads.append((name, options))

        def transcribe(self, path, language=None):
            return iter([SimpleNamespace(text=" Olá ")]), SimpleNamespace(language="pt")

    monkeypatch.setitem(sys.modules, "faster_whisper", SimpleNamespace(WhisperModel=Model))
    mac = audio_v2.MacSTT("large-v3", None)
    assert [mac(tmp_path / "chunk.wav", PRIMARY) for _ in range(3)] == ["Olá"] * 3
    assert loads == [("small", {"local_files_only": True, "device": "cpu", "compute_type": "int8"})]
    assert mac.language == "pt"


def test_three_languages_always_enqueued():
    assert worker.translation_targets(["pt"], ["ru"]) == ["ru", "en"]
    assert worker.translation_targets(["ru"], []) == ["en", "pt"]
    assert worker.translation_targets(["es"], ["de"]) == ["ru", "en", "pt", "de"]
    assert worker.translation_targets(["pt", "ru"], []) == ["ru", "en", "pt"]
    assert worker.translation_targets(["en"], ["en", "de", "de"]) == ["ru", "pt", "de"]


CONTEXT_JSON = {
    "summary": "Resumo da peça.",
    "scenes": [{"line": 1, "title": "Monólogo"}],
    "glossary": [{"heard": "Medeia", "spelling": "Medeia", "ru": "Медея"}],
    "references": [{"line": 2, "term": "Baubo", "explanation": "Figura do mito de Deméter."}],
}


def is_context_prompt(messages):
    return "Transcript:\n" in messages[1]["content"]


def context_job(tmp_path, monkeypatch, reply=None):
    """A v2 transcript job with two speech lines, a user Context section, and an LLM that answers
    context prompts with CONTEXT_JSON (or `reply`, a function of the messages)."""
    v2_media(tmp_path, monkeypatch, [(0, 4), (10, 14)], seconds=20)
    scripted_mac(monkeypatch, {0.0: "Olá tudo bem.", 10.0: "Baubo fazia rir."})
    (tmp_path / "note.typ").write_text("= Note\n\n== Context\n\nPeça: Medeia.\n")
    v2_job(tmp_path, lang="pt")
    return chat_fake(monkeypatch, lambda messages: json.dumps(CONTEXT_JSON) if reply is None else reply(messages))


def unchanged_translate(texts, source_lang, target, source_langs):
    """Translate stand-in that returns the texts as they are, so the sections keep the transcript's language."""
    return list(texts)


def marked_translate(texts, source_lang, target, source_langs):
    """Translate stand-in: each text gets its target as a marker, so a rendered line shows it was translated."""
    return [f"{target}: {text}" for text in texts]


def test_context_sections_written(tmp_path, monkeypatch):
    sent = context_job(tmp_path, monkeypatch)
    worker.run_once(tmp_path, translate=unchanged_translate, state_path=tmp_path / "state.json", probe=quiet_probe)
    job = read_job(tmp_path)
    assert (job["status"], job["lang"]) == ("done", "pt")
    assert len(sent) == 1
    assert "Peça: Medeia." in sent[0][1]["content"]
    assert "[1] Olá tudo bem.\n[2] Baubo fazia rir." in sent[0][1]["content"]
    assert (tmp_path / "note.typ").read_text() == (
        "= Note\n\n== Context\n\nPeça: Medeia.\n\n"
        "== Summary\n\n- 00:00 Resumo da peça.\n\n"
        "== Scenes\n\n- 00:00 Monólogo\n\n"
        "== References\n\n- 00:10 Baubo -- Figura do mito de Deméter. (AI)\n\n"
        "== Transcript\n\n- 00:00 Olá tudo bem.\n- 00:04 [—]\n- 00:10 Baubo fazia rir.\n- 00:14 [—]\n"
    )
    sidecar = audio_v2.load_sidecar(audio_v2.sidecar_path(tmp_path, "audio.wav"))
    assert sidecar["context"]["summary"] == "Resumo da peça."
    assert sidecar["stages"]["transcript"] == "done"


def test_context_section_never_written(tmp_path, monkeypatch):
    sent = context_job(tmp_path, monkeypatch)
    worker.run_once(tmp_path, translate=unchanged_translate, state_path=tmp_path / "state.json", probe=quiet_probe)
    note = tmp_path / "note.typ"
    note.write_text(note.read_text().replace("Peça: Medeia.", "Peça: Medeia. Eurípides, 431 a.C."))

    # Re-process: the ASR chunks are kept, the context pass runs again with the edited Context.
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, translate=unchanged_translate, state_path=tmp_path / "state.json", probe=quiet_probe)
    assert read_job(tmp_path)["status"] == "done"
    assert "Eurípides, 431 a.C." in sent[-1][1]["content"]
    text = note.read_text()
    assert audio_v2.section_text(text, "Context") == "Peça: Medeia. Eurípides, 431 a.C."
    assert text.count("== Summary") == 1 and text.count("- 00:00 Monólogo") == 1


def test_bad_json_leaves_note_unchanged(tmp_path, monkeypatch):
    context_job(tmp_path, monkeypatch, reply=lambda messages: "Desculpe, não consigo.")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    job = read_job(tmp_path)
    assert job["status"] == "failed"
    assert "Context reply" in job["error"]
    assert (tmp_path / "note.typ").read_text() == (
        "= Note\n\n== Context\n\nPeça: Medeia.\n\n"
        "== Transcript\n\n- 00:00 Olá tudo bem.\n- 00:04 [—]\n- 00:10 Baubo fazia rir.\n- 00:14 [—]\n"
    )


def test_no_llm_endpoint_skips_context(tmp_path, monkeypatch):
    v2_media(tmp_path, monkeypatch, [(0, 4)], seconds=10)
    scripted_mac(monkeypatch, {0.0: "Olá tudo bem."})
    (tmp_path / "note.typ").write_text("= Note\n")
    v2_job(tmp_path, lang="pt")
    worker.run_once(tmp_path, state_path=tmp_path / "state.json", probe=quiet_probe)
    assert read_job(tmp_path)["status"] == "done"
    assert "== Summary" not in (tmp_path / "note.typ").read_text()


def test_context_request_uses_translate_endpoint_with_thinking_off(tmp_path, monkeypatch):
    sent = []

    def fake(request, timeout):
        sent.append((request.full_url, json.loads(request.data)))
        return BytesIO(json.dumps({"choices": [{"message": {"content": json.dumps(CONTEXT_JSON)}}]}).encode())

    context_job(tmp_path, monkeypatch)
    monkeypatch.setattr(worker, "urlopen", fake)
    worker.run_once(tmp_path, translate=unchanged_translate, state_path=tmp_path / "state.json", probe=quiet_probe)
    url, payload = sent[0]
    assert url == "https://studio.example/v1/chat/completions"
    assert payload["model"] == "translator"
    assert payload["chat_template_kwargs"] == {"enable_thinking": False}
    assert payload["temperature"] == 0
    assert payload["max_tokens"] == worker.CONTEXT_MAX_TOKENS


@pytest.mark.parametrize("lang, text, target", [("pt", "Olá tudo bem.", "ru"),
                                                ("ru", "Привет, как дела.", "en")])
def test_context_sections_rendered_in_target_language(tmp_path, monkeypatch, lang, text, target):
    # The first translation target other than the recording's language: ru for pt, en for ru.
    v2_media(tmp_path, monkeypatch, [(0, 4)], seconds=10)
    scripted_mac(monkeypatch, {0.0: text})
    (tmp_path / "note.typ").write_text("= Note\n")
    v2_job(tmp_path, lang=lang)
    sent = chat_fake(monkeypatch, lambda messages: json.dumps(CONTEXT_JSON))
    calls = []

    def translate(texts, source_lang, target_lang, source_langs):
        calls.append((list(texts), source_lang, target_lang, source_langs))
        return marked_translate(texts, source_lang, target_lang, source_langs)

    worker.run_once(tmp_path, translate=translate, state_path=tmp_path / "state.json", probe=quiet_probe)
    assert read_job(tmp_path)["status"] == "done"
    # The context pass answers in the transcript's language; the translation is what names the target.
    assert "in the language of the transcript" in sent[0][0]["content"]
    # One speech line here, so the reference on line 2 is dropped by the parser; its explanation is not sent.
    assert calls == [(["Resumo da peça.", "Monólogo"], lang, target, [lang])]
    note = tmp_path / "note.typ"
    assert audio_v2.section_text(note.read_text(), "Summary") == f"- 00:00 {target}: Resumo da peça."
    assert audio_v2.section_text(note.read_text(), "Scenes") == f"- 00:00 {target}: Monólogo"
    sidecar = audio_v2.load_sidecar(audio_v2.sidecar_path(tmp_path, "audio.wav"))
    assert sidecar["context"]["summary"] == "Resumo da peça."
    assert sidecar["context_translated"][target]["summary"] == f"{target}: Resumo da peça."


def test_context_translation_failure_falls_back_to_original(tmp_path, monkeypatch):
    context_job(tmp_path, monkeypatch)

    def failing(texts, source_lang, target, source_langs):
        raise ValueError("LLM returned an empty reply")

    worker.run_once(tmp_path, translate=failing, state_path=tmp_path / "state.json", probe=quiet_probe)
    assert read_job(tmp_path)["status"] == "done"
    note = (tmp_path / "note.typ").read_text()
    assert audio_v2.section_text(note, "Summary") == "- 00:00 Resumo da peça."
    assert audio_v2.section_text(note, "Scenes") == "- 00:00 Monólogo"
    assert audio_v2.section_text(note, "References") == "- 00:10 Baubo -- Figura do mito de Deméter. (AI)"
    sidecar = audio_v2.load_sidecar(audio_v2.sidecar_path(tmp_path, "audio.wav"))
    assert sidecar["context"]["summary"] == "Resumo da peça."
    assert sidecar.get("context_translated", {}) == {}


def test_reference_suffix_kept_after_translation(tmp_path, monkeypatch):
    context_job(tmp_path, monkeypatch)
    worker.run_once(tmp_path, translate=marked_translate, state_path=tmp_path / "state.json", probe=quiet_probe)
    # The term stays as the transcript spells it; only the explanation is translated; "(AI)" stays last.
    assert audio_v2.section_text((tmp_path / "note.typ").read_text(), "References") == (
        "- 00:10 Baubo -- ru: Figura do mito de Deméter. (AI)")


def test_context_line_the_model_could_not_translate_keeps_its_original(tmp_path, monkeypatch):
    context_job(tmp_path, monkeypatch)

    def partly(texts, source_lang, target, source_langs):
        return [worker.FAILED_TRANSLATION if text.startswith("Figura") else f"{target}: {text}" for text in texts]

    worker.run_once(tmp_path, translate=partly, state_path=tmp_path / "state.json", probe=quiet_probe)
    text = (tmp_path / "note.typ").read_text()
    assert audio_v2.section_text(text, "Summary") == "- 00:00 ru: Resumo da peça."
    assert audio_v2.section_text(text, "References") == "- 00:10 Baubo -- Figura do mito de Deméter. (AI)"
    assert worker.FAILED_TRANSLATION not in text
