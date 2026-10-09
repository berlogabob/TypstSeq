#!/bin/sh
# Fails unless the named platforms' native libraries were built from this repo's
# packages/typst_flutter/rust, rather than downloaded from the upstream release.
#
# This exists because the failure is otherwise invisible: a downloaded upstream
# library links, packages, installs and launches. It only fails at runtime, inside
# RustLib.init(), because this fork's flutter_rust_bridge content hash (it adds
# api/markdown_import.rs) does not match — and the app degrades around that by
# falling back to source parsing. So "the build went green" and even "the app
# started" are both compatible with shipping something with no Typst engine.
#
# Usage: tool/assert_source_built.sh android [linux ...]
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
stamp="$root/packages/typst_flutter/.typst_flutter_prebuilt/.source-built"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <platform>..." >&2
  exit 2
fi

if [ ! -f "$stamp" ]; then
  echo "FAIL: $stamp is missing — nothing was built from this repo's Rust." >&2
  echo "Run tool/setup_typst_native.sh on a host with rustup (and the Android NDK" >&2
  echo "for Android targets)." >&2
  exit 1
fi

status=0
for platform in "$@"; do
  if grep -qx "$platform" "$stamp"; then
    echo "ok: $platform was source-built"
  else
    echo "FAIL: $platform was NOT source-built; it would ship upstream's library." >&2
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  echo "Source-built platforms: $(tr '\n' ' ' <"$stamp")" >&2
fi
exit "$status"
