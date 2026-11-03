# Activity plan (auto mode, started 2026-10-14)

Rules: Claude coordinates; codex CLI does multi-file edits; pi + Ornith 35b on Studio does new small files, scripts, docs and tests (read every diff); haiku Explore for read-only digging. Every slice: analyze + FULL flutter test green, graphify update, visual check on P30 (adb) and the Mac app, then commit. No release before the user confirms GUI. New issues go to the log below and into the queue.

## Queue (in order)
1. D3 dialogs, sheets, notices  [done 2026-10-15, 1498 tests green, P30 checked: More, Library, Insert sheet]
2. D4 icon sweep (app_icons.dart)  [done 2026-10-15, 1498 green, P30 checked; agenda icon clash fixed]
3. Release 0.18.0 candidate  [version bumped + changelog committed 2026-10-15, NOT tagged; waiting for user GUI confirmation] (D1-D4 + presets): install on P30 + Mac, A24 when connected; user confirms; then tag
4. D5 Today/Journal/Search consistency, editor menu naming, Split view entry, `/` palette Task, graph chips
5. D6 component themes, raw colours/fonts to tokens, dark hint colour
6. AI: Articles card in AI settings (tasks.articles), screenshot script reads ai.json, real-key check, schedule 03:00 test, RAG docs corpus
7. Verify on both platforms after each slice (Mac app: update from release zip; for unreleased UI use `flutter build macos`)

## Issue log
- 2026-10-14: full flutter test is blocked inside the codex sandbox (localhost sockets, disk); Claude runs the full suite after every codex slice.
- 2026-10-14: A24 not reachable over adb since the 0.17.3 release; still on 0.17.0.
- 2026-10-14: Mac app is 0.17.3; D1/D2 UI not yet on Mac (needs a local macOS build or the 0.18.0 zip).
- 2026-10-15: D3 Insert sheet shows title 'Insert' above group heading 'Insert' (duplicate). Fix in D5: sheet title 'Add to note', groups Insert / Text style / Structure.
- 2026-10-15: editor dock on P30 is a single scrolling row; Insert (+) is last, off-screen on first view. Consider moving Insert to the first slot in D5.
- 2026-10-15: codex modifies ~1300 lines per sweep (re-indentation from wrapping); always run the full suite and a P30 check before committing.
- 2026-10-15: Mac visual check impossible while the screen is locked (lock screen at 00:18); debug macOS build compiles and launches (flutter build macos --debug ok). Redo Mac checks when the user is at the Mac; do not try to unlock.
- 2026-10-15: D4 sweep changed agenda icon to view_agenda (same as group-by); fixed to checklist_outlined. Lesson: after icon sweeps look at Today, Library, Settings on P30.
- 2026-10-15: earlier bare `git push -q` silently skipped (no upstream); use `git push -q origin HEAD`.
- 2026-10-15: D5 done and checked on P30 (Add to note sheet, + first in dock, Split in view popup); Date icon changed to calendar_month grid (D4) - fine.
- 2026-10-15: D6 regression: dropping the app-level `inputDecorationTheme(border: none)` boxed the editor (then underline); restored in tyLogTheme, test pins it. Lesson: always screenshot Today (editor) after any theme change.
- 2026-10-15: Vaults sheet shows raw `content://com.android.exte...` as the vault subtitle; show a friendly path (D7 candidate).
- 2026-10-15: AI settings section: sub-headers weak (Articles/Screenshots titles look like field values); polish in D7 together with the Vaults subtitle. A24 still needs the install.
- 2026-10-15: D7 done: Vaults friendly path, AI task block headers. No new releases until the user asks.

## Wave 2 (2026-10-15, user: "do all 3", then ONE release; codex+pi max, Claude reviews)
W1 Module Packs phase C: (a) upgrade removes files dropped by the new pack (unedited only); (b) Reschedule: shift due of open module tasks to a new start date (surgical writes, task_mutation); (c) Progress: per-module done/total tasks + scores in the module dialog; (d) docs/modules/AUTHORING.md + manifest.schema.json (pi).
W2 RAG docs corpus: bundled docs (spec/, docs/modules/) indexed under `doc:` source ids in lib/retrieval, searchable alongside notes.
W3 Audio: peak backfill for pack mp3s (waveform without first open); A24 device checks pending (needs adb).
Release after W1-W3: full test, tag, install P30/Mac/A24.
- 2026-10-15: W1 core+UI, W2 RAG docs corpus done (1510 green); W3 audio: peaks backfill left to first open per plan; moduleProgress reads record paths, not a vault listing (SAF cost).
- 2026-10-15: P30 test in an empty vault (Download/TyLogModTest): install 72 notes + 99 mp3 OK, Modules sheet "0/72 tasks", Reschedule +5 days shifted all due dates and start (~50 s), Uninstall removed all 171 files (~70 s). Test vault removed from use; TyLog vault active again.
- 2026-10-15 ISSUE: Reschedule and Uninstall show no progress UI for ~50-70 s on SAF; add a progress dialog (like Install).
- 2026-10-15 ISSUE: Vaults sheet showed "SD card//storage/emulated…" for a Downloads-provider tree uri (raw:/storage/...); friendlyVaultPath now maps raw: to Internal storage (fixed, unreleased).
- 2026-10-15 OPEN: prebuilt peaks for pack audio (pack.py computes 200 buckets, app draws lesson attachment waveform from stored peaks) awaiting user decision.
- 2026-10-15: peak sidecars done: pack.py (BerloPortuga, 1.1.0) writes `<mp3>.peaks` (200 hex buckets) and manifest `unit: lessons`; app reads sidecar before codec decode (AudioInlineCard.readPeaks). P30 check: pack 1.1.0 installed in test vault (198 asset files, 99 .peaks), Modules shows "0/72 lessons", lesson 1 waveform drawn at once. Reschedule/Uninstall now show a progress dialog (not re-timed on device).
- 2026-10-15 ISSUE: after Uninstall empty folders (projects/<id>, assets/modules/<id>) remain in the vault; harmless, SAF dir delete not implemented.
- 2026-10-15 NOTE: pack.py in BerloPortuga is not under git (no repo); dist/pt-pt-a2b1.tylogpack 1.1.0 is the build to publish with the next release.

## Wave 3: pre-release checks for 0.18.1 (2026-10-15, user: Mac unlocked, A24 connected, "whole scope")
C1 pack upgrade 1.0.0 -> 1.1.0 on device (adds 99 .peaks, unit, edited note kept)
C2 RAG docs search on device (P30 + Mac)
C3 Nextcloud sync of pack files (.peaks, 198 assets)
C4 Mac visual check D1-D7, Modules sheet
C5 A24: install, record, import mp3, waveform
C6 real server key: articles/screenshots task cards, 03:00 schedule
C7 housekeeping: BerloGPortuga git init, upload pack 1.1.0 to release, empty dirs after uninstall
Then: tag v0.18.1+151, install everywhere.
- 2026-10-15 ISSUE (Mac 0.18.1 real vault 5046 notes): Search tab 'Search failed. Try again.' for query 'tylogpack manifest sha256'; investigate (RAG doc kind? FTS syntax?)
- 2026-10-15 FIXED: Mac "Search failed" = query embedder ran on the UI isolate before RustLib was initialised there ("flutter_rust_bridge has not been initialized"); nativeEmbedder now initialises it once via TypstCompiler.create(). Affected semantic search on every desktop/phone start until a Typst compile ran. Verified on Mac debug: search works, docs corpus results (AUTHORING.md, PACK-SPEC.md) appear.
- 2026-10-15 INCIDENT: blind adb taps on P30 after app relaunch (keyboard was open, active vault was the REAL TyLog) typed junk ('п', 'р-н р-н р-н р-н') into today's note; deleted it at once (Today empty again) but a sync cycle was running; check the 2026-10-15 daily in the real vault has no stray text. RULE: screenshot before every blind tap sequence; check active vault first.
- 2026-10-15 C1 DONE on P30 (test vault): 1.0.0 installed, lesson 5 edited via adb, Update to 1.1.0 -> 99 .peaks added, unit "lessons", edit kept, 72 notes / 198 assets. Uninstall showed "Removing module" dialog. Vaults sheet now shows "Internal storage/Download…" for the Downloads-provider vault.
- 2026-10-15 C3 DONE by code: isSyncableVaultPath is prefix based (assets/, projects/, _system/), no extension filter, so .peaks and module records sync.
- 2026-10-15 C4 DONE on Mac (0.18.1 release build, real vault): More, Settings, Library toolbar/chips/tabs match the design; Search failure found and fixed (see above).

