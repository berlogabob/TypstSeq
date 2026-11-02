import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

import audio_metrics
import audio_v2 as v2

LOOP ="não, " * 39 + "não!"

FIXTURE = f"""= Fixture

== Comments

- 00:10 a comment that must not count

== Transcript

- 00:00 Olá, tudo bem com você?
- 00:05 {LOOP}
- 00:40 [—]
- 01:00 (?) Acho que a ponte fica lá em cima
- 01:10 Vamos embora agora
- 01:20 Até amanhã.

== Translation ru

- 00:00 Ты в порядке?
- 00:05 Нет, это не так.
- 00:40 [—]
- 01:00 (?) Я думаю, мост там наверху
- 01:10 Vamos embora agora
- 01:20 Maybe later
"""


def test_metrics_counts_baseline_error_classes():
    m = audio_metrics.note_metrics(FIXTURE)
    assert m["lines"] == 6
    assert m["loops"] == 1
    assert m["mid_cut"] == 2
    assert m["nonspeech"] == 1
    assert m["doubtful"] == 1
    assert m["translations"]["ru"] == {"lines": 6, "untranslated": 2, "failed": 0}


def test_translation_rules_per_language():
    note = """== Transcript

- 00:00 Olá, tudo bem?
- 00:05 Vamos embora
- 00:40 [—]
- 01:00 Até amanhã.

== Translation en

- 00:00 Olá, tudo bem?
- 00:05 Let's go
- 00:40 [—]
- 01:00 [sem tradução]
"""
    m = audio_metrics.note_metrics(note)
    assert m["translations"] == {"en": {"lines": 4, "untranslated": 1, "failed": 1}}


def test_metrics_counts_marked_failed_lines():
    note = """== Translation ru

- 00:00 (?) [sem tradução]
- 00:05 (?) \\[sem tradução\\]
- 00:10 [sem tradução]
- 00:15 \\[sem tradução\\]
- 00:20 Привет, как дела у всех?

== Translation en

- 00:00 (?) [sem tradução]
- 00:05 (?) \\[sem tradução\\]
"""
    m = audio_metrics.note_metrics(note)
    assert m["translations"] == {
        "ru": {"lines": 5, "untranslated": 0, "failed": 4},
        "en": {"lines": 2, "untranslated": 0, "failed": 2},
    }


def test_empty_note_has_zero_counts():
    assert audio_metrics.note_metrics("= Empty\n") == {
        "lines": 0,
        "loops": 0,
        "mid_cut": 0,
        "nonspeech": 0,
        "doubtful": 0,
        "translations": {},
    }


def test_cli_prints_one_json_line(tmp_path):
    note = tmp_path / "note.typ"
    note.write_text(FIXTURE, encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(Path(audio_metrics.__file__)), str(note)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert len(lines) == 1
    assert json.loads(lines[0]) == audio_metrics.note_metrics(FIXTURE)


def test_metrics_mean_score(tmp_path):
    sidecar = {"translations": {"ru": {"lines": [], "scores": {"0": 5, "1": 2, "2": 4}}}}
    assert audio_metrics.note_metrics(FIXTURE, sidecar)["translations"]["ru"]["mean_score"] == 3.67
    assert "mean_score" not in audio_metrics.note_metrics(FIXTURE)["translations"]["ru"]
    assert "mean_score" not in audio_metrics.note_metrics(FIXTURE, {"translations": {"ru": []}})["translations"]["ru"]
    note = tmp_path / "note.typ"
    note.write_text(FIXTURE, encoding="utf-8")
    sidecar_file = tmp_path / "sidecar.json"
    sidecar_file.write_text(json.dumps(sidecar), encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(Path(audio_metrics.__file__)), str(note), str(sidecar_file)],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)["translations"]["ru"]["mean_score"] == 3.67


def test_regions_merge_up_to_25s_and_split_at_longest_pause():
    speech = [(0, 10), (10.5, 20), (22, 30), (30.2, 40)]
    items = v2.plan_chunks(speech, total=40)
    assert [(i["start"], i["end"]) for i in items if i["kind"] == "speech"] == [(0, 20), (22, 40)]


