import json

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
    job_path.write_text(json.dumps({"status": "queued", "audio": "audio.wav", "note": "note.typ"}))
    note = tmp_path / "note.typ"
    note.write_bytes(b"= Note\r\n== Comments\r\nKeep me\r\n")

    def fake_transcribe(audio, model, lang):
        assert audio == tmp_path / "audio.wav"
        assert (model, lang) == ("small", "pt")
        assert json.loads(job_path.read_text())["status"] == "processing"
        return [(65, "Fixed text")]

    monkeypatch.setattr(worker, "transcribe", fake_transcribe)
    worker.main(["--vault", str(tmp_path), "--once", "--lang", "pt"])
    job = json.loads(job_path.read_text())
    assert job["status"] == "done"
    assert job["finished_at"]
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
