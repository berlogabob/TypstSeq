#!/bin/bash
# Same base model, two quantizations, both served by Unsloth Studio at a 32k context.
cd "$(dirname "$0")"
export BENCH_LABEL=@32k BENCH_CTX=32768
./run.sh studio 'ollama/hf.co/pfeifferj/Ornith-1.5-35B-A3B-GSQ-RCO-GGUF:Ornith-1.5-35B-A3B-GSQ-RCO-3.5bit.gguf' "${1:-3}"
./run.sh studio 'ollama/ornith-1.5:35b' "${1:-3}"
./report.py > report.txt