def test_long_gap_becomes_gap_item_short_gap_does_not():
    items = v2.plan_chunks([(0, 5), (12, 15), (16, 20)], total=20)
    assert [i["kind"] for i in items] == ["speech", "gap", "speech"]


def test_single_region_longer_than_max_is_split_evenly():
    items = v2.plan_chunks([(0, 60)], total=60)
    assert all(i["end"] - i["start"] <= 25 for i in items) and items[-1]["end"] == 60


def test_short_recording_one_chunk():
    assert v2.plan_chunks([(0.3, 3.9)], total=4.2) == [{"start": 0.3, "end": 3.9, "kind": "speech"}]


def test_no_speech_is_one_gap():
    assert v2.plan_chunks([], total=300) == [{"start": 0, "end": 300, "kind": "gap"}]


@pytest.mark.parametrize("text", [
    "É isso aí! " * 40,
    "Não, " * 80,
    "A CIDADE NO BRASIL " * 30,
    "." * 300,
    "Legenda por Sônia Ruberti",
    "Legendas pela comunidade Amara.org",
    "Obrigado.",
])
def test_garbage_is_flagged(text):
    assert v2.is_hallucination(text)


@pytest.mark.parametrize("text", [
    "Nasci no seio de uma família muito respeitada.",
    "Não, não. O que quer dizer? Vai com calma.",
])
def test_speech_is_kept(text):
    assert not v2.is_hallucination(text)


@pytest.mark.parametrize("text", ["É isso aí! " * 40, "Legendas pela comunidade Amara.org", "Obrigado."])
def test_song_filter_drops_runaway_loops_and_credits(text):
    assert v2.is_hallucination(text, song=True)


def test_song_filter_keeps_repeated_chorus_lines():
    chorus = "Back to black. Back to black. Back to black. Back to black."
    assert not v2.is_hallucination(chorus, song=True)
    assert v2.is_hallucination(chorus)


def test_sentences_get_proportional_times_and_short_ones_join():
    lines = v2.sentence_lines(100.0, 120.0, "Toda. Menos. Eu. A minha família comunica muito através do humor.")
    assert lines[0] == (100.0, "Toda. Menos. Eu.")
    assert lines[1][0] > 100.0 and lines[1][1].startswith("A minha")


def test_text_without_punctuation_is_one_line():
    assert v2.sentence_lines(5.0, 9.0, "olá a todos") == [(5.0, "olá a todos")]


def test_short_last_sentence_joins_previous():
    assert v2.sentence_lines(0.0, 10.0, "A casa é grande. Sim.") == [(0.0, "A casa é grande. Sim.")]


def _seg(start, text, status="ok", kind="speech"):
    return {"start": start, "kind": kind, "text": text, "status": status}


def test_untouched_lines_are_rewritten():
    note, lines = v2.merge_section("= Note\n", "Transcript", [_seg(5.0, "old text")])
    lines[0]["text"] = "new text"
    note, lines = v2.merge_section(note, "Transcript", lines)
    assert "- 00:05 new text\n" in note and "old text" not in note
    assert lines[0]["rendered"]["Transcript"] == "- 00:05 new text"


def test_edited_line_is_kept_and_marked_user():
    note, lines = v2.merge_section("= Note\n", "Transcript", [_seg(5.0, "old text")])
    note = note.replace("- 00:05 old text", "- 00:05 old text, fixed by me")
    note, lines = v2.merge_section(note, "Transcript", lines)
    assert "- 00:05 old text, fixed by me" in note
    assert lines[0]["status"] == "user" and lines[0]["text"] == "old text, fixed by me"
    lines[0]["text"] = "asr says something else"  # the worker re-runs
    again, lines = v2.merge_section(note, "Transcript", lines)
    assert "- 00:05 old text, fixed by me" in again and "asr says" not in again


