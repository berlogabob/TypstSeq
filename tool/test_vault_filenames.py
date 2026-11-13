"""Temporary-vault tests for filename cleanup; never uses a real vault."""
import json
import os
import sys
import unicodedata
from pathlib import Path

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vault_filenames as vf  # noqa: E402


def put(root, rel, data=b"note bytes"):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    return p


def test_clean_stem_rules_and_idempotence():
    cases = {
        "Hello 😀 there": "Hello there",
        "A👩‍💻B": "AB",
        "Star️ name": "Star name",
        'a/b:c*?"<>|z': "abcz",
        "double   spaces": "double spaces",
        "trailing.": "trailing",
        "github.com -": "github.com",
    }
    for source, expected in cases.items():
        actual = vf.clean_stem(source)
        assert actual == expected
        assert vf.clean_stem(actual) == actual
    long = "example.com - " + "очень длинное имя " * 10
    result = vf.clean_stem(long)
    assert result.startswith("example.com - ") and len(result) <= 80
    assert vf.clean_stem(result) == result
    assert vf.clean_stem("x" * 100) == "x" * 80


def test_plan_suffix_collisions_and_recursive_skip(tmp_path):
    v = tmp_path / "vault"
    put(v, "notes/a (2).typ")
    put(v, "notes/b.typ")
    put(v, "notes/b (1).typ")
    put(v, "notes/c - (1).typ")
    put(v, "notes/name😀.typ")
    put(v, "notes/clean.typ")
    put(v, "notes/sub/illegal:name.typ")
    put(v, "notes/_private/secret😀.typ")
    put(v, "notes/.hidden/secret😀.typ")
    put(v, "notes/asset.pdf")
    # Several input names clean to the same destination.
    put(v, "notes/collision😀.typ")
    put(v, "notes/collision?.typ")
    put(v, "notes/collision*.typ")
    rows, skipped = vf.plan_with_skips(v)
    mapping = {x["old"]: x["new"] for x in rows}
    assert mapping["notes/a (2).typ"] == "notes/a.typ"
    assert mapping["notes/c - (1).typ"] == "notes/c.typ"
    assert mapping["notes/name😀.typ"] == "notes/name.typ"
    assert mapping["notes/sub/illegal:name.typ"] == "notes/sub/illegalname.typ"
    targets = [x for x in mapping.values() if x.startswith("notes/collision")]
    assert len(set(targets)) == 3
    assert {Path(x).stem for x in targets} == {"collision", "collision 2", "collision 3"}
    assert "notes/clean.typ" not in mapping
    assert "notes/asset.pdf" not in mapping
    assert not any("private" in x["old"] or ".hidden" in x["old"] for x in rows)
    assert skipped == []


def test_nfc_suffix_taken_skip_list_and_case_only(tmp_path):
    v = tmp_path / "v"
    nfd = unicodedata.normalize("NFD", "café")
    put(v, f"articles/{nfd}.typ")
    put(v, "articles/taken (2).typ")
    put(v, "articles/taken.typ")
    put(v, "articles/Case😀.typ")
    rows, skipped = vf.plan_with_skips(v, {"articles/Case😀.typ"})
    mapping = {x["old"]: x["new"] for x in rows}
    # The host filesystem stores the fixture in NFC even though NFD was passed
    # to write_bytes; exercise the pure transformation directly for NFD.
    assert vf.clean_stem(nfd) == "café"
    assert "articles/taken (2).typ" not in mapping  # suffix stays when plain name exists
    assert {"path": "articles/Case😀.typ", "reason": "skip-list"} in skipped
    assert any("nfc" in x["rules"] for x in rows)


