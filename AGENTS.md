## Dev tooling

### On-device profiling (Android)
The `profile` build type is release-signed (`android/app/build.gradle.kts`), so a profile APK installs over the release app without wiping the vault:
```bash
flutter build apk --profile && \
  ~/Library/Android/sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-profile.apk
```
Use this (not `--debug`, which has appId suffix `.debug`) to capture real frame timings via DevTools / `dumpsys gfxinfo org.tylog.tylog`.

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
