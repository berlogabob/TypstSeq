# Backlog flood, junk cleanup and two sync bugs — 2026-08-19 → 08-21

Work report covering the overnight article explosion, its root causes, the
vault cleanup, and the three app/pipeline defects found along the way.

## Scoreboard

| Metric | Before | After |
| --- | --- | --- |
| Vault articles | 3,163 | **4,722** |
| Failure ledger (unique URLs) | 3,044 | **585** |
| Uncategorized articles | 7.5% (140) | **0.0% (0)** |
| Promoted tags (used on ≥5 notes) | 297 | 346 |
| Phone vs Mac article delta | −715 | **0** |
| Pending sync conflicts | 3 | **0** |
| Phone sync memory (peak RSS) | 1.6–2.3 GB | **381 MB** |
| Junk-titled notes | 22 | **0** |
| Duplicate source URLs | 58 | **0** |

## What actually happened

The vault appeared to grow explosively overnight (~1,870 → 3,273 articles
between 23:00 and 12:09). It was not runaway duplication — only 58 duplicate
URLs existed vault-wide. It was a dam break.

Since roughly 08-14 every LLM call through the `claude` provider had failed
with `FileNotFoundError: 'claude'`: `engine.py` invoked the bare binary name
and launchd's PATH does not include `~/.local/bin`. Each URL burned six failed
attempts and landed in `failures.jsonl`, which grew to ~3,850 entries. On
08-18 at 23:47 the engine was switched to codex and a retry pass flushed the
entire backlog at once — 1,347 articles in about four hours.

Two further defects turned that flush into damage. The retry loop rewrote the
ledger only after the whole pass, so a crash mid-run lost all progress: the
resume pass re-fetched and re-summarized 3,781 already-recovered URLs, then
died too. And nothing gated quality, so 404 pages, login walls and link shells
were saved as genuine articles — summarized in earnest, tagged `ошибка`, and
auto-related to each other, polluting the concept clusters.

## Fixes shipped

### Pipeline (`~/Nextcloud/scripts/article-pipeline`)

| Commit | Change |
| --- | --- |
| `6013873` | Skip binary-file URLs (`.safetensors`, `.ckpt`, archives, media) by extension before download; stream responses. Prevents the 7 GB-download freeze. |
| `47fb36b` | Resolve `claude`/`codex` to absolute paths; checkpoint the ledger every 20 URLs; add the `junk_reason()` quality gate. |
| `e6efee8` | `prune_ledger.py` (drop ledger entries already in the vault) and `audit_junk.py` (review-first junk audit with `--apply`). |
| `f83b552` | Switch back to claude (haiku primary, sonnet fallback) after codex quota death; `stdin=DEVNULL` on CLI subprocesses. |
| `efdd86a` | Sanitize lone UTF-16 surrogates at note-write time. |
| `985ebcf` | Read `_index/index.json` whether gzipped or plain. |

The checkpointing fix paid for itself repeatedly: the drain hit three separate
mid-run failures and none cost more than 20 URLs of progress.

### App (`TypstSeq`)

**`ce1533e` — sync resurrected remote deletions.** "Local exists, remote
missing" always re-uploaded, so notes deleted on one device came back from
every other; the PUT into the deleted parent collection then returned 404 and
failed the whole run, which restarted forever (~135% CPU, 2 GB resident, zero
progress — the phone felt hung). Now, when the cursor proves the server held
this exact content (etag recorded, bytes unchanged, state not recovered, not a
rename), a missing remote is treated as another device's deletion. Local edits
still win, untracked files still upload, and a per-run guard refuses to mirror
a server wipe (remote must still carry `_system/tylog.typ` and list at least
half the cursors). The old contract test asserted the resurrection behaviour
and was rewritten to cover both sides of the new rule.

**`2630d11` — sync held every transferred file in memory.** The bulk-download
ZIP path cached each entry's decompressed bytes on its `ArchiveFile` until the
end of the run. `read()` now streams through `writeContent(freeMemory: true)`
so the working set is one file at a time, and downloads hash once instead of
twice. Measured on a 237-article catch-up: 1.6–2.3 GB → 381 MB peak.

Investigation notes for the remaining memory suspects (concurrent full-file
buffers, the Depth-infinity PROPFIND string) are in
[`sync-memory-findings.md`](sync-memory-findings.md); they were not addressed.

## Vault cleanup

Two passes, both review-first: 110 notes (junk plus 54 duplicate-URL groups,
keeping the newest of each), then 98 more after the drain — bot-wall pages
from Amazon and AliExpress, login shells, dead 404s. Kept deliberately:
HuggingFace spaces and collections, Unsloth and GitHub CLI docs, Qwen Studio,
the user's own repository notes, Claude artifact pages. Dangling
`ref-note` links in surviving notes were stripped in both passes.

Tag clustering converged on its own — the remap script proposes nothing
further, and uncategorized reached zero because the pipeline feeds established
vocabulary to the model at summarization time.

## The drain

Four passes were needed. The first (codex) recovered 768 URLs before codex
began failing every call with `Reading additional input from stdin...` at
00:20 — quota exhaustion, confirmed by the same failure on a trivial prompt.
The second and third (claude/haiku) hit the surrogate crash and a transient
APFS disk-full. The fourth completed cleanly at 01:18, recovering 859.

Throughput on claude/haiku is about 2.4 URLs/min, roughly 30 s per article, of
which ~20 s is the CLI call itself (fresh process per call). The run is
deliberately serial.

The 585 remaining ledger entries are the genuinely hard cases: 295
`parse_error`, 142 dead `not_found`, 64 `llm_error`, 46 `blocked`. The weekly
retry cron will keep chipping at the retryable ones.

## Contract note

The final reindex surfaced a cross-repo break: the app now writes
`_index/index.json` gzip-compressed under the same filename (with a magic-byte
fallback for older plain files), and every pipeline-side reader assumed text.
`vocabulary()` was failing through to "no usable tag vocabulary", which would
have restarted the singleton-tag problem on the next batch of articles. All
readers now share `tag_scan.read_index_bytes()`.

This is the second time the unpinned format contract between the app and the
pipeline has bitten silently. Both sides remain worth checking whenever either
changes its serialization.

## Verification

- Pipeline: 213 tests pass, including new regression tests for the junk gate,
  the ledger checkpoint (crash mid-retry loses ≤20 URLs), and the surrogate
  write.
- App: 471 tests pass, 87 of them in the sync suite.
- Device: fixed builds installed on the Huawei P30 via `adb install -r`;
  deletion propagation confirmed on-device (`deletedLocal: 94`), memory
  profiled across a real catch-up sync, article counts and conflict state
  matched against the Mac.
- Index: 4,722 indexed articles equals the file count exactly.
