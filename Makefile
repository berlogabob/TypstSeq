SHELL := /bin/bash

APP_NAME := tylog
BRANCH := $(shell git branch --show-current)
OWNER_REPO ?= berlogabob/TypstSeq

.PHONY: help setup-native test-core test-typst test verify verify-android verify-real-vault build-android release

help:
	@echo "TyLog release commands"
	@echo "  make setup-native  # explicitly prepare typst_flutter native libraries"
	@echo "  make test-core     # run Flutter-independent core and CLI tests"
	@echo "  make test-typst    # compile/query the Typst package and format fixture"
	@echo "  make verify        # run analysis, tests, native integration, and release builds"
	@echo "  make verify-android # every integration test, on a real device"
	@echo "  make verify-real-vault # SAF perf against the real vault (profile build)"
	@echo "  make bump-version   # 1.0.0+1 -> 1.0.0+2"
	@echo "  make build-android  # build release APK"
	@echo "  make release        # bump, test, APK, commit, tag, push; Actions publishes"

bump-version:
	@python3 -c 'from pathlib import Path; import re; p=Path("pubspec.yaml"); s=p.read_text(); m=re.search(r"^(version:\s*)(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$$", s, re.M); assert m, "version must look like: version: 1.0.0+1"; new=f"{m.group(1)}{m.group(2)}.{m.group(3)}.{m.group(4)}+{int(m.group(5))+1}"; p.write_text(s[:m.start()]+new+s[m.end():]); print(new.replace("version: ", ""))'

setup-native:
	@./tool/setup_typst_native.sh

test-core:
	@cd packages/tylog_core && dart test
	@cargo test --manifest-path packages/tylog_import_core/Cargo.toml

test-typst:
	@typst compile --root typst/tylog typst/tylog/examples/basic.typ /tmp/tylog-example.pdf
	# Every call shape the app writes must compile against the SHIPPED package
	# and survive a metadata query. A field the app emits but the package does
	# not declare is a hard Typst error, and nothing caught that until 167 real
	# notes stopped compiling.
	@typst compile --root typst/tylog typst/tylog/tests/app_written.typ /tmp/tylog-app-written.pdf
	@cd typst/tylog && typst eval 'query(<tylog-task>)' --root . --in tests/app_written.typ > /tmp/tylog-tasks.json
	@grep -q '"id":"clocked"' /tmp/tylog-tasks.json
	@grep -q '2025-12-28T10:02:11' /tmp/tylog-tasks.json
	@cd test/fixtures/tylog_format_v1 && typst eval 'query(metadata)' --root . --in valid.typ > /tmp/tylog-metadata.json
	@for entity in note link tag date attachment task; do grep -q "\"label\":\"<tylog-$$entity>\"" /tmp/tylog-metadata.json; done
	@grep -q '"schema":1' /tmp/tylog-metadata.json
	# Conformance: the package's own emissions (not a hand-written fixture)
	# must carry every entity label and schema — spec/package drift fails here.
	@cd typst/tylog && typst eval 'query(metadata)' --root . --in examples/basic.typ > /tmp/tylog-conformance.json
	@for entity in note link tag date attachment task; do grep -q "\"label\":\"<tylog-$$entity>\"" /tmp/tylog-conformance.json || { echo "package does not emit <tylog-$$entity>"; exit 1; }; done
	@grep -q '"schema":1' /tmp/tylog-conformance.json
	@grep -q '"id":"example"' /tmp/tylog-conformance.json
	@grep -q '"status":"done"' /tmp/tylog-conformance.json

test: test-core test-typst
	@flutter analyze
	@flutter test