def test_dry_run_apply_and_revert_roundtrip(tmp_path, monkeypatch):
    monkeypatch.setenv("VAULT_DEDUPE_SKIP_APP_CHECK", "1")
    v = tmp_path / "vault"
    original = b"#show: note\r\n" + bytes(range(32))
    put(v, "projects/Hello😀.typ", original)
    before = {p.relative_to(v).as_posix(): p.read_bytes() for p in v.rglob("*") if p.is_file()}
    rows = vf.plan(v)
    assert rows
    assert {p.relative_to(v).as_posix(): p.read_bytes() for p in v.rglob("*") if p.is_file()} == before
    backup, manifest = tmp_path / "backup", tmp_path / "manifest.json"
    doc = vf.apply_plan(v, rows, backup, manifest)
    assert len(doc["renames"]) == 1
    assert (v / "projects/Hello.typ").read_bytes() == original
    assert (backup / "projects/Hello😀.typ").read_bytes() == original
    assert json.loads(manifest.read_text())["renames"] == doc["renames"]
    result = vf.revert(manifest, v, apply=True)
    assert result["completed"] == 1
    assert (v / "projects/Hello😀.typ").read_bytes() == original
    assert not (v / "projects/Hello.typ").exists()


def test_apply_aborts_file_when_target_appears(tmp_path, monkeypatch):
    monkeypatch.setenv("VAULT_DEDUPE_SKIP_APP_CHECK", "1")
    v = tmp_path / "v"
    put(v, "notes/a😀.typ", b"source")
    row = vf.plan(v)[0]
    put(v, row["new"], b"target")
    doc = vf.apply_plan(v, [row], tmp_path / "backup", tmp_path / "manifest.json")
    assert doc["renames"] == []
    assert (v / row["old"]).read_bytes() == b"source"
    assert (v / row["new"]).read_bytes() == b"target"


def test_reference_updates_skip_check_and_revert(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("VAULT_DEDUPE_SKIP_APP_CHECK", "1")
    v = tmp_path / "vault"
    old = "notes/Ref😀.typ"
    put(v, old, b"body\r\n")
    put(v, "notes/Other😀.typ", b"other")
    put(v, "_system/jobs/articles/job.json", '{ "note_path" : "notes/Ref😀.typ", "keep":"\\u0061" }\n'.encode())
    put(v, "_system/reading/recent.json", '["notes/Ref😀.typ"]'.encode())
    put(v, "_system/enrich/feedback.jsonl", '{"note":"notes/Ref😀.typ","x":1}\n'.encode())
    side = "_system/enrich/mentions/notes/Ref😀.json"
    put(v, side, '{"note":"notes/Ref😀.typ"}'.encode())
    history = v / ".tylog/local-history" / __import__("hashlib").sha256(old.encode()).hexdigest()
    put(v, history.relative_to(v).as_posix(), b"history")
    put(v, "outputs/x.typ", '#include "/notes/Ref😀.typ"\r\n#include "notes/Ref😀.typ"\r\n'.encode())
    put(v, "custom/random.json", '{"path":"notes/Other😀.typ"}'.encode())
    before = {p.relative_to(v).as_posix(): p.read_bytes() for p in v.rglob("*") if p.is_file()}
    rows, skipped = vf.plan_with_skips(v)
    unhandled = vf.find_unhandled_refs(v, rows)
    assert "notes/Other😀.typ" in unhandled
    filtered, _ = vf.plan_with_skips(v, set(unhandled))
    assert "notes/Other😀.typ" not in {r["old"] for r in filtered}
    assert {p.relative_to(v).as_posix(): p.read_bytes() for p in v.rglob("*") if p.is_file()} == before
    row = next(r for r in filtered if r["old"] == old)
    backup, manifest = tmp_path / "backup", tmp_path / "manifest.json"
    doc = vf.apply_plan(v, [row], backup, manifest)
    new = row["new"]
    assert (v / "_system/jobs/articles/job.json").read_bytes() == f'{{ "note_path" : "{new}", "keep":"\\u0061" }}\n'.encode()
    assert (v / "outputs/x.typ").read_bytes() == f'#include "/{new}"\r\n#include "{new}"\r\n'.encode()
    assert (v / "_system/enrich/mentions" / (new[:-4] + ".json")).exists()
    assert (v / ".tylog/local-history" / __import__("hashlib").sha256(new.encode()).hexdigest()).read_bytes() == b"history"
    assert doc["ref_moves"]
    assert vf.main(["--check", str(manifest), str(v)]) == 0
    assert '"remaining": {}' in capsys.readouterr().out
    vf.revert(manifest, v, apply=True)
    after = {p.relative_to(v).as_posix(): p.read_bytes() for p in v.rglob("*") if p.is_file()}
    assert after == before

