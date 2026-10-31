"""Process queued audio transcription jobs in a vault."""

import argparse
from contextlib import contextmanager, suppress
from datetime import datetime, timezone
import functools
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import time
from urllib.request import Request, urlopen


KEYS_PATH = Path.home() / ".tylog/keys.json"
STUDIO_DEADLINE = 600  # seconds per chunk request, wall clock
LLM_DEADLINE = 900
CONTEXT_MAX_TOKENS = 8000  # Stage 5 reply (summary, scenes, glossary, references); translate uses 3000
PROBE_DEADLINE = 30
MAC_FALLBACK_MIN_FREE = 4 * 1024**3
LOCAL_MODEL_CAP = "small"  # the largest Whisper model this Mac runs, whatever the settings say
FAILED_TRANSLATION = "[sem tradução]"  # written for a line the model could not translate
TRANSLATION_WINDOW = 40  # lines per translation call; each call also carries the summary and glossary
TRANSLATION_PREVIOUS = 10  # source/translation pairs before a window, shown as context only
LANGUAGE_NAMES = {"ru": "Russian", "en": "English", "pt": "Portuguese"}
CYRILLIC = re.compile(r"[\u0400-\u04FF]")
# Ordered by size; a name not listed here counts as the largest.
WHISPER_SIZES = ("tiny", "base", "small", "medium", "large-v3-turbo", "large-v2", "large-v3", "large")


def escape_markup(s):
    return "".join("\\" + char if char in "\\#[]$*_@" else char for char in s)


def format_ts(seconds):
    minutes, seconds = divmod(int(seconds), 60)
    return f"{minutes:02d}:{seconds:02d}"


def render_section(segments):
    return "== Transcript\n\n" + "".join(
        f"- {format_ts(start)} " + (f"[{speaker[0]}] " if speaker else "") +
        f"{escape_markup(text)}\n" for start, text, *speaker in segments
    )


def apply_transcript(note_text, segments):
    section = render_section(segments)
    lines = note_text.splitlines(keepends=True)
    for start, line in enumerate(lines):
        if line.rstrip("\r\n") == "== Transcript":
            end = start + 1
            while end < len(lines) and not lines[end].startswith("== "):
                end += 1
            return "".join(lines[:start]) + section + "".join(lines[end:])
    separator = "" if not note_text or note_text.endswith("\n\n") else (
        "\n" if note_text.endswith("\n") else "\n\n"
    )
    return note_text + separator + section


def offline_first(load):
    """Load from the local Hugging Face cache, online only when it is missing.

    Even with the model on disk, a plain load asks the hub for updates; when
    the network dropped mid-request that call hung for 8 hours with no
    timeout, and the job behind it never finished.
    """
    import huggingface_hub.constants as hub

    previous, hub.HF_HUB_OFFLINE = hub.HF_HUB_OFFLINE, True
    try:
        return load()
    except Exception:
        hub.HF_HUB_OFFLINE = previous
        return load()
    finally:
        hub.HF_HUB_OFFLINE = previous


def speaker_embedder():
    import torch
    from speechbrain.inference.speaker import EncoderClassifier

    encoder = offline_first(lambda: EncoderClassifier.from_hparams(
        source="speechbrain/spkrec-ecapa-voxceleb",
        savedir=str(Path.home() / ".cache/tylog/spkrec-ecapa-voxceleb"),
        run_opts={"device": "cpu"}))

    def embed(samples):
        with torch.inference_mode():
            return encoder.encode_batch(torch.from_numpy(samples).unsqueeze(0)).flatten().numpy()
    return embed


def diarize_segments(samples, segments, embed=None, distance_threshold=0.35):
    """Return original timestamps/text, adding speakers only for multiple clusters."""
    import numpy as np
    from sklearn.cluster import AgglomerativeClustering

    result = [(segment.start, segment.text.strip()) for segment in segments]
    if len(segments) < 2:
        return result
    embed = embed or speaker_embedder()
    clips = [samples[int(s.start * 16000):int(s.end * 16000)] for s in segments]
    embeddings = []
    for index in range(len(segments)):
        left = right = index
        size = len(clips[index])
        # Neighbouring segments supply context only for the embedding, never the text.
        while size < 1.5 * 16000 and (left > 0 or right < len(clips) - 1):
            if right < len(clips) - 1:
                right += 1
                size += len(clips[right])
            else:
                left -= 1
                size += len(clips[left])
        embeddings.append(embed(np.concatenate(clips[left:right + 1])))
    embeddings = np.asarray(embeddings)
    if not np.isfinite(embeddings).all() or (np.linalg.norm(embeddings, axis=1) == 0).any():
        raise ValueError("Invalid speaker embedding (non-finite or zero)")
    clusters = AgglomerativeClustering(
        n_clusters=None, metric="cosine", linkage="average",
        distance_threshold=distance_threshold).fit_predict(embeddings)
    labels = {}
    for cluster in clusters:
        if cluster not in labels:
            labels[cluster] = f"S{len(labels) + 1}"
    if len(labels) < 2:
        return result
    return [(start, text, labels[cluster]) for (start, text), cluster in zip(result, clusters)]


def decode_nonempty(audio, decode_audio):
    """16 kHz samples; PyAV returns 0 s for some raw .aac, so retry via ffmpeg."""
    samples = decode_audio(str(audio), sampling_rate=16000)
    if getattr(samples, "size", 1):
        return samples
    ffmpeg = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"  # launchd PATH is minimal
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "audio.wav"
        try:
            subprocess.run([ffmpeg, "-v", "error", "-i", str(audio), "-ar", "16000", "-ac", "1", str(wav)],
                           check=True, timeout=600)
            samples = decode_audio(str(wav), sampling_rate=16000)
        except (OSError, subprocess.SubprocessError):
            pass
    if not getattr(samples, "size", 1):
        raise ValueError("Audio decoded to 0 seconds (unreadable file?)")
    return samples