# Globbed, never enumerated. The hand-written lists that used to live here left
# SIX of twelve integration tests in no target at all, so nobody noticed three of
# them had stopped working — one could not run on Android at all, one had rotted
# on both platforms, and one asserted a hardware-dependent speed ratio. A new
# file now runs automatically.
#
# One invocation per file, not one for all of them: a second file in the same
# `flutter test` call fails to load with "Unable to start the app on the device",
# because the first test's app is still holding the device.
#
# Platform exclusions belong in the test as `skip:`, next to the reason for them
# (see vault_worker_saf_test.dart). Never `if (!Platform.isX) return;` — that
# reports a PASS for a test that never ran, which is how this rotted.
#
# vault_worker_real_vault_test is excluded deliberately: it measures the real
# vault over SAF and must be a profile build via `flutter drive`, not
# `flutter test` (which builds debug, has no SAF grant, and would silently
# measure an empty vault). It has its own target below.
INTEGRATION_TESTS := $(filter-out integration_test/vault_worker_real_vault_test.dart,$(wildcard integration_test/*.dart))

verify: test
	@for t in $(INTEGRATION_TESTS); do echo "== $$t"; flutter test $$t -d macos -r expanded || exit 1; done
	@flutter build apk --release
	@flutter build macos --release
	@if [ "$$(uname -s)" = Linux ]; then flutter build linux; else echo "Skipping Linux build on $$(uname -s); covered by CI."; fi

# Checks that need real hardware, so they cannot live in CI (which has no
# device). ANDROID_DEVICE defaults to the only attached device.
ANDROID_DEVICE ?= $(shell adb devices | awk 'NR>1 && $$2=="device" {print $$1; exit}')
# Gradle needs a JDK, and `flutter build` uses Android Studio's bundled one
# rather than whatever is on PATH. Deliberately NOT defaulting to $JAVA_HOME:
# on this machine it points at .../Contents/jbr, one level above the actual
# JDK home, which Gradle rejects outright. Override explicitly if yours differs.
GRADLE_JAVA_HOME ?= /Applications/Android Studio.app/Contents/jbr/Contents/Home
verify-android:
	@if [ -z "$(ANDROID_DEVICE)" ]; then echo "No Android device attached (adb devices)."; exit 1; fi
	@echo "Using device $(ANDROID_DEVICE)"
	@for t in $(INTEGRATION_TESTS); do echo "== $$t"; flutter test $$t -d $(ANDROID_DEVICE) -r expanded || exit 1; done
	# Kotlin instrumented tests. These cover SafBridge.writeAtomic against a
	# provider that de-duplicates on rename, which is the one path that can lose
	# a note and the one the Dart suite structurally cannot reach: its "SAF"
	# fake extends LocalVaultStorage, so it uses POSIX rename and overwrites
	# silently. Reverting the fix makes them reproduce `vault (1).lock` exactly.
	@if [ ! -x "$(GRADLE_JAVA_HOME)/bin/java" ]; then \
		echo "No JDK at $(GRADLE_JAVA_HOME) — set GRADLE_JAVA_HOME=/path/to/jdk"; exit 1; \
	fi
	@cd android && JAVA_HOME="$(GRADLE_JAVA_HOME)" ./gradlew :app:connectedDebugAndroidTest

# The real-vault SAF measurement. Needs a profile build (release-signed, so it
# installs over the release app and keeps the persisted SAF grant) and a device
# whose active vault is android-tree; the test fails loudly otherwise.
verify-real-vault:
	@if [ -z "$(ANDROID_DEVICE)" ]; then echo "No Android device attached (adb devices)."; exit 1; fi
	@flutter drive --profile --driver=test_driver/integration_test.dart \
		--target=integration_test/vault_worker_real_vault_test.dart -d $(ANDROID_DEVICE)

build-android:
	@flutter build apk --release
	@echo "APK: build/app/outputs/flutter-apk/app-release.apk"

release:
	@if [ -z "$(SKIP_BUMP)" ]; then $(MAKE) bump-version; else echo "Skipping bump"; fi
	@$(MAKE) test
	@$(MAKE) build-android
	@set -e; \
	NEW_VERSION="$$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')"; \
	TAG="v$$NEW_VERSION"; \
	if [ -z "$(OWNER_REPO)" ]; then echo "No origin remote. Create/push repo first."; exit 1; fi; \
	if git rev-parse "$$TAG" >/dev/null 2>&1 || git ls-remote --exit-code --tags origin "$$TAG" >/dev/null 2>&1; then \
		echo "Tag $$TAG already exists. Run again to bump."; exit 1; \
	fi; \
	git add -A; \
	git commit -m "Release $$NEW_VERSION" || echo "No changes to commit"; \
	git tag -a "$$TAG" -m "Release $$NEW_VERSION"; \
	git push origin HEAD:$(BRANCH); \
	git push origin "$$TAG"
	@NEW_VERSION="$$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')"; TAG="v$$NEW_VERSION"; \
	echo "GitHub Actions is building and publishing $$TAG: https://github.com/$(OWNER_REPO)/actions"

