#!/usr/bin/env python3
"""Tests for tool.repair_obsidian_headers.repair (stdlib only, pytest)."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from repair_obsidian_headers import repair  # noqa: E402


def block(inner_lines):
    """Wrap lines in a minimal #show: tylog.note.with( ... ) header block."""
    return "#show: tylog.note.with(\n" + "\n".join(inner_lines) + "\n)\n"


def esc(s):
    """Wrap *s* in an escaped-quote pair: backslash-quote ... backslash-quote."""
    return "\\" + '"' + s + "\\" + '"'


# The spec's source line for rule 1 (escaped quotes), built precisely:
#   2sp + title: " : <esc 01 — Introduction> <delimiter-quote> ,
RULE1_SRC = "  title: " + '"' + ":" + " " + esc("01 — Introduction") + '"' + ","
RULE1_DST = "  title: " + '"' + "01 — Introduction" + '"' + ","


def test_rule1_title_escaped_quotes():
    assert repair(block([RULE1_SRC])) == block([RULE1_DST])


def test_rule1_title_plain():
    src = block(['  title: ": Search Systems",'])
    dst = block(['  title: "Search Systems",'])
    assert repair(src) == dst


def test_rule2_tags_brackets():
    src = block(['  tags: (": [lecture, introduction, course-overview]", ),'])
    dst = block(['  tags: ("lecture", "introduction", "course-overview",),'])
    assert repair(src) == dst


def test_rule2_tags_hashes():
    src = block(['  tags: (": #a #b #c", ),'])
    dst = block(['  tags: ("a", "b", "c",),'])
    assert repair(src) == dst


def test_rule2_tags_dedupe_and_order():
    src = block(['  tags: (": #b #a #b #c", ),'])
    dst = block(['  tags: ("b", "a", "c",),'])
    assert repair(src) == dst


    src = block(
        [
            '  properties: ("import_format": "obsidian", "created": ": 2026-05-26", "module": ": 01"),'
        ]
    )
    dst = block(
        [
            '  properties: ("import_format": "obsidian", "created": "2026-05-26", "module": "01"),',
        ]
    )
    assert repair(src) == dst


def test_rule4_heading_drops_quotes():
    src = '= : "01 — Introduction"\n'
    dst = "= 01 — Introduction\n"
    assert repair(src) == dst


def test_rule4_heading_no_quotes():
    src = "= : Simple Heading\n"
    dst = "= Simple Heading\n"
    assert repair(src) == dst


def test_rule4_tags_double_brackets():
    src = "tags:: foo " + r"\[\[\]" + "\n"
    dst = "tags:: foo\n"
    assert repair(src) == dst


def test_repair_is_idempotent():
    once = repair(FULL_SAMPLE)
    twice = repair(once)
    assert once == twice


def test_clean_header_unchanged():
    src = block(['  title: "Ok",', '  tags: ("a",),'])
    assert repair(src) == src


def test_full_sample_header():
    assert repair(FULL_SAMPLE) == FULL_EXPECTED


FULL_SAMPLE = block(
    [
        '  id: "obs-1",',
        RULE1_SRC,
        '  kind: "note",',
        "  date: none,",
        '  tags: (": [lecture, introduction, course-overview]", ),',
        "  aliases: (),",
        "  project: none,",
        '  properties: ("import_format": "obsidian", "created": ": 2026-05-26", "module": ": 01"),'
    ]
)

FULL_EXPECTED = block(
    [
        '  id: "obs-1",',
        RULE1_DST,
        '  kind: "note",',
        "  date: none,",
        '  tags: ("lecture", "introduction", "course-overview",),',
        "  aliases: (),",
        "  project: none,",
        "  properties: (\"import_format\": \"obsidian\", \"created\": \"2026-05-26\", \"module\": \"01\"),",
    ]
)


if __name__ == "__main__":
    import pytest

    raise SystemExit(pytest.main([__file__, "-v"]))
