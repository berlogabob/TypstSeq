#!/usr/bin/env python3
"""Conflict report generator for TyLog vaults.

usage: python3 tool/p03_conflict_report.py VAULT_DIR [BACKUP_DIR]

For each record in VAULT_DIR/.tylog/conflicts/*.json a single tab-separated
line is printed, followed by a SUMMARY line. Records are sorted by path.
"""
import difflib
import hashlib
import json
import os
import sys


CONFLICTS_DIR = os.path.join('.tylog', 'conflicts')


def sha256(path):
    """Full lowercase hex sha256 of a file."""
    with open(path, 'rb') as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def short_sha(value):
    """12-char prefix of a sha, or '-' when the value is None."""
    return value[:12] if value is not None else '-'


def read_bytes(path):
    with open(path, 'rb') as fh:
        return fh.read()


def to_lines(raw):
    """List of lines if `raw` decodes as UTF-8, else None (missing text)."""
    if isinstance(raw, bytes):
        try:
            return raw.decode('utf-8').splitlines()
        except UnicodeDecodeError:
            return None
    return None


def contains_in_order(sub, sup):
    """True when every line of `sub` appears in `sup` in the same order."""
    if not sub:
        return True
    sm = difflib.SequenceMatcher(None, sub, sup, autojunk=False)
    return sum(block.size for block in sm.get_matching_blocks()) == len(sub)


def diff_detail(local_lines, remote_lines):
    nd = list(difflib.ndiff(local_lines, remote_lines))
    added = sum(1 for line in nd if line.startswith('+ '))
    removed = sum(1 for line in nd if line.startswith('- '))
    detail = 'added=%d removed=%d' % (added, removed)
    if contains_in_order(local_lines, remote_lines):
        detail += ' remote-superset'
    elif contains_in_order(remote_lines, local_lines):
        detail += ' local-superset'
    return detail


def binary_detail(local_bytes, remote_bytes):
    Ln = len(local_bytes) if local_bytes is not None else 0
    Rn = len(remote_bytes) if remote_bytes is not None else 0
    return 'local=%d bytes remote=%d bytes' % (Ln, Rn)


def classify(local_bytes, remote_bytes):
    """Return (verdict, detail) for the local/remote bytes (either str bytes)."""
    if hashlib.sha256(local_bytes).digest() == hashlib.sha256(remote_bytes).digest():
        return 'identical', ''

    local_lines, remote_lines = to_lines(local_bytes), to_lines(remote_bytes)
    if local_lines is not None and remote_lines is not None:
        return 'text-differs', diff_detail(local_lines, remote_lines)
    return 'binary-differs', binary_detail(local_bytes, remote_bytes)


def side(vault_dir, record, key):
    """Resolve a JSON-relative path from a record."""
    if record.get(key) is None:
        return None
    return os.path.join(vault_dir, record[key])


def line_for_record(rec, vault_dir, backup_dir):
    id_ = rec.get('id', '-')
    path = rec.get('path', '-')

    # local side: <localSnapshot> if present, else <path>
    local_path = side(vault_dir, rec, 'localSnapshot')
    if local_path is None or not os.path.exists(local_path):
        local_path = side(vault_dir, rec, 'path')

    remote_path = side(vault_dir, rec, 'remoteSnapshot')
    backup_path = side(backup_dir, rec, 'path') if backup_dir is not None else None

    def sha(p):
        if p is None:
            return None
        if not os.path.exists(p):
            return None
        return sha256(p)

    l_sha = sha(local_path)
    r_sha = sha(remote_path)
    b_sha = sha(backup_path)

    detail = ''
    if l_sha is not None and r_sha is not None:
        verdict, detail = classify(read_bytes(local_path), read_bytes(remote_path))
    elif l_sha is not None:
        verdict = 'local-only'
    elif r_sha is not None:
        verdict = 'remote-only'
    else:
        verdict = 'missing'

    if b_sha is not None and local_path is not None and b_sha == l_sha:
        detail += ' backup=local'
    elif b_sha is not None and remote_path is not None and b_sha == r_sha:
        detail += ' backup=remote'

    return '\t'.join([id_, path, short_sha(l_sha), short_sha(r_sha),
                      short_sha(b_sha), verdict, detail])


def load_records(vault_dir):
    conflicts_dir = os.path.join(vault_dir, CONFLICTS_DIR)
    records = []
    if os.path.isdir(conflicts_dir):
        for name in os.listdir(conflicts_dir):
            if not name.endswith('.json'):
                continue
            full = os.path.join(conflicts_dir, name)
            try:
                with open(full, 'r', encoding='utf-8') as fh:
                    records.append(json.load(fh))
            except (OSError, ValueError):
                continue
    return records


def build_report(vault_dir, backup_dir):
    records = load_records(vault_dir)
    records.sort(key=lambda r: r.get('path', ''))

    counts = {k: 0 for k in ('total', 'identical', 'text-differs', 'binary-differs',
                             'local-only', 'remote-only', 'missing')}

    out = []
    for rec in records:
        line = line_for_record(rec, vault_dir, backup_dir)
        out.append(line)
        verdict = line.split('\t')[5]
        if verdict in counts:
            counts[verdict] += 1
        counts['total'] += 1
    return out, counts


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: python3 p03_conflict_report.py VAULT_DIR [BACKUP_DIR]\n")
        return 1

    vault_dir = os.path.abspath(argv[1])
    backup_dir = os.path.abspath(argv[2]) if len(argv) > 2 else None

    out, counts = build_report(vault_dir, backup_dir)
    print('\n'.join(out))
    print('SUMMARY ' + ' '.join('%s=%d' % item for item in counts.items()))
    return 0


def _selfcheck():
    assert contains_in_order(['a', 'c'], ['a', 'b', 'c'])
    assert not contains_in_order(['c', 'a'], ['a', 'b', 'c'])
    assert classify(b'x', b'x') == ('identical', '')
    assert classify(b'a\n', b'a\nb\n')[1].endswith('remote-superset')
    assert classify(b'\xff', b'\xfe')[0] == 'binary-differs'


if __name__ == '__main__':
    _selfcheck()
    sys.exit(main(sys.argv))