## Wave 4 (2026-10-15): pack docs + example pack repo (proposal, awaiting user go)
- docs/modules/AUTHORING.md grows into a step-by-step guide; spec stays in this repo (authoritative); example pack repo `tylog-pack-pt-pt` (from BerloPortuga: sources, tools/pack.py with peaks, CI building the .tylogpack onto a GitHub release) is the worked example the guide links to.
- 0.18.1+151 released 2026-10-15: pack 1.1.0 attached; installed on P30, A24, Mac.

## Wave 5 (2026-10-15): long recordings (calls, 1-1.5 h)
- 25 min cap was a sync-size guess (25 MB at ~16 kB/s), not a codec limit. Now: speech preset 16 kHz/32 kbps (~4 kB/s), cap 4 h, rotate every 20 min into separate audio notes (AudioNoteRecorder.rotate, ADTS frame boundary, gapless; parts saved via onPart while recording).
- Verified: Mac real Nextcloud chunked upload of 29 MB random file in 8.7 s (test/real_account/chunked_upload_real_test.dart); P30 test vault, 30 s segments: parts 29.9-30.0 s at 32.66 kbps, parts survive an app kill (installing over the running app), recording sheet stays on top (parts save with open:false). Full suite 1514 passed.
- 2026-10-15 ISSUE (pre-existing, reproduced on a build without these changes): a recording made from Library > Audio does not appear in the list and its note screen does not open until the app restarts; files and note are on disk. Cause not found (worker scan after SAF write?).
- 2026-10-15 OPEN: transcription has no speaker separation (tool/transcribe_worker.py is plain faster-whisper "small"); group calls need diarization (pyannote or Studio-side model). Recording is mic-only: Android does not give apps the remote side of a phone call.

## Wave 6 (2026-10-16): open items after 0.19.0
- FIXED: Library > Audio recording not shown / not opening until restart. Save awaited a full index refresh (minutes on a big SAF vault; ~10 s on a fresh app-storage vault) before opening the note. Now the note opens from its own source (scanNote) and the refresh runs in the background; emulator: note opens <1.5 s, row in list on return.
- FIXED: startup sync 22 s -> 7.3 s on P30 (real vault, app storage). Stage logs (`TYLOG_SYNC` in logcat) showed: LocalVaultStorage.list awaited one stat per entry (scan-local-shortcut 14.4 s -> 4.8 s, sync walk in an isolate); revision files re-ingested every launch (418 files, ~4 s; seen stamps now persisted in the vault database); pruneLocalRevisions ran on every 60 s poll (12.4 s; now once per 6 h per process).
- DONE: P30 backup folder Download/TyLog deleted (1.9 GB).
- OPEN: scan-local-shortcut still 4.8 s at startup (full local walk to prove no local change); background full scan at startup 10 s.

## Wave 7 (2026-10-16): 0.19.1 release checklist (user: "add all ... and go")
Recheck before release:
1. Mac, real vault: startup sync + first index with the isolate-based LocalVaultStorage.list (only P30-tested so far).
2. P30, test vault TyLogModTest: recording opens at once; 20-min parts still appear in the Audio list.
3. Revisions on devices: edit a note on the Mac, P30 picks it up (persisted seen stamps).
4. P30 background sync: prunes history on every run (fresh Vault, max every 15 min); must not hold vault.lock long enough to block the UI.
5. Release prep: bump 0.19.1, CHANGELOG, release workflow (also ships the 15-min worker online window).
6. Decide on the `TYLOG_SYNC` logcat line (one per sync); keep unless the user objects.
Leftovers (not blocking):
- Startup scan-local-shortcut 4.8 s + 10 s background index check.
- Empty folders after module uninstall.
- Speaker diarization for transcription (pyannote or Studio model).
- Unresolved: course audio origin (Qwen vs edge-tts in repo); Studio cannot load Qwen3-TTS/Chatterbox; IADE mentions + audio licence in public tylog-pack-pt-pt.
- Housekeeping: remove baseline worktree (scratchpad); remove emulator test vault; delete /sdcard/Download/TyLogModTest on P30 (backup only).
Status at stop (2026-10-16 09:30, laptop shutting down):
- Done: 1 (Mac index OK: cache 0.5 s, fresh scan 1.4 s; Mac has no in-app sync), 2 (P30 test vault: recording opens <1.5 s, row in list), 5 (0.19.1+153 bumped, CHANGELOG written, NOT tagged), housekeeping (baseline worktree removed, TyLogModTest backup deleted on P30).
- New fix in 0.19.1: Journal grey days on Mac = agenda ExpansionTile read a scroll offset from PageStorage (double as bool); now keyed per day, regression test added (fails pre-fix). Full suite 1537 green at 644f9c3.
- Open: 3 (revisions on devices, only test-covered); 4 (background job: first forced run skipped, likely <5 min since UI sync; retry: `adb shell am kill org.tylog.tylog`, wait 6 min, `adb shell cmd jobscheduler run -f org.tylog.tylog <id>` from `dumpsys jobscheduler | grep tylog`, check TYLOG_SYNC background line and job duration); emulator test vault not yet removed (AVD TyLog_v40_Acceptance, app org.tylog.tylog.debug).
- Then: tag v0.19.1+153, release workflow, install P30 + Mac (/Applications still 0.19.0).

