"""Personal Portuguese phrases from the logbook (plan: tool/championship/2026-11-24-pt-lang-bakeoff.md).

The LLM calls live here so the model competition (tool/championship/lang_bench) measures the prompts the worker ships.
`chat(messages, json_mode=False)` is the callable llm_chat() returns.
"""
import hashlib
import json
import re
from datetime import date, timedelta, timezone
from pathlib import Path

import transcribe_worker as worker

MODULE = "my-portuguese"
SCAN_DAYS = 14  # daily notes older than this are not looked at
QUIET_SECONDS = 600  # a daily note edited more recently is still being typed
# The tag as the app writes it: the tag call, or a typed hashtag kept as text ("\\#pt").
TAG = re.compile(r'(?:#tylog\.tag\("|\\#)(pt-ask-audio|pt-ask|pt-audio|pt)(?:"\)|(?![\w-]))')
# Forms a Portuguese person would not write. Also the competition's Brazilian count (tool/championship/lang_bench).
# ponytail: a fixed list; "Se ..." and "Nos ..." at a sentence start are not checked (they are also "if" and "in the").
BRAZILIAN = re.compile(
    r"\b(ônibus|trem|celular|banheiro|café da manhã|geladeira|suco|aposentad\w+|ducha|registro|time|tela|gol|"
    r"você|vocês|\w+[ôê][mn]ic[oa]s?)\b"
    r"|\b(estou|estás|está|estamos|estão|estava|estavam)\s+(?!quando\b|lindo\b|segundo\b)\w+ndo\b"
    r"|(^|[.?!—]\s+)(me|te|lhe)\s+\w+")

PT_PT = ("Write European Portuguese as spoken in Portugal (pt-PT), never Brazilian Portuguese: "
         "vocabulary, spelling, tu and você usage, pronoun placement, and 'estar a + infinitive' for ongoing actions.")


def brazilian(text):
    """The Brazilian forms found in `text`, as written."""
    return [match.group(0).strip(" .?!—") for match in BRAZILIAN.finditer(text.lower())]


def _ask(chat, system, lines, avoid=()):
    """The reply object for `lines` sent as JSON {id: text}; a reply that is not a JSON object raises ValueError."""
    if avoid:
        system += " Your previous answer used Brazilian forms: " + ", ".join(avoid) + ". Use the European forms."
    user = json.dumps({str(index): text for index, text in enumerate(lines)}, ensure_ascii=False)
    return worker._reply_object(chat([{"role": "system", "content": system}, {"role": "user", "content": user}],
                                     json_mode=True))


def _lines(reply, count):
    if not isinstance(reply, dict) or any(not isinstance(reply.get(str(index)), str) for index in range(count)):
        raise ValueError("Reply does not cover every line id")
    return [reply[str(index)].strip() for index in range(count)]


def to_portuguese(lines, source_lang, chat, avoid=()):
    """`lines` (ru or en) as European Portuguese, one output line per input line."""
    system = (f"Translate from {worker.LANGUAGE_NAMES.get(source_lang, source_lang)} into Portuguese. {PT_PT} "
              "Keep names. Informal speech to one person uses tu. No commentary. Input is a JSON object mapping "
              "line ids to lines; return only a JSON object with the same ids, each mapped to its translation.")
    return _lines(_ask(chat, system, lines, avoid), len(lines))


def correct(lines, chat, avoid=()):
    """A learner's Portuguese corrected: (lines, changes). A correct line comes back unchanged.
    changes is a list of {"from", "to", "why"}; a malformed entry is dropped."""
    system = ("A learner wrote these lines in Portuguese. Correct grammar, spelling and word choice. "
              f"{PT_PT} Change only what is wrong or Brazilian; a correct line must be returned exactly as "
              "written. Input is a JSON object mapping line ids to lines. Return only a JSON object: "
              '{"lines": {id: corrected line}, "changes": [{"from": wrong words, "to": corrected words, '
              '"why": reason in a few words}]}.')
    reply = _ask(chat, system, lines, avoid)
    changes = [{key: item[key].strip() for key in ("from", "to", "why")}
               for item in reply.get("changes") or []
               if isinstance(item, dict) and all(isinstance(item.get(key), str) for key in ("from", "to", "why"))]
    return _lines(reply.get("lines"), len(lines)), changes


