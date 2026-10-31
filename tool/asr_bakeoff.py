#!/usr/bin/env python3
"""ASR bake-off on the Unsloth Studio STT sidecar (Task 3 of docs/superpowers/plans/2026-10-31-audio-notes-v2.md).

    uv run --no-project python tool/asr_bakeoff.py [--work-dir DIR] [--only ENGINE ...]

Cuts eight mono 16 kHz clips from the source recording with ffmpeg (source is read only).
Then, one engine at a time: download the model if it is missing (20 min cap), load it on CPU,
transcribe every clip with language=pt, probe word timestamps once, unload. Prints the metrics
table and the decision by the plan's rule; writes results.json and transcripts under --work-dir.

Stdlib only plus ffmpeg. The API key is read from ~/.pi/agent/models.json and is never printed
or written. No model is loaded on this machine. Every HTTP call has a socket timeout and a
wall-clock deadline (SIGALRM).
"""

import argparse
import base64
import contextlib
import difflib
import json
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

BASE = "http://desktop-vdsrh2e:8888"
SOURCE = Path.home() / "Nextcloud/TyLogVault/assets/Friday at 21-17.aac"
WORK_DIR = Path.home() / ".tylog/asr-bakeoff"
DOWNLOAD_CAP_S = 20 * 60
LOAD_CAP_S = 10 * 60
CLIP_TIMEOUT_S = 600

# name, architecture, Studio engine, Studio model id (as stt/status lists it)
ENGINES = [
    ("whisper-large-v3-turbo", "whisper", "transformers", "large-v3-turbo"),
    ("whisper-large-v3", "whisper", "transformers", "large-v3"),
    ("qwen3-asr-1.7b", "qwen3-asr", "mtmd", "qwen3-asr-1.7b"),
    ("parakeet-tdt-0.6b-v3", "parakeet", "audiocpp", "audio-cpp/audio.cpp-gguf/Parakeet-TDT-0.6B-v3-GGUF"),
]

# clip name, start second in the recording, seconds, class
CLIPS = [
    ("speech_0600", 360, 30, "speech"),
    ("speech_1830", 1110, 30, "speech"),
    ("speech_2230", 1350, 30, "speech"),
    ("speech_2300", 1380, 30, "speech"),
    ("music_0200", 120, 30, "music"),
    ("music_0300", 180, 30, "music"),
    ("music_0430", 270, 30, "music"),
    ("short_0500", 300, 5, "short"),
]

# Credit or boilerplate strings Whisper-family models emit over music and silence.
CREDIT_MARKERS = (
    "legendas", "legendado", "amara.org", "subtítulos", "subtitles by",
    "thanks for watching", "thank you for watching", "inscreva", "subscribe", "http", "www.",
)


@contextlib.contextmanager
def deadline(seconds):
    """Hard wall-clock limit for a blocking call (main thread only)."""
    def fire(signum, frame):
        raise TimeoutError(f"hard deadline {seconds}s")
    old = signal.signal(signal.SIGALRM, fire)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old)


def api_key():
    cfg = json.loads((Path.home() / ".pi/agent/models.json").read_text())
    return cfg["providers"]["studio"]["apiKey"]


def request(key, method, path, *, body=None, raw=None, content_type=None, timeout=60):
    """Returns (status, text). HTTP errors return their status; network errors raise."""
    headers = {"Authorization": f"Bearer {key}"}
    data = raw
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    elif raw is not None:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    with deadline(timeout + 5):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status, resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as err:
            return err.code, err.read().decode("utf-8", "replace")


def multipart(fields, file_name, file_bytes):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    parts.append(
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{file_name}"\r\n'
        "Content-Type: audio/wav\r\n\r\n".encode()
    )
    parts.append(file_bytes)
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def stt_status(key):
    code, body = request(key, "GET", "/api/inference/audio/stt/status", timeout=30)
    if code != 200:
        raise RuntimeError(f"stt/status HTTP {code}")
    return json.loads(body)


def cut_clips(source, work):
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found on PATH")
    clips = []
    for name, start, seconds, kind in CLIPS:
        path = work / f"{name}.wav"
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source),
             "-ss", str(start), "-t", str(seconds), "-vn", "-ac", "1", "-ar", "16000",
             "-c:a", "pcm_s16le", str(path)],
            check=True, stdin=subprocess.DEVNULL, timeout=300,
        )
        clips.append((name, path, seconds, kind))
    return clips


def ensure_downloaded(key, engine, model):
    """Returns 'cached', 'downloaded', or a reason string the doc records as the failure."""
    if model in stt_status(key)[engine]["downloaded_models"]:
        return "cached"
    code, body = request(key, "POST", "/api/inference/audio/stt/download",
                         body={"engine": engine, "model": model}, timeout=60)
    if code != 200:
        return f"download start HTTP {code}"
    started = time.monotonic()
    while True:
        time.sleep(15)
        dl = stt_status(key)[engine]["download"]
        if dl.get("error"):
            return f"download error: {dl['error']}"
        if not dl["downloading"]:
            return "downloaded" if model in stt_status(key)[engine]["downloaded_models"] else "download finished, model not listed"
        if time.monotonic() - started > DOWNLOAD_CAP_S:
            with contextlib.suppress(Exception):
                request(key, "POST", "/api/inference/audio/stt/download/cancel",
                        body={"engine": engine, "model": model, "download_id": dl.get("download_id")}, timeout=30)
            return "download over 20 min, cancelled"


