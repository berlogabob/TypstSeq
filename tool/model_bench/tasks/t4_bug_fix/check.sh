set -e
[ "$(git diff --numstat HEAD -- packages/tylog_core/lib/src/scanner.dart | cut -f2)" -le 60 ] || { echo "too many deletions"; exit 1; }
[ -z "$(git status --porcelain -- packages/tylog_core/test)" ] || { echo "tests were edited"; exit 1; }
cd packages/tylog_core && dart analyze lib && dart test
