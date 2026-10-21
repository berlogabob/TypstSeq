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
