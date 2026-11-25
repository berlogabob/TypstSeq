#!/bin/bash
# Time rule (user, 2026-11-25): a model slower on the first task than the two reference models
# (Ornith 35b, qwen3.6: slowest run 166 s) is skipped. usage: skip_slow.sh [limit seconds] [pid to end with]
cd "$(dirname "$0")"; LIMIT="${1:-166}"; OWNER="${2:-$PPID}"; seen=; since=0
while kill -0 "$OWNER" 2>/dev/null; do
  sleep 20
  line=$(pgrep -fl "run.sh studio" | head -1); pid=${line%% *}; model=$(echo "$line" | awk '{print $5}')
  [ -z "$pid" ] && continue
  rows=$(grep -c "\"model\":\"$model@64k\",\"task\":\"t1_new_file\"" results.jsonl)
  slow=$(grep "\"model\":\"$model@64k\",\"task\":\"t1_new_file\"" results.jsonl | sed 's/.*"secs":\([0-9]*\).*/\1/' | awk -v l="$LIMIT" '$1>l' | wc -l)
  pi=$(pgrep -f pi-run.sh | head -1); age=0
  [ "$pi" != "$seen" ] && { seen=$pi; since=$(date +%s); }  # macOS ps has no etimes
  [ "$rows" -lt 3 ] && [ -n "$pi" ] && age=$(( $(date +%s) - since ))
  if [ "$slow" -gt 0 ] || [ "${age:-0}" -gt "$LIMIT" ]; then
    echo "$(date +%T) skipped $model: first task slower than ${LIMIT}s"
    kill "$pid"; sleep 1; [ -n "$pi" ] && { pkill -TERM -P "$pi"; kill "$pi"; }
    sleep 30
  fi
done
