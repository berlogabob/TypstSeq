import json
import subprocess
import sys
from pathlib import Path

import audio_metrics

LOOP = "não, " * 39 + "não!"

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
