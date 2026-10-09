#!/bin/bash
# Controls for the bench itself. For every task:
#   null control      - untouched baseline must FAIL the hidden check
#   reference control - the known-good answer from git history must PASS
# plus one sloppy control: a same-value edit with one changed number must FAIL.
set -u
BASE=9dbfa0f
REPO="$(cd "$(dirname "$0")/../.." && pwd)"; BENCH="$REPO/tool/model_bench"
WT="${BENCH_WORKTREE:-$REPO/../TypstSeq-bench}"
if [ ! -d "$WT" ]; then
  git -C "$REPO" worktree add --detach "$WT" "$BASE" || exit 1
  (cd "$WT" && flutter pub get >/dev/null && cd packages/tylog_core && dart pub get >/dev/null)
fi
bad=0
reset() { cd "$WT" && git reset -q --hard && git clean -qfd -e .dart_tool -e build && git checkout -q --detach "$BASE" && git clean -qfd -e .dart_tool -e build \
  && bash "$BENCH/tasks/$1/setup.sh" "$REPO" && git add -A && git -c user.name=bench -c user.email=bench@local commit -qm baseline --allow-empty; }
expect() { # name want task
  if bash "$BENCH/tasks/$3/check.sh" "$REPO" > "/tmp/bench_selftest.log" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$2" ]; then echo "ok   $3 $1 -> $got"; else echo "BAD  $3 $1 -> $got (want $2)"; tail -5 /tmp/bench_selftest.log; bad=1; fi
}
for t in $(ls "$BENCH/tasks"); do
  reset "$t"; expect null fail "$t"
  bash "$BENCH/tasks/$t/reference.sh"; expect reference pass "$t"
done
reset t2_same_value_edit; bash "$BENCH/tasks/t2_same_value_edit/reference.sh"
sed -i '' 's/EdgeInsets.all(kEditorInset)/EdgeInsets.all(kSpace16)/' lib/widgets/editor_panel.dart
expect sloppy fail t2_same_value_edit
exit $bad
