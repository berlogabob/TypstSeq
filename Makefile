SHELL := /bin/bash

APP_NAME := tylog
BRANCH := $(shell git branch --show-current)
RELEASE_GIT_PATHS ?= .gitignore .metadata Makefile README.md PLAN.md USER_MANUAL.md analysis_options.yaml pubspec.yaml pubspec.lock android integration_test ios lib linux macos packages tool sample_vault test
OWNER_REPO ?= berlogabob/TypstSeq

.PHONY: help setup-native test verify build-android release clean

help:
	@echo "TyLog release commands"
	@echo "  make setup-native  # explicitly prepare typst_flutter native libraries"
	@echo "  make verify        # run analysis, tests, native integration, and release builds"
	@echo "  make bump-version   # 1.0.0+1 -> 1.0.0+2"
	@echo "  make build-android  # build release APK"
	@echo "  make release        # bump, test, APK, commit, tag, push, GitHub Release"

bump-version:
	@python3 -c 'from pathlib import Path; import re; p=Path("pubspec.yaml"); s=p.read_text(); m=re.search(r"^(version:\s*)(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$$", s, re.M); assert m, "version must look like: version: 1.0.0+1"; new=f"{m.group(1)}{m.group(2)}.{m.group(3)}.{m.group(4)}+{int(m.group(5))+1}"; p.write_text(s[:m.start()]+new+s[m.end():]); print(new.replace("version: ", ""))'

setup-native:
	@./tool/setup_typst_native.sh

test:
	@flutter analyze
	@flutter test

verify: test
	@flutter test integration_test/pkms_native_test.dart -d macos
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
	git push origin "$$TAG"; \
	if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then \
		gh release create "$$TAG" --title "Release $$NEW_VERSION" --notes "TyLog $$NEW_VERSION" --target "$(BRANCH)" \
			build/app/outputs/flutter-apk/app-release.apk#tylog-android.apk; \
	fi; \
	echo "Release: https://github.com/$(OWNER_REPO)/releases/tag/$$TAG"

clean:
	@rm -rf build
