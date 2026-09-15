#!/usr/bin/env python3
"""Create a privacy-safe aggregate corpus manifest."""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def _validate_path_name(name):
    """Reject control characters."""
    return all(ord(character) >= 32 and ord(character) != 127 for character in name)


def manifest(root, output):
    """Create privacy-safe aggregate corpus manifest."""
    root_path = Path(root).resolve()
    output_path = Path(output).resolve()

    if not root_path.exists():
        raise ValueError("root must exist")
    if not root_path.is_dir():
        raise ValueError("root must be a directory")
    if output_path.exists():
        raise ValueError("output must not exist")
    if output_path.is_relative_to(root_path):
        raise ValueError("output must be outside root")

    try:
        total_files = 0
        total_bytes = 0
        extensions = {}
        size_buckets = {"0-1k": 0, "1k-10k": 0, "10k-100k": 0,
                        "100k-1m": 0, "1m-10m": 0, "10m+": 0}
        typ_count = 0

        corpus_digest = hashlib.sha256()
        for root_dir, dirs, files_list in os.walk(root_path):
            dirs.sort()
            files_list.sort()
            for name in list(dirs):
                path = Path(root_dir) / name
                if path.is_symlink():
                    dirs.remove(name)
                elif not _validate_path_name(name):
                    dirs.remove(name)

            for name in files_list:
                if not _validate_path_name(name):
                    continue
                path = Path(root_dir) / name
                if path.is_symlink():
                    continue

                try:
                    rel_path = path.relative_to(root_path)
                    size = path.stat().st_size

                    digest = hashlib.sha256()
                    with open(path, "rb") as f:
                        while True:
                            block = f.read(1024 * 1024)
                            if not block:
                                break
                            digest.update(block)
                    file_hash = digest.hexdigest()

                    corpus_digest.update(os.fsencode(str(rel_path)))
                    corpus_digest.update(size.to_bytes(8, "big"))
                    corpus_digest.update(file_hash.encode("ascii"))

                    total_files += 1
                    total_bytes += size
                    ext = rel_path.suffix or "(none)"
                    extensions[ext] = extensions.get(ext, 0) + 1

                    if ext == ".typ":
                        typ_count += 1

                    if size < 1024:
                        size_buckets["0-1k"] += 1
                    elif size < 10 * 1024:
                        size_buckets["1k-10k"] += 1
                    elif size < 100 * 1024:
                        size_buckets["10k-100k"] += 1
                    elif size < 1024 * 1024:
                        size_buckets["100k-1m"] += 1
                    elif size < 10 * 1024 * 1024:
                        size_buckets["1m-10m"] += 1
                    else:
                        size_buckets["10m+"] += 1

                except (OSError, IOError):
                    pass

        corpus_digest_hex = corpus_digest.hexdigest()

        manifest_data = {
            "schema_version": 1,
            "generated_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "corpus_digest": corpus_digest_hex,
            "aggregate": {
                "total_files": total_files,
                "total_bytes": total_bytes,
                "typ_file_count": typ_count,
                "extensions": extensions,
                "size_buckets": size_buckets
            }
        }

        output_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as output_file:
            output_file.write(json.dumps(manifest_data, indent=2, sort_keys=True) + "\n")

        summary = {
            "total_files": total_files,
            "total_bytes": total_bytes,
            "corpus_digest": corpus_digest_hex
        }
        print(json.dumps(summary, sort_keys=True))

    except OSError as error:
        raise ValueError(str(error)) from error


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--output", required=True)

    args = parser.parse_args(argv)

    try:
        manifest(args.root, args.output)
    except (ValueError, OSError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
