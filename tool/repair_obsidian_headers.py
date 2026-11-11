#!/usr/bin/env python3
"""Repair Typst note headers written by a buggy Obsidian import.

Usage:
    python tool/repair_obsidian_headers.py VAULT [--apply]

Walks VAULT recursively for ``*.typ`` files (skipping any path containing
``/_system/`` or ``/.``). The default is a dry run: it prints each file it
would change and a final line ``N files``.

With ``--apply`` it first writes a backup tarball
``~/Documents/tylog-backups/vault-typ-backup-obsidian-<YYYY-MM-DD>.tgz`` of
only the files it will change (paths relative to VAULT), then rewrites them
(UTF-8, everything else byte-identical).

The core transformation lives in :func:`repair`, a pure function.
"""

from __future__ import annotations

import argparse
import datetime
import os
import re
import sys
import tarfile

# Header block markers.
SHOW_LINE = "#show: tylog.note.with("
BLOCK_END = ")"

# Rule 1: a title line inside the header block.
TITLE_RE = re.compile(r'^(\s*title:\s*")(.*)",\s*$')

# Rule 2: a tags line inside the header block.
#   group1: leading "  tags: ("
#   group2: the raw list text between the (escaped-string) quotes
#   group3: the closing '", )'
#   group4: optional trailing statement comma / whitespace
TAGS_RE = re.compile(r'^(\s*tags:\s*\()":(.*?)(",\s*\))([,]\s*)?$')

# Rule 3: a value string that starts with ":" on the properties line.
#   Matches the key separator '": "' immediately followed by a value that
#   begins with ':' and any following spaces, e.g. '": ": 2026-05-26'.
RULE3_RE = re.compile(r'"\s*:\s*":\s*')

# Rule 4: the "double-bracket" placeholder that follows tags:: lines.
TAGS_DOLLAR_BRACKETS = r" \[\[\]"


def _strip_escaped_quotes(value: str) -> str:
    """Remove a surrounding pair of escaped quotes (``\\"``) from *value*.

    An escaped quote is the two-character sequence ``\\"``; a surrounding pair
    is therefore four characters, two at each end.
    """
    if (
        len(value) >= 4
        and value[0] == "\\"
        and value[1] == '"'
        and value[-2] == "\\"
        and value[-1] == '"'
    ):
        return value[2:-2]
    return value


def _process_title_value(content: str) -> str:
    """Apply rule 1 to the raw content of a ``title:`` value string."""
    match = re.match(r"^:\s*(.*)$", content)
    if match:
        content = match.group(1)
    return _strip_escaped_quotes(content)


def _split_tags(raw: str) -> list[str]:
    """Turn a raw tags list into a de-duplicated, order-preserving list.

    The ``#a #b`` form is split on whitespace (with a leading ``#`` stripped);
    the ``[a, b, c]`` form is split on commas. Whitespace is trimmed, empty
    entries dropped, and duplicates removed while keeping first-seen order.
    """
    stripped = raw.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        items = [part.strip() for part in stripped[1:-1].split(",")]
    else:
        items = [part.lstrip("#") for part in stripped.split()]

    seen: set[str] = set()
    out: list[str] = []
    for item in items:
        if not item or item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out


def _apply_rule1(line: str) -> str | None:
    match = TITLE_RE.match(line)
    if not match:
        return None
    new_value = _process_title_value(match.group(2))
    return f'{match.group(1)}{new_value}",'


def _apply_rule2(line: str) -> str | None:
    match = TAGS_RE.match(line)
    if not match:
        return None
    items = _split_tags(match.group(2))
    items_str = ", ".join(f'"{item}"' for item in items)
    trailing = match.group(4) or ""
    return f'{match.group(1)}{items_str},){trailing}'


def _apply_rule3(line: str) -> str:
    return RULE3_RE.sub('": "', line)


