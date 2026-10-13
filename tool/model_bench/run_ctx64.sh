#!/bin/bash
# Bug-fix task only, both 35B builds, Studio context 64k (matches pi's contextWindow).
cd "$(dirname "$0")"
export BENCH_LABEL=@64k BENCH_CTX=65536
./run.sh studio 'ollama/hf.co/pfeifferj/Ornith-1.5-35B-A3B-GSQ-RCO-GGUF:Ornith-1.5-35B-A3B-GSQ-RCO-3.5bit.gguf' 3 t4_bug_fix
./run.sh studio 'ollama/ornith-1.5:35b' 3 t4_bug_fix
./report.py > report.txt