def load(key, engine, model):
    """Returns None when the model is resident, else a failure reason."""
    code, body = request(key, "POST", "/api/inference/audio/stt/load",
                         body={"engine": engine, "model": model, "device": "cpu"}, timeout=LOAD_CAP_S)
    if code != 200:
        return f"load HTTP {code}: {body[:200]}"
    started = time.monotonic()
    while True:
        st = stt_status(key)[engine]
        if st["loaded_model"] == model and not st["loading"]:
            return None
        if not st["loading"] and st["loaded_model"] != model:
            return f"load finished, loaded_model={st['loaded_model']}"
        if time.monotonic() - started > LOAD_CAP_S:
            return "load over 10 min"
        time.sleep(5)


def unload(key, engine, model):
    query = urllib.parse.urlencode({"engine": engine, "model": model, "wait": "true"})
    code, body = request(key, "POST", f"/api/inference/audio/stt/unload?{query}", timeout=120)
    if code != 200:
        return f"unload HTTP {code}"
    return ""


def transcribe_json(key, engine, model, wav):
    body = {"audio": base64.b64encode(wav).decode(), "engine": engine, "model": model,
            "language": "pt", "device": "cpu"}
    return request(key, "POST", "/api/inference/audio/transcribe", body=body, timeout=CLIP_TIMEOUT_S)


def words_v1(key, model, wav):
    """OpenAI-style call asking for word timings. Returns (words or None, text or None, error)."""
    body, ctype = multipart(
        {"model": model, "language": "pt", "response_format": "verbose_json",
         "timestamp_granularities[]": "word"},
        "clip.wav", wav,
    )
    code, out = request(key, "POST", "/v1/audio/transcriptions", raw=body, content_type=ctype,
                        timeout=CLIP_TIMEOUT_S)
    if code != 200:
        return None, None, f"HTTP {code}: {out[:160]}"
    data = json.loads(out)
    words = data.get("words")
    if not words:
        return None, data.get("text"), "no words key in response"
    return words, data.get("text"), ""


def run_engine(key, name, arch, engine, model, clips, work):
    rec = {"arch": arch, "engine": engine, "model": model, "status": "ok", "reason": "",
           "download": "", "load_s": None, "clips": {}, "timestamps": "", "v1_matches_json": None}
    print(f"== {name} ({engine}/{model})", flush=True)
    rec["download"] = ensure_downloaded(key, engine, model)
    print(f"   download: {rec['download']}", flush=True)
    if rec["download"] not in ("cached", "downloaded"):
        rec["status"], rec["reason"] = "not run", rec["download"]
        return rec
    started = time.monotonic()
    failure = load(key, engine, model)
    rec["load_s"] = round(time.monotonic() - started, 1)
    if failure:
        rec["status"], rec["reason"] = "not run", failure
        unload(key, engine, model)
        return rec
    try:
        for clip_name, path, seconds, kind in clips:
            wav = path.read_bytes()
            started = time.monotonic()
            try:
                code, body = transcribe_json(key, engine, model, wav)
            except Exception as exc:  # deadline or socket error: record and go on
                code, body = 0, f"{type(exc).__name__}: {exc}"
            elapsed = round(time.monotonic() - started, 2)
            text = json.loads(body).get("text", "") if code == 200 else None
            entry = {"kind": kind, "seconds": seconds, "elapsed_s": elapsed, "http": code,
                     "text": text, "error": "" if code == 200 else body[:200]}
            rec["clips"][clip_name] = entry
            if text is not None:
                (work / "transcripts" / f"{name}__{clip_name}.txt").write_text(text + "\n", encoding="utf-8")
            print(f"   {clip_name}: http {code}, {elapsed} s, {len(text or '')} chars", flush=True)
        words, v1_text, err = words_v1(key, model, (work / "speech_0600.wav").read_bytes())
        rec["timestamps"] = f"yes ({len(words)} words)" if words else f"no: {err}"
        json_text = rec["clips"]["speech_0600"]["text"]
        rec["v1_matches_json"] = (v1_text == json_text) if v1_text is not None else None
        print(f"   word timestamps: {rec['timestamps']}", flush=True)
    except Exception as exc:
        rec["status"], rec["reason"] = "partial", f"{type(exc).__name__}: {exc}"
    finally:
        err = unload(key, engine, model)
        if err:
            rec["reason"] = (rec["reason"] + "; " + err).strip("; ")
    return rec


def words_of(text):
    return re.findall(r"\w+", text.lower())