def test_deleted_line_stays_deleted():
    note, lines = v2.merge_section("= Note\n", "Transcript", [_seg(5.0, "gone soon"), _seg(10.0, "stays")])
    note = note.replace("- 00:05 gone soon\n", "")
    note, lines = v2.merge_section(note, "Transcript", lines)
    assert "gone soon" not in note and "stays" in note
    assert [line["status"] for line in lines] == ["deleted", "ok"]
    note, lines = v2.merge_section(note, "Transcript", lines)
    assert "gone soon" not in note


def test_user_added_line_is_kept_in_time_order():
    note, lines = v2.merge_section("= Note\n", "Transcript", [_seg(0.0, "first"), _seg(10.0, "third")])
    note = note.replace("- 00:10 third", "- 00:05 my line\n- 00:10 third")
    note, lines = v2.merge_section(note, "Transcript", lines)
    body = [line for line in note.splitlines() if line.startswith("- ")]
    assert body == ["- 00:00 first", "- 00:05 my line", "- 00:10 third"]
    assert any(line["status"] == "user" and line["text"] == "my line" and line["start"] == 5.0
               for line in lines)


def test_two_lines_same_second_keep_order():
    note, lines = v2.merge_section("= Note\n", "Transcript", [_seg(5.0, "first"), _seg(5.0, "second")])
    note = note.replace("- 00:05 first", "- 00:05 first, edited")
    note, lines = v2.merge_section(note, "Transcript", lines)
    assert [line for line in note.splitlines() if line.startswith("- 00:05")] == [
        "- 00:05 first, edited", "- 00:05 second"]
    note, lines = v2.merge_section(note, "Transcript", lines)
    assert [line for line in note.splitlines() if line.startswith("- 00:05")] == [
        "- 00:05 first, edited", "- 00:05 second"]


def test_rerun_drops_new_lines_inside_user_span():
    note, lines = v2.merge_section("= Note\n", "Transcript", [_seg(60.0, "A"), _seg(80.0, "B")])
    note = note.replace("- 01:00 A", "- 01:00 A, corrigido")
    note, lines = v2.merge_section(note, "Transcript", lines)
    lines[1]["text"] = "B2"  # the next line is re-run and written as usual
    lines += [_seg(60.0, "fresh 1"), _seg(65.0, "fresh 2"), _seg(72.0, "fresh 3")]
    note, lines = v2.merge_section(note, "Transcript", lines)
    assert [line for line in note.splitlines() if line.startswith("- ")] == [
        "- 01:00 A, corrigido", "- 01:20 B2"]


def test_last_user_line_pins_at_most_20s():
    note, lines = v2.merge_section("= Note\n", "Transcript", [_seg(60.0, "A")])
    note = note.replace("- 01:00 A", "- 01:00 A, corrigido")
    note, lines = v2.merge_section(note, "Transcript", lines)
    lines += [_seg(65.0, "run 1"), _seg(90.0, "run 2"), _seg(120.0, "run 3")]
    note, lines = v2.merge_section(note, "Transcript", lines)
    assert [line for line in note.splitlines() if line.startswith("- ")] == [
        "- 01:00 A, corrigido", "- 01:30 run 2", "- 02:00 run 3"]


def test_rerun_keeps_lines_outside_user_span():
    note, lines = v2.merge_section("= Note\n", "Transcript",
                                   [_seg(30.0, "pre"), _seg(60.0, "A"), _seg(80.0, "B")])
    note = note.replace("- 01:00 A", "- 01:00 A, corrigido")
    note, lines = v2.merge_section(note, "Transcript", lines)
    lines += [_seg(50.0, "before"), _seg(80.0, "boundary"), _seg(85.0, "after")]
    note, lines = v2.merge_section(note, "Transcript", lines)
    assert [line for line in note.splitlines() if line.startswith("- ")] == [
        "- 00:30 pre", "- 00:50 before", "- 01:00 A, corrigido", "- 01:20 B",
        "- 01:20 boundary", "- 01:25 after"]


