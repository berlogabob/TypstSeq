import json

import enrich_worker as enrich
import enrich_prompt_stats as stats


def _vault(tmp_path):
    vault = tmp_path / "vault"
    day = vault / "daily/2026/10/22.typ"
    day.parent.mkdir(parents=True)
    day.write_text("- Café met Катя in Lisbon\n", encoding="utf-8")
    (vault / "_index").mkdir()
    index = {"notes": [
        {"id": "cafe", "title": "Café Dias", "kind": "organization", "aliases": ["Café"]},
        {"id": "katya", "title": "Екатерина", "kind": "person", "aliases": ["Катя"]},
        {"id": "lisbon", "title": "Lisbon", "kind": "place", "aliases": []},
        {"id": "gear", "title": "Lisbon gear", "kind": "equipment", "aliases": []},
    ]}
    (vault / "_index/index.json").write_text(json.dumps(index), encoding="utf-8")
    sidecar = vault / "_system/enrich/mentions/daily/2026/10/22.json"
    sidecar.parent.mkdir(parents=True)
    sidecar.write_text(json.dumps({"mentions": [{"entity": "katya"}, {"entity": "gear"}]}))
    return vault, day, index


def test_select_candidates_ranking_cap_recent_and_dedup():
    entities = [{"id": str(i), "title": title, "kind": "person", "aliases": aliases}
                for i, (title, aliases) in enumerate([
                    ("Alpha Beta Gamma", []), ("Alpha Beta", []), ("Gamma", []),
                    ("Delta", []), ("Café", []), ("Катя", [])])]
    lines = [(1, "- alpha beta gamma Café Катя")]
    got = enrich.select_candidates(lines, entities, recent=["5", "3", "3"], limit=4)
    assert [item["id"] for item in got] == ["0", "1", "2", "4"]
    recent_only = enrich.select_candidates([(1, "unmatched text")], entities,
                                           recent=["5", "3", "5"], limit=3)
    assert [item["id"] for item in recent_only] == ["5", "3"]
    assert len(enrich.select_candidates(lines, entities * 10, limit=30)) == 30


def test_folded_matching_and_recent_entity_ids(tmp_path):
    vault, day, index = _vault(tmp_path)
    entities = enrich.known_entities(index)
    chosen = enrich.select_candidates(enrich.body_lines(day.read_text()), entities)
    assert {e["id"] for e in chosen} == {"cafe", "katya", "lisbon"}
    prior = vault / "daily/2026/10/2026-10-21.typ"
    prior.write_text('#tylog.ref-note("Café Dias")[Café Dias]\n', encoding="utf-8")
    side = vault / "_system/enrich/mentions/daily/2026/10/2026-10-21.json"
    side.parent.mkdir(parents=True, exist_ok=True)
    side.write_text(json.dumps({"mentions": [{"entity": "lisbon"}]}))
    assert enrich.recent_entity_ids(vault, index, "2026-10-22") == ["lisbon", "cafe"]


def test_prompt_is_fixed_ordered_and_excludes_equipment():
    lines = [(1, "text")]
    candidates = [{"id": "a", "title": "A", "kind": "person", "aliases": []}]
    one = enrich.build_messages(lines, candidates)
    two = enrich.build_messages(lines, candidates, [{"id": "m", "title": "M", "examples": [], "not": []}])
    assert one[0]["content"] == two[0]["content"] == enrich.SYSTEM_PROMPT
    assert "MARKERS" in enrich.SYSTEM_PROMPT
    assert one[1]["content"].rfind("JOURNAL:") > one[1]["content"].find("CANDIDATE ENTITIES:")
    assert "equipment" not in one[1]["content"]


def test_stats_recall_and_read_only_main(tmp_path, capsys):
    vault, day, index = _vault(tmp_path)
    # Give the fixture a date inside the rolling window.
    today = stats.date.today()
    target = today - stats.timedelta(days=1)
    moved = vault / "daily" / f"{target:%Y/%m}/{target.isoformat()}.typ"
    moved.parent.mkdir(parents=True, exist_ok=True)
    moved.write_text(day.read_text(), encoding="utf-8")
    day.unlink()
    old_side = vault / "_system/enrich/mentions/daily/2026/10/22.json"
    old_side.unlink()
    side = vault / "_system/enrich/mentions" / moved.relative_to(vault).with_suffix(".json")
    side.parent.mkdir(parents=True, exist_ok=True)
    side.write_text(json.dumps({"mentions": [{"entity": "katya"}]}))
    before = sorted(str(p.relative_to(vault)) for p in vault.rglob("*"))
    rows = stats.collect(vault, 30)
    assert rows[0]["truth"] == rows[0]["hits"] == 1
    summary = stats.main(["--vault", str(vault), "--days", "30"])
    assert summary["recall_at_30_micro"] == 1
    assert summary["recall_days_counted"] == 1
    assert "recall@30 micro" in capsys.readouterr().out
    after = sorted(str(p.relative_to(vault)) for p in vault.rglob("*"))
    assert before == after
