## Dev tooling

### On-device profiling (Android)
On the P30, use only the isolated `org.tylog.tylog.profiletest` package for device builds and measurements. Never install, uninstall, clear, or launch `org.tylog.tylog` during development; verify its recorded `firstInstallTime` remains unchanged before and after device work. The `.profiletest` app already has a real-vault copy for measurements.

For integration tests, prefer `flutter test integration_test/<test_file>.dart -d <device-id> --no-uninstall`. If the test requires a separately installed APK, build with the `.profiletest` suffix and run it with `adb install -r` plus `adb shell am instrument`; do not use `flutter drive` on phones that have the real app, because it can uninstall the production package. Keep profile measurements release-signed when the matching key is available:
```bash
cd android && ./gradlew :app:assembleProfile -PtylogProfileSuffix=.profiletest && \
  ~/Library/Android/sdk/platform-tools/adb -s <device-id> install -r app/build/outputs/apk/profile/app-profile.apk
```
Use this APK with DevTools or `integration_test/support/editor_frame_metrics.dart` for Flutter frame timings. `dumpsys gfxinfo` measures platform decor and cannot establish Flutter jank. Never use `svc power stayon` or `flutter drive` for device work.

Cold-start measurements: after `adb install -r` Android relaunches the isolated `.profiletest` app if it was in the foreground, so a following `am start` only reaches the running instance ("intent delivered to currently running top-most instance") and its `TYLOG_STARTUP` marks are not a cold start. Always `adb shell am force-stop org.tylog.tylog.profiletest` and wait a few seconds before `adb shell monkey -p org.tylog.tylog.profiletest 1`; enlarge the log buffer first on noisy phones (`adb logcat -G 16M`).

Engineering policies and their local test gates live in [CONTEXT.md → Engineering rules](CONTEXT.md#engineering-rules); read them when changing startup, indexing, editor layout, sync, or release tooling.

### pxpipe (optional token-cost proxy)
`pxpipe-proxy` renders bulky context to images to cut token cost (~59-70% on dense workloads). It is a proxy, **not** a Claude Code skill, and can only be used at session launch:
```bash
npx pxpipe-proxy                                   # starts proxy on 127.0.0.1:47821
ANTHROPIC_BASE_URL=http://127.0.0.1:47821 claude   # in a new terminal
```
Caveat: imaging is lossy — byte-exact recall of long hex/IDs/secrets is imperfect, so keep those as text. Metrics log to `~/.pxpipe/events.jsonl`.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