def test_special_chars_escaped_and_parse_back():
    text = "#tag [x] $5 *a* _b_ @c"
    note, lines = v2.merge_section("= Note\n", "Transcript", [_seg(3.0, text)])
    body = next(line for line in note.splitlines() if line.startswith("- 00:03 "))[len("- 00:03 "):]
    assert body == r"\#tag \[x\] \$5 \*a\* \_b\_ \@c"
    assert re.sub(r"\\(.)", r"\1", body) == text
    again, _ = v2.merge_section(note, "Transcript", lines)
    assert again.count("- 00:03 ") == 1


def test_gap_and_doubtful_markers_and_section_placement():
    note = "= Note\n\n== Comments\n\n- 00:10 keep me\n"
    lines = [_seg(40.0, "", kind="gap"), dict(_seg(60.0, "Acho que a ponte", status="doubtful"), doubt_mark=True)]
    note, _ = v2.merge_section(note, "Transcript", lines)
    assert note == ("= Note\n\n== Comments\n\n- 00:10 keep me\n\n"
                    "== Transcript\n\n- 00:40 [—]\n- 01:00 (?) Acho que a ponte\n")


def test_existing_section_is_replaced_before_next_heading():
    note, lines = v2.merge_section("== Transcript\n", "Transcript", [_seg(1.0, "old")])
    note += "\n== Translation ru\n\n- 00:01 Привет\n"
    lines[0]["text"] = "new"
    note, _ = v2.merge_section(note, "Transcript", lines)
    assert note == "== Transcript\n\n- 00:01 new\n\n== Translation ru\n\n- 00:01 Привет\n"


def test_backup_legacy_writes_v1_once(tmp_path):
    audio = "assets/audio/take.m4a"
    legacy = "== Transcript\n\n- 00:01 old\n"
    path = v2.backup_legacy(tmp_path, audio, legacy)
    expected = tmp_path / "_system/jobs/segments" / (hashlib.sha1(audio.encode("utf-8")).hexdigest() + ".v1.typ")
    assert path == expected and path.read_text(encoding="utf-8") == legacy
    assert v2.backup_legacy(tmp_path, audio, "changed") is None
    assert path.read_text(encoding="utf-8") == legacy


def test_backup_legacy_is_noop_once_sidecar_exists(tmp_path):
    audio = "assets/audio/take.m4a"
    v2.save_sidecar(v2.sidecar_path(tmp_path, audio), {"lines": [], "stages": {}})
    assert v2.backup_legacy(tmp_path, audio, "legacy") is None
    assert not list((tmp_path / "_system/jobs/segments").glob("*.v1.typ"))


def test_sidecar_defaults_and_round_trip(tmp_path):
    path = v2.sidecar_path(tmp_path, "assets/audio/take.m4a")
    assert path.parent == tmp_path / "_system/jobs/segments" and path.suffix == ".json"
    assert v2.load_sidecar(path) == {"lines": [], "stages": {}}
    data = {"lines": [_seg(1.0, "olá")], "stages": {"transcript": "done"}}
    v2.save_sidecar(path, data)
    assert v2.load_sidecar(path) == data
    assert not path.with_name(path.name + ".tmp").exists()


def _chunk(start, end, asr, asr_alt=None):
    chunk = {"start": start, "end": end, "kind": "speech", "asr": asr}
    if asr_alt is not None:
        chunk["asr_alt"] = asr_alt
    return chunk


def test_agreement_ignores_case_and_punctuation():
    assert v2.agreement("Não, não. Vai!", "não NÃO vai") == 1.0
    assert v2.agreement("Olá mundo", "tchau") == 0.0
    assert v2.agreement("a b c d", "a b c x") == 0.75


def test_low_agreement_makes_chunk_lines_doubtful():
    chunks = [
        _chunk(0.0, 6.0, "Olá, tudo bem com você? Vamos embora agora.", "tchau mundo"),
        _chunk(6.0, 9.0, "Até amanhã, meu amigo.", "Até amanhã, meu amigo."),
    ]
    lines = v2.lines_from_chunks(chunks)
    assert [(line["text"], line["status"]) for line in lines] == [
        ("Olá, tudo bem com você?", "doubtful"),
        ("Vamos embora agora.", "doubtful"),
        ("Até amanhã, meu amigo.", "ok"),
    ]
    note, _ = v2.merge_section("= Note\n", "Transcript", lines)
    assert "(?)" not in note  # no arbitration verdict: status doubtful, no mark (see the doubt_mark tests)


