#!/usr/bin/env python3
"""Validate the private 90-query embedding benchmark pack."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

LANGS = ("en", "pt", "ru")
ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")


class PackError(ValueError):
    pass


def validate(path: Path) -> dict:
    seen = set()
    counts = {lang: 0 for lang in LANGS}
    cross = {lang: 0 for lang in LANGS}
    with path.open(encoding="utf-8") as stream:
        for line_no, line in enumerate(stream, 1):
            if not line.strip():
                raise PackError(f"line {line_no}: blank_record")
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                raise PackError(f"line {line_no}: invalid_json") from None
            if not isinstance(record, dict):
                raise PackError(f"line {line_no}: record_object_required")
            qid = record.get("query_id")
            if not isinstance(qid, str) or not ID.fullmatch(qid):
                raise PackError(f"line {line_no}: unsafe_query_id")
            if qid in seen:
                raise PackError(f"line {line_no}: duplicate_query_id")
            seen.add(qid)
            lang = record.get("query_language")
            if lang not in LANGS:
                raise PackError(f"line {line_no}: invalid_query_language")
            if not isinstance(record.get("query"), str) or not record["query"].strip():
                raise PackError(f"line {line_no}: empty_query")
            relevant = record.get("relevant")
            if not isinstance(relevant, list) or not relevant:
                raise PackError(f"line {line_no}: no_relevant_passage")
            other_language = False
            for passage in relevant:
                if not isinstance(passage, dict):
                    raise PackError(f"line {line_no}: passage_object_required")
                for key in ("chunk_id", "source_id"):
                    value = passage.get(key)
                    if not isinstance(value, str) or not ID.fullmatch(value):
                        raise PackError(f"line {line_no}: unsafe_{key}")
                start, end = passage.get("start"), passage.get("end")
                if (
                    isinstance(start, bool)
                    or not isinstance(start, int)
                    or start < 0
                    or isinstance(end, bool)
                    or not isinstance(end, int)
                    or end <= start
                ):
                    raise PackError(f"line {line_no}: invalid_offsets")
                passage_lang = passage.get("language")
                if passage_lang not in LANGS:
                    raise PackError(f"line {line_no}: invalid_passage_language")
                other_language |= passage_lang != lang
            counts[lang] += 1
            cross[lang] += other_language
    if len(seen) != 90:
        raise PackError("pack: query_count")
    if any(counts[lang] != 30 for lang in LANGS):
        raise PackError("pack: language_counts")
    if any(cross[lang] < 10 for lang in LANGS):
        raise PackError("pack: cross_language_counts")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return {
        "queries": 90,
        "en": 30,
        "pt": 30,
        "ru": 30,
        "cross_language": sum(cross.values()),
        "sha256": digest,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    args = parser.parse_args(argv)
    try:
        result = validate(args.input)
    except OSError:
        print("error: input_unavailable", file=sys.stderr)
        return 2
    except PackError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