def is_garbage(text):
    """Loop or credit line (plan's rule). Empty output is not garbage: silence on music is the goal.
    A failed call (None) counts as garbage so a broken engine cannot win on music."""
    if text is None:
        return True
    words = words_of(text)
    if len(words) > 20 and len(set(words)) / len(words) < 0.25:
        return True
    low = text.lower()
    return any(marker in low for marker in CREDIT_MARKERS)


def summarise(results):
    rows = {}
    speech = [n for n, _, _, k in CLIPS if k == "speech"]
    for name, arch, _engine, _model in ENGINES:
        rec = results["engines"].get(name)
        if rec is None:
            continue
        clips = rec["clips"]
        music = [c for c in clips.values() if c["kind"] == "music"]
        music_garbage = sum(is_garbage(c["text"]) for c in music)
        music_words = sum(len(words_of(c["text"] or "")) for c in music)
        credit = sum(
            1 for c in clips.values()
            if c["text"] is not None and any(m in c["text"].lower() for m in CREDIT_MARKERS)
        )
        per30 = [c["elapsed_s"] * 30 / c["seconds"] for c in clips.values() if c["seconds"] == 30]
        rows[name] = {
            "arch": arch, "status": rec["status"], "reason": rec["reason"], "load_s": rec["load_s"],
            "music_garbage": music_garbage if rec["status"] in ("ok", "partial") else None,
            "music_words": music_words, "credit_hits": credit,
            "s_per_30s": round(sum(per30) / len(per30), 1) if per30 else None,
            "timestamps": rec["timestamps"] or "not probed", "agreement": None,
        }
    for name, row in rows.items():
        scores = []
        for other, orow in rows.items():
            if other == name or orow["status"] not in ("ok", "partial"):
                continue
            for clip in speech:
                a = results["engines"][name]["clips"].get(clip, {}).get("text")
                b = results["engines"][other]["clips"].get(clip, {}).get("text")
                if a is None or b is None:
                    continue
                scores.append(difflib.SequenceMatcher(None, words_of(a), words_of(b)).ratio())
        row["agreement"] = round(sum(scores) / len(scores), 3) if scores else None
    return rows


def table(rows):
    head = ("| engine | arch | status | load s | music garbage (of 3) | music words | credit hits (of 8) "
            "| speech agreement | s per 30 s | word timestamps |")
    lines = [head, "|" + "---|" * 10]
    for name, r in rows.items():
        def cell(v):
            return "-" if v is None else str(v)
        lines.append(
            f"| {name} | {r['arch']} | {r['status']} | {cell(r['load_s'])} | {cell(r['music_garbage'])} "
            f"| {r['music_words']} | {r['credit_hits']} | {cell(r['agreement'])} | {cell(r['s_per_30s'])} "
            f"| {'yes' if r['timestamps'].startswith('yes') else 'no'} |"
        )
    return "\n".join(lines)


def decide(rows):
    ranked = [(n, r) for n, r in rows.items() if r["status"] == "ok" and r["music_garbage"] is not None]
    if not ranked:
        return "No engine completed; no decision."

    def key(item):
        _, r = item
        return (r["music_garbage"], -(r["agreement"] or 0.0))

    primary = min(ranked, key=key)
    rest = [(n, r) for n, r in ranked if r["arch"] != primary[1]["arch"]]
    secondary = min(rest, key=key) if rest else None
    lines = [f"primary: {primary[0]} (music garbage {primary[1]['music_garbage']}/3, "
             f"agreement {primary[1]['agreement']})"]
    if secondary:
        lines.append(f"secondary: {secondary[0]} (music garbage {secondary[1]['music_garbage']}/3, "
                     f"agreement {secondary[1]['agreement']})")
    else:
        lines.append("secondary: none (no other architecture completed)")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--work-dir", type=Path, default=WORK_DIR)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--only", nargs="*", default=None, help="engine names from ENGINES")
    parser.add_argument("--skip-cut", action="store_true", help="reuse clips already in --work-dir")
    parser.add_argument("--report-only", action="store_true", help="re-score results.json without calling Studio")
    args = parser.parse_args()

    work = args.work_dir
    results_path = work / "results.json"
    if args.report_only:
        rows = summarise(json.loads(results_path.read_text(encoding="utf-8")))
        print(table(rows))
        print()
        print(decide(rows))
        return 0

    (work / "transcripts").mkdir(parents=True, exist_ok=True)
    if args.skip_cut:
        clips = [(n, work / f"{n}.wav", seconds, k) for n, _, seconds, k in CLIPS]
    else:
        clips = cut_clips(args.source, work)
    key = api_key()

    results_path = work / "results.json"
    results = {"engines": {}}
    if results_path.exists() and args.only:
        results = json.loads(results_path.read_text(encoding="utf-8"))
    for name, arch, engine, model in ENGINES:
        if args.only and name not in args.only:
            continue
        results["engines"][name] = run_engine(key, name, arch, engine, model, clips, work)
        results_path.write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")

    rows = summarise(results)
    print()
    print(table(rows))
    print()
    print(decide(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