def test_doubtful_with_high_agreement_has_no_marker():
    # Arbitration doubts this chunk, but the engines agree (0.77): the line keeps status doubtful, no (?).
    chunks = [_chunk(0.0, 6.0, "Nasci no seio de uma família.", "Nasci no seio de uma familia, sim.")]
    reply = json.dumps({"text": "Nasci no seio de uma família.", "status": "doubtful"})
    v2.arbitrate_chunks(chunks, [], "", [], lambda messages: reply)
    lines = v2.lines_from_chunks(chunks)
    assert [(line["text"], line["status"]) for line in lines] == [("Nasci no seio de uma família.", "doubtful")]
    note, _ = v2.merge_section("= Note\n", "Transcript", lines)
    assert "- 00:00 Nasci no seio de uma família.\n" in note and "(?)" not in note


def test_doubtful_with_low_agreement_has_marker():
    chunks = [_chunk(0.0, 6.0, "Olá, tudo bem com você?", "tchau mundo")]
    reply = json.dumps({"text": "Olá, tudo bem com você?", "status": "doubtful"})
    v2.arbitrate_chunks(chunks, [], "", [], lambda messages: reply)
    note, _ = v2.merge_section("= Note\n", "Transcript", v2.lines_from_chunks(chunks))
    assert "- 00:00 (?) Olá, tudo bem com você?\n" in note


def test_missing_alt_not_doubtful():
    chunks = [_chunk(0.0, 6.0, "Olá, tudo bem com você?"),
              _chunk(6.0, 9.0, "Até amanhã, meu amigo.", "")]  # "" is what the Mac fallback stores
    assert [line["status"] for line in v2.lines_from_chunks(chunks)] == ["ok", "ok"]


CONTEXT_REPLY = json.dumps({
    "summary": "Uma peça sobre uma família de comediantes.",
    "scenes": [{"line": 1, "title": "Monólogo"}, {"line": 99, "title": "fora do intervalo"}],
    "glossary": [{"heard": "Baubo", "spelling": "Baubo", "ru": "Бубо"}],
    "references": [{"line": 2, "term": "Baubo", "explanation": "Figura do mito de Deméter."},
                   {"line": "3", "term": "Eleusis", "explanation": "Santuário."}],
})
SPEECH = [{"start": 0.0, "kind": "speech", "text": "Nasci no seio de uma família."},
          {"start": 5.0, "kind": "speech", "text": "Baubo fazia rir."},
          {"start": 9.0, "kind": "speech", "text": "Vamos embora."}]
CONTEXT_NOTE = "= Note\n\n== Context\n\nPeça: Medeia.\n\n== Transcript\n\n- 00:00 Nasci.\n- 00:05 Baubo fazia rir.\n"
CONTEXT = {"summary": "Resumo.", "scenes": [{"line": 1, "title": "Início"}],
           "glossary": [], "references": [{"line": 2, "term": "Baubo", "explanation": "Figura do mito."}]}


def test_context_reply_keeps_valid_items_and_drops_bad_line_numbers():
    result = v2.parse_context_reply(CONTEXT_REPLY, {1, 2, 3}, "ru")
    assert result["summary"] == "Uma peça sobre uma família de comediantes."
    assert result["scenes"] == [{"line": 1, "title": "Monólogo"}]
    assert result["glossary"] == [{"heard": "Baubo", "spelling": "Baubo", "ru": "Бубо"}]
    assert result["references"] == [{"line": 2, "term": "Baubo", "explanation": "Figura do mito de Deméter."}]


def test_fenced_context_reply_is_accepted():
    assert v2.parse_context_reply("```json\n" + CONTEXT_REPLY + "\n```", {1, 2, 3}, "ru")["scenes"]


