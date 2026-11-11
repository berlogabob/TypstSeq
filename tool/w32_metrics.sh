#!/bin/bash
# Wave 32 audit metrics, plain grep, no LLM. Run at A3 (baseline) and Z2.
set -u
cd "$(dirname "$0")/.." || exit 1
n() { wc -l | tr -d ' '; }
ts=packages/typst_flutter/rust/src/api/typst.rs
p2p=packages/typst_flutter/rust/src/api/p2p_folder.rs

echo "swallowed_catch        $(grep -rF 'catch (_) {}' lib packages/*/lib --include='*.dart' | n)   (target <= 33)"
echo "http_no_timeout_files  $(grep -rl 'HttpClient()' lib --include='*.dart' | xargs grep -L connectionTimeout | n)   (target 0)"
echo "typst_proc_timeout     $(grep -A6 "Process.start(" lib/workspace_note_merge.dart | grep -c "timeout")   (target >= 1)"
u=$(( $(grep -c 'requested_files.lock().unwrap()' $ts) \
    + $(grep -A2 'duration_since(' $ts | grep -c 'unwrap()') \
    + $(grep -A2 'join_next()' $p2p | grep -c 'unwrap()') ))
echo "ffi_unwrap_sites       $u   (target 0)"
echo "dead_symbols           $(grep -rlE 'parseLabCalendar|sameIndexedContent' lib packages test --include='*.dart' | n)   (target 0)"
ci=3
grep -q 'typst_flutter/rust/Cargo.toml' .github/workflows/ci.yml Makefile && ci=$((ci+1))
grep -q 'pytest' .github/workflows/ci.yml && ci=$((ci+1))
echo "ci_suites              $ci   (target 5)"
echo "make_git_add_all       $(grep -c 'git add -A' Makefile)   (target 0)"
echo "tracked_junk           $(git ls-files android/build tool/audio_plan/logs | n)   (target 0)"
echo "test_declarations      $(grep -rhE '^\s*(test|testWidgets)\(' test packages/tylog_core/test --include='*_test.dart' | n)   (target baseline + 12)"
