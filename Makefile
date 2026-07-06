SHELL := /bin/bash

APP_NAME := tylog
REPO_NAME ?= $(notdir $(CURDIR))
BRANCH := $(shell git branch --show-current)
GITHUB_PAGES_BASE_HREF ?= /$(REPO_NAME)/
RELEASE_GIT_PATHS ?= .gitignore .metadata Makefile README.md PLAN.md USER_MANUAL.md analysis_options.yaml pubspec.yaml pubspec.lock android integration_test ios lib linux macos packages tool web docs sample_vault test
VERSION := $(shell grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')
OWNER_REPO ?= berlogabob/TypstSeq

.PHONY: help setup-native test verify build-web package-pages deploy-pages build-android release clean

help:
	@echo "TyLog release commands"
	@echo "  make setup-native  # explicitly prepare typst_flutter native libraries"
	@echo "  make verify        # run analysis, tests, native integration, and release builds"
	@echo "  make bump-version   # 1.0.0+1 -> 1.0.0+2"
	@echo "  make package-pages  # build Flutter web into docs/ for GitHub Pages"
	@echo "  make deploy-pages   # package docs/, commit, push, enable GitHub Pages"
	@echo "  make build-android  # build release APK"
	@echo "  make release        # bump, test, web docs, APK, commit, tag, push, GitHub Release"

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
	@flutter build linux

build-web:
	@flutter build web --release --no-wasm-dry-run --base-href "$(GITHUB_PAGES_BASE_HREF)"

package-pages: build-web
	@rm -rf docs
	@mkdir -p docs
	@cp -R build/web/. docs/
	@touch docs/.nojekyll
	@echo "GitHub Pages package: docs/"

build-android:
	@flutter build apk --release
	@echo "APK: build/app/outputs/flutter-apk/app-release.apk"

deploy-pages: package-pages
	@git add $(RELEASE_GIT_PATHS)
	@git commit -m "Deploy web $(VERSION)" || echo "No changes to commit"
	@git push origin HEAD:$(BRANCH)
	@if command -v gh >/dev/null && [ -n "$(OWNER_REPO)" ]; then \
		gh api --method POST repos/$(OWNER_REPO)/pages -f source[branch]=$(BRANCH) -f source[path]=/docs >/dev/null 2>&1 || \
		gh api --method PUT repos/$(OWNER_REPO)/pages -f source[branch]=$(BRANCH) -f source[path]=/docs >/dev/null 2>&1 || true; \
		echo "Pages: https://$$(echo $(OWNER_REPO) | cut -d/ -f1).github.io/$$(echo $(OWNER_REPO) | cut -d/ -f2)/"; \
	fi

release:
	@if [ -z "$(SKIP_BUMP)" ]; then $(MAKE) bump-version; else echo "Skipping bump"; fi
	@$(MAKE) test
	@$(MAKE) package-pages
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
		gh api --method POST repos/$(OWNER_REPO)/pages -f source[branch]=$(BRANCH) -f source[path]=/docs >/dev/null 2>&1 || \
		gh api --method PUT repos/$(OWNER_REPO)/pages -f source[branch]=$(BRANCH) -f source[path]=/docs >/dev/null 2>&1 || true; \
		gh release create "$$TAG" --title "Release $$NEW_VERSION" --notes "TyLog $$NEW_VERSION" --target "$(BRANCH)" \
			build/app/outputs/flutter-apk/app-release.apk#tylog-android.apk; \
	fi; \
	echo "Pages: https://$$(echo $(OWNER_REPO) | cut -d/ -f1).github.io/$$(echo $(OWNER_REPO) | cut -d/ -f2)/"; \
	echo "Release: https://github.com/$(OWNER_REPO)/releases/tag/$$TAG"

clean:
	@rm -rf build docs