## Wave 8 (2026-10-16): everything open blocks 0.19.1 (user: "no new release until all tasks and blockers or leftovers" are closed)
Done since stop: background worker skips while app is foreground (44106e2); revision prune time persisted in `.tylog/revision_prune.stamp` (ea009ff); Journal grey days (644f9c3); emulator test vault removed. Ornith (Studio) failed a 10-line edit in nextcloud_sync.dart (looped, overwrote the file; restored) - Studio only for new/small files.
Queue (all block the release):
1. Huawei drops the WorkManager job while the app is dead (no background sync until next launch): re-register on BOOT_COMPLETED / package replaced / network change, document Huawei battery settings.
2. App returning while a background run holds the lock waits up to ~2 min: UI asks the service to stop (cancel flag file / deadline shortening) and takes over.
3. Startup scan-local-shortcut 4.8 s (P30) and background scan-local 7 s: skip the full local walk when nothing was written locally since the last sync (persisted listing stamp), or reuse the worker's listing.
4. Startup background index check 10 s: reuse the sync's no-change result / cached listing so the worker skips the fresh scan.
5. Empty folders after module uninstall (projects/<id>, assets/modules/<id>): delete empty dirs (SAF + local).
6. Check 3: revisions Mac -> P30 on devices (needs a note the user allows editing).
7. Verify on P30: next background run shows no prune-revisions (marker works).
8. Speaker diarization for transcription (pyannote or Studio model).
9. Course audio origin (Qwen vs edge-tts in repo) - needs user answer.
10. Studio cannot load Qwen3-TTS / Chatterbox (transformers 5.5.0).
11. Public tylog-pack-pt-pt: IADE mentions + audio licence.
12. Battery notice layout: title wraps in a narrow column beside the button (P30); put the button under the text.
13. Sync screen shows "Recovery backup: content://…Download/TyLog" after the backup folder was deleted; hide/clear a backup that no longer exists, friendly path.
14. One note is re-parsed on every launch (parsedNotes 1 each startup): find which and why.
Progress 2026-10-16 13:40: 1 (receiver + battery notice), 2 (handover; in-sync cancel with codex), 3 (startup defers walk: startup sync 22 s -> 3.9 s), 4 (unchanged rescan skips encode; scan ~10 s in background), 5 (empty module dirs), 7 (prune marker verified on P30) done at 4f2f278.
Progress 2026-10-16 14:00: 2 (sync cancel: in-flight files finish, partial checkpoint, UI takes over), 4 (unchanged rescan: re-derived notes compared by JSON, encode/write 0 on P30), 12 (notice layout), 13 (backup line hidden when gone, "App storage"), 14 (abandoned uncommitted dirty marker made one note re-parse every launch; markers >10 min old cleared) done. P30 startup now: today 0.46 s, cached index 1.7 s, startup sync 3.0 s, background rescan done 16 s.
15. Desktop-managed vaults (Mac + Nextcloud desktop client) never publish or ingest entity revisions: _syncNow returns before the revision steps (all 418 revision files are from phones).
16. Global Search tab does not find a note synced in from another device (P30: 'TyLog sync test' created on the Mac is in Library > Notes but Search finds neither its title nor its body).
Progress 14:30: 8 diarization (S1/S2 verified on two-voice audio, launchd worker now --diarize), 9 (no Qwen claims anywhere; README names edge-tts), 15 (desktop vaults publish/ingest revisions, test; device check pending: needs Mac UI while user is not using it), 16 (ranking: exact-title hit first after fusion; latency not reproduced: edit searchable ~25 s after sync on P30; worker+maintenance tests for new-note search added).
17. Course audio must be clearly open source + European Portuguese (user 14:45): edge-tts dropped; 1.1.0 pack asset removed from the v0.18.1 release (14:50). Candidate voices: Piper pt_PT-tugão (MIT, CC0 data; sample sent) + Chatterbox (MIT) cloned from a CC0 pt-PT reference on the Studio PC (needs SSH: port 22 still closed). Pack 1.2.0 on hold until audio is regenerated.
    User can't judge accent (learning PT): quality judged by Whisper-medium word accuracy vs lesson text (tools/check_audio.py in pack repo). Lesson 1: edge-tts 0.97, Piper tugão 0.73 (mishears e.g. 'na Escola Lumen') -> Piper rejected. Testing Chatterbox Multilingual (MIT) on Mac MPS cloned from CC0 tugão dataset clip (OHF-Voice/voice-datasets). Female pt-PT CC0 reference still needed (Common Voice pt, accent Portugal, CC0).