@pytest.mark.parametrize("reply", [
    "Desculpe, não consigo.", "[]", json.dumps({"summary": 3}),
    json.dumps({"summary": "ok", "scenes": "Monólogo"}),
])
def test_malformed_context_reply_is_an_error(reply):
    with pytest.raises(ValueError, match="Context reply"):
        v2.parse_context_reply(reply, {1}, "ru")


def test_context_messages_carry_context_numbers_and_target_language():
    messages = v2.context_messages("Medeia, Eurípides.", "ru", [(1, "Olá."), (2, "Tchau.")])
    system, user = messages[0]["content"], messages[1]["content"]
    assert "Russian" in system and '"ru": string' in system
    assert user == "Context:\nMedeia, Eurípides.\n\nTranscript:\n[1] Olá.\n[2] Tchau."
    assert "(none)" in v2.context_messages("", "ru", [(1, "Olá.")])[1]["content"]


def test_glossary_keeps_heard_and_spelling():
    reply = json.dumps({"summary": "Resumo.", "glossary": [
        {"heard": "Deméria", "spelling": "Deméter", "ru": "Деметра"},
        {"heard": "Paulo", "spelling": "Paulo", "ru": "Паулу"},
        {"heard": "Goçambique", "spelling": "Moçambique", "ru": "Мозамбик"}]})
    assert v2.parse_context_reply(reply, {1}, "ru")["glossary"] == [
        {"heard": "Deméria", "spelling": "Deméter", "ru": "Деметра"},
        {"heard": "Paulo", "spelling": "Paulo", "ru": "Паулу"},
        {"heard": "Goçambique", "spelling": "Moçambique", "ru": "Мозамбик"}]
    # No spelling given: the heard form stands for it.
    reply = json.dumps({"summary": "Resumo.", "glossary": [{"heard": "Baubo", "ru": "Бубо"}]})
    assert v2.parse_context_reply(reply, {1}, "ru")["glossary"] == [
        {"heard": "Baubo", "spelling": "Baubo", "ru": "Бубо"}]


def test_context_pass_one_call_for_a_short_transcript():
    calls = []

    def chat(messages):
        calls.append(messages)
        return CONTEXT_REPLY

    result = v2.context_pass(SPEECH, "", "ru", chat)
    assert len(calls) == 1
    assert result["summary"] == "Uma peça sobre uma família de comediantes."
    assert [scene["line"] for scene in result["scenes"]] == [1]


def test_long_transcript_is_windowed_then_summaries_merged():
    speech = [{"start": float(i), "kind": "speech", "text": f"Linha {i}."}
              for i in range(v2.CONTEXT_WINDOW + 5)]
    calls = []

    def chat(messages):
        calls.append(messages)
        if messages[0]["content"].startswith("Combine the partial summaries"):
            return json.dumps({"summary": "Resumo final."})
        numbers = [int(n) for n in re.findall(r"^\[(\d+)\]", messages[1]["content"], re.M)]
        return json.dumps({"summary": f"Parte {numbers[0]}.",
                           "scenes": [{"line": numbers[0], "title": "Início"}],
                           "glossary": [{"heard": "Linha", "spelling": "Linha", "ru": "Строка"}],
                           "references": [{"line": numbers[-1], "term": f"T{numbers[0]}", "explanation": "x"}]})

    result = v2.context_pass(speech, "", "ru", chat)
    assert len(calls) == 3  # two windows, then one call to merge their summaries
    assert result["summary"] == "Resumo final."
    assert [scene["line"] for scene in result["scenes"]] == [1, v2.CONTEXT_WINDOW + 1]
    assert [ref["line"] for ref in result["references"]] == [v2.CONTEXT_WINDOW, v2.CONTEXT_WINDOW + 5]
    assert len(result["glossary"]) == 1  # the same term from both windows is kept once


def test_no_speech_means_no_llm_call():
    def chat(messages):
        raise AssertionError("no LLM call without speech")

    assert v2.context_pass([], "Contexto", "ru", chat) == {
        "summary": "", "scenes": [], "glossary": [], "references": []}


