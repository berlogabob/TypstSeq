#!/bin/bash
# W36.25: lab catalogue into the vault, then confirmed TyLog loans into OLT (ADR 0003).
# Dry run by default (prints only). Writes only with: lab_sync.sh --apply --staff-id N
# Usage: lab_sync.sh [--apply --staff-id N]   env: TYLOG_VAULT, OLT_REPO
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
vault="${TYLOG_VAULT:-$HOME/Nextcloud/TyLogVault}"
olt="${OLT_REPO:-$HOME/Documents/GitHub/openlabtwin}"
uv="$(command -v uv || echo /opt/homebrew/bin/uv)"
tylog="$(command -v tylog || echo "$HOME/.local/bin/tylog")"
# shortcut: the installed CLI is shared with org.tylog.indexer; rebuild it with `make install-indexer` when a phase ships.
"$tylog" 2>&1 | grep -q "tylog loans" || { echo "lab_sync: $tylog has no 'loans' command; run make install-indexer" >&2; exit 2; }
apply=0; for a in "$@"; do [ "$a" = --apply ] && apply=1; done
tmp="$(mktemp -d)"; loans="$tmp/loans.jsonl"   # outside the vault, as `tylog loans --jsonl` requires
trap 'rm -rf "$tmp"' EXIT
echo "lab_sync $(date -u +%FT%TZ) apply=$apply"
if [ $apply = 1 ]; then (cd "$olt" && nice -n 10 "$uv" run python scripts/export_tylog.py --vault "$vault")
else (cd "$olt" && nice -n 10 "$uv" run python scripts/export_tylog.py); fi
nice -n 10 "$tylog" loans "$vault" --jsonl "$loans" >/dev/null
nice -n 10 "$uv" run python "$repo/tool/lab_bridge.py" --jsonl "$loans" --vault "$vault" --env-file "$olt/.env" "$@"