def _process_block_line(line: str) -> str:
    """Apply rules 1-3 (which only apply inside the header block)."""
    if TITLE_RE.match(line):
        result = _apply_rule1(line)
        if result is not None:
            return result
    if TAGS_RE.match(line):
        result = _apply_rule2(line)
        if result is not None:
            return result
    if "properties" in line:
        return _apply_rule3(line)
    return line


def _apply_rule4(line: str) -> str:
    """Apply rule 4, which applies anywhere in the file."""
    if line.startswith("= : "):
        rest = line[4:]
        if len(rest) >= 2 and rest[0] == '"' and rest[-1] == '"':
            rest = rest[1:-1]
        return "= " + rest
    if line.startswith("tags::"):
        return line.replace(TAGS_DOLLAR_BRACKETS, "")
    return line


def repair(text: str) -> str:
    """Return *text* with buggy Typst headers repaired.

    Rules 1-3 only apply inside the header block that starts at the line
    ``#show: tylog.note.with(`` and ends at the first line that is exactly
    ``)``. Rule 4 applies anywhere in the file. Returns *text* unchanged when
    nothing applies.
    """
    lines = text.split("\n")

    start = None
    for i, line in enumerate(lines):
        if line == SHOW_LINE:
            start = i
            break

    if start is not None:
        end = None
        for j in range(start + 1, len(lines)):
            if lines[j] == BLOCK_END:
                end = j
                break
        if end is not None:
            for i in range(start, end + 1):
                lines[i] = _process_block_line(lines[i])

    for i, line in enumerate(lines):
        lines[i] = _apply_rule4(line)

    return "\n".join(lines)


def _is_skippable(path: str) -> bool:
    return "/_system/" in path or "/." in path


def find_typ_files(vault: str) -> list[str]:
    """Return sorted *.typ paths under *vault*, skipping ignored paths."""
    results: list[str] = []
    for dirpath, _dirnames, filenames in os.walk(vault):
        if _is_skippable(dirpath):
            continue
        for name in filenames:
            if not name.endswith(".typ"):
                continue
            full = os.path.join(dirpath, name)
            if _is_skippable(full):
                continue
            results.append(full)
    results.sort()
    return results


def changed_files(vault: str, paths: list[str]) -> list[str]:
    """Return the paths whose repaired content differs from the original."""
    changed: list[str] = []
    for full in paths:
        with open(full, "r", encoding="utf-8") as handle:
            original = handle.read()
        if repair(original) != original:
            changed.append(full)
    return changed


def write_backup(changed: list[str], vault: str) -> str:
    """Tar *changed* files (relative to *vault*) into a dated .tgz."""
    backup_dir = os.path.expanduser("~/Documents/tylog-backups")
    os.makedirs(backup_dir, exist_ok=True)
    date = datetime.date.today().isoformat()
    tgz = os.path.join(backup_dir, f"vault-typ-backup-obsidian-{date}.tgz")
    with tarfile.open(tgz, "w:gz") as tar:
        for full in changed:
            tar.add(full, arcname=os.path.relpath(full, vault))
    return tgz


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Repair buggy Typst note headers from an Obsidian import."
    )
    parser.add_argument("vault", help="root directory to walk for *.typ files")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="rewrite changed files (after writing a backup tarball)",
    )
    args = parser.parse_args(argv)

    vault = args.vault
    paths = find_typ_files(vault)
    changed = changed_files(vault, paths)

    for full in changed:
        print(os.path.relpath(full, vault))
    print(f"{len(changed)} files")

    if args.apply and changed:
        tgz = write_backup(changed, vault)
        print(f"backup: {tgz}", file=sys.stderr)
        for full in changed:
            with open(full, "r", encoding="utf-8") as handle:
                original = handle.read()
            # Atomic: a crash mid-write must not truncate a vault note.
            temporary = full + ".tmp"
            with open(temporary, "w", encoding="utf-8") as handle:
                handle.write(repair(original))
            os.replace(temporary, full)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