def test_section_text_reads_only_the_named_section():
    assert v2.section_text(CONTEXT_NOTE, "Context") == "Peça: Medeia."
    assert v2.section_text(CONTEXT_NOTE, "Summary") == ""


def test_context_sections_written_above_transcript_and_context_untouched():
    note, sections = v2.render_context(CONTEXT_NOTE, {}, {"pt": CONTEXT}, SPEECH)
    assert note == (
        "= Note\n\n== Context\n\nPeça: Medeia.\n\n"
        "== Summary pt\n\n- 00:00 Resumo.\n\n"
        "== Scenes pt\n\n- 00:00 Início\n\n"
        "== References pt\n\n- 00:05 Baubo -- Figura do mito. (AI)\n\n"
        "== Transcript\n\n- 00:00 Nasci.\n- 00:05 Baubo fazia rir.\n"
    )
    assert sections["Summary pt"][0]["text"] == "Resumo."


def test_reference_lines_marked_ai():
    note, _ = v2.render_context(CONTEXT_NOTE, {}, {"pt": dict(CONTEXT, references=[
        {"line": 1, "term": "A", "explanation": "one"}, {"line": 2, "term": "B", "explanation": "two"}])}, SPEECH)
    references = note.split("== References pt\n\n")[1].split("\n\n")[0].splitlines()
    assert references == ["- 00:00 A -- one (AI)", "- 00:05 B -- two (AI)"]


def test_context_section_never_written_by_render():
    note, _ = v2.render_context(CONTEXT_NOTE, {}, {"pt": CONTEXT}, SPEECH)
    assert note.split("== Summary")[0] == "= Note\n\n== Context\n\nPeça: Medeia.\n\n"


def test_user_edit_in_generated_line_survives_rerun():
    note, sections = v2.render_context(CONTEXT_NOTE, {}, {"pt": CONTEXT}, SPEECH)
    edited = note.replace("- 00:00 Resumo.", "- 00:00 Resumo meu.")
    again = dict(CONTEXT, summary="Resumo novo.", scenes=[{"line": 1, "title": "Abertura"}])
    note2, _ = v2.render_context(edited, sections, {"pt": again}, SPEECH)
    assert "- 00:00 Resumo meu.\n" in note2
    assert "Resumo novo" not in note2
    assert "- 00:00 Abertura\n" in note2 and "Início" not in note2


def test_generated_line_the_user_deleted_stays_deleted():
    note, sections = v2.render_context(CONTEXT_NOTE, {}, {"pt": CONTEXT}, SPEECH)
    note2, sections2 = v2.render_context(note.replace("- 00:00 Início\n", ""), sections, {"pt": CONTEXT}, SPEECH)
    assert "Início" not in note2
    assert sections2["Scenes pt"][0]["status"] == "deleted"
    assert "Início" not in v2.render_context(note2, sections2, {"pt": CONTEXT}, SPEECH)[0]


def test_generated_line_no_longer_produced_is_removed():
    note, sections = v2.render_context(CONTEXT_NOTE, {}, {"pt": CONTEXT}, SPEECH)
    note2, _ = v2.render_context(note, sections, {"pt": dict(CONTEXT, scenes=[])}, SPEECH)
    assert "Início" not in note2 and "== Scenes pt" in note2


def test_no_generated_sections_without_content():
    empty = {"summary": "", "scenes": [], "glossary": [], "references": []}
    note, _ = v2.render_context("= Note\n\n== Transcript\n\n- 00:00 Nasci.\n", {}, {"pt": empty}, SPEECH)
    assert note == "= Note\n\n== Transcript\n\n- 00:00 Nasci.\n"


# Task 12: arbitration of disputed chunks. The LLM is a fake chat(messages) -> reply text.

def test_guard_rejects_invented_words():
    invented = json.dumps({"text": "Nasci no seio de uma família nobre.", "status": "fixed"})
    for reply in (invented, "Nasci no seio de uma família nobre."):  # a bad JSON reply is refused the same way
        chunks = [_chunk(0.0, 6.0, "Nasci no seio de uma família.", "Nasci no seio de uma familia.")]
        v2.arbitrate_chunks(chunks, [], "", [], lambda messages: reply)
        assert chunks[0]["arbitration"] == {"text": "Nasci no seio de uma família.", "status": "doubtful"}
    lines = v2.lines_from_chunks(chunks)
    assert [(line["text"], line["status"]) for line in lines] == [("Nasci no seio de uma família.", "doubtful")]


