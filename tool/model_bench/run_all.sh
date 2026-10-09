#!/bin/bash
# Full matrix on the Studio PC, one model at a time (it loads one at once).
cd "$(dirname "$0")"
for m in 'unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF' 'ollama/ornith-1.5:9b' 'ollama/ornith-1.5:35b' 'ollama/mannix/ornith-1.5-27b-a3b-coder:latest'; do
  ./run.sh studio "$m" "${1:-3}"
done
./report.py > report.txt