def clean_line(raw):
    """A daily-note line as plain text: no bullet, time stamp, tag call or link markup."""
    text = TAG.sub("", raw)
    text = re.sub(r'#tylog\.[\w-]+\((?:"(?:\\.|[^"\\])*"|[^")])*\)\[([^\]]*)\]', r"\1", text)
    text = re.sub(r"^\s*(?:\\?[-+]\s+)?(?:\d{1,2}:\d{2}\s+)?", "", text)  # "\-": a dash the app kept as text
    return re.sub(r"\\(.)", r"\1", text).strip()


AUDIO = re.compile(r'#tylog\.attachment\("/?assets/audio/[^"]*?([^"/]+)\.\w+", kind: "audio"\)')


def transcript_rows(vault, recording):
    """The `== Transcript` rows of the audio note the worker wrote for a recording; [] until it exists."""
    note = Path(vault) / "notes" / f"Audio {recording}.typ"
    text = note.read_text(encoding="utf-8") if note.is_file() else ""
    return [row for row in text.partition("\n== Transcript\n")[2].split("\n== ")[0].splitlines() if row.strip()]


def tagged_blocks(text, vault=None):
    """[(lines, audio, ask)] for each #pt / #pt-audio / #pt-ask / #pt-ask-audio tag in a daily note.
    ask: the lines are a question about Portuguese, answered in a note of its own.

    A tagged voice recording stands for what was said: its rows are the transcript from its audio note, and
    the block is left for a later sweep while that transcript is not written yet.

    The block is the tagged line and the more-indented lines under it. A tag alone on its line belongs to the
    lines directly above it, up to a blank line."""
    rows = text.splitlines()
    indent = lambda row: len(row) - len(row.lstrip())  # noqa: E731
    blocks = []
    for index, row in enumerate(rows):
        tag = TAG.search(row)
        if not tag:
            continue
        if clean_line(row):
            last = index + 1
            while last < len(rows) and rows[last].strip() and indent(rows[last]) > indent(row):
                last += 1
            block = rows[index:last]
        else:
            first = index
            while first > 0 and rows[first - 1].strip() and not rows[first - 1].startswith(("=", "#show", ")")):
                first -= 1
            block = rows[first:index]
        spoken = [(row, AUDIO.search(row)) for row in block]
        block = [line for row, recording in spoken
                 for line in (transcript_rows(vault, recording[1]) if recording and vault else [row])]
        lines = [line for line in map(clean_line, block) if line]
        if lines and not any(recording and not transcript_rows(vault, recording[1]) for _, recording in spoken if vault):
            blocks.append((lines, tag.group(1).endswith("audio"), tag.group(1).startswith("pt-ask")))
    return blocks


def sweep(vault, now, state, force=False):
    """Queues a `phrases` job per tagged block of the recent daily notes. Returns the number created.

    Runs once a day from the processing time (processing.json audio.time, default 03:00) or on "process now":
    the phrases model is slow to load, so the jobs run as one batch and not all day."""
    local = now.astimezone()
    today = local.date()
    audio = worker._read_json(worker._settings_path_for(vault / "_system/settings/processing.json")).get("audio", {})
    start = audio.get("time") if re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", audio.get("time") or "") else "03:00"
    if not force and (local.strftime("%H:%M") < start or state.get("last_phrases_date") == today.isoformat()):
        return 0
    created = 0
    for back in range(SCAN_DAYS):
        day = (today - timedelta(days=back)).isoformat()
        note = vault / "daily" / day[:4] / day[5:7] / f"{day}.typ"
        if not note.is_file() or now.timestamp() - note.stat().st_mtime < QUIET_SECONDS:
            continue
        for lines, with_audio, ask in tagged_blocks(note.read_text(encoding="utf-8"), vault):
            key = hashlib.sha1(("ask\n" * ask + "\n".join(lines)).encode("utf-8")).hexdigest()[:8]
            phrase = f"{day}-{'ask-' * ask}{key}"
            path = worker._job_file(vault, "phrases", f"{day}\n{'ask-' * ask}{key}")
            path.parent.mkdir(parents=True, exist_ok=True)
            try:
                with path.open("x", encoding="utf-8") as stream:
                    json.dump({"note": note.relative_to(vault).as_posix(), "date": day, "phrase": phrase,
                               "lines": lines, "audio": with_audio, "ask": ask, "status": "queued", "auto": True,
                               "requested_at": now.astimezone(timezone.utc).isoformat()},
                              stream, ensure_ascii=False, indent=2)
                created += 1
            except FileExistsError:
                pass
    state["last_phrases_date"] = today.isoformat()
    return created


