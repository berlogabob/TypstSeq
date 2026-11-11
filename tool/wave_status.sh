#!/bin/bash
# Wave status without an LLM: progress, next step, Ornith liveness/stall, changes.
# Usage: tool/wave_status.sh <wave number>   e.g. tool/wave_status.sh 32
set -u
w="${1:?usage: wave_status.sh <wave number>}"
cd "$(dirname "$0")/.." || exit 1
sec=$(sed -n "/^## Wave $w /,/^## /p" docs/plans/activity-plan.md)
done=$(grep -c "^- \[x\] W$w\." <<<"$sec")
all=$(grep -c "^- \[.\] W$w\." <<<"$sec")
echo "Wave $w: $done/$all done"
echo "Next: $(grep -m1 "^- \[ \] W$w\." <<<"$sec" | cut -c7-90)"
pid=$(pgrep -f "pi-delegate/scripts/pi-run.sh" | head -1)
if [ -n "$pid" ]; then
  log=$(ls -t .pi-runs/*.jsonl 2>/dev/null | head -1)
  idle=$(( $(date +%s) - $(stat -f %m "$log") ))
  echo "Ornith: running $(ps -o etime= -p "$pid" | tr -d ' '), log idle ${idle}s$([ "$idle" -gt 180 ] && echo '  STALLED?')"
else
  echo "Ornith: idle"
fi
cpid=$(pgrep -f "codex exec" | head -1)
if [ -n "$cpid" ]; then
  clog=$(ls -t .codex-runs/*.log 2>/dev/null | head -1)
  cidle=$(( $(date +%s) - $(stat -f %m "${clog:-.}") ))
  echo "Codex: running $(ps -o etime= -p "$cpid" | tr -d ' '), log idle ${cidle}s$([ "$cidle" -gt 300 ] && echo '  STALLED?')"
else
  echo "Codex: idle"
fi
git status --short -- tool packages lib test android ios | head -6
git log --oneline -2 | cut -c1-80
