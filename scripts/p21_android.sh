#!/bin/sh
set -eu

device=${1:?usage: $0 <device-id> [vault-dir]}
vault=${2:-}
target=${P21_TARGET:-integration_test/p21_semantic_search_native_test.dart}
: "${P21_MODEL_DIR:?set P21_MODEL_DIR to the verified model directory}"

test -f "$P21_MODEL_DIR/model_O4.onnx"
test -f "$P21_MODEL_DIR/tokenizer.json"
test -z "$vault" || test -d "$vault"

log=$(mktemp)
trap 'rm -f "$log"' EXIT
flutter drive --profile -PtylogProfileSuffix=.profiletest \
  --dart-define=P21_HANDSHAKE=true \
  --driver=test_driver/integration_test.dart \
  --target="$target" -d "$device" >"$log" 2>&1 &
pid=$!

ready=
while kill -0 "$pid" 2>/dev/null; do
  ready=$(sed -n 's/^P21_READY //p' "$log" | tail -1)
  test -n "$ready" && break
  sleep 1
done
if test -z "$ready"; then
  cat "$log"
  wait "$pid"
  exit 1
fi

adb -s "$device" push "$P21_MODEL_DIR/model_O4.onnx" "$ready/"
adb -s "$device" push "$P21_MODEL_DIR/tokenizer.json" "$ready/"
if test -n "$vault"; then
  adb -s "$device" shell mkdir -p "$ready/TyLog"
  adb -s "$device" push "$vault/." "$ready/TyLog/"
fi
adb -s "$device" shell touch "$ready/.done"
status=0
wait "$pid" || status=$?
cat "$log"
exit "$status"
