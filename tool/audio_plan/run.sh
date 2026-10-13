#!/bin/bash
# usage: tool/audio_plan/run.sh [task ...]     (default: every task, in order)
# Runs each task in an isolated worktree on branch plan/audio-learning.
# ornith tasks go to Ornith 1.5 35b on Studio via pi-run.sh; if one fails it is
# retried ONCE with codex. A task only lands (one commit) when its verify
# command passes and nothing outside its allow list changed. Every attempt
# appends one row to docs/plans/audio-plan-results.jsonl. Resumable.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PLAN="$REPO/tool/audio_plan"
WT="${AUDIO_WT:-$REPO/../TypstSeq-audio}"
BRANCH=plan/audio-learning
PI="$HOME/.claude/skills/pi-delegate/scripts/pi-run.sh"
MODEL=ollama/ornith-1.5:35b
OUT="$REPO/docs/plans/audio-plan-results.jsonl"; LOGS="$PLAN/logs"; mkdir -p "$LOGS"
tasks=("$@"); [ ${#tasks[@]} -eq 0 ] && tasks=($(ls "$PLAN/tasks"))

if [ ! -d "$WT" ]; then
  git -C "$REPO" worktree add -b "$BRANCH" "$WT" HEAD || exit 1
  (cd "$WT" && flutter pub get >/dev/null && cd packages/tylog_core && dart pub get >/dev/null)
fi

studio_ok=false
if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://desktop-vdsrh2e:8888/v1/models)" = 401 ] \
   && "$REPO/tool/model_bench/studio_load.py" "$MODEL" 65536 >/dev/null 2>&1; then studio_ok=true; fi
echo "studio_ok=$studio_ok"

run_agent() { # agent task log
  local agent=$1 T="$PLAN/tasks/$2" log=$3
  cd "$WT" || return 1
  if [ "$agent" = ornith ]; then
    PI_PROVIDER=studio PI_MODEL="$MODEL" PI_ALLOW_BASH=1 PI_MAX_ITERS=3 PI_CHECKPOINT=0 \
      PI_TIMEOUT=900 PI_LOGDIR="$LOGS/pi" PI_VERIFY="$(cat "$T/verify")" \
      "$PI" "$(cat "$T/prompt.md")" < /dev/null > "$log" 2>&1
  else
    timeout 1500 codex exec -s workspace-write -C "$WT" -c model_reasoning_effort=low \
      "$(cat "$T/prompt.md")" < /dev/null > "$log" 2>&1
  fi
}

for task in "${tasks[@]}"; do
  T="$PLAN/tasks/$task"
  grep -q "\"task\":\"$task\".*\"pass\":true" "$OUT" 2>/dev/null && { echo "$task already passed"; continue; }
  first="$(cat "$T/agent")"
  if [ "$first" = ornith ] && ! $studio_ok; then first=codex; fi
  if [ "$first" = ornith ]; then order="ornith codex"; else order="$first"; fi
  attempt=0
  for agent in $order; do
    attempt=$((attempt+1))
    cd "$WT" && git reset -q --hard && git clean -qfd -e .dart_tool -e build -e .pi-runs
    log="$LOGS/$task-$agent-$attempt.log"; start=$(date +%s)
    run_agent "$agent" "$task" "$log"
    secs=$(( $(date +%s) - start ))
    cd "$WT" || exit 1
    allow="$(cat "$T/allow")"
    stray=$(git status --porcelain | awk '{print $2}' | grep -v -x -F -f <(echo "$allow") | grep -v '^\.pi-runs' | wc -l | tr -d ' ')
    pass=false
    [ "$stray" = 0 ] && bash -c "$(cat "$T/verify")" > "$log.verify" 2>&1 && pass=true
    git add -A -N
    read added deleted <<<"$(git diff --numstat HEAD -- $allow | awk '{a+=$1; d+=$2} END {print a+0, d+0}')"
    printf '{"date":"%s","task":"%s","agent":"%s","attempt":%s,"pass":%s,"stray":%s,"added":%s,"deleted":%s,"secs":%s}\n' \
      "$(date +%F)" "$task" "$agent" "$attempt" "$pass" "$stray" "$added" "$deleted" "$secs" | tee -a "$OUT"
    if $pass; then
      git add -- $allow && git -c user.name=plan -c user.email=plan@local commit -qm "plan: $task ($agent)"
      break
    fi
    git reset -q --hard && git clean -qfd -e .dart_tool -e build -e .pi-runs
  done
done
echo "branch $BRANCH at $(git -C "$WT" rev-parse --short HEAD)"