def phrase_settings(settings):
    """`settings` with the phrases task's model in the translate slot, which is what the worker's LLM calls read."""
    tasks = settings.get("tasks", {})
    return {**settings, "tasks": {**tasks, "translate": tasks.get("phrases") or tasks.get("translate", {})}}


def _european(make, lines):
    """make(lines, avoid) -> result whose Portuguese lines are result[0] if a tuple, else result. A line with a
    Brazilian form is asked again once, alone. Returns (result, {line index: forms still there})."""
    result = make(lines, ())
    out = list(result[0] if isinstance(result, tuple) else result)
    left = {}
    for index, line in enumerate(out):
        forms = brazilian(line)
        if forms:
            again = make([lines[index]], forms)
            out[index] = (again[0] if isinstance(again, tuple) else again)[0]
            if brazilian(out[index]):
                left[index] = brazilian(out[index])
    return (out, result[1]) if isinstance(result, tuple) else (out, []), left


def language(text, chat):
    """ISO 639-1 code of `text`. Not worker.detect_language: its 16-token reply limit is used up by a model that
    reasons before answering (Muse-Glimmer does, whatever the thinking switch says) and the reply comes back empty."""
    if worker.CYRILLIC.search(text):
        return "ru"
    reply = chat([{"role": "system", "content": "Reply with the ISO 639-1 code of the language of the user's text, "
                                                "lowercase, and nothing else."},
                  {"role": "user", "content": text[:500]}])
    code = reply.strip().strip(".'\"` ").lower()
    if not re.fullmatch(r"[a-z]{2}", code):
        raise ValueError(f"Language reply is not a code: {reply[:40]!r}")
    return code


def render(job, lang, portuguese, changes, translations, left):
    """The phrase note's Typst source."""
    esc = worker.escape_markup
    quoted = lambda text: json.dumps(text, ensure_ascii=False).replace("#", "\\u{23}")  # noqa: E731
    ident = f"{MODULE}-{job['phrase']}"
    title = portuguese[0] if len(portuguese[0]) <= 60 else portuguese[0][:57].rstrip() + "..."
    body = lambda lines: "\n\n".join(esc(line) for line in lines)  # noqa: E731
    parts = ['#import "/_system/tylog.typ" as tylog',
             f'#show: tylog.note.with(id: "{ident}", title: {quoted(title)}, kind: "note", project: "Português", '
             f'tags: ("português", "module-{MODULE}"), properties: ("source": "{job["date"]}", "lang": "{lang}"))',
             "",
             f'#tylog.task(id: "{ident}-task", text: {quoted(title)}, project: "Português")',
             "",
             f'From #tylog.ref-note("{job["date"]}")[{job["date"]}]',
             "", "== Original", "", body(job["lines"]), "",
             "== Corrected" if lang == "pt" else "== Translation pt", "", body(portuguese)]
    if left:
        parts += ["", "#emph[Not checked as European Portuguese: " + esc(", ".join(sorted({f for v in left.values() for f in v}))) + "]"]
    if lang == "pt":
        parts += ["", "== Changes", ""]
        parts += [f"- {esc(c['from'])} → {esc(c['to'])}: {esc(c['why'])}" for c in changes] or ["No changes."]
    for target, lines in translations.items():
        parts += ["", f"== Translation {target}", "", body(lines)]
    return "\n".join(parts) + "\n"


ASK_LABELS = {"ru": ("По-португальски", "Произношение", "Перевод"), "en": ("Portuguese", "Say it", "Meaning")}


