#!/bin/bash
set -eu
: "${TYLOG_PRIVATE_PDF_ROOT:?Set TYLOG_PRIVATE_PDF_ROOT to the private PDF corpus root}"

log_file=$(mktemp)
trap 'rm -f "$log_file"' EXIT
flutter test --no-pub integration_test/private_pdf_corpus_test.dart -d macos >"$log_file" 2>&1 &
test_pid=$!
peak_kb=0
while kill -0 "$test_pid" 2>/dev/null; do
  for app_pid in $(pgrep -f '[T]yLog.app/Contents/MacOS/TyLog' 2>/dev/null || true); do
    rss_kb=$(ps -o rss= -p "$app_pid" | tr -d ' ')
    if [ -n "$rss_kb" ] && [ "$rss_kb" -gt "$peak_kb" ]; then
      peak_kb=$rss_kb
    fi
  done
  sleep 0.1
done
if ! wait "$test_pid"; then
  echo 'PRIVATE_PDF_TEST=FAIL (details suppressed to protect corpus data)'
  exit 1
fi
summary=$(rg '^PRIVATE_PDF_SUMMARY ' "$log_file" || true)
if [ -z "$summary" ]; then
  echo 'PRIVATE_PDF_TEST=FAIL (aggregate summary missing)'
  exit 1
fi
if [ "$peak_kb" -eq 0 ]; then
  echo 'PRIVATE_PDF_TEST=FAIL (app process RSS was not sampled)'
  exit 1
fi
printf '%s APP_PEAK_RSS_KB=%s\n' "$summary" "$peak_kb"
echo 'PRIVATE_PDF_TEST=PASS'
