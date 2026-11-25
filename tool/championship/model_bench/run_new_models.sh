#!/bin/bash
# 2026-11-25 round: the new Studio models against Ornith 35b, all five tasks at 64k context.
# Stops the Mac jobs that load models on the Studio, starts them again at the end.
set -uo pipefail
cd "$(dirname "$0")"
JOBS="enrich transcribe worker screenshots screenshots.schedule retry"
restore() { for job in $JOBS; do launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/org.tylog.$job.plist" 2>/dev/null; done; echo "restored: jobs started"; }
trap restore EXIT
for job in $JOBS; do
  launchctl bootout "gui/$UID/org.tylog.$job" 2>/dev/null
  while launchctl print "gui/$UID/org.tylog.$job" >/dev/null 2>&1; do sleep 1; done  # bootout returns before the job is gone
done
export BENCH_LABEL=@64k BENCH_CTX=65536
for m in 'ollama/ornith-1.5:35b' 'ollama/qwen3.6:27b' 'unsloth/Qwen3.8-27B-GGUF' 'unsloth/gemma-4-26B-A4B-it-qat-GGUF' \
         'unsloth/Muse-Glimmer-30B-GGUF' 'unsloth/Inkling-2-Mini-GGUF' 'prism-ml/Ternary-Bonsai-2-27B-gguf'; do
  ./run.sh studio "$m" "${1:-3}"
done
./report.py > report.txt
