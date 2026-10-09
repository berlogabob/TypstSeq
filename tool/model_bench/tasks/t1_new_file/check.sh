set -e
cp "$1/tool/model_bench/tasks/t1_new_file/hidden/bench_t1_test.dart" test/bench_t1_test.dart
trap 'rm -f test/bench_t1_test.dart' EXIT
flutter analyze --no-pub lib/sync_stage_text.dart
flutter test test/bench_t1_test.dart