def answer(lines, lang, chat):
    """The answer to a learner's question about Portuguese, in the question's language:
    {"title", "answer": [paragraphs], "replies": [{"pt", "say", "meaning"}], "pick", "why"}.
    A reply entry that is not three strings is dropped; a reply that is not a JSON object raises ValueError."""
    name = worker.LANGUAGE_NAMES.get(lang, lang)
    system = (f"A learner of European Portuguese asks a question in {name}. Answer it in {name}, briefly, as a "
              f"teacher who lives in Portugal. {PT_PT} Return only a JSON object: "
              '{"title": the Portuguese words the question is about, "answer": [short paragraphs: what it means '
              'and when it is used], "replies": [{"pt": a Portuguese phrase, "say": how to pronounce it, written '
              f'in {name} letters, "meaning": its meaning in {name}}}] (natural answers or examples, 3 to 6), '
              '"pick": the one phrase from replies you would use with colleagues, "why": one sentence}.')
    reply = worker._reply_object(chat([{"role": "system", "content": system},
                                       {"role": "user", "content": "\n".join(lines)}], json_mode=True))
    if not isinstance(reply, dict):
        raise ValueError("Answer is not a JSON object")
    text = lambda key: reply.get(key).strip() if isinstance(reply.get(key), str) else ""  # noqa: E731
    paragraphs = reply.get("answer")
    paragraphs = [paragraphs] if isinstance(paragraphs, str) else paragraphs or []
    replies = [{key: item[key].strip() for key in ("pt", "say", "meaning")}
               for item in reply.get("replies") or []
               if isinstance(item, dict) and all(isinstance(item.get(key), str) for key in ("pt", "say", "meaning"))]
    if not replies and not any(isinstance(p, str) and p.strip() for p in paragraphs):
        raise ValueError("Answer has neither text nor replies")
    return {"title": text("title"), "answer": [p.strip() for p in paragraphs if isinstance(p, str) and p.strip()],
            "replies": replies, "pick": text("pick"), "why": text("why")}


def render_answer(job, lang, reply, left):
    """The answer note's Typst source. The day page lists it under its linked references."""
    esc = worker.escape_markup
    quoted = lambda text: json.dumps(text, ensure_ascii=False).replace("#", "\\u{23}")  # noqa: E731
    ident = f"{MODULE}-{job['phrase']}"
    title = reply["title"] or job["lines"][0]
    title = title if len(title) <= 60 else title[:57].rstrip() + "..."
    parts = ['#import "/_system/tylog.typ" as tylog',
             f'#show: tylog.note.with(id: "{ident}", title: {quoted(title)}, kind: "note", project: "Português", '
             f'tags: ("português", "pt-ask", "module-{MODULE}"), properties: ("source": "{job["date"]}", '
             f'"lang": "{lang}"))',
             "",
             f'From #tylog.ref-note("{job["date"]}")[{job["date"]}]',
             "", "== Question", "", "\n\n".join(esc(line) for line in job["lines"]),
             "", "== Answer", "", "\n\n".join(esc(p) for p in reply["answer"])]
    if reply["replies"]:
        head = ASK_LABELS.get(lang, ASK_LABELS["en"])
        cells = [f"[*{esc(label)}*]" for label in head]
        cells += [f"[{esc(item[key])}]" for item in reply["replies"] for key in ("pt", "say", "meaning")]
        parts += ["", "== Replies", "", "#table(columns: 3, " + ", ".join(cells) + ")"]
    if left:
        parts += ["", "#emph[Not checked as European Portuguese: " + esc(", ".join(sorted({f for v in left.values() for f in v}))) + "]"]
    if reply["pick"]:
        parts += ["", "== Use", "", f"*{esc(reply['pick'])}*" + (f" — {esc(reply['why'])}" if reply["why"] else "")]
        parts += ["", f'#tylog.task(id: "{ident}-task", text: {quoted(reply["pick"])}, project: "Português")']
    return "\n".join(parts) + "\n"


