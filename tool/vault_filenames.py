#!/usr/bin/env python3
"""Plan and apply safe filename cleanup for Typst vault notes."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import unicodedata

from vault_dedupe import atomic_write, backup_file, require_app_closed

HOST = re.compile(r"^([A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,} - )(.*)$", re.S)
SUFFIX = re.compile(r"\s*-?\s*\(\d+\)$")
ILLEGAL = set('\\/:*?"<>|')
TRIM_END = " .-–—,;:"


def _emoji_or_control(c: str) -> bool:
    n = ord(c)
    return (0x2600 <= n <= 0x27BF or 0x2B00 <= n <= 0x2BFF or
            0x1F000 <= n <= 0x1FAFF or 0x1F1E6 <= n <= 0x1F1FF or
            0x1F3FB <= n <= 0x1F3FF or n == 0x200D or
            0xFE00 <= n <= 0xFE0F or 0xE0100 <= n <= 0xE01EF or
            n == 0x20E3 or 0xE0020 <= n <= 0xE007F or
            unicodedata.category(c) == "Cc")


def _clean_part(s: str) -> str:
    s = "".join(c for c in s if c not in ILLEGAL)
    s = re.sub(r"\s+", " ", s).strip(" .")
    return s


def _cut(s: str, limit: int) -> str:
    if limit <= 0: return ""
    if len(s) <= limit: return s
    cut = s[:limit]
    if " " in cut: cut = cut.rsplit(" ", 1)[0]
    return cut.rstrip(TRIM_END)


def clean_stem(stem: str, max_chars: int = 80) -> str:
    original = stem
    s = unicodedata.normalize("NFC", stem)
    s = "".join(c for c in s if not _emoji_or_control(c))
    s = _clean_part(s)
    s = re.sub(r"^([A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}) -$", r"\1", s)
    m = HOST.match(s)
    if m:
        prefix, rest = m.groups()
        room = max_chars - len(prefix)
        rest = _cut(rest, max(0, room))
        s = prefix + rest if rest else prefix.removesuffix(" - ")
    else:
        s = _cut(s, max_chars)
    s = s.strip(" .")
    if not s: s = "Untitled"
    # Keep the transformation idempotent, including tiny max_chars values.
    if len(s) > max_chars and max_chars > 0:
        s = _cut(s, max_chars).strip(" .") or "Untitled"
    return s


def _key(name: str) -> str:
    return unicodedata.normalize("NFC", name).casefold()


def _walk(vault: Path):
    for dirname in ("articles", "notes", "projects"):
        root = vault / dirname
        if not root.exists(): continue
        for p in root.rglob("*.typ"):
            rel = p.relative_to(vault)
            if any(part.startswith(("_", ".")) for part in rel.parts): continue
            if p.is_file(): yield p


def plan_with_skips(vault, skip=set(), max_chars=80):
    vault = Path(vault)
    skip = {Path(x).as_posix() for x in skip}
    paths = sorted(_walk(vault), key=lambda p: p.relative_to(vault).as_posix())
    existing = {}
    for p in paths:
        existing.setdefault((p.parent, _key(p.name)), set()).add(p.relative_to(vault).as_posix())
    renames, skipped, planned = [], [], set()
    for p in paths:
        rel = p.relative_to(vault).as_posix()
        if rel in skip:
            skipped.append({"path": rel, "reason": "skip-list"}); continue
        old_stem = p.stem
        cleaned = clean_stem(old_stem, max_chars)
        rules = []
        nfc = unicodedata.normalize("NFC", old_stem)
        if nfc != old_stem: rules.append("nfc")
        if any(_emoji_or_control(c) for c in old_stem): rules.append("emoji")
        if any(c in ILLEGAL for c in old_stem): rules.append("illegal")
        if re.search(r"\s{2,}", old_stem): rules.append("whitespace")
        if old_stem != old_stem.rstrip(" ."): rules.append("trailing")
        if len(clean_stem(old_stem, 10**9)) > max_chars: rules.append("length")
        if cleaned != old_stem and not any(r in rules for r in ("nfc", "emoji", "illegal", "whitespace", "trailing", "length")):
            rules.append("suffix")

        suffix = SUFFIX.search(cleaned)
        if suffix:
            plain = cleaned[:suffix.start()].rstrip(" .")
            candidate = plain + p.suffix
            other_existing = any(x != rel for x in existing.get((p.parent, _key(candidate)), set()))
            if not other_existing and (p.parent, _key(candidate)) not in planned:
                cleaned = plain
                if "suffix" not in rules: rules.append("suffix")

        target = cleaned + p.suffix
        target_rel = (p.parent.relative_to(vault) / target).as_posix()
        key = _key(target)
        conflicts = any(x != rel for x in existing.get((p.parent, key), set())) or (p.parent, key) in planned
        if conflicts:
            base = cleaned
            n = 2
            while True:
                counter = f" {n}"
                candidate_stem = _cut(base, max_chars - len(counter)).rstrip(TRIM_END) + counter
                candidate = candidate_stem + p.suffix
                k = _key(candidate)
                if not any(x != rel for x in existing.get((p.parent, k), set())) and (p.parent, k) not in planned: break
                n += 1
            cleaned = candidate_stem
            target_rel = (p.parent.relative_to(vault) / candidate).as_posix()
            if "collision" not in rules: rules.append("collision")
        if target_rel == rel:
            continue
        if (unicodedata.normalize("NFC", p.name) == p.name and
                _key(target) == _key(p.name) and target != p.name):
            skipped.append({"path": rel, "reason": "case-only"}); continue
        renames.append({"old": rel, "new": target_rel, "rules": rules})
        planned.add((p.parent, _key(Path(target_rel).name)))
    return renames, skipped


def plan(vault):
    return plan_with_skips(vault)[0]


def plan_targets(vault, wanted, max_chars=80):
    """Plan explicit old-relative-path -> desired-stem moves with normal collisions."""
    vault = Path(vault)
    paths = sorted(_walk(vault), key=lambda p: p.relative_to(vault).as_posix())
    existing = {(p.parent, _key(p.name)) for p in paths}
    reserved = set()
    rows = []
    for old, stem in wanted.items():
        src = vault / old
        if not src.is_file():
            continue
        stem = clean_stem(stem, max_chars)
        base = stem
        target = stem + src.suffix
        n = 2
        while ((src.parent, _key(target)) in existing and _key(target) != _key(src.name)) or (src.parent, _key(target)) in reserved:
            counter = f" {n}"
            stem = _cut(base, max_chars - len(counter)).rstrip(TRIM_END) + counter
            target = stem + src.suffix
            n += 1
        rel = (src.parent.relative_to(vault) / target).as_posix()
        if rel == old or (unicodedata.normalize("NFC", src.name) == src.name and _key(target) == _key(src.name) and target != src.name):
            continue
        rows.append({"old": old, "new": rel, "rules": ["collision"] if stem != base else []})
        reserved.add((src.parent, _key(target)))
    return rows


def _sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


JSON_TOKEN = re.compile(r'"(?:\\.|[^"\\])*"')
PATH_TOKEN = re.compile(r'^(?:articles|notes|projects)/.*\.typ$')


def _variants(path):
    return {path, unicodedata.normalize("NFC", path), unicodedata.normalize("NFD", path)}


def _json_files(vault):
    roots = [("_system/jobs", "*.json"), ("_system/enrich", "*.json"),
             ("_system/enrich", "*.jsonl"), ("_system/reading", "*.json"),
             ("_system/decisions", "*.jsonl"), ("_system/health", "*.json"), ("boards", "*.json")]
    found = set()
    for folder, pattern in roots:
        root = vault / folder
        if root.exists(): found.update(root.rglob(pattern))
    return sorted(found)


def _rewrite_json(text, mapping):
    def replace(m):
        token = m.group()
        try: value = json.loads(token)
        except ValueError: return token
        if value not in mapping: return token
        return json.dumps(mapping[value], ensure_ascii="\\u" in token)
    updated, n = JSON_TOKEN.subn(replace, text)
    return updated, text != updated


def _read_text(path):
    with Path(path).open(encoding="utf-8", newline="") as f: return f.read()


def _ref_mapping(renames):
    result = {}
    for r in renames:
        new = unicodedata.normalize("NFC", r["new"])
        for old in _variants(r["old"]): result[old] = new
    return result


def _edit(vault, path, backup_dir, doc, text):
    rel = path.relative_to(vault).as_posix()
    backup_file(vault, rel, backup_dir)
    if not any(x["file"] == rel for x in doc["ref_edits"]): doc["ref_edits"].append({"file": rel, "backup": rel})
    atomic_write(path, text)


def update_references(vault, renames, backup_dir, doc):
    vault, backup_dir = Path(vault), Path(backup_dir)
    mapping = _ref_mapping(renames)
    # The ordinary JSON files are edited in place before any sidecar/history moves.
    for path in _json_files(vault):
        try: original = _read_text(path)
        except (OSError, UnicodeError): continue
        updated, changed = _rewrite_json(original, mapping)
        if changed: _edit(vault, path, backup_dir, doc, updated)
    for r in renames:
        old, new = r["old"], unicodedata.normalize("NFC", r["new"])
        for variant in _variants(old):
            side = vault / "_system/enrich/mentions" / (variant[:-4] + ".json")
            target = vault / "_system/enrich/mentions" / (new[:-4] + ".json")
            if side.exists() and not target.exists():
                try: original = _read_text(side)
                except (OSError, UnicodeError): continue
                updated, changed = _rewrite_json(original, mapping)
                if changed: _edit(vault, side, backup_dir, doc, updated)
                target.parent.mkdir(parents=True, exist_ok=True); os.rename(side, target)
                doc["ref_moves"].append({"old": side.relative_to(vault).as_posix(), "new": target.relative_to(vault).as_posix()})
                break
        target = vault / ".tylog/local-history" / hashlib.sha256(new.encode("utf-8")).hexdigest()
        for variant in _variants(old):
            source = vault / ".tylog/local-history" / hashlib.sha256(variant.encode("utf-8")).hexdigest()
            if source.exists() and not target.exists():
                os.rename(source, target)
                doc["ref_moves"].append({"old": source.relative_to(vault).as_posix(), "new": target.relative_to(vault).as_posix()})
                break
    # Literal Typst includes, preserving the spelling/form of each matched path.
    for path in vault.rglob("*.typ"):
        rel = path.relative_to(vault)
        if any(x in ("_system", "_index", ".tylog") for x in rel.parts): continue
        try: original = _read_text(path)
        except (OSError, UnicodeError): continue
        updated = original
        for r in renames:
            for old in _variants(r["old"]):
                new = unicodedata.normalize("NFC", r["new"])
                updated = updated.replace(f'#include "/{old}"', f'#include "/{new}"').replace(f'#include "{old}"', f'#include "{new}"')
        if updated != original: _edit(vault, path, backup_dir, doc, updated)


def after_rename(vault, renames, backup_dir, doc):
    update_references(vault, renames, backup_dir, doc)


def find_unhandled_refs(vault, renames):
    """Old paths still referenced from files the updater does not handle.

    Each file is read once; candidate path tokens are extracted by regex and
    looked up in sets (a per-rename scan was O(renames x files)).
    """
    vault = Path(vault); out = {}
    olds = {x for r in renames for x in _variants(r["old"])}
    names = {Path(x).name for x in olds}
    handled_json = set(_json_files(vault))
    path_re = re.compile(r"(?:articles|notes|projects)/[^\"\n\\]*?\.typ")
    name_re = re.compile(r'"([^"\n\\/]*\.typ)"')
    for p in vault.rglob("*"):
        if not p.is_file(): continue
        rel = p.relative_to(vault).as_posix(); parts = rel.split("/")
        if p in handled_json or ("_system" in parts and "mentions" in parts): continue
        if parts[0] in {"assets", "_index", "screenshots"} or rel.startswith(("_system/index/", "_system/revisions/", ".tylog/")): continue
        if p.suffix not in {".typ", ".json", ".jsonl", ".md", ".txt", ".yaml", ".yml", ".toml", ".csv"}: continue
        try: text = _read_text(p)
        except (OSError, UnicodeError): continue
        if p.suffix == ".typ":
            text = re.sub(r'#include "/[^"]+"|#include "[^"]+"', "", text)
        hits = {m.group(0) for m in path_re.finditer(text)} & olds
        hits |= {x for x in olds if Path(x).name in {m.group(1) for m in name_re.finditer(text)}} if name_re.search(text) else set()
        for old in hits:
            out.setdefault(old, []).append(rel)
    return out


def _write_manifest(path, doc):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists(): atomic_write(path, json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    else: path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def apply_plan(vault, renames, backup_dir, manifest):
    require_app_closed()
    vault = Path(vault)
    doc = {"version": 1, "vault": str(vault), "backup": str(backup_dir), "created": dt.datetime.now(dt.timezone.utc).isoformat(), "renames": [], "ref_edits": [], "ref_moves": []}
    _write_manifest(manifest, doc)
    for item in renames:
        src, dst = vault / item["old"], vault / item["new"]
        if dst.exists() and not os.path.samefile(src, dst):
            print(f"skip target exists: {item['old']} -> {item['new']}", file=sys.stderr); continue
        backup_file(vault, item["old"], backup_dir)
        try: os.rename(src, dst)
        except OSError as exc:
            print(f"skip rename failed: {item['old']}: {exc}", file=sys.stderr); continue
        doc["renames"].append({"old": item["old"], "new": item["new"], "sha256": _sha(dst)})
        if len(doc["renames"]) % 200 == 0: _write_manifest(manifest, doc)
    after_rename(vault, doc["renames"], backup_dir, doc)
    _write_manifest(manifest, doc)
    return doc


def revert(manifest, vault, apply=False):
    doc = json.loads(Path(manifest).read_text(encoding="utf-8")); vault = Path(vault)
    actions = []
    for item in reversed(doc.get("renames", [])):
        src, dst = vault / item["new"], vault / item["old"]
        actions.append(("rename", src, dst, item))
    for item in reversed(doc.get("ref_moves", [])): actions.append(("move", vault / item["new"], vault / item["old"], item))
    for item in reversed(doc.get("ref_edits", [])): actions.append(("copy", Path(doc.get("backup", "")) / item["backup"], vault / item["file"], item))
    for item in reversed(doc.get("creates", [])): actions.append(("delete", vault / item["path"], None, item))
    if apply: require_app_closed()
    done = 0
    for kind, src, dst, item in actions:
        if kind in ("rename", "move"):
            if not src.exists() or (dst.exists() and not os.path.samefile(src, dst)): continue
            if kind == "rename" and _sha(src) != item["sha256"]: continue
            if apply: dst.parent.mkdir(parents=True, exist_ok=True); os.rename(src, dst)
        elif kind == "delete":
            if not src.exists() or not src.is_file() or _sha(src) != item["sha256"]: continue
            if apply: src.unlink()
        else:
            if not src.exists(): continue
            if apply:
                import shutil
                dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dst)
        done += 1
    return {"planned": len(actions), "completed": done if apply else 0, "would_revert": done if not apply else 0}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("vault", nargs="?"); ap.add_argument("--apply", action="store_true")
    ap.add_argument("--backup"); ap.add_argument("--manifest"); ap.add_argument("--skip-list")
    ap.add_argument("--limit", type=int); ap.add_argument("--revert", metavar="MANIFEST")
    ap.add_argument("--check", nargs=2, metavar=("MANIFEST", "VAULT"))
    args = ap.parse_args(argv)
    if args.check:
        manifest, root = args.check; doc = json.loads(Path(manifest).read_text(encoding="utf-8")); root = Path(root)
        mapping = _ref_mapping(doc.get("renames", [])); counts = {}
        for p in _json_files(root):
            try: txt = _read_text(p)
            except (OSError, UnicodeError): continue
            _, changed = _rewrite_json(txt, mapping)
            if changed: counts.setdefault(p.parent.relative_to(root).as_posix(), 0); counts[p.parent.relative_to(root).as_posix()] += 1
        for p in root.rglob("*.typ"):
            rel = p.relative_to(root)
            if any(x in ("_system", "_index", ".tylog") for x in rel.parts): continue
            try: txt = _read_text(p)
            except (OSError, UnicodeError): continue
            n = sum(txt.count(f'#include "/{old}"') + txt.count(f'#include "{old}"') for old in mapping)
            if n: counts.setdefault("includes", 0); counts["includes"] += n
        dangling = {}
        for p in _json_files(root):
            try: txt = p.read_text(encoding="utf-8")
            except (OSError, UnicodeError): continue
            for m in JSON_TOKEN.finditer(txt):
                try: value = json.loads(m.group())
                except ValueError: continue
                if isinstance(value, str) and PATH_TOKEN.match(value) and not (root / unicodedata.normalize("NFC", value)).exists():
                    dangling.setdefault(p.parent.relative_to(root).as_posix(), []).append(value)
        print(json.dumps({"remaining": counts, "dangling": {k: v[:20] for k, v in dangling.items()}}, ensure_ascii=False, indent=2)); return 0
    if args.revert:
        if not args.vault: ap.error("VAULT is required with --revert")
        result = revert(args.revert, args.vault, args.apply); print(json.dumps(result, indent=2)); return 0
    if not args.vault: ap.error("VAULT is required")
    skip = set(Path(args.skip_list).read_text(encoding="utf-8").splitlines()) if args.skip_list else set()
    renames, skipped = plan_with_skips(args.vault, skip)
    unhandled = find_unhandled_refs(args.vault, renames)
    auto_skip = {old for old in unhandled}
    if auto_skip:
        for old in sorted(auto_skip): skipped.append({"path": old, "reason": "unhandled-ref"})
        renames, skipped_again = plan_with_skips(args.vault, skip | auto_skip)
        skipped = [x for x in skipped if x["reason"] == "unhandled-ref"] + skipped_again
    vpath = Path(args.vault); refmap = _ref_mapping(renames)
    ref_counts = {"json-state": {}, "sidecars": 0, "local-history": 0, "include-literals": 0}
    for p in _json_files(vpath):
        try: txt = _read_text(p)
        except (OSError, UnicodeError): continue
        n = sum(1 for m in JSON_TOKEN.finditer(txt) if (lambda val: isinstance(val, str) and val in refmap)(json.loads(m.group())))
        if n:
            parts = p.relative_to(vpath).parts
            key = "/".join(parts[:2]) if parts[0] == "_system" else parts[0]
            ref_counts["json-state"][key] = ref_counts["json-state"].get(key, 0) + n
    for r in renames:
        for old in _variants(r["old"]):
            if (vpath / "_system/enrich/mentions" / (old[:-4] + ".json")).exists(): ref_counts["sidecars"] += 1; break
            if (vpath / ".tylog/local-history" / hashlib.sha256(old.encode()).hexdigest()).exists(): ref_counts["local-history"] += 1; break
    for p in vpath.rglob("*.typ"):
        if any(x in ("_system", "_index", ".tylog") for x in p.relative_to(vpath).parts): continue
        try: txt = _read_text(p)
        except (OSError, UnicodeError): continue
        ref_counts["include-literals"] += sum(txt.count(f'#include "/{old}"') + txt.count(f'#include "{old}"') for old in refmap)
    print("handled reference counts: " + json.dumps(ref_counts, ensure_ascii=False))
    if args.limit is not None: renames = renames[:args.limit]
    for x in renames: print(f"{x['old']} -> {x['new']}  [{', '.join(x['rules'])}]")
    counts = {}
    for x in renames:
        for r in x["rules"]: counts[r] = counts.get(r, 0) + 1
    print("summary: " + json.dumps({"renames": len(renames), "rules": counts, "skipped": {r: sum(x["reason"] == r for x in skipped) for r in sorted({x["reason"] for x in skipped})}}, ensure_ascii=False))
    if args.apply:
        if not args.backup or not args.manifest: ap.error("--apply requires --backup and --manifest")
        apply_plan(args.vault, renames, args.backup, args.manifest)
    return 0


if __name__ == "__main__": raise SystemExit(main())
