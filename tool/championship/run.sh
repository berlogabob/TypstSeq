#!/bin/bash
# All three competitions for new Studio models, one model at a time, Mac jobs stopped.
#   tool/championship/run.sh <model id> [<model id> ...]
# Put the reference model (ollama/ornith-1.5:35b) first only when its rows must be redone; old rows are reused.
# A model slower on the first coding task than the reference pair (166 s) is dropped from the coding round.
cd "$(dirname "$0")/../.." || exit 1
[ $# -gt 0 ] || { sed -n 2,5p "$0"; exit 1; }
HERE=tool/championship
JOBS="enrich transcribe worker screenshots screenshots.schedule retry"
restore() { for job in $JOBS; do launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/org.tylog.$job.plist" 2>/dev/null; done; echo "restored: jobs started"; }
trap restore EXIT
for job in $JOBS; do
  launchctl bootout "gui/$UID/org.tylog.$job" 2>/dev/null
  while launchctl print "gui/$UID/org.tylog.$job" >/dev/null 2>&1; do sleep 1; done  # bootout returns before the job is gone
done
python3 - "$@" <<'PY'  # pi must know a model before the coding round can use it
import json, os, sys
path = os.path.expanduser("~/.pi/agent/models.json"); config = json.load(open(path)); models = config["providers"]["studio"]["models"]
models += [{**models[0], "id": model} for model in sys.argv[1:] if model not in {entry["id"] for entry in models}]
json.dump(config, open(path, "w"), indent=2)
PY
$HERE/model_bench/skip_slow.sh 166 $$ &
for model in "$@"; do
  BENCH_LABEL=@64k BENCH_CTX=65536 $HERE/model_bench/run.sh studio "$model" 3
  python3 $HERE/lang_bench/bench.py "$model"
  python3 $HERE/extract_bench/bench.py "$model"
done
(cd $HERE/model_bench && ./report.py > report.txt && grep -E "^(ollama|unsloth|prism).*pass" report.txt)
python3 $HERE/lang_bench/bench.py --report
python3 $HERE/extract_bench/bench.py --report