18. A24 (16:03-16:12): updated to 0.19.1 build, real vault moved to app storage (9 min, original Internal storage/TyLog kept as backup). Cold start before (SAF): today 0.5 s, sync 9-10 s (SAF queue behind startup scan; lock/trace/prune fixed in 773342a). After: today 0.22 s, cached index 0.9 s, startup sync 1.6-1.75 s, background rescan done 7 s.
19. DROPPED (user 2026-10-16: only user uses the app; both phones already moved). Was: proposal: after updating, ask once on devices whose vault is still an external SAF folder: "Move to app storage?" so no device stays on the slow path by accident.
20. Back navigation (user: 'from some app screens user can't go back'): audit every tab/mode/overlay/sheet for Android back + visible back arrow; non-Today tabs should return to Today; tests per screen. Emulator only.
    DONE 2026-10-16 17:00: codex audit docs/audits/2026-10-16-back-navigation.md; 26 widget tests; emulator: Library/Journal/Search/Graph back -> Today with arrows; note from Library -> Library -> Today -> exit. Full suite 1573.
PARKED by user 2026-10-16 17:05 ('forget about portuguese module now, we are fixing the main app'): items 9, 11, 17 (course audio/pack 1.2.0) and 10 (Studio TTS) are out of 0.19.1 scope. State: pack repo has uncommitted IADE->Escola Lumen edits, tools/tts_open.py + check_audio.py, 25/98 Chatterbox clips; resume with the loop in tts_open.py (memory: split long lines, restart on kill).
Status 17:20: current build (95e5edf+) installed on P30 and A24; item 8 Huawei job OK (registered after 1h40 in background). Left: Mac revision check (Mac UI while user away; check ~/Library/Application Support/org.tylog.tylog/tylog.db revisions for phone revision note-f5d6648a...), delete scratch note 'TyLog sync test' on both sides, release prep (CHANGELOG done for most, tag v0.19.1, install Mac).
RELEASED 2026-10-16 ~19:00: v0.19.1+153 (workflow ok, 6 assets; APK has libtypst_flutter.so 49.6 MB; Mac zip sha256 matches). Installed: Mac /Applications 0.19.1 (153), P30 + A24 0.19.1 (95e5edf build; later changes are Mac-revision + changelog only). Parked: Portuguese pack (9, 11, 17) and Studio TTS (10).
User answers 2026-10-16: 6 scratch note OK; 9 course audio = edge-tts (document it); 10 enable SSH on Studio (user action, then uv env with qwen-tts/chatterbox-tts); 11 strip IADE + add licence, user reviews before push; 8 diarization with non-gated speechbrain ECAPA (codex).
Then: full suite, device checks, tag 0.19.1.

## Screenshots (2026-10-16 evening)
- Cause of 'recent screenshots missing': no screenshot LaunchAgent was installed (last run a manual backfill 2026-10-08); the app's watch mode also called a local Ollama OCR model that isn't installed.
- Fix (scripts repo ~/Nextcloud/InstantUpload/Screenshots, local commits d211a52, 7a853d8, 40d4cb2): watcher runs the incremental backfill pipeline (Studio OCR), waits on the backfill lock instead of crashing. LaunchAgents installed: org.tylog.screenshots (watch, KeepAlive) + org.tylog.screenshots.schedule (03:00 backfill); logs next to the scripts.
- Backfill caught up: 54 processed (to 2026-10-16 08:39), 1 error (2024 telegram jpg), 1 sensitive skip. Watcher test with a duplicate file: picked up in seconds, no note created.
- Runs in the lab: Mac (AC sleep 0) + Studio on one LAN; Nextcloud on the home Fedora. Risk: Mac restart without auto-login.

## Wave 9 (2026-10-20): fix found problems (plan: ~/.claude/plans/lets-think-how-its-eager-moonbeam.md)
- T1 no change needed (only the first poll after launch walks; later polls ~128 ms); guard test 234a314.
- T2/T3 (c-luna + Claude fixes): worker search index lazy. P30 3 cold starts: PSS 576 MB -> 196-249 MB, scan-done 17-30 s -> 8.2-10.9 s, today 0.41 s, list 1.4 s. After the first search PSS returns to ~630 MB: the search index itself is ~400 MB -> follow-up T2b (smaller search index). Codex's "scan waits for startup sync" rejected (delayed note list to 3-15 s).
- T4/T6/T7 ad4f31f (Mac Settings real mode + health line; prelude marks removed). T5/T6 scripts 592dea7 (blocks of 5, health check nightly).
- T8 AGENTS.md 971c876 (force-stop before cold-start measurement). T9 Mac disk 17 -> 34 GB free. T10 A24 backup: pending connection.


## Wave 11 (2026-10-20): close wave 10 + settings/providers/sync (plan: docs/superpowers/plans/2026-10-20-settings-providers-sync.md)
- S2 screenshot notes: reading view re-reveals on note change (7f3b37c); editor paints the match as a span background, since an unfocused field paints no selection (b0f34d5); same-query second result reveals again (5b789f8). P30: 'Cervejaria' highlighted.
- S3 images: collapse to a 64 px strip, per device (fold_state.json, keyed by asset path); editor via image toolbar, reading view via button (dffcf31). P30 verified, note unchanged.
- S4 list subtrees: OPEN. Codex reading-view version discarded (parallel list renderer lost inline parsing). Needs hidden ranges in the block loop + an editor-side collapsed block.
- S5 DB projection (a63df5a, b0f34d5, 5b789f8): every index build inserts missing nodes (no revisions published, import mapping respected). Mac 103 -> 9,853 nodes. P30: FTS delete-by-UNINDEXED-id made the first projection quadratic, searches waited 12-13 s; fixed, queries ~1.6 s incl. adb overhead.
- S6 memory (0a515e8): worker drops the search index after 60 s idle. P30 PSS: 252-318 MB before a search, 570-597 MB right after, 267-270 MB a minute later. '<=350 MB after a search' met only after the idle window.
- Keep query on back (88d02cb).
- Settings: calendar feeds have no built-in owner URLs, blank = off (a63df5a, 5b789f8; owner's vault settings now hold the URLs + group explicitly). AI: local-first preset menu + cloud presets (OpenAI, Claude, Gemini, Mistral, OpenRouter), keys in OS secure storage (a2993c2). Screenshots: Mac folder picker, uv lookup (a97a2b3). Scripts already read the Studio URL from ai.json (no change).
- Sync: 'WebDAV (any server)' backend, single PUT, https-only (ef36c19); device round-trip not done yet.
- P2P spike: iroh 1.4 endpoint arm64 .so 5.4 MB; Ouisync v0.9.4 pre-1.0, git-only crate. LAN sync timing needs a prototype (own plan).
- Full suite 1620 pass; codex review: 4 Important fixed/ruled, 3 minors deferred (fold store late load, concurrent fold writes, toolbar position after collapse).
- Release 0.19.2 blocked by: S4, S6 peak memory.

## Wave 12 (2026-10-21): leftovers + new findings
- S4 list-subtree folding, editor + reading view (d4abe47, bf8b063, 940fef9, 68c2968): tap a bullet to fold; works across task blocks; offsets/source unchanged; selection into a fold unfolds it. P30 2023-03-29 verified (no stray bullet, no leftover blank lines, note mtime unchanged). Span build 2,000 blocks/500 folds: 9 ms (codex v1: 179 ms).
- S6 memory: packed search index v4 (d3da535, 7d7df67): loaded index 540 -> 175 MB on the Mac; P30 PSS 317 MB before a search, 353-371 MB right after (was 570-597), back to ~270 a minute later. 40 real queries identical before/after. Corrupt v4 files are rejected and rebuilt.
- Fold minors (26f39d2): late store load, serialized writes, toolbar under a collapsed image.
- Projection duplicates dropped, skipping nodes used by revisions/edges/import mappings (599b2c0, 2f76b1d).
- WebDAV against a real server (rclone, 4493638): edits never arrived because plain WebDAV doesn't propagate folder ETags; now full listing in WebDAV mode. Test: 20 notes, 12 MB file, edit, delete.
- New: day title of another year unreadable next to a back button (459244e, c109fc2): compact arrows, two-line small title; P30 verified.
- P2P: sendme/iroh builds for arm64 (9.4 MB CLI) but aborts on Android outside an app ('android context was not initialized'); LAN timing needs an in-app harness.
- Full suite 1641, tylog_core 406. Codex review: 1 critical + 4 important, all fixed with tests.
- Open: S6 target <=350 MB right after a search missed by 3-21 MB (index cost now ~50 MB; baseline ~317 MB); P2P LAN timing.
- Memory target revised with the user (2026-10-21, option 2): <=350 MB idle, <=400 MB right after a search; met (P30 270-317 idle, 353-371 after). Baseline profiling (Dart heap ~171 MB idle) moves to the next wave.
- 0.19.2+154 released (CHANGELOG); A24 install pending its connection.

## After 0.19.2 (2026-10-21, user UI requests)
- Title bar: day arrows removed (tap the date for the calendar), back-button slot always reserved, so the date no longer jumps or shrinks (893d596). P30 verified (Today vs Tue 20 Oct identical position/size).
- Calendars: any number of feeds, none by default; Google / Outlook (ICS links), IADE preset (classes, lab or both), Other (fa421b9). Owner's two IADE feeds migrated with ids and cache. P30 verified.
- Screenshot OCR settable from any device via ai.json; the Mac applies it every minute and publishes its running mode (fa421b9, 9f3aa1c). Readable status times.
- Found: Mac screenshot agents were broken since 10:09 (schedule agent deleted, watcher not loaded; launchctl bootstrap error 5 race). Fixed (48f0acd); agents restored to watch + 03:00 schedule via the synced setting; verified both loaded.
- Agenda showed 183 items on the P30: calendar settings did not sync (.tylog) and the phone migrated the IADE feed without its group. Calendar list now syncs via _system/settings/calendars.json (14ffafd, 435decc; seeded from the Mac). P30: Agenda 4.
- Today agenda timeline (17c0e8b + tint fix): times, room, sorted across calendars, moving now dot, running events tinted. P30 verified 11:55. Ornith 1.5 35b (Studio Ollama, 64k) drafted the widget but it did not compile and it edited 10 unrelated files: reverted, rewritten by Claude. Unsloth Studio API key rejected (401); pi provider studio-ollama added.
- 0.19.3+155 released (2026-10-21). Open: A24 idle PSS 386 MB > 350 idle target (P30 270-317) -> baseline memory profiling next wave; P2P in-app harness.

## Next (2026-10-21, after Settings pages / Windows build)
- Settings as pages: done (40af289, 3533789); P30 + A24 + Mac verified. Screenshot thumbnails no longer flicker on sync/index updates (0a2f121, P30 14 frames identical).
- Windows: CI builds a zip with source-built engine (run 39608752041). Waiting: user smoke test on Studio.
- Windows single file with self-update (user choice, design agreed in chat): `TyLog.exe` = small Rust launcher with the app packed inside; first start per version unpacks to %LOCALAPPDATA%\TyLog\app\<version> and runs it, old versions removed; self-update like the Mac (GitHub latest release, TyLog-windows.exe + sha256, detached helper waits for exit, replaces the single exe, relaunches); no update offered when not started from the single file. Caveats: SmartScreen "unknown publisher" without a code-signing certificate; self-extractors are flagged more often than installers (fallback: Inno Setup installer). Needs a plan, then two releases to test the update on Studio.
- Screenshot note layout redesign (before the next release): desktop two columns (picture maximised left, text right); phone layout to be decided.
- Then: release 0.19.4; memory baseline profiling (A24 idle 386 MB > 350); P2P in-app test.
- 0.19.4+156 released (2026-10-21): Settings pages, screenshot view, steady thumbnails, single-file Windows exe with self-update (Rust launcher tool/windows_launcher). Update test on Studio pending (0.19.3 test exe -> 0.19.4).

## Wave 13 (2026-10-22): open items + user findings (plan; P2P harness moves to its own session)
Screenshot-mode "overwrite" closed: the user changed it by hand while the picker was broken.

| # | Task | Owner | Done when |
|---|---|---|---|
| W1 | Timeline graph misses read books: `buildTimelineGraph` (packages/tylog_core/lib/src/graph.dart) takes only `kind == 'article'` and read days only from recently opened (`_mergedRecent`). Include books (and other read kinds), and take read days from the daily `== Reading` log lines too, so deleted/rated items keep a day | codex | core test: a book read on day X gets a `read` edge; a logged-but-deleted article shows on its day; Mac timeline shows the user's read books |
| W2 | Reading log: a trashed article is logged as "- Read: <title> — 🗑" (app_mobile.dart `_logReading`). Confirm with the user what it should say (e.g. "Dropped: <title>" or no line) | Claude asks, codex fixes | test for the trash line |
| W3 | Bullet list: "problem with the dot list" + a leading dash also turns into a dot. Reproduce first on the P30 in a scratch note (never real notes), record exact keystrokes and before/after source, then fix in the rich editor | Claude repro, codex fix | failing editor test reproduces it before the fix; P30 retest |
| W4 | New entity dialog (`_createEntity`): kind is a dropdown of existing kinds (person, place, organization, event, project, website + every kind already used in the vault) with "add new kind"; default none chosen; fields follow the kind (email for person/organization, link/map URL for place/website, address for place); any entity can add a "link" property | codex (dialog), Ornith (kind list helper + test) | widget test: choose place → link field, no email; new kind appears next time; created header has `link:`; entity header shows the link tappable |
| W5 | A24 idle memory 386 MB > 350: profile build on the A24, compare Dart heap / native / graphics with the P30 (270-317); fix the biggest difference | codex measures, Claude reads | A24 idle PSS <= 350 MB, numbers in this file |
| W6 | Flaky `workspace_revision_cache_test` (desktop variant): run it 30x, find the timing dependency, fix | codex | 30/30 passes |
| W7 | Settings: search box on the Settings home (finds a setting by name and opens its page); two-pane layout on wide windows | codex | widget tests: search "OCR" opens Screenshots; >= 900 px shows list + page side by side |

User answers (2026-10-22): W2 keep the 🗑 line, add the source URL so a deleted article can be found again (today only the title is kept). W1 timeline edges: added, last opened, finished; finish day stored as a `finished` property when an item is finished. W3 cause: the time button appends `- HH:MM` at the end of the daily note, i.e. inside `== Reading`; fix: insert before the Reading section (helper lib/journal_insert.dart). Tasks split small so Ornith output can be judged.

Order: W3 repro and W2 question first (cheap, need the user), then W1, W4, W6 in parallel; W5; W7 last. Release 0.19.5 only after all are verified on the Mac and a phone.
Wave 13 results (2026-10-22):
- W3 done (5dff5a1): the time button inserts before `== Reading`. Ornith's raw-text helper had a wrong spec (the editor shows the heading as "Reading", not "== Reading"), so it was dropped and the lookup uses document blocks.
- W2 done (bd9d808): the trash line keeps the source link. Ornith wrote readingLogLine; the test caught its null-rating bug.
- W1 done (96a2c20, 2e8e043): the timeline shows only articles you opened or finished (cause: 200-node bound vs thousands of pipeline articles); added/opened/finished edges; finish stores `finished:`; phones get a vertical timeline (newest at the bottom). P30 verified.
- W4 done (ad182e5, 2e8e043): kind dropdown (standard kinds + vault kinds, type to add), fields per kind (email / address / link). Ornith wrote entity_kinds.dart (6/6 correct first try). P30 verified (place -> address + link).
- W7 done (a41c7cf, 32feb57): Settings search and two-pane >= 900 px. P30 verified ("ocr" -> Screenshots).
- W6: not reproducible (30/30 alone, 10/10 with the workspace tests); codex's speculative sync change reverted. Watch the full-suite runs.
- W5: A24 idle 242-246 MB, P30 250-324 MB over 30 min (both under 350). The 665 MB P30 reading came after ~1 h of use plus an install; a post-install launch scans in ~35 s CPU and settles at ~300 MB. Peak-after-use profiling stays open.
- Release blockers (2026-10-22 afternoon): the 665 MB P30 reading reproduced as Library > Screenshots: each group was a SliverGrid, which builds its first card even off-screen, so ~370 thumbnails decoded on opening (P30 290 -> 646 MB; scrolling to 895). Fix 5103398: one lazy row list + image cache 32 MB. P30: open 279 MB, 40 swipes 329 MB; A24: 295-311 MB. Per-action P30 numbers: search +40 MB, screenshot open/close x5 flat, journal 90 swipes ~340, graph modes <=337, articles ~+60 then flat. Timeline titles + Settings subtitle fixed (c5afa9d). A24 checked by eye (entity dialog, Screenshots tab). Mac check: user.

## Parked: pt-pt pack audio on Studio (2026-10-30, resume after the weekend TyLog run)
State: all 98 clips exist in `tylog-pack-pt-pt/assets/audio` (25 from torch Chatterbox on the Mac, 73 from Studio). Scored on Studio STT (large-v3-turbo): 80 pass 0.9, 18 fail (worst 0002-dialogue 0.68, 0028-audio2 0.75, 0058-dialogue 0.83, 0040-audio2 0.83, 0046-audio1 0.84). Round-1 backup: session scratchpad `audio-round1`.
Why it stalled: the TyLog ornith worker reloads ornith and evicts Chatterbox from Studio (16 GB); the earlier "GPU crash" was this eviction. Studio setting "Keep multiple models loaded" is now "When they fit". Never run audio generation on the Mac (rule: berloga-tts-on-studio-not-mac).
Resume:
1. Wait until the TyLog run is idle (or lower ornith context), then `POST /v1/load` Chatterbox-GGUF.
2. `python3 tools/tts_studio.py --clips=<failing ids>`; rescore with `STUDIO_URL=http://desktop-vdsrh2e:8888 python3 tools/check_audio.py`; keep the better take per clip; repeat for clips still < 0.9.
3. Rebuild pack (`tools/build.sh`), `pack-validate`; then P30 install test. No release until the user says.
Tools (uncommitted in tylog-pack-pt-pt): `tools/tts_studio.py` (Studio API, auto-reload, `--clips=`), `tools/check_audio.py` (`STUDIO_URL` = Studio STT). Studio engines vLLM/SGLang: skipped by the user (WSL VM cannot start, HCS_E_SERVICE_NOT_AVAILABLE).

## Enrich backfill fast (2026-10-30, user: "go", status every 5 min)
Cause of the slow run: Ornith 35b reasoned before every answer (57 s/day, 12/20 days blew a 4000-token cap; uncapped = 185-900 s and timeouts). Fix a591c17: thinking off + JSON-constrained + max_tokens 4000 -> 3.2 s/day on the 20-day bench, 0 failures, 16/20 vs 18/20 earlier mentions kept on days both finished. PROMPT_VERSION kept at 4.
- [x] Bench 20 days thinking on/off (scratchpad bench.py)
- [x] Commit + merge a591c17, worker re-enabled (launchd), run-request.json written (process now)
- [x] Backfill days: 994/995 (2026-10-31 00:23)
- [x] Backfill screenshots: 2519/2519 (2026-10-31 02:56; one rerun after a clean early exit at 1672)
- [x] Error check: 9 log errors; 7 old-code screenshot errors and shot-09ddd22b succeeded on reruns, 2022-07-19 hit the 4000 cap -> rerun at 12000 (33 mentions); cap now 8000 (33bbca8), date-flaky test fixed (3a75387). All 995 days + 2519 screenshots have results.
- [ ] Optional later: thinking-on second pass only for days where the fast run finds nothing

## Audio notes v2 (2026-10-31, user: "run the work", loop, status every 5 min, max token save)
Spec docs/superpowers/specs/2026-10-31-audio-notes-v2-design.md, plan docs/superpowers/plans/2026-10-31-audio-notes-v2.md. Haiku subagents + pi/Ornith (when Studio GPU is free); Claude at gates. Text in ru+en+pt always (critical). Mac: no models > small, 4 GB guard.
- [x] T2 metrics script + baseline (f094597): 205 lines, 40 loops, 51 mid-cut, ru 66 untranslated
- [x] T1 hard deadline on Studio calls + guarded Mac fallback (4422241, 158 tests); free mem = free+inactive+speculative
- [x] T1b guard + small cap on every local transcription (5a97cc3, 181 tests); tiny language probe stays unguarded (tiny < small, allowed)
- [x] T3 STT bake-off: primary whisper-large-v3-turbo, secondary qwen3-asr-1.7b (best on names, no punctuation); large-v3 too slow (72 s/clip); parakeet silent on music (Phase 2 music gate option)
- [x] T4 speech map (26267f6; regions merge only across pauses < mark_gap)
- [x] T5 hallucination filter + sentence lines (95b9177, 181 tests)
- [x] T6 sidecar + edit-protected rendering; Dart stable same-second order (0c52630, 192 py + dart green)
- [x] T6b pinned span on re-run (6143966, 194 tests)
- [x] T6c last user-edited line pins at most +20 s (3a1b44e, 195 tests)
- [x] T7 v2 path in worker, ru/en/pt always (a579f58, 216 tests)
- [x] T7b/T8b legacy Translation sections removed on first v2 run; translation merges into a fresh read (657b86d, 218 tests)
- [x] T7c a finished transcript re-queues its translations (00f98f4, 219 tests)
- [x] T8 translation lines follow transcript lines; failures marked (039b076, 199 tests; state in sidecar translations[target])
- [x] T9 theatre re-run: 3 min transcript + ~2 min per translation; loops 40->0, mid-cut 51->19, ru untranslated 66->13, en 0; readable sentences; agent reloaded
- [x] T10 translation target-script check + retry + marker (443cefa)
- [x] T11 doubtful from disagreement (348412e, 226 tests): threshold 0.01 = 13% chunks, i.e. only zero-overlap chunks; name errors sit in agreeing chunks -> T12 arbitrates every chunk with agreement < 0.95
- [x] T13 context pass (04558db, 249 tests); shared llm_chat
- [x] T12 arbitration (cfb3313, 253 tests): 0.95 -> 142/151 chunks get an LLM call
- [x] T15 ensure_model reloads Ornith at 64k when loaded at 8k; empty reply -> clear error (c7dc4c8, 256 tests)
- [x] T15b (3e74906, 257 tests) T15 checked the wrong field: Studio max_context_length stays 8192 even at 64k (context_length shows the loaded value, but native on default loads) -> worker looped reloading. Fix: drop the field check; empty reply -> reload at 64k with force_cancel_active, retry once
- [x] T14 theatre re-run with context + arbitration: 3 min; 30 chunks fixed well (aristocratas, Barreiro, Hermano José), Summary/Scenes(23)/References(9) written
- [x] T16 (9b8e2b4) context sections in the first target language (ru), not the transcript's; glossary gives corrected spelling of misheard names (heard -> spelling), arbitration may use spelling
- [x] T17 (e462376, 263 tests) (?) only when arbitration says doubtful AND engine agreement < 0.3 (59 doubtful chunks -> 12; now 30% of lines carry (?), most read fine)
- [x] T18 re-run: (?) 154 -> 18 lines (3.6%), glossary corrects Deméter/elefantes/Moçambique/Yorick; ru failed 10 (2%), en 1
- [x] T19 (bb14d15, 266 tests; verified 19:58: Summary/Scenes/References in Russian, references now right: agelast stone, Demeter/Persephone, Aristophanes) Summary/Scenes/References still Portuguese (Ornith ignores the language instruction): generate in source language, then translate the section lines into ru through the validated translate path
- [x] T20 Phase 4 tasks written (plan: Tasks 21-22)
- [x] T21 (db67edc) translations wait for the context pass; windows of 40 lines with Summary + glossary + previous 10 pairs
- [x] T22 (a95e8e8, 280 tests) review pass: score 1-5 per line, retranslate < 3 once with thinking on, (?) if still < 3
- [x] T23 translations with context + review: ru mean 3.89, en 3.93, 15 min each; ru first window 00:27-07:59 failed (10 lines)
- [x] T28 (63a1926, 287 tests) (a) Studio reverts Ornith to the default load after idle (context_length == native_context_length is the default-load signature, seen twice): load at 64k before each job's LLM stages when that holds, keep the empty-reply fallback; (b) a failed window splits in halves before single lines; (c) review reply: JSON mode + one retry; (d) audio_metrics counts '(?) [sem tradução]' as failed
- [x] T29 ru after T28: failed 10 -> 5 (1.0%), mean score 4.06 (target met); en 0 failed, 3.93
- [x] T24-26 Phase 5 app (codex): parallel text + markers; Summary/Scenes/References; Re-process; toggle read-only (analyze clean, 1755 tests)
- [x] T27 P30 release build on real vault: parallel original/ru, Summary + Scenes in ru, RU/EN chips work
- [x] T30 no add-translation chip for the source language (1756 tests)
- [x] T31 P30: audio note screen shows 'No transcript yet' + 'Request transcription' for 5-15 s while the note loads (risk: needless re-transcription) -> loading state; transcript load must not wait for audio
- [x] T32 P30: each [—] gap renders as two stacked '—' chips in parallel mode (~200 on the theatre note) -> one muted row per gap, consecutive gaps merged
- [x] T33 user: language/view header takes too much space -> one compact row (parallel toggle icon, source chip marked original, translation chips, translate action); drop the 'Language: X' line
- [x] Release v0.20.6+164 (user: go; Mac check not needed): run 41246968798 success, 8 assets, APK has libtypst_flutter.so, installed on P30. First run cancelled by GitHub's macos-14 brownout -> apple job on macos-15 (70598b6), tag moved before publish
- [x] T34 (1761 tests) user on 0.20.6: split toggle and RU/EN/PT seem to do nothing, 'transcribe doesn't work': controls work, but Summary + 25 Scenes + References fill the screen above the transcript, so the change is off-screen. Collapse Scenes/References to one line with count (Summary already collapsed); transcript starts under the header. Split toggle misaligned (32 px filled circle vs chips) -> same chip shape/height
- [x] T35 (602c628, 290 tests) worker: Summary/Scenes/References in every language (source + ru/en/pt targets) as '== Summary <lang>' etc.; legacy unsuffixed sections removed on re-run
- [x] T36 (f675cfe, 1765 tests) app: sections follow the selected language chip; source chip (PT) selectable = original only + its sections; legacy unsuffixed sections as fallback
- [x] Release v0.20.7+165 (user: go): run 41256415780 success, 8 assets, APK has libtypst_flutter.so, installed on P30
- [x] T37 song mode (1989a1c, 301 tests); 3 songs re-queued 2026-11-02 - songs (2026-11-01: Amy Winehouse 'Back to Black' en; Flor Damico 'cosas claras', 'delincuente' es; MP3 320k 44.1 kHz + cover art, files valid): not transcribed. Causes: Studio offline (no ping) -> Mac fallback small model; VAD cut the singing -> 'you' / [—]; job then failed on the LLM stage (Studio). Need a music mode: no VAD gate, 30 s windows, chorus repeats not treated as loops, language per song (en/es), lyrics-friendly engine on Studio
- [x] T38 closed by Wave 14 B3 (source MP3s were sped up) - song playback at wrong speed/pitch (user report): files are clean; suspect two players at once (daily audio card + note screen) or speed state; reproduce on the device the user used
- [x] T39 closed by Wave 14 B1 - Translate tab redundant now that Transcribe shows translations side by side -> rethink the tab/menu line (design with user first)
- [x] T40 closed by Wave 14 B2 - screenshots must get the same ru/en/pt translations as audio notes (OCR text -> Translation sections, same worker path + review); design after T39
- [ ] Monday (user): Mac GUI check; user test with a Russian recording on a familiar topic; release only after user OK
Issues found during the run:
- T1: job without a Studio connection still ran local faster-whisper uncapped/unguarded -> T1b
- T6: pinned-span rule not implemented -> T6b; legacy lines survive merge as user lines -> T7 clears them after backup
- T7: translate toggle in lib/widgets/audio_processing_settings.dart is now a no-op (ru/en/pt invariant) -> Phase 5 app: remove or relabel it
- T14 run 1: context pass failed, 'not JSON' = empty reply; Studio had ornith-1.5:35b at max_context_length 8192 -> T15
- T14: references partly invented by the local model (Paulo as 'Hades/Padre'); marked (AI); user Context or a cloud model is the lever (user: tune local now)
- T13: translations may run before the context pass (sweep queues them once lang is set) -> Phase 4 translation must wait for context
- T7: legacy Translation sections not cleared; translation path reads note too early -> T7b/T8b

## Open items audit (2026-10-31, whole file re-read)
Closed by later waves: 0.18.0 tag (superseded by 0.18.1), empty module dirs (W8 #5), startup scan (W8 #3-4), diarization (W8 #8), smaller search index (W12 v4), WebDAV round trip (W12 rclone), fold minors (26f39d2), A24 idle memory (W13 W5: 242-246 MB), screenshot layout (0.19.4).
- [x] 2026-10-15 adb junk-text incident: real-vault daily 2026-10-15 has no 'п' / 'р-н' lines (checked 2026-10-31).
- [x] Revisions Mac -> P30 (W7 #3, W8 #6/#15): found the Mac stops the revision poll when its window is closed (hide-on-close -> lifecycle hidden -> stopCloudPolling); desktops now keep polling. Unit-tested; Mac in-app edit check skipped (user away). Revisions come only from in-app edits, not file edits.
- [x] Peak-after-use memory (W13 W5), P30 0.20.5 release, real vault, 6-10 rounds of Journal/Library scroll + Search/More/Today: cold start settles 274 MB; under use 353-388, idle+60 s 334 (targets <=350 idle / <=400 active met). Flat under use, no growth per round.
- [x] Post-sync/post-update memory (P30 600-860 MB): cause = scanner shipped every non-note vault file (17 m4a, PDFs, 3.5k enrich JSONs) to the Typst engine whenever one note re-parsed; now compile inputs only (P30: 826 -> 342 peak, settles 277). Also: embedding model unloads after 60 s idle (Mac 790 -> 294 MB). Sync itself is fine (harness: 21.7k listed + 2.7k downloads, +47 MB).
- [ ] Mac check of the W13 release-blocker fixes (W13: "Mac check: user").
- [ ] Windows self-update test on Studio (0.19.3 -> 0.19.4 pending since 2026-10-21; updater hang log %TEMP%\tylog-update.log): needs the user at Studio.
- [ ] A24 backup (W9 T10): needs the A24 on adb.
- [ ] P2P LAN timing: in-app iroh harness (moved to its own session).
- Parked by user: Portuguese pack audio (W8 #9-11, #17; 18 clips < 0.9), pack repo IADE/licence review.

## Wave 14 (2026-11-02): extraction UX + fixit backlog (plan ~/.claude/plans/fancy-swinging-steele.md)
Codex (luna/terra) for major UI tasks, haiku for small ones, Claude reviews at gates; Studio = app models only.
- [x] D1 Search opens the result before closing; failure says so (bcbf623, 1784 tests); confirm on P30
- [x] A1 Processing screen with retry, More > Views + badge (1f6bbf2)
- [x] A2 every add action shows "Queued -> see Processing"
- [x] B1 tabs Comments · Text · Properties; no Translate tab/button; missing language chip with progress/retry; Re-process in ⋮ (T39, fixit 11-02)
- [x] B2 screenshots: worker translations (9afc241) + app Text view
- [x] B2b (c488c56, 315 tests; worker reloaded) worker paused 12:25: first sweep queued 207 screenshot jobs (2500 in vault) -> auto only last 7 days, audio first, prune queued backlog; then reload org.tylog.transcribe
- [x] Songs (T37) re-run done: lyrics recognised (Back to Black, cosas claras), Summary/Scenes/References in ru/en/pt; song translations queued behind the pause
- [x] B3 not an app bug: the vault MP3 is a sped-up copy. Original 'Flor Damico - Delincuente.wav' (A24 Download, 48 kHz/24-bit) is 202.4 s; vault MP3 (LAME 3.99, lowercase tags) is 162.0 s = 1.25x faster, ~+3.9 semitones. Both Flor MP3s were sped up (delincuente 1.249x, cosas claras 1.349x): replaced in place 2026-11-02 with 320k MP3 from the WAV masters (tags/cover kept, old files in scratchpad), re-queued for transcription (old timestamps were wrong). Was: song playback speed/pitch (T38), Flor Damico songs only (LAME 3.99, ID3v2.4, ReplayGain side data; Amy's ID3v2.3 file fine). P30 13:06: one AudioTrack started (no double player); pitch can't be measured over adb. Needs user: device + stutter vs constant shift, on the new build
- [x] C1 copy line / copy all (original, RU, EN, PT, side by side)
- [x] C2 (a9705f4) export Markdown / PDF via share sheet
- [x] C3 (a9705f4) "Open as page": translation as an editable linked note
- [x] D2 OCR written after a screenshot's first projection stayed out of full-text search; now re-projected on hash change (423fa84); confirm 'MONSANTOS' on P30/Mac real vault
- [x] D3 @ autocomplete: hang on @fixit, jumps, popup covers text, new page at bottom (10-05, 10-07)
- [x] D4 indent typed after a list glyph now nests (dcf94b0)
- [x] D4b no Tab/Shift-Tab and no mobile indent/outdent control exists: add them
- [x] D5 already folded under the More row since 51bcbe2 (no change); confirm on P30
- [x] D7 screenshots library: newest first, no grouping (ec7b48f)
- [x] D8 screenshot shelf sort/group choice is not persisted (shelfPrefs const {}): remember the user's choice
- [x] A3 (8b94f9b) P30: Processing lists old October failures first; order running > queued > newest, failures older than 3 days folded under 'Older failures (N)'
- [x] B4 (3fe46d5; 3 songs re-queued to pick up titles) P30: song notes keep 'Audio 20261101-143642' titles, so searching 'Back to Black' finds nothing; worker sets title 'Artist — Title' from tags when the title is still the default stamp
- [x] B5 P30: a song opened from Search shows as 'Entity' in results and opens the generic page view (sections as raw lines) instead of the audio screen with the Text tab
- [x] B6 (5f19a00; songs re-queued 13:21) song jobs end with lang None/langs [] (song mode never sets language) -> no translation jobs, no source-language Summary, no source chip in the app. Detect language from the transcript text (llm_chat, like screenshots), store lang/langs
- [x] B7 (00b8e1b) audio screen opens on Comments; open on Text when a transcript exists
- [x] P30 check 13:41: Processing + badge, search opens tapped result, song opens on Text with ES/RU/EN/PT, PT summary, side by side, ⋮ Copy all / Export / Open as page / Re-process. Not driven: @ autocomplete, indent, screenshot Text (covered by tests) (release build, real vault): Processing, search, tabs/copy/export/open as page, screenshots Text, @ autocomplete, indent, OCR search
- [x] D6 closed as unknown: no offline loss path in sync code (path_sync, conflicts, deleteLocal guards); 10-07 revisions intact; no sync trace for that window; reopen if it recurs - entry lost offline (10-07): sync_trace first
- [x] Release 0.20.8+166 published (8 assets, libtypst_flutter.so in APK), installed on P30
- [x] E1 (44ed8c3) user 11-03: journal tasks ugly (emoji ✅ glyph on Android, empty flag/date/clock/repeat chips, tall rows): compact row, Material checkbox icons, chips only for set fields; P30 checked
- [x] E2 (c5ccb09) user 11-03 'where are new bookings': OpenLabTwin missing from Settings root (take(6) predates it); Today Incoming showed requested bookings only on their start day and ideas only on their creation day -> today lists every pending request from today on + every new idea, sheet shows the date
- [ ] E3 user: sign in to OpenLabTwin on the P30 (email code), then confirm bookings in Today > More · N incoming
- [ ] E4 user 11-03 new screenshot missing: not on the Nextcloud server (newest 11-02 23:26); Mac watcher fine -> phone (likely A24) Nextcloud auto upload not running; check on A24 via adb
- [ ] Release 0.20.9 with E1/E2 when user says go
- Deferred: image wrap/crop/anchors (10-07) - separate design

## Wave 15 (2026-11-03): entities + boards P1 (plan: docs/plans/2026-11-03-entities-boards/README.md)
Workers: codex gpt-6.1-terra (tasks), gpt-6-luna (small fixes), pi Ornith 35b on Studio (new small files/tests). Claude reviews + runs Flutter tests (codex sandbox blocks them).
- [x] A project = entity kind, part_of in index (v14), childrenByParent
- [x] B kind registry: icon + label per kind (_system/settings/kinds.json)
- [x] D entity page: Part of / Contains, magic "Part of…"
- [x] E entity list as tree
- [x] F1 board model (board.dart 135 lines, 12 tests)
- [x] F project kanban (board file v1, columns)
- [x] H issue lines: @Project @fixit = kanban card (status = inline #metadata on the line)
- [x] G1 namespace planner (pure fn, 7 tests pass)
- [x] G Logseq namespace titles -> part_of (apply + maintenance UI)
- [x] P1 review + full test suite + macOS /verify: review+suite done; Mac verify found 5 issues (verify-mac-p1.md) -> 4 fixed; round 2 found #6-#10 -> #6-#8 fixed; #9 = entity body nested fixed-height scroll (found on device), #10 flaky in full suite -> codex terra (sandbox could not run flutter). Full suite 1866 pass
- [x] P1 committed 5f2696d
- [x] P1 phase end: P30 profile build on real vault (source-built typst .so, cold start index v14: 10059 notes in 23 s, no rebuild storm, no errors)

Issues found:
- [x] USER DATA 11-03: duplicate OpenLabTwin pages: notes/OpenLabTwin.typ (kind note, id 20261103-104633) + projects/OpenLabTwin.typ (kind project, id 20261103-104705); daily links the note copy. merged with user OK: daily refs -> project id, empty notes copy deleted (backup in session scratchpad)
- [x] P1.1 (user 11-03: no app-wide scrollbars) entity page body is a fixed-height Expanded viewport with hidden scroll; content below the fold looks missing (found 11-03 on Mac). Real cause: editor IS the page scroll (Expanded); header card + EntityRelationships + references panel are fixed chrome above/below it, leaving ~90 px on short windows. Codex declined a shared scroll (editor windowing). Fix: compact chrome - Part of/Contains move into the header card as one wrapping row
- [ ] FLAKY under load: workspace_controller_test 'worker publishes newly scanned issues' timed out once in full suite; 3/3 pass alone
- [x] PRE-EXISTING (fails on 49cf87b too): processing_screen_test 3x 'Retry preserves the <worker> payload' - Retry TextButton not found. Cause: fixed Oct 31 timestamps aged into collapsed 'Older' section; fixtures now use current time (luna)
- [x] P1 review (docs/plans/2026-11-03-entities-boards/review-p1.md): 11 findings. Batch 1 board/issues/kinds #1,4,7,8,10,11; batch 2 namespace/relationships #2,3,5,6,9 -> codex terra x2: 10/11 fixed (#1 mutateNote, #4 sync queued, #7, #8, #10, #11, #2, #3, #5, #6); #9 fixed by luna (clears project:, drops part_of entry). Full suite 1855 pass, core 502 pass
- [x] P1 full suite 1845 pass / 6 fail: 3 pre-existing above + issue drag no write (H), EntityHeader kind text 'person' gone (B), entity creation during blocked scan (B/D) -> fixed (header label app fix; creation test updated; issue test polled file instead of hanging completer). Now 1848 pass, 3 pre-existing fail
- [x] B test opened a non-vault folder (fixed: create vault, then reopen)
- [x] G1 pi (Ornith 35b) wrote planner but clobbered its test to a fragment + left verify.sh/run_verify.sh in root (removed); test handed to codex luna
- [x] F1 pi again clobbered its test file (19-line fragment, does not load); board.dart kept, test to codex luna. Rule: pi writes impl only, codex writes tests
- [x] codex sandbox cannot run dart/flutter test (telemetry + SDK cache writes): F1 luna fix was blind and still did not compile. FIXED with scratchpad cx.sh wrapper with --add-dir for ~/.dart-tool, ~/.pub-cache, flutter/bin/cache

## Wave 16 (2026-11-03): P2 mounts + GitHub (plan: docs/plans/2026-11-03-mounts-github/README.md)
- [x] P1.1 entity page: Part of/Contains in header card, compact header; editor >= 50% of 632 px (90 -> 330 px)
- [x] P2-A composite storage + mount registry (core): 506 core tests pass
- [x] P2-B1 controller loads mounts.json + index/scan through CompositeVaultStorage (worker too)
- [x] P2-B2 ext/ notes read-only in editor + badge (badge padding -> tokens)
- [x] P2-B3 Settings > Extensions page (test-only issue: scan must run in real async zone; codex full-access fixed). Full suite 1874 pass
- [x] P2-B0 composite rejects ext/ writes, sync excludes ext/ (codex, partial P2-B run)
- [x] P2-C GitHub client + device-flow auth (lib/github, 4 tests; UI comes with P2-B/D)
- [x] P2-C2 desktop: use existing `gh auth token` (GitHub CLI login) when present; device flow only for phones (user 11-03: official login, no key creation)
- [x] P2-D GitHub pull mount (sha check, zipball, safe extract, atomic swap, 6 h refresh, Add GitHub repo dialog); live fetch check pending in P2 Mac verify. Suite 1880 pass
- [x] P2-E pack updates from GitHub releases (source in install record, not manifest; daily check, persisted notice). Widget tests for Modules page missing -> covered by P2 Mac verify (install v1.3.0 from GitHub)
- [x] P2-F0 per-file git blob shas in mount cache meta (= git hash-object)
- [x] P2-F1 outbox + pusher core (lib/github/github_outbox.dart): entries, push in order, sha update, 409 -> conflict record
- [x] P2-F2a editing push-enabled ext notes: lock only when push false; composite allows writes for push mounts; save -> cache + outbox enqueue (controller)
- [x] P2-F2b Extensions page: Allow editing toggle (permissions.push), Push now, pending/conflict counts; pusher on 30 s debounce + resume
- [x] P2-F3a pull skips pending/conflict paths
- [x] P2-F3b Incoming review item 'GitHub conflict' with Keep mine / Take theirs
- [x] P2-G issue lines <-> GitHub issues (github: property, Send to GitHub, number written back hidden, closed<->done sync, #n chip)
- [x] P2-G2 no duplicate issues if local write fails after create (recovery record / match by marker in body) + Send action in Today issue menu (search query used literal '+': fixed by Claude; recovery map .tylog/github-issues.json syncs across devices). Suite 1900 pass
- [ ] P2 review (docs/plans/2026-11-03-mounts-github/review-p2.md): 9 findings (5 P1). Batch A mounts/outbox #1,2,3,4,6,8; batch B #5 issue identity, #7 GitHub sign-in UI, #9 verify pack before update -> codex terra x2: BLOCKED 17:32, codex usage limit until 19:14 (no partial edits); resume then
- [ ] P2 macOS verify + P30
- [ ] USER (11-03 chose reuse GitDoIt app): its client id (Iv1..., a GitHub App) returns 'Not Found' at /login/device/code -> enable Device Flow in the GitHub App settings or create an OAuth app; send client id
- [x] PT pack repo: lesson rework committed 293ced8, version 1.3.0 (voices/ left untracked: licence unknown)
- [x] PT pack 1.3.0 build (user 11-03: pause Ornith ~1h; 16:02-16:33, Ornith 64k + agents restored): bootout enrich+worker, unload Ornith, Chatterbox TTS --force -> check_audio -> pack -> pack-validate (scratchpad pt_pack_build.sh, running)
- [x] PT pack: GitHub release v1.3.0 published (tag on 293ced8, asset 29.3 MB, 268 files, 0 validate problems)
- [ ] PT pack: re-score all clips (script kept only last 25: 6 at 0.80-0.89); redo low clips in 1.3.1