def record_file(vault, relative):
    """Adds or refreshes `relative` in the personal module's record, which lists the module in the app."""
    path = vault / "_system/modules" / f"{MODULE}.json"
    record = worker._read_json(path) or {"id": MODULE, "name": "Meu português", "version": "1", "unit": "phrases",
                                         "files": {}}
    record["files"][relative] = hashlib.sha256((vault / relative).read_bytes()).hexdigest()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(record, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def run_job(vault, job, settings):
    """Writes the phrase note of a `phrases` job and, for #pt-audio, queues its `phrase-audio` job.
    ponytail: a re-run rewrites the whole note; edits made to it in the app are lost. Merge sections if that hurts."""
    settings = phrase_settings(settings)
    lines = job["lines"]
    # 8000: a reasoning model spent the default 3000 thinking about a five-line dialogue and answered nothing.
    model, chat = worker.llm_chat(settings, max_tokens=8000)
    lang = language("\n".join(lines), chat)
    if job.get("ask"):
        return _run_ask(vault, job, lang, chat, model)
    if lang == "pt":
        (portuguese, changes), left = _european(lambda rows, avoid: correct(rows, chat, avoid), lines)
    else:
        (portuguese, changes), left = _european(lambda rows, avoid: to_portuguese(rows, lang, chat, avoid), lines)
    source, source_lang = (portuguese, "pt") if lang == "pt" else (lines, lang)
    translations = {target: worker.translate(source, source_lang, target, settings=settings)
                    for target in ("ru", "en") if target != lang}
    relative = f"projects/{MODULE}/{job['phrase']}.typ"
    target = vault / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render(job, lang, portuguese, changes, translations, left), encoding="utf-8")
    record_file(vault, relative)
    job.update(lang=lang, llm=model, phrase_note=relative, portuguese=portuguese)
    if left:
        job["brazilian"] = sorted({form for forms in left.values() for form in forms})
    if job.get("audio"):
        _queue_audio(vault, job, relative, portuguese)


def _queue_audio(vault, job, relative, lines):
    path = worker._job_file(vault, "phrase-audio", job["phrase"])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"note": relative, "phrase": job["phrase"], "lines": lines,
                                "status": "queued", "auto": True, "requested_at": job["requested_at"]},
                               ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _run_ask(vault, job, lang, chat, model):
    """Writes the answer note of a #pt-ask job; for #pt-ask-audio, queues a clip of the replies.
    The answer is asked again once when a reply uses a Brazilian form; forms still there are flagged."""
    reply = answer(job["lines"], lang, chat)
    left = {index: brazilian(item["pt"]) for index, item in enumerate(reply["replies"]) if brazilian(item["pt"])}
    if left:
        again = answer(job["lines"] + ["(" + PT_PT + " Avoid: " + ", ".join(f for v in left.values() for f in v) + ")"],
                       lang, chat)
        again_left = {i: brazilian(item["pt"]) for i, item in enumerate(again["replies"]) if brazilian(item["pt"])}
        if again["replies"] and len(again_left) < len(left):
            reply, left = again, again_left
    relative = f"projects/{MODULE}/{job['phrase']}.typ"
    target = vault / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render_answer(job, lang, reply, left), encoding="utf-8")
    record_file(vault, relative)
    portuguese = [item["pt"] for item in reply["replies"]]
    job.update(lang=lang, llm=model, phrase_note=relative, portuguese=portuguese)
    if left:
        job["brazilian"] = sorted({form for forms in left.values() for form in forms})
    if job.get("audio") and portuguese:
        _queue_audio(vault, job, relative, portuguese)


if __name__ == "__main__":
    demo = '- 10:05 Fui ao médico #tylog.tag("pt-audio")\n  - Médico: Bom dia\n- other\n\nХочу кофе\n#tylog.tag("pt")\n'
    assert tagged_blocks(demo) == [(["Fui ao médico", "Médico: Bom dia"], True, False), (["Хочу кофе"], False, False)]
    assert tagged_blocks("Таш бэйм?\nКак отвечать?\n\\#pt-ask\n") == [(["Таш бэйм?", "Как отвечать?"], False, True)]
    assert clean_line('- #tylog.ref-note("x")[Rui] disse \\#olá') == "Rui disse #olá"
    assert brazilian("Me chamo Alex. Você tem um celular?") == ["me chamo", "você", "celular"]
    assert not brazilian("Se chover, fico em casa. Está lindo! Nos dias de sol estou a trabalhar.")
    print("ok")
