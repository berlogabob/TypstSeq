#!/bin/bash
# usage: run.sh <provider> <model> [reps=3] [task ...]
set -u
BASE=9dbfa0f
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH="$REPO/tool/model_bench"
WT="${BENCH_WORKTREE:-$REPO/../TypstSeq-bench}"
PI="$HOME/.claude/skills/pi-delegate/scripts/pi-run.sh"
provider="${1:?provider}"; model="${2:?model}"; reps="${3:-3}"; shift 3 2>/dev/null || shift $#
tasks=("$@"); [ ${#tasks[@]} -eq 0 ] && tasks=($(ls "$BENCH/tasks"))
OUT="$BENCH/results.jsonl"; LOGS="$BENCH/logs"; mkdir -p "$LOGS"

if [ ! -d "$WT" ]; then
  git -C "$REPO" worktree add --detach "$WT" "$BASE" || exit 1
  (cd "$WT" && flutter pub get >/dev/null && cd packages/tylog_core && dart pub get >/dev/null)
fi

for task in "${tasks[@]}"; do
  T="$BENCH/tasks/$task"
  for rep in $(seq 1 "$reps"); do
    # Resumable: a finished run is never repeated.
    grep -q "\"model\":\"$model\",\"task\":\"$task\",\"rep\":$rep," "$OUT" 2>/dev/null && continue
    cd "$WT" || exit 1
    git reset -q --hard && git clean -qfd -e .dart_tool -e build && git checkout -q --detach "$BASE" && git clean -qfd -e .dart_tool -e build
    bash "$T/setup.sh" "$REPO" || { echo "setup failed: $task"; continue; }
    git add -A && git -c user.name=bench -c user.email=bench@local commit -qm baseline --allow-empty
    log="$LOGS/$(echo "$model" | tr '/:' '__')-$task-$rep.log"
    start=$(date +%s)
    PI_PROVIDER="$provider" PI_MODEL="$model" PI_ALLOW_BASH=1 PI_MAX_ITERS=3 PI_CHECKPOINT=0 \
      PI_TIMEOUT=900 PI_LOGDIR="$LOGS/pi" PI_VERIFY="$(cat "$T/verify")" \
      "$PI" "$(cat "$T/prompt.md")" < /dev/null > "$log" 2>&1
    secs=$(( $(date +%s) - start ))
    visible=false; (cd "$WT" && bash -c "$(cat "$T/verify")" >/dev/null 2>&1) && visible=true
    allow="$(cat "$T/allow")"
    stray=$(git status --porcelain | awk '{print $2}' | grep -v -x -F -f <(echo "$allow") | grep -v '^\.pi-runs' | wc -l | tr -d ' ')
    git add -A -N
    read added deleted <<<"$(git diff --numstat HEAD -- $allow | awk '{a+=$1; d+=$2} END {print a+0, d+0}')"
    pass=false; bash "$T/check.sh" "$REPO" > "$log.check" 2>&1 && pass=true
    printf '{"date":"%s","provider":"%s","model":"%s","task":"%s","rep":%s,"pass":%s,"visible":%s,"stray":%s,"added":%s,"deleted":%s,"secs":%s}\n' \
      "$(date +%F)" "$provider" "$model" "$task" "$rep" "$pass" "$visible" "$stray" "$added" "$deleted" "$secs" | tee -a "$OUT"
  done
done
