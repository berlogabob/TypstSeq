#!/usr/bin/env bash
# Apple Silicon release workaround for Xcode 27's multi-arch lipo verification.
set -euo pipefail
cd "$(dirname "$0")/.."
config=$(mktemp -t tylog-arm64)
trap 'rm -f "$config"' EXIT
printf 'ARCHS = arm64\nONLY_ACTIVE_ARCH = YES\n' > "$config"
XCODE_XCCONFIG_FILE="$config" "${FLUTTER_BIN:-flutter}" build macos --release "$@"