@contextmanager
def deadline(seconds):
    """Raise TimeoutError after a wall-clock limit, even when a socket never times out.

    Uses SIGALRM, so it only works on the main thread (the worker's CLI).
    """
    def expire(signum, frame):
        raise TimeoutError(f"No answer within {seconds} s")

    previous = signal.signal(signal.SIGALRM, expire)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def _free_memory_bytes():
    """Free, inactive and speculative bytes from vm_stat; None if unreadable.

    Inactive and speculative pages are reclaimable. "Pages free" alone would
    refuse almost every run, since macOS keeps it near zero by design.
    """
    try:
        output = subprocess.run(["vm_stat"], capture_output=True, text=True, check=True,
                                timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    page = re.search(r"page size of (\d+) bytes", output)
    if not page:
        return None
    counts = {name: int(count) for name, count in re.findall(
        r"^(Pages (?:free|inactive|speculative)):\s+(\d+)\.", output, re.MULTILINE)}
    return sum(counts.values()) * int(page[1])


def mac_fallback_allowed(free_bytes=None):
    """True only with at least 4 GiB available; unknown memory counts as not allowed."""
    if free_bytes is None:
        free_bytes = _free_memory_bytes()
    return free_bytes is not None and free_bytes >= MAC_FALLBACK_MIN_FREE


def min_model(model, cap):
    """The smaller of two Whisper names; a name not in WHISPER_SIZES counts as the largest."""
    def rank(name):
        return WHISPER_SIZES.index(name) if name in WHISPER_SIZES else len(WHISPER_SIZES)

    return cap if rank(model) > rank(cap) else model


@functools.lru_cache(maxsize=None)
def lower_priority():
    """Run the Mac fallback at nice 19. os.nice adds to the current value, so only once per process."""
    os.nice(19)


def transcribe_local(audio, model, lang=None, *, diarize=False, studio_failed=False):
    """Every local transcription on this Mac: refused under low memory, capped at small, niced."""
    if not mac_fallback_allowed():
        prefix = "Studio unreachable; " if studio_failed else ""
        raise RuntimeError(prefix + "Mac fallback refused (low memory)")
    lower_priority()
    options = {"diarize": True} if diarize else {}
    return transcribe(audio, model=min_model(model, LOCAL_MODEL_CAP), lang=lang, **options)


def transcribe(audio, model="small", lang=None, *, diarize=False):
    from faster_whisper import WhisperModel, decode_audio

    name = model
    # int8 on the CPU: the default turned large-v3 into float32 (6.6 GB) on a
    # Mac without fast float16, and under memory pressure macOS paged it out
    # until a 3.5-minute note sat "stuck" at 2% CPU. int8 is ~1.6 GB and faster.
    options = {"device": "cpu", "compute_type": "int8"}
    try:
        model = WhisperModel(name, local_files_only=True, **options)
    except OSError:  # not downloaded yet (LocalEntryNotFoundError)
        model = WhisperModel(name, **options)
    samples = decode_nonempty(audio, decode_audio)
    segments, info = model.transcribe(samples, language=lang or None,
                                      **({"multilingual": True} if not lang else {}))
    segments = list(segments)
    languages = [lang] if lang else [info.language]
    if not lang:
        try:
            windows = {}
            for segment in segments:
                window = int(segment.start // 30)
                windows[window] = windows.get(window, 0) + segment.end - segment.start
            weights = {}
            for window, duration in windows.items():
                detected, _, _ = model.detect_language(
                    audio=samples[window * 30 * 16000:(window + 1) * 30 * 16000])
                weights[detected] = weights.get(detected, 0) + duration
            total = sum(windows.values())
            languages += [language for language in sorted(weights, key=weights.get, reverse=True)
                          if language != info.language and weights[language] >= 0.15 * total]
        except Exception:
            languages = [info.language]
    if diarize:
        result = diarize_segments(samples, segments)
    else:
        result = [(segment.start, segment.text.strip()) for segment in segments]
    return result, info.language, languages


def transcribe_studio(audio, base, key, lang=None, model="unsloth/whisper-large-v3-turbo",
                      chunk_seconds=30, post=None):
    """Chunked Studio transcription; post accepts a Request and timeout like urlopen."""
    post = post or urlopen
    ffmpeg = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([ffmpeg, "-v", "error", "-i", str(audio), "-f", "segment",
                        "-segment_time", str(chunk_seconds), "-ac", "1", "-ar", "16000",
                        str(Path(tmp) / "out%05d.wav")], check=True, timeout=600)
        chunks = sorted(Path(tmp).glob("out*.wav"))
        if not chunks:
            raise ValueError("Audio split into no chunks")
        if not lang:
            from faster_whisper import WhisperModel, decode_audio

            detector = WhisperModel("tiny", device="cpu", compute_type="int8")
            lang, _, _ = detector.detect_language(
                audio=decode_nonempty(audio, decode_audio)[:30 * 16000])
        boundary = os.urandom(16).hex()
        headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
        if key:
            headers["Authorization"] = f"Bearer {key}"
        fields = {"model": model, "response_format": "json", "language": lang}
        segments = []
        for index, chunk in enumerate(chunks):
            parts = [f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode("utf-8")
                     for name, value in fields.items()]
            parts += [f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{chunk.name}"\r\n'
                      'Content-Type: audio/wav\r\n\r\n'.encode("utf-8"),
                      chunk.read_bytes(), f"\r\n--{boundary}--\r\n".encode("utf-8")]
            request = Request(base.rstrip("/") + "/audio/transcriptions",
                              data=b"".join(parts), headers=headers)
            with deadline(STUDIO_DEADLINE), post(request, timeout=120) as response:
                text = json.load(response)["text"].strip()
            if text:
                segments.append((index * chunk_seconds, text))
    return segments, lang, [lang]


LLM_CONTEXT = 65536  # the long prompts (context pass, translation batches) overflow Studio's 8k default


def _load(base, request, model):
    """Load `model` at LLM_CONTEXT and wait until Studio lists it loaded. Raises ValueError on failure."""
    root = base.rstrip("/").rsplit("/v1", 1)[0]
    local = request(root + "/api/models/local")["models"]
    reference = next((entry["id"] for entry in local if entry.get("model_id") == model), model)
    result = request(base.rstrip("/") + "/load",
                     {"model_path": reference, "max_seq_length": LLM_CONTEXT, "force_cancel_active": True})
    if result.get("error") or result.get("success") is False:
        raise ValueError(f"Studio rejected load: {result}")
    deadline = time.monotonic() + 15 * 60
    while time.monotonic() < deadline:
        if any(entry["id"] == model and entry.get("loaded") is True for entry in request("/models")["data"]):
            return
        time.sleep(min(5, max(0, deadline - time.monotonic())))
    raise ValueError("not loaded after 15 minutes")


def ensure_model(base, key, prefer, request):
    """Select Ornith or load the preferred model using the authenticated request."""
    try:
        loaded = [entry["id"] for entry in request("/models")["data"] if entry.get("loaded") is True]
        if prefer in loaded:
            return prefer
        ornith = next((model for model in loaded if "ornith" in model.lower()), None)
        if ornith:
            return ornith
        _load(base, request, prefer)
        return prefer
    except Exception as error:
        raise ValueError(f"Could not load preferred translation model {prefer}: {error}") from error


_REPEAT = re.compile(r"(\S.{0,60}?[.!?…])(?:\s+\1){2,}")


def collapse_repeats(text):
    """A phrase repeated three or more times in a row is kept once, then '…'."""
    return _REPEAT.sub(r"\1 …", text)


def looks_translated(source, text, target):
    """Whether `text` can be a translation of `source` into `target`. A script and identity check, not a quality check.

    ru: at least one Cyrillic letter per three source words (min 1), unless the source has no letters.
    Other targets: the reply must differ from the source, unless the source is two words or fewer.
    An empty reply never counts.
    """
    if not text.strip():
        return False
    if target == "ru":
        if not any(char.isalpha() for char in source):
            return True
        return len(CYRILLIC.findall(text)) >= max(1, len(source.split()) // 3)
    return len(source.split()) <= 2 or text.strip() != source.strip()


def translate_connection(settings):
    """The translate task's connection entry, or None for the default endpoint. An unknown id raises."""
    task = settings.get("tasks", {}).get("translate", {})
    connection = next((entry for entry in settings.get("connections", [])
                       if entry["id"] == task.get("connection")), None)
    if task.get("connection") and connection is None:
        raise ValueError(f"Unknown translation connection: {task['connection']}")
    return connection


def llm_chat(settings, *, max_tokens=3000):
    """(model, chat) for the translate task's LLM: connection, model choice and request deadlines.

    chat(messages) returns the reply text with thinking off. The caller asks for JSON in the
    prompt and parses it. The Stage 5 context pass uses this endpoint with a larger max_tokens.
    """
    task = settings.get("tasks", {}).get("translate", {})
    base, key = connection_credentials(translate_connection(settings))
    if not base:
        raise ValueError("Set TYLOG_LLM_URL or configure provider studio in ~/.pi/agent/models.json")

    def request(route, payload=None):
        headers = {"Content-Type": "application/json"}
        if key:
            headers["Authorization"] = f"Bearer {key}"
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        url = route if route.startswith(("http://", "https://")) else base.rstrip("/") + route
        request = Request(url, data=data, headers=headers)
        with deadline(LLM_DEADLINE), urlopen(request, timeout=900 if route.endswith("/load") else 300) as response:
            return json.load(response)

    model = os.environ.get("TYLOG_LLM_MODEL") or task.get("model")
    if not model:
        model = ensure_model(base, key, os.environ.get("TYLOG_LLM_PREFER") or
                             ("ollama/ornith-1.5:9b" if task.get("quality") == "fast"
                              else "ollama/ornith-1.5:35b"),
                             request)

    def complete(messages):
        # Thinking off and 10 lines per request: with reasoning on, 40 theatre
        # lines ran past the 120 s timeout (2026-10-31), same as the enrich worker.
        return request("/chat/completions", {
            "model": model,
            "temperature": 0,
            "max_tokens": max_tokens,
            "chat_template_kwargs": {"enable_thinking": False},
            "messages": messages,
        })["choices"][0]["message"]["content"] or ""

    def chat(messages):
        reply = complete(messages)
        if not reply.strip():
            # Studio answers an empty reply once a prompt outgrows the context it loaded with, and
            # its context fields do not show which one that is. Reload at LLM_CONTEXT, retry once.
            try:
                _load(base, request, model)
            except Exception as error:
                raise ValueError(f"Could not reload {model} at {LLM_CONTEXT} after an empty reply: {error}") from error
            reply = complete(messages)
        if not reply.strip():
            raise ValueError(f"LLM {model} returned an empty reply{_context_note(request, model)}")
        return reply.strip()

    return model, chat


def _context_note(request, model):
    """' (max_context_length N)' when Studio lists the model with one, else ''. Only runs on an empty reply."""
    try:
        context = next((entry.get("max_context_length") for entry in request("/models")["data"]
                        if entry.get("id") == model), None)
    except Exception:  # the note is diagnostics; never mask the empty-reply error
        return ""
    return f" (max_context_length {context})" if context is not None else ""


def _glossary_lines(glossary, target):
    """Glossary items as "heard -> spelling", plus " -> rendering" when the context pass rendered it in `target`."""
    lines = []
    for item in glossary:
        heard = item.get("heard") or item.get("term")  # sidecars from before `heard` hold `term`
        if not heard:
            continue
        rendering = item.get(target)
        lines.append(f"{heard} -> {item.get('spelling') or heard}" + (f" -> {rendering}" if rendering else ""))
    return lines


def _translation_system(target, source_langs, context):
    """Translation instructions; with a context (summary and glossary from the context pass), both are added."""
    system = (
        f"Translate faithfully into {target}. Keep names. "
        "Segments that are already in the target language must be returned unchanged. "
        f"The source may mix these languages: {', '.join(source_langs)}. "
        "No commentary. Input is a JSON object mapping line ids to source lines; return only a JSON object "
        "with the same ids, each mapped to the translation of its line."
    )
    if context:
        glossary = _glossary_lines(context.get("glossary") or [], target)
        system += (f"\n\nSummary of the recording, in the source language: {context.get('summary') or '(none)'}"
                   f"\n\nGlossary, heard -> spelling -> {target}:\n" + ("\n".join(glossary) or "(none)"))
    return system


def _window_user(texts, indices, pairs):
    """The previous source/translation pairs (context only), then the window as JSON {id: text} on the last line."""
    before = json.dumps([{"source": source, "translation": text} for source, text in pairs], ensure_ascii=False)
    window = json.dumps({str(index): texts[index] for index in indices}, ensure_ascii=False)
    return (f"Previous lines, for context only; do not translate or repeat them:\n{before if pairs else '(none)'}\n\n"
            f"Lines to translate, JSON {{id: text}}:\n{window}")


def translate(texts, source_lang, target, source_langs=None, *, settings=None, context=None):
    """Translates `texts` in windows of TRANSLATION_WINDOW lines. A window's reply is a JSON object {id: translation},
    the id being the line's index in `texts`. `context` is {"summary", "glossary"} from the transcript's context pass."""
    translate.last_model = None
    model, chat = llm_chat(settings or {})
    # Whisper loops on music and applause ("É isso aí! É isso aí! ..."); the
    # model copies the loop until the reply cap and the batch fails.
    texts = [collapse_repeats(text) for text in texts]

    def ask(indices, pairs):
        """{id: translation} for the lines the reply covers; a line it leaves out is absent. A reply that is not
        a JSON object raises."""
        reply = chat([
            {"role": "system", "content": _translation_system(target, source_langs or [source_lang], context)},
            {"role": "user", "content": _window_user(texts, indices, pairs)},
        ])
        if reply.startswith("```"):
            reply = re.sub(r"^```[^\n]*\n", "", reply)
            reply = re.sub(r"\s*```$", "", reply)
        result = json.loads(reply)
        if not isinstance(result, dict):
            raise ValueError("Translation reply must be a JSON object keyed by line id")
        return {key: value for key, value in result.items() if isinstance(value, str)}

    def settle(text, reply):
        """The reply when it is in the target language; else one plain retry of the line alone; None if that fails too."""
        nonlocal last_error
        if looks_translated(text, reply, target):
            return reply
        try:
            retry = chat([
                {"role": "system", "content": (
                    f"Translate this line into {LANGUAGE_NAMES.get(target, target)}. "
                    "Reply with the translation only.")},
                {"role": "user", "content": text},
            ])
        except (ValueError, OSError) as error:
            last_error = error
            return None
        if looks_translated(text, retry, target):
            return retry
        last_error = ValueError(f"Reply is not a translation into {target}")
        return None

    # A window whose reply is broken is asked line by line; a line the reply leaves out is
    # asked alone. A reply in the wrong language (Portuguese for ru, the source copied for
    # en/pt) gets one plain retry. A line that still fails is marked FAILED_TRANSLATION, never
    # copied from the source. Only a job where nothing translates fails, so one noisy minute
    # cannot sink a 2-hour recording.
    results = [None] * len(texts)

    def prior_pairs(index):
        """Up to TRANSLATION_PREVIOUS settled (source, translation) pairs just before line `index`."""
        return [(texts[i], results[i]) for i in range(max(0, index - TRANSLATION_PREVIOUS), index)
                if results[i] is not None]

    for first in range(0, len(texts), TRANSLATION_WINDOW):
        window = list(range(first, min(first + TRANSLATION_WINDOW, len(texts))))
        try:
            replies = ask(window, prior_pairs(first))
        except (ValueError, OSError) as error:  # bad JSON, timeout
            last_error = error
            replies = None
        for index in window:
            if replies is not None and str(index) in replies:
                results[index] = settle(texts[index], replies[str(index)])
                continue
            if replies is None and len(window) == 1:
                continue  # the one-line window already failed: nothing smaller to ask
            try:
                reply = ask([index], prior_pairs(index)).get(str(index))
                if reply is None:
                    raise ValueError(f"Translation reply has no line {index}")
                results[index] = settle(texts[index], reply)
            except (ValueError, OSError) as error:
                last_error = error
    if texts and all(result is None for result in results):
        raise last_error
    translate.last_model = model
    return [FAILED_TRANSLATION if result is None else result for result in results]


def apply_translation(note_text, source_lang, target, translate, source_langs=None, previous=None, reread=None,
                      context=None):
    """Writes `== Translation <target>` from the Transcript section. Returns (note_text, lines).

    One translation line per transcript line, same mm:ss. `[—]` gap lines are copied
    and never sent to the model. `previous` is the `lines` list returned last run
    (kept in the job sidecar); merge_section keeps a line the user edited. None means
    the first run or a legacy section: the old section is replaced. `reread`, when given,
    returns the note as it is now; the lines are merged into that text, so edits made
    while the model ran survive. `context` ({"summary", "glossary"}) goes to translate.
    """
    from audio_v2 import DOUBTFUL_PREFIX, GAP_TEXT, merge_section

    heading = f"Translation {target}"
    note_lines = note_text.splitlines(keepends=True)

    def section_bounds(title):
        for start, line in enumerate(note_lines):
            if line.rstrip("\r\n") == title:
                end = start + 1
                while end < len(note_lines) and not note_lines[end].startswith("== "):
                    end += 1
                return start, end
        return None

    transcript = section_bounds("== Transcript")
    if transcript is None:
        raise ValueError("Note has no Transcript section")
    segments = []
    for line in note_lines[transcript[0] + 1:transcript[1]]:
        match = re.fullmatch(r"- (\d{2,}):([0-5]\d) (.*)", line.rstrip("\r\n"))
        if not match:
            continue
        start = float(int(match[1]) * 60 + int(match[2]))
        text = re.sub(r"\\(.)", r"\1", match[3])
        if text == GAP_TEXT:
            segments.append({"start": start, "kind": "gap", "text": "", "status": "ok"})
        elif text.startswith(DOUBTFUL_PREFIX):
            segments.append({"start": start, "kind": "speech", "text": text[len(DOUBTFUL_PREFIX):],
                             "status": "doubtful", "doubt_mark": True})
        else:
            segments.append({"start": start, "kind": "speech", "text": text, "status": "ok", "doubt_mark": False})

    speech = [segment["text"] for segment in segments if segment["kind"] == "speech"]
    # Context is passed only when the transcript has one, so translate stand-ins with four arguments still work.
    extra = {} if context is None else {"context": context}
    translated = translate(speech, source_lang, target, source_langs or [source_lang], **extra) if speech else []
    if len(translated) != len(speech):
        raise ValueError("Translation reply must have the same length as the transcript")
    if reread is not None:
        note_lines = reread().splitlines(keepends=True)
    translated = iter(translated)
    existing = section_bounds(f"== {heading}")
    if existing is None:
        previous = None  # the section was removed on purpose: regenerate, do not keep "deleted" lines

    previous_by_key = {}
    for line in previous or []:
        previous_by_key.setdefault((int(line["start"]), line["kind"]), []).append(line)
    built = []
    for segment in segments:
        text = next(translated) if segment["kind"] == "speech" else ""
        queue = previous_by_key.get((int(segment["start"]), segment["kind"]))
        old = queue.pop(0) if queue else None
        if old is not None and old.get("status") in ("user", "deleted"):
            built.append(old)
            continue
        built.append({"start": segment["start"], "kind": segment["kind"], "text": text,
                      "status": segment["status"], "doubt_mark": segment.get("doubt_mark", False),
                      "rendered": dict(old.get("rendered", {})) if old else {}})

    # A machine line that no transcript line produces any more is removed from the
    # note; a user-edited one stays (merge_section keeps it as a user line).
    stale = {line["rendered"][heading] for queue in previous_by_key.values() for line in queue
             if line.get("status") not in ("user", "deleted") and heading in line.get("rendered", {})}
    if existing:
        start, end = existing
        # No state (first run or legacy section): nothing says which lines the user edited.
        note_lines[start:end] = [] if previous is None else [
            raw for raw in note_lines[start:end] if raw.rstrip("\r\n") not in stale]
    return merge_section("".join(note_lines), heading, built)


def _vault_path(vault, relative):
    path = (vault / relative).resolve()
    if Path(relative).is_absolute() or not path.is_relative_to(vault):
        raise ValueError(f"Path must be inside the vault: {relative}")
    return path


def read_note(note):
    with note.open(encoding="utf-8", newline="") as stream:  # newline="": CRLF notes stay CRLF
        return stream.read()


def _translation_headings(note_text):
    """Titles of the `== Translation <lang>` sections in the note, e.g. "Translation ru"."""
    return sorted({line.strip()[3:] for line in note_text.splitlines()
                   if re.fullmatch(r"== Translation \S+", line.strip())})


def _read_json(path):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (FileNotFoundError, ValueError):
        return {}


def _settings_path_for(shared_path):
    local_path = shared_path.with_suffix(".local.json")
    return local_path if local_path.exists() else shared_path


def load_ai_settings(vault):
    """Read the supported settings schema, ignoring malformed/unknown fields."""
    try:
        value = _read_json(_settings_path_for(Path(vault) / "_system/settings/ai.json"))
    except OSError:
        return {}
    if value.get("schema") != 1:
        return {}
    tasks = value.get("tasks")
    tasks = tasks if isinstance(tasks, dict) else {}
    clean_tasks = {}
    for name in ("transcribe", "translate"):
        task = tasks.get(name)
        if isinstance(task, dict):
            clean_tasks[name] = {key: item for key, item in task.items()
                                 if key in ("quality", "model", "connection")
                                 and isinstance(item, str) and item}
    connections = value.get("connections")
    connections = connections if isinstance(connections, list) else []
    return {"schema": 1, "tasks": clean_tasks,
            "connections": [entry for entry in connections if isinstance(entry, dict)
                            and isinstance(entry.get("id"), str) and entry["id"]
                            and isinstance(entry.get("url"), str) and entry["url"]]}


def resolve_whisper_model(settings, cli_model=None):
    task = settings.get("tasks", {}).get("transcribe", {})
    return cli_model or task.get("model") or {
        "fast": "small", "balanced": "large-v3-turbo", "best": "large-v3"
    }.get(task.get("quality"), "large-v3")


def connection_credentials(connection=None):
    provider_id = connection["id"] if connection else "studio"
    providers = _read_json(Path.home() / ".pi/agent/models.json").get("providers", {})
    provider = providers.get(provider_id, {}) if isinstance(providers, dict) else {}
    provider = provider if isinstance(provider, dict) else {}
    base = connection["url"] if connection else (
        os.environ.get("TYLOG_LLM_URL") or provider.get("baseUrl"))
    key = os.environ.get("TYLOG_LLM_KEY")
    if connection and not key:
        env_name = "TYLOG_KEY_" + re.sub(r"[^A-Z0-9]", "_", provider_id.upper())
        key = os.environ.get(env_name)
        if not key:
            local_key = _read_json(KEYS_PATH).get(provider_id)
            key = local_key if isinstance(local_key, str) else None
    return base, key or provider.get("apiKey")


def probe_connection(base, key):
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    request = Request(base.rstrip("/") + "/models", headers=headers)
    with deadline(PROBE_DEADLINE), urlopen(request, timeout=15) as response:
        entries = json.load(response)["data"]
    return {"reachable": True, "loaded": [entry["id"] for entry in entries
            if isinstance(entry.get("id"), str) and entry.get("loaded", True) is True]}


def write_heartbeat(vault, settings, state, state_path, now, hostname, probe):
    """Best effort presence and cached connection health; never break jobs."""
    try:
        host = hostname()
        filename = re.sub(r"[^A-Za-z0-9_.-]", "_", host).strip(".") or "unknown"
        now = now.astimezone(timezone.utc)
        connections = {}
        cache = state.setdefault("connection_probes", {}) if settings.get("connections") else {}
        for connection in settings.get("connections", []):
            identifier = connection["id"]
            previous = cache.get(identifier, {})
            age = now.timestamp() - previous.get("last_probe", 0)
            if previous.get("url") != connection["url"] or not 0 <= age < 300:
                try:
                    result = probe(*connection_credentials(connection))
                except Exception:
                    result = {"reachable": False, "loaded": []}
                previous = {"url": connection["url"], "last_probe": now.timestamp(),
                            "result": result}
                cache[identifier] = previous
            connections[identifier] = previous["result"]
        prefix = "models--Systran--faster-whisper-"
        hub = Path.home() / ".cache/huggingface/hub"
        models = sorted(path.name[len(prefix):] for path in hub.glob(prefix + "*")
                        if path.is_dir())
        heartbeat = {"host": host, "last_seen": now.isoformat(),
                     "whisper_models": models, "connections": connections}
        state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        directory = vault / "_system/workers"
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / (filename + ".json")
        # Rewrite only on change or every 4 min (apps treat >5 min as offline): each write changes the synced
        # folder, and phones then run a full sync on every poll.
        try:
            previous = json.loads(target.read_text(encoding="utf-8"))
            seen = datetime.fromisoformat(previous.pop("last_seen"))
            fresh = {k: v for k, v in heartbeat.items() if k != "last_seen"}
            if previous == fresh and (now - seen).total_seconds() < 240:
                return
        except Exception:
            pass
        target.write_text(
            json.dumps(heartbeat, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except Exception:
        pass


def _has_pending_jobs(vault):
    for kind in ("transcripts", "translations"):
        for path in (vault / "_system/jobs" / kind).glob("*.json"):
            if _read_json(path).get("status") in ("queued", "processing"):
                return True
    return False


TRANSLATION_LANGS = ("ru", "en", "pt")  # every recording gets all three; not switchable off


def translation_targets(source_langs, settings_targets):
    """ru, en, pt always, then any extra targets from settings. A transcript that is only one of
    these languages skips that language; a mixed transcript gets all three."""
    targets = []
    for lang in (*TRANSLATION_LANGS, *settings_targets):
        if lang in targets or source_langs == [lang]:
            continue
        targets.append(lang)
    return targets


def _job_file(vault, kind, key):
    return vault / "_system/jobs" / kind / (hashlib.sha1(key.encode("utf-8")).hexdigest() + ".json")


def requeue_translations(vault, transcript):
    """A finished transcript replaces the one its translations came from: existing translation jobs for its
    targets go back to queued, other fields kept. Sweep creates the targets that have no job yet."""
    if not transcript.get("lang"):
        return
    audio = transcript["audio"]
    settings = _read_json(_settings_path_for(vault / "_system/settings/processing.json")).get("audio", {})
    for target in translation_targets(transcript.get("langs", [transcript["lang"]]),
                                      settings.get("translate_to", [])):
        path = _job_file(vault, "translations", audio + "\n" + target)
        if path.exists():
            job = _read_json(path)
            job.pop("error", None)
            job.pop("finished_at", None)
            job["status"] = "queued"
            path.write_text(json.dumps(job, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _llm_configured(settings):
    """Whether the translate task has an LLM endpoint. An unknown connection counts as none: its job reports it."""
    try:
        return bool(connection_credentials(translate_connection(settings))[0])
    except ValueError:
        return False


def _context_pending(vault, audio):
    """A v2 transcript whose context pass has not run: its sidecar has the transcript stage done and no `context`.
    The pass runs inside the transcript job, after the transcript is written."""
    import audio_v2

    data = _read_json(audio_v2.sidecar_path(vault, audio))
    return data.get("stages", {}).get("transcript") == "done" and "context" not in data


def translation_context(sidecar):
    """The summary and glossary of a v2 transcript's context pass, for the translation prompt; None without one."""
    context = sidecar.get("context")
    if not isinstance(context, dict):
        return None
    return {"summary": context.get("summary") or "", "glossary": context.get("glossary") or []}


def sweep(vault, now, state, force=False):
    vault = Path(vault).resolve()
    audio_settings = _read_json(_settings_path_for(vault / "_system/settings/processing.json")).get("audio", {})
    transcribe_enabled = audio_settings.get("transcribe", False)
    targets = audio_settings.get("translate_to", [])  # extra targets; the processing "translate" flag is ignored
    local_now = now.astimezone()
    today = local_now.date().isoformat()
    scheduled = False
    time = audio_settings.get("time", "")
    if audio_settings.get("scheduled") and re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", time):
        scheduled = (local_now.strftime("%H:%M") >= time
                     and state.get("last_scheduled_date") != today)
    if not (force or audio_settings.get("on_the_fly") or scheduled):
        return 0
    llm = _llm_configured(load_ai_settings(vault))

    def section(text, heading):
        match = re.search(r"^" + re.escape(heading) + r"\r?$(.*?)(?=^== |\Z)",
                          text, re.MULTILINE | re.DOTALL)
        return match.group(1) if match else None

    created = 0

    def enqueue(kind, key, job):
        nonlocal created
        path = _job_file(vault, kind, key)
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with path.open("x", encoding="utf-8") as stream:
                json.dump({**job, "requested_at": now.astimezone(timezone.utc).isoformat(),
                           "status": "queued", "auto": True}, stream, ensure_ascii=False, indent=2)
                stream.write("\n")
            created += 1
        except FileExistsError:
            pass

    for note in sorted((vault / "notes").glob("Audio *.typ")):
        text = note.read_text(encoding="utf-8")
        header = re.search(r'#show:\s*tylog\.note\.with\(((?:"(?:\\.|[^"\\])*"|[^")])*)\)',
                           text, re.DOTALL)
        if not header or not re.search(r'\bkind:\s*"audio"', header.group(1)):
            continue
        attachment = re.search(r'#tylog\.attachment\(\s*"((?:\\.|[^"\\])*)"\s*,\s*kind:\s*"audio"\s*\)', text)
        if not attachment:
            continue
        audio = re.sub(r"\\(.)", r"\1", attachment.group(1)).lstrip("/")
        try:
            if not _vault_path(vault, audio).is_file():
                continue
        except ValueError:
            continue
        job = {"audio": audio, "note": note.relative_to(vault).as_posix()}
        transcript = section(text, "== Transcript")
        if not transcript or not transcript.strip():
            if transcribe_enabled:
                enqueue("transcripts", audio, job)
            continue
        source = _read_json(vault / "_system/jobs/transcripts" /
                            (hashlib.sha1(audio.encode("utf-8")).hexdigest() + ".json"))
        source_lang = source.get("lang")
        source_langs = source.get("langs", [source_lang])
        # With an LLM endpoint, a v2 transcript's translations wait for its context (summary, glossary).
        if source_lang and not (llm and _context_pending(vault, audio)):
            for target in translation_targets(source_langs, targets):
                if section(text, f"== Translation {target}") is None:
                    enqueue("translations", audio + "\n" + target,
                            {**job, "target": target, "source_lang": source_lang,
                             "source_langs": source_langs})
    # The scheduled run stays open until a sweep finds nothing new and nothing
    # queued or running: translations only appear after their transcripts
    # finish, so closing after the first sweep would push them to tomorrow.
    if scheduled and created == 0 and not _has_pending_jobs(vault):
        state["last_scheduled_date"] = today
    return created


def studio_root(base):
    """Studio API root from a connection URL, which ends in /v1 for the OpenAI-style routes."""
    return base.rstrip("/").rsplit("/v1", 1)[0]


def _redacted(error, key):
    return str(error).replace(key, "[redacted]") if key else str(error)


def _release(studio):
    """Unloads the pass's Studio model. A failed unload does not fail a finished pass;
    the next load replaces the resident model."""
    with suppress(Exception):
        studio.close()


def transcribe_v2_job(vault, job, note, model, settings):
    """v2 transcript job: speech chunks through the Studio passes, then sentence lines merged into the note.

    The primary pass runs on Studio; if Studio fails, the Mac fallback (guarded, small model) runs the
    remaining chunks. The secondary pass runs on Studio only and its failure is not fatal. Every chunk
    is saved to the sidecar as it finishes, so a failed run resumes from there.

    Returns (note text, sidecar path, lines, language). The caller writes the note, then calls
    audio_v2.finish_transcript with the sidecar path and lines.
    """
    import audio_v2

    audio = _vault_path(vault, job["audio"])
    sidecar = audio_v2.sidecar_path(vault, job["audio"])
    state = audio_v2.load_sidecar(sidecar)
    legacy = state.get("stages", {}).get("transcript") != "done"
    job.pop("studio_error", None)
    with note.open(encoding="utf-8", newline="") as stream:
        note_text = stream.read()
    if legacy and audio_v2.section_has_lines(note_text, "Transcript"):
        audio_v2.backup_legacy_note(vault, job["audio"], note_text)  # before the first v2 write to the sidecar
    lang = job.get("lang") or None
    identifier = settings.get("tasks", {}).get("transcribe", {}).get("connection") or "studio"
    connection = next((entry for entry in settings.get("connections", []) if entry["id"] == identifier), None)
    studio = key = None
    if connection:
        base, key = connection_credentials(connection)
        studio = audio_v2.StudioSTT(studio_root(base), key, lang)
    job["engine"] = "local"
    result = None
    primary_failed = False
    if studio is not None:
        try:
            result = audio_v2.transcribe_v2(audio, sidecar, studio, engines=(audio_v2.PRIMARY,))
            job["engine"] = "studio"
        except Exception as error:
            job["studio_error"] = _redacted(error, key)
            primary_failed = True
        _release(studio)
    mac = None
    if studio is None or primary_failed:
        mac = audio_v2.MacSTT(model, lang, studio_failed=primary_failed)
        result = audio_v2.transcribe_v2(audio, sidecar, mac, engines=(audio_v2.PRIMARY,))
    if job["engine"] == "studio":
        try:
            result = audio_v2.transcribe_v2(audio, sidecar, studio, engines=(audio_v2.SECONDARY,))
        except Exception as error:
            job["studio_error"] = _redacted(error, key)
        _release(studio)
    language = lang
    if language is None and studio is not None:
        language = studio.language
    if language is None and mac is not None:
        language = mac.language
    # Re-read right before the write: a user edit made while the passes ran is part of the note now.
    with note.open(encoding="utf-8", newline="") as stream:
        note_text = stream.read()
    previous = [] if legacy else state.get("lines", [])
    if legacy:
        note_text = audio_v2.clear_section(note_text, "Transcript")
        # v1 translations describe the replaced transcript, so their sections go. Dropped, not emptied:
        # an empty heading would keep the sweep from queueing a fresh translation.
        for heading in _translation_headings(note_text):
            note_text = audio_v2.remove_section(note_text, heading)
    note_text, lines = audio_v2.merge_transcript(note_text, previous, result)
    return note_text, sidecar, lines, language


def context_stage(vault, job, note, sidecar, lines, settings, translate):
    """Stage 5 of a v2 transcript: Summary, Scenes and References from the transcript and the user's Context.

    The LLM writes them in the transcript's language. They are then translated into the target, the first
    translation language, through `translate` (the translate task's validated path). The sidecar keeps the
    transcript-language result as `context` and the translated one as `context_translated[target]`; the sections
    render the translated one. A translation that fails outright renders the original and stores no translation.
    Without an LLM endpoint the stage is skipped. A failed or malformed reply raises: the job fails, the note
    keeps its transcript, and a re-process runs the stage again.
    """
    import audio_v2

    if not connection_credentials(translate_connection(settings))[0]:
        return
    extra = _read_json(_settings_path_for(vault / "_system/settings/processing.json")).get("audio", {})
    source_langs = job.get("langs", [])
    target = translation_targets(source_langs, extra.get("translate_to", []))[0]
    _, chat = llm_chat(settings, max_tokens=CONTEXT_MAX_TOKENS)
    speech = [line for line in lines if line["kind"] == "speech"]
    result = audio_v2.context_pass(speech, audio_v2.section_text(read_note(note), "Context"), target, chat)
    translated = audio_v2.translated_context(result, translate, source_langs, target)
    shown = result if translated is None else translated
    # Read again after the model ran: a user edit made meanwhile is part of the note now.
    previous = audio_v2.load_sidecar(sidecar).get("context_lines", {})
    note_text, context_lines = audio_v2.render_context(read_note(note), previous, shown, speech)
    with note.open("w", encoding="utf-8", newline="") as stream:
        stream.write(note_text)
    data = audio_v2.load_sidecar(sidecar)
    data.update(context=result, context_lines=context_lines,
                context_translated={} if translated is None else {target: translated})
    audio_v2.save_sidecar(sidecar, data)


def _render_transcript(note, sidecar, data):
    """Re-renders the Transcript from the sidecar's chunks and saves the merged lines. The note is read
    right before the write, so a user edit made meanwhile survives (merge_section reads it as a user line)."""
    import audio_v2

    text, data["lines"] = audio_v2.merge_transcript(read_note(note), data.get("lines", []),
                                                    audio_v2.lines_from_chunks(data["chunks"]))
    with note.open("w", encoding="utf-8", newline="") as stream:
        stream.write(text)
    audio_v2.save_sidecar(sidecar, data)


def arbitration_stage(note, sidecar, settings):
    """Stage 4 of a v2 transcript: LLM arbitration of the disputed speech chunks, then the Transcript is re-rendered.

    Runs after the context pass, so the glossary and the Context exist. Each decision is saved to the sidecar
    as it is made; a finished chunk is never sent again, so a failed run resumes where it stopped. Without an
    LLM endpoint the stage is skipped and the (?) lines stay. A failed call raises and fails the job.
    """
    import audio_v2

    data = audio_v2.load_sidecar(sidecar)
    if data.get("stages", {}).get("arbitration") == "done":
        return
    if not connection_credentials(translate_connection(settings))[0]:
        return
    _, chat = llm_chat(settings)
    _render_transcript(note, sidecar, data)  # user edits since the transcript was written become user lines first
    glossary = data.get("context", {}).get("glossary", [])
    audio_v2.arbitrate_chunks(data["chunks"], data["lines"], audio_v2.section_text(read_note(note), "Context"),
                              glossary, chat, save=lambda: audio_v2.save_sidecar(sidecar, data))
    data.setdefault("stages", {})["arbitration"] = "done"
    _render_transcript(note, sidecar, data)


STALE_CLAIM_HOURS = 2  # no single audio takes this long; the worker died or hung


def _stale_claim(job, now):
    """A "processing" job its worker abandoned (killed, hung, Mac asleep)."""
    if job.get("status") != "processing":
        return False
    since = job.get("processing_at") or job.get("requested_at")
    try:
        started = datetime.fromisoformat(since)
    except (TypeError, ValueError):
        return True
    return (now - started).total_seconds() > STALE_CLAIM_HOURS * 3600


def run_once(vault, model=None, translate=None, *, now=None, state_path=None,
             hostname=None, clock=None, probe=None, diarize=False):
    import audio_v2  # imports this module; a top-level import would be circular
    vault = Path(vault).resolve()
    clock = clock or (lambda: datetime.now(timezone.utc))
    supplied_now = now
    now = now if now is not None else clock()
    settings = load_ai_settings(vault)
    model = resolve_whisper_model(settings, model)
    if translate is None:
        def translate(texts, source_lang, target, source_langs, context=None):
            identifier = settings.get("tasks", {}).get("translate", {}).get("connection")
            connection = next((entry for entry in settings.get("connections", [])
                               if entry["id"] == identifier), None)
            _, key = connection_credentials(connection)
            try:
                result = globals()["translate"](texts, source_lang, target, source_langs, settings=settings,
                                                context=context)
            except Exception as error:
                message = str(error).replace(key, "[redacted]") if key else str(error)
                raise ValueError(message) from None
            translate.last_model = globals()["translate"].last_model
            return result
    state_path = Path(state_path).expanduser() if state_path is not None else Path.home() / ".tylog-transcribe-state.json"
    state = _read_json(state_path)
    try:
        requested_at = _read_json(vault / "_system/jobs/process-now.json").get("requested_at")
        force = bool(requested_at) and requested_at != state.get("last_process_now")
        sweep(vault, now, state, force=force)
        if force:
            state["last_process_now"] = requested_at
        state_path.parent.mkdir(parents=True, exist_ok=True)
        state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        # Read once, before any job runs: a translation requeued by a transcript in this pass waits for the next one.
        jobs = [(kind, path, json.loads(path.read_text(encoding="utf-8")))
                for kind in ("transcripts", "translations")
                for path in sorted((vault / "_system/jobs" / kind).glob("*.json"))]
        for kind, job_path, job in jobs:
            if job.get("status") != "queued" and not _stale_claim(job, now):
                continue
            try:
                job["status"] = "processing"
                job["processing_at"] = now.astimezone(timezone.utc).isoformat()
                job_path.write_text(json.dumps(job, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                note = _vault_path(vault, job["note"])
                finish = None
                if kind == "transcripts" and job.get("engine") != "v1":
                    updated_note, sidecar_path, lines, language = transcribe_v2_job(
                        vault, job, note, model, settings)
                    finish = (sidecar_path, lines)
                    job["lang"] = language
                    job["langs"] = [language] if language else []
                else:
                    with note.open(encoding="utf-8", newline="") as stream:
                        note_text = stream.read()
                    if kind == "transcripts":
                        audio = _vault_path(vault, job["audio"])
                        identifier = settings.get("tasks", {}).get("transcribe", {}).get("connection") or "studio"
                        connection = next((entry for entry in settings.get("connections", [])
                                           if entry["id"] == identifier), None)
                        job["engine"] = "local"
                        job.pop("studio_error", None)
                        if connection:
                            key = None
                            try:
                                base, key = connection_credentials(connection)
                                segments, language, languages = transcribe_studio(
                                    audio, base, key, lang=job.get("lang") or None)
                                job["engine"] = "studio"
                            except Exception as error:
                                job["studio_error"] = str(error).replace(key, "[redacted]") if key else str(error)
                        if job["engine"] == "local":
                            segments, language, languages = transcribe_local(
                                audio, model, lang=job.get("lang") or None,
                                diarize=diarize or job.get("diarize") is True,
                                studio_failed=connection is not None)
                        updated_note = apply_transcript(note_text, segments)
                        job["lang"] = language
                        job["langs"] = languages
                    else:
                        segments_sidecar = audio_v2.sidecar_path(vault, job["audio"])
                        sidecar = audio_v2.load_sidecar(segments_sidecar)
                        translations = sidecar.setdefault("translations", {})
                        updated_note, translations[job["target"]] = apply_translation(
                            note_text, job["source_lang"], job["target"], translate,
                            job.get("source_langs", [job["source_lang"]]),
                            previous=translations.get(job["target"]),
                            reread=lambda: read_note(note),
                            context=translation_context(sidecar))
                with note.open("w", encoding="utf-8", newline="") as stream:
                    stream.write(updated_note)
                if finish is not None:
                    audio_v2.finish_transcript(*finish)
                    context_stage(vault, job, note, *finish, settings, translate)
                    arbitration_stage(note, finish[0], settings)
                if kind == "translations":
                    audio_v2.save_sidecar(segments_sidecar, sidecar)
                    if getattr(translate, "last_model", None) is not None:
                        job["llm"] = translate.last_model
                if kind == "transcripts":
                    requeue_translations(vault, job)
                job["status"] = "done"
                job["finished_at"] = datetime.now(timezone.utc).isoformat()
                job.pop("error", None)
            except Exception as error:
                job["status"] = "failed"
                job["error"] = str(error)
            job_path.write_text(json.dumps(job, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    finally:
        write_heartbeat(vault, settings, state, state_path,
                        supplied_now if supplied_now is not None else clock(),
                        hostname or socket.gethostname, probe or probe_connection)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True, type=Path)
    parser.add_argument("--once", required=True, action="store_true")
    parser.add_argument("--model", default=None)
    parser.add_argument("--diarize", action="store_true", help="Label speakers using ECAPA embeddings")
    parser.add_argument("--state", type=Path, default=Path.home() / ".tylog-transcribe-state.json")
    args = parser.parse_args(argv)
    run_once(args.vault, model=args.model, state_path=args.state, diarize=args.diarize)


if __name__ == "__main__":
    main()
