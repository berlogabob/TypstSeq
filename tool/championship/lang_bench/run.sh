#!/bin/bash
# Run the Portuguese model competition on the Studio: stop the Mac jobs that load models there,
# bench every candidate, then start the jobs again and reload the model that was loaded before.
#   tool/championship/lang_bench/run.sh [--limit N] [model ...]     (no models = the candidate list below)
cd "$(dirname "$0")/../../.." || exit 1
BENCH="${BENCH:-tool/championship/lang_bench/bench.py}"  # BENCH=tool/championship/extract_bench/bench.py runs the extraction competition
JOBS="enrich transcribe worker screenshots screenshots.schedule retry"
CANDIDATES=(ollama/ornith-1.5:35b ollama/qwen3.6:27b Qwen3.6-35B-A3B-UD-Q4_K_M unsloth/Qwen3.8-27B-GGUF
  unsloth/gemma-4-26B-A4B-it-qat-GGUF unsloth/LFM2.5-24B-A2B-GGUF unsloth/Muse-Glimmer-30B-GGUF
  unsloth/Inkling-2-Mini-GGUF unsloth/flint-GGUF prism-ml/Ternary-Bonsai-2-27B-gguf)
LIMIT=()
[ "$1" = "--limit" ] && { LIMIT=(--limit "$2"); shift 2; }
[ $# -gt 0 ] && CANDIDATES=("$@")
before=$(python3 - <<'PY'
import json, os, urllib.request
p = json.load(open(os.path.expanduser("~/.pi/agent/models.json")))["providers"]["studio"]
r = urllib.request.Request(p["baseUrl"].rstrip("/") + "/models", headers={"Authorization": "Bearer " + p["apiKey"]})
m = [x for x in json.load(urllib.request.urlopen(r, timeout=30))["data"] if x.get("loaded")]
print(m[0]["id"], m[0].get("context_length") or 65536) if m else print()
PY
)
restore() {
  for job in $JOBS; do launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/org.tylog.$job.plist" 2>/dev/null; done
  [ -n "$before" ] && python3 tool/championship/model_bench/studio_load.py $before
  echo "restored: jobs started, model before the run: ${before:-none}"
}
trap restore EXIT
for job in $JOBS; do
  launchctl bootout "gui/$UID/org.tylog.$job" 2>/dev/null
  while launchctl print "gui/$UID/org.tylog.$job" >/dev/null 2>&1; do sleep 1; done  # bootout returns before the job is gone
done
for model in "${CANDIDATES[@]}"; do
  python3 "$BENCH" "$model" "${LIMIT[@]}" || echo "FAILED $model"
done
python3 "$BENCH" --report
