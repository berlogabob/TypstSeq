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
    lines = [_seg(40.0, "", kind="gap"), _seg(60.0, "Acho que a ponte", status="doubtful")]
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