def test_glossary_spelling_allowed():
    reply = json.dumps({"text": "A Baubo fazia rir.", "status": "fixed"})
    without = [_chunk(0.0, 6.0, "A Bobo fazia rir.", "A Bambo fazia rir.")]
    v2.arbitrate_chunks(without, [], "", [], lambda messages: reply)
    assert without[0]["arbitration"] == {"text": "A Bobo fazia rir.", "status": "doubtful"}

    with_glossary = [_chunk(0.0, 6.0, "A Bobo fazia rir.", "A Bambo fazia rir.")]
    glossary = [{"term": "Baubo", "spelling": "Baubo", "ru": "Бубо"}]
    v2.arbitrate_chunks(with_glossary, [], "", glossary, lambda messages: reply)
    assert with_glossary[0]["arbitration"] == {"text": "A Baubo fazia rir.", "status": "fixed"}


def test_old_glossary_items_still_load():
    # Sidecars from before `heard` hold {"term", "spelling", "ru"} items; arbitration reads their spelling.
    glossary = [{"term": "Baubo", "spelling": "Baubo", "ru": "Бубо"}]
    chunks = [_chunk(0.0, 6.0, "A Bobo fazia rir.", "A Bambo fazia rir.")]
    reply = json.dumps({"text": "A Baubo fazia rir.", "status": "fixed"})
    v2.arbitrate_chunks(chunks, [], "", glossary, lambda messages: reply)
    assert chunks[0]["arbitration"] == {"text": "A Baubo fazia rir.", "status": "fixed"}
    assert "Glossary spellings: Baubo" in v2.arbitration_messages("", glossary, [], "A", "B", [])[1]["content"]


def test_fixed_lines_lose_marker():
    chunks = [_chunk(0.0, 6.0, "Olá, tudo bem com você?", "tchau mundo")]  # no common word
    doubtful = json.dumps({"text": "Olá, tudo bem com você?", "status": "doubtful"})
    v2.arbitrate_chunks(chunks, [], "", [], lambda messages: doubtful)
    note, lines = v2.merge_section("= Note\n", "Transcript", v2.lines_from_chunks(chunks))
    assert "- 00:00 (?) Olá, tudo bem com você?\n" in note

    # The next run's arbitration says fixed: the rewritten note line loses its mark.
    chunks[0]["arbitration"] = {"text": "Olá, tudo bem?", "status": "fixed"}
    note, lines = v2.merge_transcript(note, lines, v2.lines_from_chunks(chunks))
    assert "(?)" not in note and "- 00:00 Olá, tudo bem?\n" in note


def test_user_edited_lines_untouched():
    chunks = [_chunk(0.0, 6.0, "Olá, tudo bem com você?", "tchau mundo"),
              _chunk(6.0, 9.0, "Nasci.", "Nasci no seio.")]
    note, lines = v2.merge_section("= Note\n", "Transcript", v2.lines_from_chunks(chunks))
    edited = note.replace("Olá, tudo bem com você?", "Olá, tudo bem com o Baubo?")
    note, lines = v2.merge_transcript(edited, lines, v2.lines_from_chunks(chunks))

    calls = []

    def chat(messages):
        calls.append(messages)
        return json.dumps({"text": "Nasci no seio.", "status": "fixed"})

    v2.arbitrate_chunks(chunks, lines, "", [], chat)
    assert len(calls) == 1 and "arbitration" not in chunks[0] and chunks[1]["arbitration"]["status"] == "fixed"
    note, _ = v2.merge_transcript(note, lines, v2.lines_from_chunks(chunks))
    assert "- 00:00 Olá, tudo bem com o Baubo?\n" in note
    assert "- 00:06 Nasci no seio.\n" in note and "com você" not in note
