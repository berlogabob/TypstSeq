import io
import json

import fill_worker as fill

PAGE = """#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "20261108-111220",
  title: "Конимбрига",
  kind: "place",
  aliases: ("Conímbriga",),
  properties: (:),
)

= Конимбрига
"""


class _Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def _opener(pages):
    def opener(request, timeout=0):
        url = request.full_url
        assert request.get_header("User-agent") == fill.USER_AGENT
        for key, value in pages.items():
            if key in url:
                return _Response(json.dumps(value).encode())
        return _Response(json.dumps(["", [], [], []]).encode())
    return opener


def _vault(tmp_path):
    (tmp_path / "notes").mkdir()
    (tmp_path / "notes/c.typ").write_text(PAGE, encoding="utf-8")
    requests = tmp_path / "_system/enrich/fill/requests"
    requests.mkdir(parents=True)
    (requests / "20261108-111220.json").write_text(json.dumps({"note": "notes/c.typ"}))
    return tmp_path


def test_process_drafts_from_sources_only(tmp_path):
    vault = _vault(tmp_path)
    opener = _opener({
        "pt.wikipedia.org/w/api.php": ["Conímbriga", ["Conímbriga"], [], []],
        "pt.wikipedia.org/api/rest_v1/page/summary/Con%C3%ADmbriga": {
            "title": "Conímbriga", "extract": "Cidade romana perto de Condeixa.",
            "content_urls": {"desktop": {"page": "https://pt.wikipedia.org/wiki/Con%C3%ADmbriga"}}},
    })
    seen = []

    def chat(messages):
        seen.append(messages)
        return (json.dumps({"properties": {"type": "ruins", "invented": "x", "period": ""},
                           "sections": {"Кратко": "Римский город.", "Other": "drop",
                                        "Посещение": "В предоставленных источниках отсутствует информация о посещении."}}),
                "ornith", "studio")

    assert fill.process(vault, chat, opener) == 1
    draft = json.loads((vault / "_system/enrich/fill/20261108-111220.json").read_text())
    assert draft["note"] == "notes/c.typ"
    assert draft["properties"] == {"type": "ruins"}
    assert draft["sections"] == {"Кратко": "Римский город."}
    assert draft["sources"] == ["https://pt.wikipedia.org/wiki/Con%C3%ADmbriga"]
    assert draft["model"] == "ornith"
    assert "Cidade romana" in seen[0][1]["content"]
    assert not list((vault / "_system/enrich/fill/requests").iterdir())


def test_nothing_found_and_failed_chat(tmp_path):
    vault = _vault(tmp_path)

    def broken(messages):
        raise ValueError("down")

    assert fill.process(vault, broken, _opener({})) == 1
    draft = json.loads((vault / "_system/enrich/fill/20261108-111220.json").read_text())
    assert draft["status"] == "not_found"

    (vault / "_system/enrich/fill/requests/x.json").write_text(json.dumps({"note": "notes/c.typ"}))
    opener = _opener({
        "w/api.php": ["C", ["C"], [], []],
        "page/summary": {"title": "C", "extract": "text"},
    })
    assert fill.process(vault, broken, opener) == 0
    assert (vault / "_system/enrich/fill/requests/x.json").exists(), "kept for the next run"


def test_request_outside_vault_is_dropped(tmp_path):
    vault = _vault(tmp_path)
    (vault / "_system/enrich/fill/requests/evil.json").write_text(json.dumps({"note": "../x.typ"}))
    fill.process(vault, lambda m: ("{}", "m", "c"), _opener({}))
    assert not (vault / "_system/enrich/fill/requests/evil.json").exists()
    assert not (vault / "_system/enrich/fill/evil.json").exists()


def test_kind_registry_template_wins(tmp_path):
    (tmp_path / "_system/settings").mkdir(parents=True)
    (tmp_path / "_system/settings/kinds.json").write_text(json.dumps(
        {"boat": {"fields": ["hull"], "sections": ["Summary"]}}))
    assert fill.template_for(tmp_path, "boat") == {"fields": ["hull"], "sections": ["Summary"]}
    assert fill.template_for(tmp_path, "place") == fill.DEFAULT_TEMPLATES["place"]


def test_language_links_and_fuzzy_hits():
    opener = _opener({
        "ru.wikipedia.org/w/api.php?action=opensearch": ["К", ["Конимбрига"], [], []],
        "ru.wikipedia.org/api/rest_v1/page/summary": {"title": "Конимбрига", "extract": "Римский город.",
                                                       "content_urls": {"desktop": {"page": "ru-url"}}},
        "ru.wikipedia.org/w/api.php?action=query": {"query": {"pages": [{"langlinks": [
            {"lang": "pt", "title": "Conímbriga"}]}]}},
        "pt.wikipedia.org/api/rest_v1/page/summary/Con%C3%ADmbriga": {
            "title": "Conímbriga", "extract": "Cidade romana.", "content_urls": {"desktop": {"page": "pt-url"}}},
        "pt.wikipedia.org/w/api.php?action=opensearch": ["К", ["Monomorium"], [], []],
    })
    found = fill.wikipedia(["Конимбрига"], opener)
    assert [(s["lang"], s["url"]) for s in found] == [("ru", "ru-url"), ("pt", "pt-url")]


def test_model_mismatch_is_reported(tmp_path):
    vault = _vault(tmp_path)
    opener = _opener({
        "w/api.php?action=opensearch": ["C", ["Конимбрига"], [], []],
        "page/summary": {"title": "Конимбрига", "extract": "A water mill."},
    })
    assert fill.process(vault, lambda m: ('{"mismatch": true}', "ornith", "s"), opener) == 1
    draft = json.loads((vault / "_system/enrich/fill/20261108-111220.json").read_text())
    assert draft["status"] == "mismatch" and draft["sections"] == {}
