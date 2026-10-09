set -e
[ "$(wc -l < lib/workspace_controller.dart)" -ge 2450 ] || { echo "file truncated"; exit 1; }
[ "$(git diff --numstat HEAD -- lib/workspace_controller.dart | cut -f2)" -le 3 ] || { echo "too many deletions"; exit 1; }
cp "$1/tool/model_bench/tasks/t3_large_file_edit/hidden/bench_t3_test.dart" test/bench_t3_test.dart
trap 'rm -f test/bench_t3_test.dart' EXIT
flutter analyze --no-pub lib/workspace_controller.dart
flutter test test/bench_t3_test.dart
