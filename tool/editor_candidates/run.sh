#!/usr/bin/env bash
# Isolated synthetic evaluation; never installs the TyLog production package.
set -euo pipefail
engine="${1:?Usage: run.sh super_editor|flutter_quill DEVICE_ID [flutter drive flags]}"
device="${2:?Supply macos or an adb device ID}"
shift 2
case "$engine" in
  super_editor) version=0.3.0-dev.52 ;;
  flutter_quill) version=11.5.1 ;;
  *) printf 'Unknown editor: %s\n' "$engine" >&2; exit 2 ;;
esac
sources="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$sources/../.." && pwd)"
probe="$(mktemp -d "${TMPDIR:-/tmp}/tylog-editor-probe.XXXXXX")"
printf 'Synthetic probe and results: %s\n' "$probe"
flutter create --platforms=macos,android --project-name=tylog_editor_probe \
  --org=org.tylog.probe --no-pub "$probe"
cat > "$probe/pubspec.yaml" <<YAML
name: tylog_editor_probe
publish_to: none
environment:
  sdk: ^3.12.2
dependencies:
  flutter:
    sdk: flutter
  $engine: $version
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
flutter:
  uses-material-design: true
YAML
rm "$probe/test/widget_test.dart"
mkdir -p "$probe/integration_test" "$probe/test_driver"
cp "$sources/$engine.dart.template" "$probe/lib/main.dart"
cp "$sources/editor_probe_test.dart.template" "$probe/integration_test/editor_probe_test.dart"
cp "$repo/integration_test/support/editor_frame_metrics.dart" "$probe/integration_test/"
cp "$repo/test_driver/integration_test.dart" "$probe/test_driver/"
cd "$probe"
flutter pub get
flutter drive --no-pub --profile --device-id "$device" \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/editor_probe_test.dart "$@"
