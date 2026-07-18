SHELL := /bin/bash

APP_NAME := tylog
BRANCH := $(shell git branch --show-current)
RELEASE_GIT_PATHS ?= .github .gitignore .graphifyignore .metadata Makefile README.md PLAN.md USER_MANUAL.md analysis_options.yaml pubspec.yaml pubspec.lock android docs integration_test ios lib linux macos windows packages spec tool typst sample_vault test graphify-out/GRAPH_REPORT.md graphify-out/graph.html graphify-out/graph.json
OWNER_REPO ?= berlogabob/TypstSeq

.PHONY: help setup-native test-core test-typst test verify build-android publish-release release clean

help:
	@echo "TyLog release commands"
	@echo "  make setup-native  # explicitly prepare typst_flutter native libraries"
	@echo "  make test-core     # run Flutter-independent core and CLI tests"
	@echo "  make test-typst    # compile/query the Typst package and format fixture"
	@echo "  make verify        # run analysis, tests, native integration, and release builds"
	@echo "  make bump-version   # 1.0.0+1 -> 1.0.0+2"
	@echo "  make build-android  # build release APK"
	@echo "  make publish-release # upload/resume the current version's GitHub Release"
	@echo "  make release        # bump, test, APK, commit, tag, push, GitHub Release"

bump-version:
	@python3 -c 'from pathlib import Path; import re; p=Path("pubspec.yaml"); s=p.read_text(); m=re.search(r"^(version:\s*)(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$$", s, re.M); assert m, "version must look like: version: 1.0.0+1"; new=f"{m.group(1)}{m.group(2)}.{m.group(3)}.{m.group(4)}+{int(m.group(5))+1}"; p.write_text(s[:m.start()]+new+s[m.end():]); print(new.replace("version: ", ""))'

setup-native:
	@./tool/setup_typst_native.sh

test-core:
	@cd packages/tylog_core && dart test
	@cargo test --manifest-path packages/tylog_import_core/Cargo.toml

test-typst:
	@typst compile --root typst/tylog typst/tylog/examples/basic.typ /tmp/tylog-example.pdf
	@cd test/fixtures/tylog_format_v1 && typst eval 'query(metadata)' --root . --in valid.typ > /tmp/tylog-metadata.json
	@for entity in note link tag date attachment task; do grep -q "\"label\":\"<tylog-$$entity>\"" /tmp/tylog-metadata.json; done
	@grep -q '"schema":1' /tmp/tylog-metadata.json

test: test-core test-typst
	@flutter analyze
	@flutter test

verify: test
	@flutter test integration_test/pkms_native_test.dart -d macos
	@flutter test integration_test/markdown_import_native_test.dart -d macos
	@flutter build apk --release
	@flutter build macos --release
	@if [ "$$(uname -s)" = Linux ]; then flutter build linux; else echo "Skipping Linux build on $$(uname -s); covered by CI."; fi

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
	git add $(RELEASE_GIT_PATHS); \
	git commit -m "Release $$NEW_VERSION" || echo "No changes to commit"; \
	git tag -a "$$TAG" -m "Release $$NEW_VERSION"; \
	git push origin HEAD:$(BRANCH); \
	git push origin "$$TAG"
	@NEW_VERSION="$$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')"; TAG="v$$NEW_VERSION"; \
	echo "GitHub Actions is building and publishing $$TAG: https://github.com/$(OWNER_REPO)/actions"

publish-release:
	@set -e; \
	command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || { echo "GitHub CLI is unavailable or not authenticated."; exit 1; }; \
	APK="build/app/outputs/flutter-apk/app-release.apk"; \
	test -f "$$APK" || { echo "Missing $$APK; run make build-android first."; exit 1; }; \
	UPLOAD_APK="build/app/outputs/flutter-apk/tylog-android.apk"; \
	cp "$$APK" "$$UPLOAD_APK"; \
	NEW_VERSION="$$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')"; \
	TAG="v$$NEW_VERSION"; \
	echo "Uploading $$(du -h "$$APK" | cut -f1) APK for $$TAG; this may take several minutes..."; \
	if gh release view "$$TAG" --repo "$(OWNER_REPO)" >/dev/null 2>&1; then \
		gh release upload "$$TAG" "$$UPLOAD_APK" --clobber --repo "$(OWNER_REPO)"; \
	else \
		gh release create "$$TAG" --title "Release $$NEW_VERSION" --notes "TyLog $$NEW_VERSION" --target "$(BRANCH)" --repo "$(OWNER_REPO)" "$$UPLOAD_APK"; \
	fi; \
	echo "GitHub Release upload complete."

clean:
	@rm -rf build
