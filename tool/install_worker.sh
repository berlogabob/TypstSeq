#!/bin/bash
# Installs the Mac workers (transcribe, enrich) to ~/.tylog/worker and points their launchd jobs there.
#   tool/install_worker.sh        run again after changing the worker code
# Why not run them from the repo: ~/Documents is a protected folder. macOS grants access per uv version, so
# after every uv upgrade the jobs block on a permission prompt (and hang when nobody is there to answer it).
# It also keeps half-edited code from running against the real vault.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"; DEST="$HOME/.tylog/worker"
MODULES="transcribe_worker enrich_worker audio_v2 fill_worker phrase_notes phrase_audio"
mkdir -p "$DEST"
for module in $MODULES; do python3 -m py_compile "$SRC/$module.py"; done   # never install code that does not parse
for module in $MODULES; do cp "$SRC/$module.py" "$DEST/$module.py"; done
for job in transcribe enrich; do
  plist="$HOME/Library/LaunchAgents/org.tylog.$job.plist"
  [ -f "$plist" ] || continue
  sed -i '' "s#<string>[^<]*/${job}_worker.py</string>#<string>$DEST/${job}_worker.py</string>#" "$plist"
  launchctl bootout "gui/$UID/org.tylog.$job" 2>/dev/null || true
  while launchctl print "gui/$UID/org.tylog.$job" >/dev/null 2>&1; do sleep 1; done
  launchctl bootstrap "gui/$UID" "$plist"
done
echo "installed to $DEST: $(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo '?')"
