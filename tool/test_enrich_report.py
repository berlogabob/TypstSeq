import json

import enrich_report as report


def test_groups_case_forms_but_not_model_guesses(tmp_path):
    vault = tmp_path
    days = [
        ("2026-10-01", [{"surface": "Ромой", "type": "person", "line": 1, "hints": ["Роман"]},
                        {"surface": "Катя", "type": "person", "line": 1, "hints": ["Жаворонкова"]}]),
        ("2026-10-02", [{"surface": "Рома", "type": "person", "line": 1, "hints": ["Роман"]},
                        {"surface": "Жаворонкова", "type": "person", "line": 1}]),
        ("2026-10-03", [{"surface": "Рома", "type": "person", "line": 1},
                        {"surface": "Катя", "type": "person", "line": 1}]),
    ]
    for date, mentions in days:
        path = vault / "_system/enrich/mentions/daily/2026/10" / f"{date}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"schema": 1, "note": f"daily/2026/10/{date}.typ",
                                    "content_sha": "x", "mentions": mentions, "keywords": ["k"]}))
    text = report.report(vault)
    assert "| Рома | 3 | 0 |" in text
    assert "| Катя | 2 | 0 |" in text
    assert "| Жаворонкова | 1 | 0 |" in text
    assert "- Рома (person, 3 days, 0 pages)" in text
    assert "Often together" not in text  # 2 shared days is below the 3-day bar
