#!/bin/bash
# Renders the launchd templates for this user into ~/Library/LaunchAgents.
# Does not load them: run `launchctl bootstrap gui/$(id -u) <plist>` yourself.
# Usage: install.sh [name ...]   (default: cluster enrich indexer)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
dest="$HOME/Library/LaunchAgents"
mkdir -p "$dest" "$HOME/Library/Logs"
names=("$@"); [ ${#names[@]} -gt 0 ] || names=(cluster enrich indexer)
for n in "${names[@]}"; do
  sed -e "s#@REPO@#$repo#g" -e "s#@HOME@#$HOME#g" "$here/org.tylog.$n.plist.template" > "$dest/org.tylog.$n.plist"
  plutil -lint "$dest/org.tylog.$n.plist" >/dev/null
  echo "wrote $dest/org.tylog.$n.plist"
done
