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
- [x] P2 review (docs/plans/2026-11-03-mounts-github/review-p2.md): 9 findings all fixed (#1 per-vault+repo@ref cache/outbox, no migration). Suite 1910 pass (5 P1). Batch A mounts/outbox #1,2,3,4,6,8; batch B #5 issue identity, #7 GitHub sign-in UI, #9 verify pack before update -> codex terra x2: BLOCKED 17:32, codex usage limit until 19:14 (no partial edits); resume then
- [x] P2 macOS verify (scratch vault): real GitHub issue round-trip (berlogabob/tylog-test-issues #1 created with marker, number written back, closed on GitHub -> Sync -> done), PT course repo mounted (86 notes under ext/ptcourse, per-vault cache), Install from GitHub v1.3.0 (72 lessons, source recorded)
- [x] P2 polish: Extensions settings subtitle repeats 'Extensions' (show mount count); issue card text drops project/marker titles
- [x] P2 P30 profile build (source-built .so). First start after install: one-off rescan 67 s (scan stage 51 s); 2nd cold start: today 0.45 s, index 1.8 s, scan-done 16.3 s (P1: 25.6 s). Watch the one-off on next update
- [ ] USER (11-03 chose reuse GitDoIt app): its client id (Iv1..., a GitHub App) returns 'Not Found' at /login/device/code -> enable Device Flow in the GitHub App settings or create an OAuth app; send client id
- [x] PT pack repo: lesson rework committed 293ced8, version 1.3.0 (voices/ left untracked: licence unknown)
- [x] PT pack 1.3.0 build (user 11-03: pause Ornith ~1h; 16:02-16:33, Ornith 64k + agents restored): bootout enrich+worker, unload Ornith, Chatterbox TTS --force -> check_audio -> pack -> pack-validate (scratchpad pt_pack_build.sh, running)
- [x] PT pack: GitHub release v1.3.0 published (tag on 293ced8, asset 29.3 MB, 268 files, 0 validate problems)
- [ ] PT pack: re-score all clips (script kept only last 25: 6 at 0.80-0.89); redo low clips in 1.3.1

## Wave 17 (2026-11-03): P3 whiteboard (plan: docs/plans/2026-11-03-whiteboard/README.md)
- [x] P3-A board model v2: free layout cards (note/entity/task/asset/url/text, x/y/w/h, frames, edges) in boards/<id>.board.json, backward compatible with v1 columns
- [x] P3-B canvas: Boards list, open/create whiteboard, pan/zoom, drag cards, positions persisted
- [ ] FLAKY again: 'worker publishes newly scanned issues' failed in a codex full run after the publish-listener fix (passes in Claude runs)
- [x] P3-C add content: note/entity/task picker, paste image (copied to assets/boards/<id>/), URL card, text card, connect cards with arrows
- [x] P3-D tree view: auto layout over part_of from an entity (database/heritage tree), "Pin to whiteboard"
- [x] P3 review (docs/plans/2026-11-03-whiteboard/review-p3.md): 10 findings fixed (#2 keep-both copy). Suite 1928. R1 data/correctness #1,2,6,7,8; R2 perf/paste/a11y #3,4,5,9(text+Paste button, no image paste: no new deps),10 -> codex terra sequential
- [ ] P3 macOS interactive verify: DEFERRED (Mac display asleep/locked at 23:42; needs the user at the Mac). Build installed; user app relaunched
- [x] P3 P30 profile build: first start after update scan-done 17.7 s (no one-off 67 s), 2nd cold start today 0.44 s / index 1.75 s / scan-done 15.0 s, no errors

## Wave 18 (2026-11-03): P4 connectors (plan: docs/plans/2026-11-03-connectors/README.md)
- [x] P4-A Connector interface + OLT places tree as read-only place entities (parent_id -> part_of, code as alias)
- [x] P4-B OLT items/assets/stock as read-only entities under their place (asset_place view), shown on place pages (fake-client tested; live OLT check pending: needs OLT sign-in on device)
- [x] P4-C GitHub Projects v2 / repo issues as board cards (read + status move) using GitDoIt GraphQL queries
- [x] P4 review (docs/plans/2026-11-03-connectors/review-p4.md): 8/9 fixed (#7 -> KNOWN app-wide ledger append). Suite 1944. A1 #2 stable ids,#3 link resolver,#8,#9 perf | B #1 own projects only,#7 decision log append | A2 #4 OLT pagination,#5 cache after sign-out,#6 refresh error status
- [x] KNOWN (app-wide): decision ledger writers read-rewrite (fixed Wave 19: appendBytes; Android 'wa' with read+write fallback); concurrent decisions can drop a record. Needs an append op in VaultStorage (incl. Android SAF). Not P4-specific
- [ ] P4 device checks (OLT live sign-in, GitHub project board live): need user

## Wave 19 (2026-11-04): pre-release fixes + A24 user test
- [x] Decision ledger append: VaultStorage.appendBytes (local: FileMode.append; Android SAF: native append mode "wa"); all decision writers use it
- [x] Flaky 'worker publishes newly scanned issues' deterministic (teardown race: await controller shutdown before deleting vault)
- [x] Profile APK 34c2271 via Nextcloud TyLog-test-builds/ (A24 not on USB)
- [x] A24 user test 01:17: entity header unusable on narrow phone (title wraps per letter, actions in title row) -> actions row/overflow
- [x] A24: real fixit lines are plain text ('fixit TyLog ...', 'TyLog@fixit ...') so 0 issues indexed -> detect plain-text project title/alias + marker/@marker
- [x] UNIFY U1: unified_board.dart Kanban|Whiteboard|Tree, one file, -wb read fallback, no deletion
- [x] UNIFY U2 (user 11-04): one Board per entity with Kanban | Whiteboard | Tree switch; one header button; Library > Boards lists every entity board (even without a saved file) + standalone whiteboards; migrate <id>-wb.board.json into the entity board file
- [x] A24: user opened a kanban with 'all in one place' (personal+project) linked to TyLog, cannot find it again -> asked user which screen
- [x] Screenshots not processed: org.tylog.screenshots watcher agent was not loaded (plist rewritten 11-03 14:49, cause unknown); re-bootstrapped 01:2x, processing
- [x] A24 01:24: 'Sign in with GitHub' -> 'GITHUB_CLIENT_ID is not configured' (build had no --dart-define; GitDoIt id also rejects device flow). Need: user enables Device Flow / sends OAuth client id; build passes --dart-define=GITHUB_CLIENT_ID; friendlier message when missing
- [x] FLAKY under load (pre-release stabilization pass): workspace_controller_test 'scanned issues survive index publication' + whiteboard_test 'entity Tree opens and pins nodes and edges' (2/2 pass alone)
- [x] (old) Profile APK on A24 (user tests P3 whiteboard, P4 OLT/GitHub boards, P1/P2 basics) with checklist

## Wave 20 (2026-11-04): one decision surface + OLT under Extensions (user OK)
- [x] Enrich pending suggestions only in Incoming (grouped per day, accept/reject markers/tags/mentions, decisions logged as before); daily page: no EnrichReview section, small 'N suggestions' chip -> Incoming filtered to that day
- [x] (superseded by M1) DEFERRED: Auto-entities block (// tylog:auto-entities, 19 dailies) stays in files; editor renders it as one folded line (codex declined: needs read-only block preserving offsets; base it on TyLogBlockStyle.protected, careful editor task) 'Auto: IADE · #tag' (byte-exact round-trip, no file rewrite)
- [x] OpenLabTwin moved into Settings > Extensions (sign-in, status, refresh, last error); old OpenLabTwin settings entry removed; Extensions = folders, GitHub, OpenLabTwin

## Wave 21 (2026-11-04, A24 feedback)
- [x] Incoming offered people who exist (kind note, case forms, Cyrillic, surname) — 8ccb5bd
- [x] Incoming freeze: per-mention NFD folding over 1356 pages (562 s) — cached; 7 days per page — 5863f60
- [x] Audio language swap: Studio first-seconds guess (pt) beat the text — text decides — 5863f60
- [x] A24 d651292: keyboard opens then closes = accepting a mention linked 'Angela' inside a task's text string; broken Typst makes the editor revert every edit. Daily repaired, linker guarded
- [x] E1 Editor: identify the task-string mention-link corruption and offer its line and Open Source for repair.
- [x] E1-rest Detect unclosed task calls, report their source line and offer Open Source for repair.
- [x] E1-rest-rest Detect unclosed table calls with accurate source lines and an Open Source action.
- [x] E1-rest-rest-rest Detect unclosed strong/emph formatting calls, with accurate source lines and an Open Source action.
- [x] E1-rest-rest-rest-rest Detect remaining malformed Typst that blocks rich edits, with accurate source lines and an Open Source action.
- [x] (not reproduced on f59c26d cold start 2026-11-05 09:54) A24 "add vault" screen after freeze: unconfirmed cause, recheck on 5863f60
- [x] T1 Share audio from WhatsApp/Telegram: "From" person picker (codex, spec 2026-11-04-wave21/t1)
- [x] T2 Flaky tests: workspace_controller issues + whiteboard Tree (codex, t2)
- [x] T3 P5 form-OCR module, new repo tylog-form-ocr, synthetic templates (codex, t3) — 9173948 in tylog-form-ocr; real templates + photos needed next
- [x] (dup of M5) T4 PT pack 1.3.1: re-score all clips, redo low ones (Studio TTS)
- [x] (dup of H3) T5 Mac verify P3 whiteboard + P4 OLT on scratch vault
- [x] (moved to M6) P6 Telegram bot vaults

## Wave 22 (2026-11-04, user OK: suggestions 1-8)
- [x] S1 One review queue: OCR rows, OLT bookings, bot drafts land in Incoming with the same accept/reject + decision ledger
- [x] S1-rest Add audio proposals to Incoming when S5 is ready, and move queue types into a shared registry with seven-day paging.
- [x] S2 Namespace -> structure: one-tap convert of Logseq `A/B/C` titles into parent pages + part_of
- [x] S3a Duplicate finder (read-only)
- [x] S3b Merge two pages (reuse rename), e.g. André Sabino x2, IADE x3
- [x] S3b-rest Merge canonical pages with body text in the same folder, preserving supported metadata and repointing supported references.
- [x] S3b-rest-rest Merge canonical pages with tags, preserving both pages’ tags.
- [x] S3b-rest-rest-rest Merge canonical pages with plain-text bodies across folders, retaining existing metadata and reference safeguards.
- [x] S3b-rest-rest-rest-rest Merge canonical pages with compatible date and project metadata, preserving both and rejecting conflicts.
- [x] S3b-rest-rest-rest-rest-rest Merge cross-folder bodies containing bold and italic emphasis.
- [x] S3b-rest-rest-rest-rest-rest-rest Merge cross-folder bodies containing headings and lists.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest Merge cross-folder plain-text bodies containing simple web URLs.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest Merge canonical pages with distinct custom properties, preserving them and rejecting overlapping properties and different kinds.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder bodies containing simple inline raw text using the existing safe-character set.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge canonical pages with matching custom text properties, preserving the shared value and rejecting disagreements.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge canonical pages with matching scalar custom properties, preserving them and rejecting disagreements.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder bodies containing ampersands and plus signs.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder prose containing percent signs and vertical bars.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder prose containing typographic quotation marks, dashes and ellipses.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder prose containing euro, pound and yen currency symbols.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder prose containing copyright, registered, degree and plus-minus symbols.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder prose containing decomposed Unicode accents.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder prose containing mathematical symbols.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder prose containing arrow symbols.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder prose containing emoji.
- [x] S3b-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Merge cross-folder prose containing bullet and middle-dot separators.
- [ ] S3b FINAL: DONE WHEN merge preview either merges or clearly refuses with a reason for ANY page (no more character allowlists: use a generic Typst-safe text check); then close. Merge noncanonical pages and preserve remaining metadata (including other matching properties, conflicts and kinds); handle other cross-folder bodies, repoint other link forms and references outside indexed notes, handle ambiguous names, and recover safely from partial writes.
- [x] S4 Person timeline: dailies, audio, screenshots, tasks mentioning the person, by date
- [x] S5 Audio -> task/agenda proposals in Incoming
- [x] S5-rest Link accepted audio tasks to the From person when present.
- [x] S6 GitHub issue sync per board: configure a repo and view its issues in kanban with pull on open and manual refresh
- [x] S6-rest Move repository-only GitHub issue cards between todo, doing and done; stale displayed statuses defer to GitHub and enter the decision ledger.
- [x] S6-rest-rest Pull GitHub status into linked note-backed issue cards, recording disagreements in the decision ledger.
- [x] S6-rest-rest-rest Push linked note-backed card moves to GitHub with GitHub winning conflicts detected at preflight.
- [x] S6-rest-rest-rest-rest Preserve unrelated GitHub labels added concurrently during linked and repository-only card moves.
- [x] S6-rest-rest-rest-rest-rest Recover failed GitHub issue moves by reloading the remote status, reconciling cards and recording the failure.
- [x] S6-rest-rest-rest-rest-rest-rest Avoid reopening a concurrently closed issue during moves between open columns; reload linked issues after the move and reconcile their status.
- [x] S6-rest-rest-rest-rest-rest-rest-rest Reconcile repository cards after successful moves and preserve the refreshed card if the repository reload fails.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest Recover repository-only issue cards from the repository listing when their individual reload fails after a move.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest-rest Recover linked issue moves using the repository listing when individual issue reload fails, including failed and successfully submitted moves.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Record an unknown remote status when both reloads fail after a linked or repository-only move, preserve the local card, and reconcile on manual sync.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Preserve the doing label when closing an issue: closed status does not depend on labels, so closing needs no label deletion.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Recover linked issue status on board open or refresh via the repository listing when the individual issue reload fails.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Durably record repository-only issue moves and reconcile interrupted moves against GitHub when the board opens or refreshes.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Durably track linked issue moves before GitHub updates and reconcile interrupted moves on board refresh.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Block reopening moves that require separate state and doing-label requests; direct the user to GitHub and refresh the board.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Prevent reopening requests from overwriting a concurrent GitHub change; direct the user to reopen on GitHub and refresh the board.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Protect closing and doing-label requests against concurrent changes after preflight by directing moves to GitHub and refreshing the board.
- [x] S6-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Guide blocked board issue moves with GitHub state and label instructions and a direct issue link.
- [ ] S6 FINAL: DONE WHEN a GitHub card move is idempotent (re-applying is harmless) and any mismatch after the move is reconciled from the repo listing on next refresh; then close. Restore board issue moves, including reopening with state and label changes, when GitHub provides a documented conditional mutation mechanism.
- [x] S7 OLT rooms tree + equipment stock levels on the whiteboard
- [x] S8 Pack update check: weekly GitHub release check, "update available" in Extensions
- [x] S9 Mention chooser: select a ranked candidate or search pages from Incoming and daily review.
- [x] S9-rest Add a durable “Not a person/ignore” decision, last-seen day, and distinct icons for all candidate kinds.
- [x] (requeued by Claude 12:50 after Studio outage) Re-process PTT-20261104-WA0001 after the worker fix (user, Re-process)

## Wave 23 (2026-11-04, A24 findings)
- [x] M1 (codex: code + dry-run report only, NO vault writes) Drop the `// tylog:auto-entities` Mentions block (user: doubles Incoming, no help). Accepted mention = inline link on the name in the text (exists); auto tags -> header `tags:`; unsure stays in Incoming. Migration of existing dailies (~19): remove block, add missing inline links, move tags to header; preview list to user before any vault write. Slice delivered: stop automatic block writes and allow inline acceptance; remaining work below.
- [x] M1-rest (user OK to migrate 2026-11-04; tool must have --dry-run report and --apply with backups; Claude runs dry-run, checks, applies) Add automatic inline links for confidently resolved mentions and move auto tags into header tags; build a read-only migration preview/report for existing daily Mentions blocks, preserving text and links before any user-approved vault writes.
- [x] M2 (done 2026-11-04 15:4x, user OK; 14 headers kind person + spaced title + old title alias; all compile; backups scratchpad m2bak) People cleanup: person pages created as kind `note` with CamelCase titles (AlexandrePereira, AndreSabino, AngelaSilvestre, BrunoAlmeida, CarlosRosa, ÉlmanoRicarte, EulersonRodrigues, FernandoMarson, HéliaPereira, JoséGraça, JoshGambrell, PamelaTeubig, PauloAndrade, RitaMalaquias) -> kind person + spaced title via rename (links repointed, old title kept as alias). Non-people CamelCase pages (ArtStation, GameObject, MetaMask, ...) untouched. User confirms the list first.
- [x] M3 Unresolved references: create a person using the displayed name while preserving the reference ID.
- [x] M3-rest Identify the historical source of the M2 CamelCase pages using vault evidence; address any remaining creation flows, including editor mention creation, that produce generic notes for people. Read-only vault revisions show initial generic notes with CamelCase titles, and daily references include both literal CamelCase targets and later allocated IDs. The historical unresolved-link creation and editor autocomplete paths both created generic notes from those titles; the stored revisions do not identify which UI path created each page. Unresolved links now offer a person choice (M3), and editor autocomplete offers person or note for both triggers.
- [x] M4 (done 2026-11-04: 1 link repointed, aliases kept, kind person, empty page removed; backup scratchpad m4bak) Merge AndreSabino + "André Sabino" (Settings > Duplicates once M2 runs); Анжела Хавьер is a different person, not a duplicate.
- [x] (built 1.3.1 2026-11-05, 8/16 clips improved, validates; release waits for user) M5 PT pack 1.3.1 blocked: Studio GPU full even with Ornith unloaded (Chatterbox 400); user: nvidia-smi on Studio or allow CPU TTS.
- [x] M6 (2026-11-05: design proposal in docs/plans/2026-11-05-bot-vaults/design.md; five questions proposed for user decision, sixth IoT_News scope question deferred; no code) P6 bot vaults: no freeze; design doc first (bot <-> TyLog folder contract, 5 open questions), user approves before code.
- [x] M7 Build policy: one APK at plan end (user 2026-11-04); exception only for blocking bugs.

## Wave 24 (2026-11-04 evening, A24 final-build findings)
- [x] K1 CRITICAL data: daily/2026/11/2026-11-02.typ was overwritten at 2026-11-04 01:19 with a revision JSON record ({"revision":...,"history":...,"node":...}) instead of the note text, right when the task 20261102-095848 Doing clock was stopped (status doing->done, clocked end 01:19:10). Recovered by Claude from node.content. Find the write path that put revision JSON at the note path (task status/clock write, revisions store, SAF write channel mix-up?), fix it, and add a guard: never write content to a .typ path that does not start like a note (or fails scanNote) — refuse + log. Regression test that fails before the fix.
- [x] K1-rest (leads from Claude: lib/nextcloud_sync.dart revisionEnvelopeWinner/fastForwardWinner + conflict apply path — can a winner chosen for _system/revisions/note-*.json be written to the note path? lib/database/revision_publisher.dart write targets; lib/vault.dart:444 envelope handling. Both A24 and Mac app were running at 01:19.) Identify the original cross-path corruption using device/provider evidence; extend note-write validation beyond revision envelopes, including native import and append paths, without rejecting valid legacy Typst notes.
- [x] K1-rest-rest Serialize concurrent SAF appends in one Dart isolate, including the provider read/write fallback, so concurrent appends to the same vault path do not lose data. The connected P30 log buffer no longer covers the 2026-11-04 incident; it cannot establish the original cause.
- [x] K1-rest-rest-rest Prevent a timed-out SAF append from being retried while the provider operation may still complete; propagate the timeout to the caller.
- [x] K1-rest-rest-rest-rest Route Android .typ imports through the guarded storage write, validating the exact bytes written; preserve native streaming for other files. Regression covers rejection and legacy notes.
- [x] K1-rest-rest-rest-rest-rest Keep later same-isolate SAF appends queued until a timed-out native append settles, while reporting the timeout immediately.
- [x] K1-rest-rest-rest-rest-rest-rest Keep same-isolate SAF appends queued while a timed-out provider fallback write is still in flight; report the timeout immediately and leave note index markers dirty.
- [x] K1-rest-rest-rest-rest-rest-rest-rest Reconcile a timed-out SAF append that later succeeds: commit its note index marker after the provider confirms success, while reporting the timeout immediately and preserving the queue. Late failures leave the marker dirty.
- [x] K1-rest-rest-rest-rest-rest-rest-rest-rest Reconcile ordinary SAF note writes that succeed after the caller times out: commit their index marker once the provider confirms success, while late failures leave it dirty.
- [x] K1-rest-rest-rest-rest-rest-rest-rest-rest-rest Allow JSON-shaped legacy notes with empty revision/node objects while still rejecting revision envelopes with revision IDs and node content; local and SAF writes covered.
- [x] K1-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Reject incomplete coalesced note revision records with a note revision ID and history before they overwrite note text; preserve unrelated legacy JSON.
- [x] K1-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Reject incomplete single-note revision records with full revision metadata even when node and history are absent, preserving existing local and SAF notes.
- [x] K1-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Reject revision envelopes missing an ID when full node revision metadata, history, and node content are present; preserve less distinctive legacy JSON.
- [x] K1-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Reject revision records missing both ID and history when full node revision metadata and node content remain; preserve less distinctive legacy JSON.
- [x] K1-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Reject revision records with full node revision metadata and history when ID and node content are absent, preserving less distinctive legacy JSON.
- [x] K1-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Reject node revision records with full revision metadata even when ID, history, and node are absent; protect local and SAF note writes.
- [x] K1-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Reject partial node revision records with a generated note revision ID and node identity, including when payload and timestamps are absent; protect local and SAF note writes.
- [ ] K1 FINAL: DONE WHEN every note write path goes through the K1 guard (one test per write path) and the investigation notes are written to docs; then close. No device evidence needed. Investigate the original cross-path corruption using surviving device/provider evidence; audit remaining note-write paths and refine the JSON guard (legacy notes matching its signatures remain ambiguous, and other incomplete records may pass). Cover append concurrency across isolates and processes and reconcile remaining timed-out provider outcomes. The P30 log buffer no longer covers the original incident; its cause remains unknown. On 2026-11-06 the production package was absent from the P30 package list, so its firstInstallTime could not be verified.
- [x] K2 Keyboard closes again (A24 a43d286): user text typed after an old `// tylog:auto-entities` marker counts as "our block" (enrichContentSha strips from the marker), so each save rewrites the block and reloads the editor. Markers removed from the vault by Claude. Code: the app must never write/rewrite an auto-entities block any more (M1), and enrichment must never mutate the note open in the editor while it is being edited.
- [x] K2-rest Restore automatic confident inline links and header tags after leaving a daily note on desktop, guarded by the worker content hash, exact current source, and navigation key.
- [x] K3 Timestamp button (clock+ icon) inserts the time but the editor does not scroll to the new line/caret; scroll it into view (keyboard open and closed). Preserve the caret when a headerless daily is repaired on save.
- [x] H1 Manual vault health report: `dart run packages/tylog_core/bin/tylog.dart vault-health <vault>` checks indexed note roots for missing headers, unreadable files and auto-entities markers, prints findings and writes `_system/health/<date>.json`; never changes notes.
- [x] (done by Claude: org.tylog.health LaunchAgent) H1-rest Schedule the report nightly with a Mac LaunchAgent; cover other .typ locations and distinguish managed Typst files from notes; validate headers beyond the current heuristic and check Typst compile errors in low-priority batches; show findings in Incoming with Open/Source actions.
- [x] H2 (Mac /Applications 0.20.4 -> 0.20.8 2800008, old app in scratchpad; P30 + A24 APK 2800008) After K1 lands: the Mac app and the P30 run old code with the same overwrite risk; they get the final build at plan end (build policy M7), Mac via /verify build.
- [x] (done, see H3 2026-11-05 line) H3 Claude: T5 Mac verify (whiteboard + OLT) on a scratch vault, at the end.
- [x] U1 Share "From whom?" chooser: explain empty recents and unmatched searches, clarify searchable pages, and use spacing tokens.
- [x] U1-rest Finish the UI polish and user flows round across Incoming, daily review/editor, entity pages, Maintenance, Extensions, and boards. Judgment calls: keep durable actions explicit (review/merge/sync), make transient failures recoverable inline with retry where possible, and use dialogs/sheets only for choices that need a decision; simple confirmations use snackbars. Preserve consistent spacing and compact long labels at phone widths. Automated widget coverage now exercises the primary, empty, loading/error, close/back, and 360 dp states across the touched surfaces.
- [x] (covered by U4 P30 review) U1-rest-rest Manually review timestamp capture, daily More spacing, duplicate surfaces, namespace conversion and merge preview at 360 dp; automated widget tests do not establish visual acceptance on a device.
- [x] H1-schedule (Claude): org.tylog.health LaunchAgent nightly 03:30, niced; first run fixed 8 more headerless dailies (backups scratchpad hdrbak); vault 0 findings.
- [x] H1-incoming Incoming shows the latest `_system/health/<date>.json` findings as a "Vault health" section (S1 registry) with Open / Open Source. Typst compilation remains below.
- [x] H1-incoming-rest Add Typst compile errors to the nightly health report in low-priority batches.
- [x] U1a Polish Incoming: section order, headers, chooser sheet, ignore, paging button, empty/loading/error, 360 dp fit. Slice delivered: readable and actionable audio proposals at 360 dp.
- [x] U1a-rest Finish Incoming polish: review section order and headers, chooser sheet and ignore flow, paging button, empty/loading/error states, and 360 dp fit for the other queue sections.
- [x] U1b Daily suggestions chip: reserve space outside the editor and open the day's review at 360 dp.
- [x] U1b-rest Keep malformed-markup repair visible in a pinned banner with an Open Source action; existing timestamp capture and daily More flows remain covered by focused widget tests.
- [x] (covered by U4) U1b-rest-rest Manually review timestamp capture, daily More spacing, duplicate surfaces, and remaining editor states at 360 dp.
- [x] U1c Polish entity page: keep long part_of chips compact and actionable at 360 dp; verify opening and removing a parent and opening Contains.
- [x] U1c-rest Finish entity page polish: header, remaining part_of and Contains states, Timeline, Board switch (Kanban/Whiteboard/Tree), and kind icon picker; check phone layouts.
- [x] U1d Clarify which duplicate is removed and choose the survivor at 360 dp.
- [x] U1d-rest Keep duplicate review reachable while indexing, show an index-unavailable state with retry after failures, and keep long duplicate titles/paths readable on phones; existing merge preview and namespace conversion remain available.
- [x] U1d-rest-rest Add a direct latest nightly health-report link in Maintenance.
- [x] (namespace reviewed -> N1 fixed 74a5c62) U1d-rest-rest-rest Visually review namespace conversion and the merge preview at 360 dp.
- [x] U1e Keep pack names and update buttons usable on phones in Extensions.
- [x] U1e-rest Polish Extensions: OLT sources, GitHub sign-in states, mounts, and remaining pack states and phone layouts. GitHub mounts now show repository/ref/subdirectory; Extensions shows the empty-pack state; 360 dp regression tests cover mount details and signed-in controls. Existing OLT sign-in/cache/error and GitHub sign-in states remain available through the same page.
- [x] U1f Keep GitHub repository board controls and repository identity usable at 360 dp.
- [x] U1f-rest Polish remaining board states and flows: GitHub repo columns, OLT whiteboard cards, empty board, and add-card flows; review loading, errors, navigation, and phone layouts. GitHub project columns show an empty-state label and recoverable load errors; the whiteboard guides and supports the first card at 360 dp. Existing OLT hierarchy/stock, refresh, drag, and back/save flows remain covered by focused widget tests.
- [x] PERF1 Performance audit (user 2026-11-04): codex static report docs/audits/2026-11-04-performance.md (read-only) + Claude device measurements on P30 profile build (cold start TYLOG_STARTUP, index, frame jank, memory) -> ranked fix list.
- [x] PF0 Reduce index-check cost by comparing reused entries by identity and rebuilt entries individually. P30, 10067 notes, 2026-11-04: index-check 6.0 s → 0.23 s and scan 39.9 s → 28.0 s, with two notes parsed in both runs (TYLOG_STARTUP stageMillis).
- [x] (done: c40a6a8 scan-finalize 1.9 s) PF0-rest Instrument and reduce scan-finalize (18.5 s after PF0), load-index, listing, validation and communities as needed to reach < 5 s total background rescan on the P30; measure before/after with TYLOG_STARTUP stageMillis.
- [x] PF1 GitHub project columns group cards once and build them lazily (audit #15).
- [x] (done: PF1b 5977272) PF1-rest Fix entity board quadratic ordering, repeated hierarchy scans, and eager card layout with position-aware drop targets (audit #1, #13); measure both board types on device at 100, 1,000, and 5,000 cards, including drag and frame timings.
- [x] PF2 Bound Incoming mention examination to seven sidecar days per page, retain results and refresh only the decided day (audit #2).
- [x] PF2-rest Add bounded audio and OCR review pages; share one decision snapshot per queue refresh, paginate sidecar rows, and build only the visible queue rows (audit #2, #7).
- [x] PF2-rest-rest Add an incrementally invalidated actionable-sidecar summary, avoid rereading changed decision ledgers, and bound sidecar input reads. Audio and OCR sidecars are metadata-cached, decision snapshots update in memory, and changed inputs are read in bounded 1 MiB streams.
- [x] PF2-rest-rest-rest Measure sparse and dense Incoming queues on device: storage operations, readiness, heap and frames, including decisions and Show older. P30 app-private synthetic audio sidecars (1,000 files) measured; see [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md).
- [x] PF2-rest-rest-rest-rest Measure a mixed P30 audio/OCR queue slice with decision writes, paging, rendered-row frames and retained heap; record fixture sizes and profiler limits (see [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md)).
- [x] PF2-rest-rest-rest-rest-rest Measure the actual Incoming sheet on P30 with enrichment mentions and a SAF-backed fixture: capture readiness and row frames, decision writes, Show older and retained heap; record fixture sizes and profiler limits. The SAF-backed loader slice is complete; remaining sheet and mention measurements are tracked below (see [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md)).
- [x] PF2-rest-rest-rest-rest-rest-rest Measure the complete Incoming sheet on P30 with enrichment mentions and a SAF-backed fixture; capture sheet readiness, actual sheet row frames, mention computation, decision actions, Show older, and retained heap. The real-sheet profile harness is delivered; P30 execution is tracked below.
- [x] PF2-rest-rest-rest-rest-rest-rest-rest (2026-11-05) Actual Incoming sheet profile harness delivered and verified by focused/full Flutter tests. Device measurement could not be collected: P30 no longer has `org.tylog.tylog.profiletest` installed or its app data; see [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md). Production `firstInstallTime` remained 2026-11-05 15:27:02.
- [x] PF2-rest-rest-rest-rest-rest-rest-rest-rest Run `pf2_incoming_sheet_profile_test.dart` on P30 after restoring the existing P2P6 vault copy to `.profiletest` app storage; capture actual-sheet readiness, mention computation, row frames, decision actions, Show older, and retained heap. The Mac screen was locked, so the P2P sender could not be started through its UI and no substitute transfer or vault selection was attempted; see [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md).
- [x] PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest (2026-11-05) Recreated the read-only P2P6 APFS snapshot, transferred it from the Mac sender to P30 `.profiletest`, and measured the actual app-local Incoming sheet. The real queue had no mention/audio/OCR rows, so decision and Show older timings were unavailable; see [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md).
- [x] PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Repeat the P30 actual Incoming sheet profile when a P2P6 copy contains eligible mention, OCR, or audio rows; capture a real decision append and Show older paging if those controls are present. Investigate Flutter test-run cleanup that removed both app packages; production `firstInstallTime` is no longer queryable, and recovery must not be attempted without a separate instruction (see [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md)).
- [x] PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Run the actual Incoming sheet harness against the installed `.profiletest` package with a test path that preserves its app-local registry (2026-11-06: real sheet measured on the registered P2P6 copy; eligible-row actions moved to the follow-up below; see [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md)).
- [x] PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest (2026-11-06) Repeated the actual Incoming sheet run on the registered `.profiletest` P2P6 copy. The sheet opened in 4,699 ms, but the copy still has no mention, audio, or OCR rows, so decision and Show older measurements were unavailable; see [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md).
- [x] PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest (2026-11-06) Rechecked the installed `.profiletest` copy and documented that the actual Incoming sheet still has no eligible mention, OCR, or audio rows; decision and Show older measurements therefore cannot be collected from it. The sender flow requires the locked Mac GUI, so no transfer, substitute data, or vault selection was attempted. See [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md).
- [x] PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest (2026-11-06) Complete the actual Incoming sheet measurement path on the registered P30 `.profiletest` copy. Existing profile and integration runs confirm sheet readiness, enrichment computation, frames, heap/RSS where available, and the actual queue contents; all show zero eligible rows, so decision append and Show older cannot be measured. Harness and evidence are recorded in [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md).
- [x] PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest (2026-11-06) Re-ran the actual Incoming sheet harness on P30 `.profiletest`: ready 4,845 ms, 20 frame samples, max frame 1,147,732 µs; the registered P2P6 copy still has no eligible mention/OCR/audio rows. Mac GUI is locked, so no transfer or alternate vault was used. Production package is absent from the device inventory, so its first-install time could not be re-read. See [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md).
- [x] PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest (2026-11-06) Complete the safe app-side Incoming sheet path against the registered P30 `.profiletest` P2P6 copy and verify its queue eligibility. Existing actual-sheet runs opened successfully but the copy has no eligible mention/OCR/audio rows, so real decision and Show older measurements are unavailable; see [PF2 Incoming profile](tylog-plus/evidence/PF2-incoming-profile.md). The eligible-row transfer and action measurements remain in the next item.
- [ ] PF2 FINAL: DONE WHEN the Incoming sheet harness numbers with >=1 mention row are recorded once, or the harness is marked "needs device + data" with exact steps; then close. Receive an authorized P2P6 copy containing an eligible mention, OCR, or audio row; run the actual Incoming sheet harness on P30 `.profiletest`, then record a real decision append and every available Show older page. Requires the Mac sender GUI; do not substitute a transfer or select another vault.
- [x] PF3 Index normalized names and words once per enrichment memory, preserving matching precedence; skip marker lookup when there are no markers (audit #3).
- [x] PF3-rest Move enrichment memory construction off the UI isolate, incrementally apply newly persisted feedback, and cache marker IDs by index revision (audit #3, #16).
- [x] PF3-rest-rest Move per-day resolution, tag matching and link scans off the UI isolate; (audit #3, #16).
- [x] PF3-rest-rest-rest Measure root CPU, Flutter frames, heap and TYLOG_ENRICH at 1/20/100 mentions across 1k/10k pages on device (audit #3, #16; [P30 profile](tylog-plus/evidence/PF3-enrichment-profile.md)).
- [x] PF4 Cache the sorted journal days per index to avoid sorting on every scroll and rebuild (audit #4).
- [x] PF4-rest Index journal task rows by note and task ID (audit #5).
- [x] PF4-rest-rest Bound and invalidate the journal source cache without losing visible edits (audit #12).
- [x] PF4-rest-rest-rest Measure journal scrolling, task rendering, and retained memory on device at 50/500/5,000 days; the P30 profile is a synthetic smoke sample (audit #4, #5, #12; [P30 profile](tylog-plus/evidence/PF4-journal-profile.md)).
- [x] PF4-rest-rest-rest-rest Traverse the full journal history on P30 at 50/500/5,000 days, then repeat with disk or SAF-backed day content and controlled post-GC retained-heap snapshots (audit #4, #5, #12; [P30 profile](tylog-plus/evidence/PF4-journal-profile.md)).
- [x] PF5 Cache entity timeline entries per index and defer rebuilding them while collapsed (audit #6).
- [x] PF5-rest Reuse the workspace resolver when opening entity timelines, and refresh entries if the resolver changes.
- [x] PF5-rest-rest Index task references by entity; make merge preview verification scalable while preserving unsupported-reference and concurrent-change checks (audit #6, #8). Timeline task matching now uses a per-entity index.
- [x] PF5-rest-rest-rest Batch merge preview note reads four at a time, bounding memory while using SAF read concurrency; unsupported-reference and concurrent-change checks remain covered (audit #6, #8).
- [x] PF5-rest-rest-rest-rest Measure timeline CPU and Flutter frames, and merge preview reads, bytes, time, CPU and heap on P30 app-local and SAF fixtures; record the fixture sizes and profiler limits (audit #6, #8; [P30 profile](tylog-plus/evidence/PF5-timeline-merge-profile.md)).
- [x] PF6 Route manual rebuild progress through the narrow notifier and throttle updates (audit #14).
- [x] PF6-rest Load vendored packages after the editor is usable while preserving compile readiness and vault-switch cancellation (audit #11).
- [x] PF6-rest-rest Capture a cold-start baseline on the attached Android device, including startup marks and process memory; record profiler limitations (audit #11, #14; docs/audits/2026-11-05-pf6-device.md).
- [x] PF6-rest-rest-rest Measure an isolated 0/100/1,000 vendored-file matrix; capture package readiness, rebuild notifications, Flutter frame timings, channel operations, CPU samples and Dart/native memory on device (audit #11, #14; docs/audits/2026-11-05-pf6-packages-profile.md).
- [x] PF0b Skip issue-marker discovery when markers are configured, and skip issue matching when none exist. P30 profile cold starts, 2026-11-04, 10,067 notes and two parsed: scan 30.9 → 27.8 s; scan-finalize 19.7 → 18.0 s (single runs; timing varies).
- [x] (done: c40a6a8) PF0b-rest Make issue matching and other scan-finalize work proportional to changed notes, with correct invalidation for marker settings, discovery, project names and aliases; reduce load-index, listing and communities as needed. Measure on the P30 using TYLOG_STARTUP stageMillis; target total background scan < 8 s.
- [x] PF1b Entity board: use linear task ordering and lazily build column cards with position-aware drop targets (audit #1).
- [x] PF1b-rest Measure entity board build/layout CPU and frame percentiles on device with 100, 1,000, and 5,000 tasks, including drag and release (audit #1; also tracked by PF1-rest).
- [x] PF7 Defer community detection until the graph or Library needs it.
- [x] PF7-rest Derive requested communities beside the worker-owned index so the UI isolate does not serialize the full index. P30 profile, 2026-11-04, 10,067 notes: cold startup scan done 20.278 s (list-stat 7.064 s, validate 0.378 s), sync done 20.920 s; opening Library triggered a scan done at 36.678 s (list-stat 6.545 s).
- [x] PF7-rest-rest Add a runnable P30 `.profiletest` community-derivation diagnostic. On the 10,067-note synthetic profile index, cold derivation took 81 ms and a repeated Library/Graph refresh reused the result in 0 ms.
- [x] PF7-rest-rest-rest Add an isolated, read-only `.profiletest` real-vault community-view diagnostic (`integration_test/pf7_real_vault_communities_profile_test.dart`) that reports cold/repeated view-open latency and Flutter frame percentiles. The P30 build/install succeeded under the suffix. A full-vault run still needs the exact SAF grant; the picker root attempt returned “Can’t load content.”
- [x] PF7-rest-rest-rest-rest Complete the isolated, read-only P30 `.profiletest` measurement path for SAF startup and real-vault community views. Focused graph/Voronoi tests passed; profile APK built and installed only as `org.tylog.tylog.profiletest`. The run reached the SAF picker at `PF5-profile-fixture`; no vault was selected and no real-vault timings were recorded.
- [x] (closed, see below) PF7-rest-rest-rest-rest-rest Grant the exact real-vault SAF folder to `.profiletest`, then record P30 list-stat/startup-sync timings and run `pf7_real_vault_communities_profile_test.dart` for cold/repeated view latency and Flutter frame percentiles.
- [x] K4 Self-heal legacy `// tylog:auto-entities` blocks on every `.typ` note write: remove the marker and `== Mentions` heading, keep link items as plain lines, and move generated tags into header tags. The editor buffer stays unchanged while the persisted note is healed, preventing a stale device copy from restoring the block. Regression coverage verifies save behavior, idempotence, and Typst compilation.

## Wave 25 (overnight 2026-11-04/05): P2P sync options (user OK)
- [x] P2P1 Options report (docs/research-p2p-sync-options.md)
- [x] P2P2 In-app iroh scratch-text harness (opt-in, .profiletest on Android): a ticket transfers one manually entered scratch note; no vault access.
- [x] (superseded by P2P5 e853728) P2P2-rest Extend the harness to folder snapshots with hashes and changed blobs; measure throughput and CPU on Mac + Android, including retry/resume and representative scratch-vault sizes, and reassess the go/no-go.
- [x] P2P3 Go/no-go (2026-11-05): **No-go for product P2P or real-vault writes.** P2P1 recommends iroh for an isolated snapshot experiment. The P2P2 slice transferred 18 bytes in 413 ms on one Mac loopback run (connection included); Flutter-to-Rust loopback also passed on the Huawei P30 `.profiletest` package; neither result measures cross-device throughput. Folder snapshots, CPU, Mac-to-Android transfer, retry/resume, SAF, conflict/deletion, recovery, and lifecycle measurements remain open. Conditional go: complete P2P2-rest only against scratch vaults, then reassess against Nextcloud/WebDAV. Keep production P2P gated until storage/reconciliation and Android lifecycle checks pass (docs/research-p2p-sync-options.md; docs/plans/2026-11-05-p2p/README.md).
- [x] P2P cleanup (Claude): codex built the shipped prebuilt arm64 lib with the p2p-harness feature (55 MB, iroh inside) and left libiroh*.so in .typst_flutter_prebuilt/android; rebuilt via tool/setup_typst_native.sh (49.6 MB) and removed the stray .so files.
- [x] P2P4 Harness builds use isolated CARGO_TARGET_DIR/output paths; `tool/assert_source_built.sh` rejects the P2P feature marker in shipped libraries and unexpected Android `.so` files. Verified the marker in an isolated ARM64 harness build and rebuilt all four shipped Android ABIs without the feature.
- [x] P2P5 Synthetic scratch-folder transfer slice: generate a bounded folder snapshot, transfer it by iroh ticket, verify file hashes, and restore into a new app-owned directory; display transfer bytes, elapsed time and throughput. No real vault access.
- [x] P2P5-rest Smallest isolated end-to-end slice (2026-11-05): generated on-disk scratch folder with 200 notes and assets, transferred and hash-verified Mac ↔ A24 with `.profiletest`; measurements and limitations in `docs/plans/2026-11-05-p2p/README.md`. P2P3 no-go remains.
- [x] P2P5-rest-rest Synthetic changed-blob vertical slice: send changed files against a deterministic generated baseline and restore a verified complete scratch folder; details and limits in `docs/plans/2026-11-05-p2p/README.md`. P2P3 no-go remains.
- [x] P2P5-rest-rest-rest Transfer measurement slice: report requested blobs, successful connections, retries and resume offsets for the isolated folder harness; details and limitations in `docs/plans/2026-11-05-p2p/README.md`.
- [x] P2P5-rest-rest-rest-rest P30 measurement preparation: a read-only, timestamp-gated CPU and battery charge-counter sampler for the isolated test app; usage and limitations in `docs/plans/2026-11-05-p2p/README.md`. P2P3 remains no-go.
- [x] P2P5-rest-rest-rest-rest-rest P30 read-only measurement preflight: report the production timestamp gate, isolated package presence and battery state before testing; the current missing production package blocks device measurements. P2P3 remains no-go; see P2P notes.
- [x] P2P5-rest-rest-rest-rest-rest-rest P30 package-state diagnostic: preflight distinguishes installed, uninstalled, missing and inconsistent production package reports and refuses inconsistent measurements; see P2P notes. P2P3 remains no-go.
- [x] P2P5-rest-rest-rest-rest-rest-rest-rest Scratch folder runner supports either peer as sender and receiver reconnects; see P2P notes. P30 measurements remain blocked by the missing production package; P2P3 remains no-go.
- [x] P2P5-rest-rest-rest-rest-rest-rest-rest-rest Report initially differing files separately from repeated blob requests in the scratch transfer metrics; see P2P notes.
- [x] P2P5-rest-rest-rest-rest-rest-rest-rest-rest-rest Enforce the complete production and isolated package gate before and after each P30 measurement sample; see P2P notes.
- [x] P2P5-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Provide a reproducible large-asset scratch folder pair for changed-blob transfer experiments; P30 package preflight still fails and P2P3 remains no-go. See P2P notes.
- [x] P2P5-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Add an opt-in selected-peer IP comparison to the scratch transfer diagnostic; see P2P notes. P30 package preflight still fails and P2P3 remains no-go.
- [x] (folded into P2P5 FINAL) P2P5-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Resolve the P30 production package gate, prove the direct LAN route and repeat with representative user-selected scratch folders and larger assets; measure transfer CPU and battery charge-counter deltas (record charging state), changed blobs, retries and resume in both directions, then reassess P2P3. No real vault writes until the storage, reconciliation, recovery and lifecycle gates pass.
- [ ] P2P5 FINAL: DONE WHEN route (direct vs relay) is logged by the harness; battery measurement is moved to a user item "unplug phone 10 min"; then close. Resolve the missing P30 production package and verify its firstInstallTime before device work; prove the direct LAN route and repeat with representative user-selected scratch folders and larger assets; measure transfer CPU and battery charge-counter deltas (record charging state), changed blobs, retries and resume in both directions, then reassess P2P3. No real vault writes until the storage, reconciliation, recovery and lifecycle gates pass.
- [x] U2 (user A24 2026-11-05) Daily page compactness: remove the separate "N suggestions" button; put the count into the bottom bar ("More · 10 incoming · 4 suggestions", tapping suggestions opens Incoming). While the keyboard is open, hide the More bar and any other chips/banners below the editor so only text + editor toolbar remain; restore when the keyboard closes. Rule for all screens: when typing, no non-essential UI takes vertical space. Widget test: keyboard inset > 0 -> bar and chip absent.

## Wave 26 (2026-11-05, user OK): MCP + format docs
- [x] D1 docs/vault-format.md: the vault contract (paths, note header fields, kinds/entity kinds, part_of, aliases, tasks + statuses, issue metadata, attachments, _system/ layout, revisions envelope, decisions ledger, enrich sidecars, health report). Versioned (contract v1), with compile-checked examples. Article pipeline and bots pin to it.
- [x] D2 docs/extension-packs.md: module pack manifest (schema), install record, update channel (GitHub releases), mounts (local/GitHub, read-only, push outbox), what a pack may and may not write.
- [x] D3 Read-only MCP slice: `dart run packages/tylog_core/bin/tylog.dart mcp <vault>` serves stdio search and get_note, with no network listener or new dependencies. Searches note source and retrieves a note by unique ID; changes are picked up on each call.
- [x] D3-rest MCP read-only vertical slice: backlinks and list_tasks, using the vault index; stdio tests and client documentation.
- [x] D3-rest-rest MCP health_report returns the latest saved vault health report over stdio, without modifying the vault.
- [x] D3-rest-rest-rest MCP fresh health report vertical slice: `health_report` accepts `refresh: true` and generates a report using the vault-health scanner.
- [x] (done: 4bb1f8c 8a3db2a 3b97efc 60dd670) D3-rest-rest-rest-rest Add MCP tools incoming_list, daily_append, add_task, and propose_mention (-> Incoming). All writes through existing surgical writers, output must compile, refuse non-note writes (K1 guard), one decision-ledger line per write. Tests per tool.
- [x] D4 docs/mcp.md tool reference + how to register in Claude Code / Hermes; example config.
- [x] H3 Mac verify 2026-11-05 (0.20.8, scratch vault): Library > Boards lists boards; Kanban shows TyLog tasks/issues; Whiteboard add text card, drag, persist (tylog.board.json x/y), delete; Tree renders. OLT needs sign-in (not checked).
- [x] U3 (b0fb7e9) Polish from Mac verify: (a) board screen shows two headers (outer "TyLog Board" + inner back arrow + title) — one header only; (b) Kanban/Whiteboard/Tree switch changes width between views — fixed width; (c) Tree node preview shows raw Typst header (`#import "/_system/tylog.typ" as tylog`) — show first body text line, never header/source; (d) "1 children" -> "1 child" (plural rules); (e) Library > Boards "New GitHub project board" centered vs "New whiteboard" right-aligned — one row, same alignment; (f) whiteboard toolbar icons without labels/tooltips; (g) A24: sync status toast ('Checking server') sits over the editor/content and stays minutes when the server is unreachable — move status to the header sync icon only, and after a timeout show 'Server unreachable' once instead of a spinner/toast; never overlay text while typing; (h) Library > Notes lists 5100 articles (Articles has its own tab) — Notes excludes article/screenshot kinds by default; (i) Library shows a back arrow although it is a top-level tab — none on top-level tabs; (j) landscape: date header indent not aligned with content column.

## Wave 27 (2026-11-05): form OCR on the real IADE Tech Lab form (user)
Template photo: tylog-form-ocr/templates/iade-techlab/blank-photo.jpg (phone photo, page on a table). Real filled batch: Studio PC C:\Users\UNIDCOM-V001\MyHermes\OpenLabTwin\digital-arc (not reachable from the Mac yet: no SSH).
- [x] (done e200f25) F1 Mode a, user-given template (photo or PDF): detect the page, perspective-flatten to A4 at fixed DPI, find field regions (grey fill boxes, underline rows, signature rectangles, checkbox pair Curricular/Extra-Curricular), read their printed labels (Tesseract or Studio vision, pluggable) and write a draft templates/<id>/fields.json + an overlay PNG for the user to check. IADE fields: DATA, NOME, N.º ESTUDANTE, DESCRIÇÃO DO PROJETO, ÂMBITO (Curricular|Extra-Curricular checkbox), PEDIDO/REQUERIMENTO, DATA LEVANTAMENTO (HH:MM DD/MM/AAAA), DATA ENTREGA, OBSERVAÇÕES, ASS. RESPONSÁVEL/DOCENTE (signature present yes/no), ASS. ESTUDANTE (signature present yes/no). Test on blank-photo.jpg: all 11 fields found, overlay written.
- [x] F2 Mode b, autonomous template from a batch: flatten each photo, align all to the first by ORB+homography, median image = blank form estimate, per-pixel variance across the batch = handwriting regions; cluster into field boxes; match to labels like F1. Output the same fields.json + overlay. Test with synthetic filled copies generated from blank-photo.jpg (handwriting-like strokes in field boxes).
- [x] (superseded by F3b) F3 (Studio via SSH: `ssh -i ~/.ssh/techlab UNIDCOM-V001@desktop-vdsrh2e`; code synced to C:\Users\UNIDCOM-V001\MyHermes\OpenLabTwin\tylog-form-ocr with `git archive HEAD | ssh ... tar -xf - -C <dir>` after each commit; photos C:\...\OpenLabTwin\digital-arc = 22 GoPro JPGs (fisheye: add lens undistortion before page detection/alignment), read-only, never copied to the Mac; output to C:\...\OpenLabTwin\digital-arc-out (rows.jsonl, crops, overlays per photo, summary.md). Vision reader = Studio Unsloth at http://localhost:8888 (OpenAI-compatible) from the Studio itself; API key from the Mac's ~/.pi/agent/models.json passed via env over ssh, never printed or written to files. Develop + unit-test on the Mac repo, run the batch on the Studio with uv.) Run on the real batch when it is reachable: rows.jsonl + crops, low-confidence -> review; summary of accuracy on 10 hand-checked forms.
- [x] F4 (user 2026-11-05: real handwriting overflows field borders) Overflow first: ink connected components that intersect a field box belong to that field — grow its crop to their union (bounded by neighbouring fields and the page), read the grown crop; only components touching no field become extra notes. After F4, re-run the whole Studio batch into digital-arc-out (overwrite) and compare per-field confidence before/after in summary.md. Handwriting outside fields: after alignment, diff each photo against the blank template (illumination-normalised), find ink regions that overlap no field box (margin notes, arrows, stamps, text across fields), crop them, read with the same reader, store in the row as `extra_notes: [{bbox, text, confidence, crop}]`; every extra note sets review: true. Overlay marks them in another colour. Test with a synthetic margin note on blank-photo.jpg; then run on the Studio batch.
- [x] F3b Run the real batch now (user wants results): estimate GoPro undistortion per photo automatically (straighten the detected page border / form ruling lines by fitting k1,k2 radial coefficients; or a standard GoPro wide preset as start), no calibration board needed. Process all 22 photos on the Studio into digital-arc-out (rows.jsonl, per-photo overlay PNG, crops, summary.md with per-field confidence). Accuracy check by the user later from the overlays; do not block on it.
- [x] F5 (ee04943; overflow done; extra notes still capped at 5/form = noise) Fix F4 on the real batch: (1) implement field overflow growth (ink components intersecting a field box join that field; crop = union, bounded by neighbouring fields/page) — F4 did not; (2) cut extra-note false positives (692 on 22 forms): illumination-normalise, threshold the diff against the blank, drop components below a minimum ink area / stroke width, drop printed template structure (lines, labels) via the template mask, merge nearby components into note regions, cap per page; target < 3 candidates per form on average. Re-run the Studio batch detached into digital-arc-f5-out; summary.md with candidates per form and per-field confidence vs F3b.
- [x] F6 Extra-note precision via the Studio vision model: send each candidate crop (with a little context) and ask "handwritten note / printed form element / noise"; keep only handwritten ones; cache verdicts per crop hash. Target: printed template parts never reported; < 1 candidate per form on this batch unless real notes exist. Re-run detached into digital-arc-f6-out; summary.md lists kept notes per form with crop paths.
- [x] (decided: P30 = test phone; junk cleaned) P30 RESET (2026-11-05 15:27): production TyLog on the P30 had been uninstalled during codex device runs; its app-storage vault was deleted with it (data safe on Nextcloud + Mac). Decide: re-setup P30 with Nextcloud (full download, Nextcloud load!) or keep P30 as test device on /sdcard/TyEmp. Clean codex junk in /sdcard root (pf7-*.xml, window*.xml, u.xml, ui.xml, s.png, fg_*.xml, h.xml).
- [x] PF7-rest-rest-rest-rest-rest closed: real-vault startup already measured with the production app (15 s, c40a6a8); granting the real vault to a test package is not allowed.
- [x] P2P6 Synthetic scratch transfer integrity slice (2026-11-05): after receiving, re-read and SHA-256-check every restored file before reporting success; show the verified file count. Missing or corrupted files fail verification. Focused tests cover both failures. No real vault was accessed; the full measurement remains below.
- [x] P2P6-rest (2026-11-05) Transferred an explicitly authorized read-only APFS vault snapshot Mac -> P30 `.profiletest`: 25,206 files, 2,461,600,858 bytes, SHA-256 verified, 367 s including receiver kill and fresh-ticket resume; a repeat verified the complete manifest in 33.667 s with zero bytes needed. CPU and powered battery-counter observations are in `docs/plans/2026-11-05-p2p/README.md`; production install time was unchanged. No real-vault folder grant or nettop.
- [x] P2P6-rest-rest (2026-11-05) Opened the verified received copy in the isolated P30 test app: 10,085 notes, index publication 30.359 s after open-start (29.038 s reported indexing duration). The copy remains open for visual review. Powered charge-counter observations and limitations are in `docs/plans/2026-11-05-p2p/README.md`.
- [x] P2P6-rest-rest-rest (2026-11-05) Fixed a same-ticket harness stall: a new receiver replaces an old connection still awaiting input. A synthetic loopback regression reproduces the stall and verifies the replacement; see the P2P notes. P2P3 remains no-go.
- [x] P2P6-rest-rest-rest-rest Add selected-path sampling to the isolated folder-transfer harness; loopback reports direct IP and the existing same-ticket reconnection regression passes. No P30 transfer was attempted because the production package and its required first-install timestamp could not be verified. P2P3 remains no-go.
- [x] (P30 is a test phone, no production app by decision) P2P6-rest-rest-rest-rest-rest Resolve the missing production package/first-install timestamp with the user before device work; then verify same-ticket recovery after an actual P30 receiver process kill, record selected paths during a new authorized transfer, and measure unplugged battery consumption. The earlier transfer did not record its route, its source clone was removed, and P30 reported AC power. Retain P2P3 no-go until the remaining safety gates pass.
- [x] (done 16:5x, see U4 line) U4 Claude: visual review 4-6 on the P30 test app with the P2P6 vault (timestamp scroll, More bar while typing, namespace convert + merge preview at phone width).
- [x] (done: f240fcd 323a852 16937f3, merged) P2P7 Streamed folder transfer in the harness: replace the 1 MiB scratch-text path with iroh blob streaming (iroh-blobs or chunked QUIC streams): per-file chunks, hash-verified, resumable after interruption, progress events; memory bounded (no whole-file buffering of 100 MB assets). Unit + loopback tests with a 200 MB synthetic folder. Then rerun P2P6-rest (full real-vault snapshot Mac -> P30 test app) with the same safety rules.
- [x] U4 Claude visual review on P30 test app (real-vault copy): timestamp inserts and caret stays visible above the keyboard; agenda + More bar hidden while typing (OK).
- [x] N1 BUG (U4): Settings > Maintenance > Migrate namespace titles treats every title containing "/" as a namespace, including articles and screenshots (e.g. "Add DRIVE tensor encoder by amitport · Pull Request #905 · tensorflow"); Apply would create hundreds of junk parent pages. Limit to note/entity kinds (never article/screenshot/audio/daily), Logseq namespace shape only (segments without URL-ish or long sentence parts; real Logseq imports used "A/B/C"), and show a spinner while building the plan (took ~15 s on 10k notes with no feedback). Preview should show counts first. Test with an article title containing "/".
- [x] H4 Health: extended `migrate-mentions` to discover marked `.typ` notes throughout the vault, including screenshots and other folders; dry-run remains read-only and apply keeps timestamped backups. Focused CLI test covers both locations and compiles behavior. The P30 `.profiletest` vault copy is not exposed by adb as a host CLI path; Mac GUI remained locked, so no real-copy write was performed.
- [x] (not needed: test copy only) H4-rest Apply `migrate-mentions` to the P30 `.profiletest` vault copy when it can be accessed by the existing CLI: dry-run first, review and print the full list, apply with backups, then compile-check every changed note.
- [x] H1 nightly LaunchAgent fixed: it ran without dart on PATH ('nice: dart: No such file'); now uses /Users/berloga/development/flutter/bin/dart.
- [x] (done via F9 d1d8ee3: 47 G4G, duplicate groups) F7 (user 2026-11-05) Run batch02 (digital-arc\batch02, 91 phone photos, no fisheye; batch01 = the 22 GoPro photos, now in digital-arc\batch01). (1) Duplicates: same physical form photographed more than once, within batch02 or also in batch01 -> keep one canonical row, others get `duplicate_of: <row id>` (perceptual hash of the flattened page + field-value similarity; never delete photos). (2) Event metadata: some forms belong to the event "Games for Good"; store it as `annotations: {event: {name, date, source}}` separate from `fields` (it is not original form data). Batch02 rule from the user: one photo is a handwritten separator sheet (not a form); every photo AFTER it in capture order (filename timestamp IMG_YYYYMMDD_HHMMSSmmm) belongs to Games for Good (G4G); read name/date for the annotation from the separator text if present. Also detect from OCR text on the page, and allow a manual override file `events.json` in the batch folder ({"photo": "...", "event": "Games for Good", "date": "YYYY-MM-DD"} or a list of photos per event). Non-form photos (other documents) -> `kind: not_form`, skipped. Output digital-arc-out\batch02 (rows.jsonl, overlays, summary.md with duplicate groups and event counts). Studio batch detached.
- [x] H4-rest Claude ran migrate-mentions vault-wide 2026-11-05 18:2x: only daily/2026/11/2026-11-04.typ had a block (again); applied with backup, compiles.
- [x] K5 Stop the app enrichment writer: current app refresh no longer writes blocks (02e092a), and the now-unused core block writer was removed. `tool/enrich_worker.py` writes only enrichment sidecars. K4 strips legacy blocks on app note writes. Source history rules out the worker and current app; revision attribution to the old Mac/A24 runtime remains below.
- [x] (moot: old writer removed 40dd13d, all devices updated) K5-rest Read the 2026-11-04 revision envelopes in the P30 `.profiletest` vault copy and identify which installed runtime restored the marker. The package was not installed during this run, and the Mac GUI is locked; do this when the copy is accessible without touching `org.tylog.tylog`.
- [x] H5 Health check flags `// tylog:auto-entities` anywhere in a line (OCR text in screenshots) — only flag it at line start outside list items.
- [x] (superseded by F9, 19 s/photo) F8 Fast page reader (user: old Mac script does 3-8 s/photo; current pipeline ~80 s/photo because it calls the vision model per field + per extra-note candidate). Reuse the pattern of ~/Documents/GitHub/openlabtwin/scripts/archive_ocr.py: flattened page as one ~2000 px JPEG, model unsloth/gemma-4-26B-A4B-it-qat-GGUF (or the Studio's loaded equivalent), thinking off, temperature 0; call 1 = transcription, call 2 = JSON with all 11 IADE fields + confidence + extra notes (text outside fields). Per-field crop re-read only when a field's confidence < threshold. Extra notes come from the transcription, not from ink-candidate vision calls. Keep alignment, duplicates, G4G separator/event annotation (F7). Target <= 10 s/photo on the Studio. Then rerun batch02 (91 photos, detached) into digital-arc-out\batch02 (overwrite), summary with timing per photo.
- [x] (done: compare report, gemma chosen) F8b (F8c measured 42.7 s/photo with gemma) Add per-stage timing (load/resize, page detect, undistort, align, transcription call, fields call, per-field re-reads, dedupe) and print it per photo; skip per-field re-reads unless confidence < 0.4. If F8 misses <= 10 s/photo or accuracy is weak: compare readers on 10 batch02 forms: gemma-4-26B-A4B page reader (F8) vs the user's fast screenshot OCR model qwen3.5:2b via ollama (~/Nextcloud/InstantUpload/Screenshots/ollama_ocr.py + config.py, 3-8 s/photo on the Mac). Report time and per-field agreement; pick the default.
- [x] F8c F8 ran ~60 s/photo because the Studio only had ornith-1.5:35b loaded (enrich worker); the page reader must use the fast vision model gemma-4-26B-A4B (Unsloth Studio id per ~/Documents/GitHub/openlabtwin/scripts/archive_ocr.py). Batch wrapper on the Mac: launchctl bootout org.tylog.enrich and org.tylog.worker, unload Ornith, load gemma via the Studio API (tool/model_bench/studio_load.py pattern), run the Studio batch, then ALWAYS restore (trap): unload gemma, load ornith-1.5:35b at 64k, bootstrap the agents — same shape as the PT pack script. Measure s/photo; target <= 10.
- [x] PF8 Incoming sheet performance slice: avoid loading enrichment feedback/shown ledgers again in the audio/OCR decision snapshot, and skip vault-wide enrichment memory when the requested page has no eligible daily notes. See `docs/plans/tylog-plus/evidence/PF8-incoming-performance.md`.
- [x] PF8-rest (2026-11-05) Deliver the PF8 Incoming hot-path slice and regression coverage; focused and full Flutter tests pass, and the release-signed `.profiletest` profile APK builds. The P30 measurements need a profile-compatible Dart instrumentation runner; see [PF8 Incoming performance](tylog-plus/evidence/PF8-incoming-performance.md).
- [x] PF8-rest-rest Run the changed Incoming-sheet harness on the existing P30 `.profiletest` real-vault copy through a release-signed, profile-compatible Dart instrumentation runner; record ready time, max Flutter frame, and Dart heap against the <1.5 s / <40 MB targets, then trim the first-page path if it misses. Preserve `.profiletest`; do not use `flutter drive` or the Mac GUI while locked. (2026-11-06: 1,358 ms ready, 337 ms max frame, −8.4 MB heap delta; first-page resolution batched and sidecar directory scan removed.)
- [x] DEV1 Device-run rule: documented `.profiletest`-only P30 device work, `flutter test integration_test --no-uninstall` or `adb install` + `am instrument`, and prohibited `flutter drive` / `svc power stayon` in AGENTS.md. Production package was absent during this run, so its `firstInstallTime` could not be re-read; no production install, uninstall, or clear was run. Mac GUI check skipped (screen locked).
- [x] F9 Page reader: one gemma call per photo (fields JSON + extra notes; drop the separate transcription call), smaller image if accuracy holds; keep qwen3.5:2b as an optional fast first pass behind a flag. Rerun batch02 with the GPU-swap wrapper into digital-arc-out\batch02 (overwrite); summary with s/photo, duplicate groups, G4G count.

## Wave 28 (2026-11-05, user: questions settled, build it)
- [x] P6a Bot vaults: read-only folder mount and item viewer under Extensions, with schema-1 manifest validation and fixture tests. Desktop folder picker only; mounted items currently enter the regular note index.
- [x] P6a-rest Bot vault refresh: refresh a mounted bot vault from Extensions, validating its manifest before scanning and reporting incompatible schemas; covered by a widget test.
- [x] P6a-rest-rest Desktop bot draft review: open a mounted schema-1 bot item in Extensions and append retry-safe advisory accept, reject, or dismiss decisions to its outbox.
- [x] P6a-rest-rest-rest Bot vault compatibility on mount reload: reject incompatible manifests before mounting or indexing, report the reason, and restore access when compatible again.
- [x] P6a-rest-rest-rest-rest Bot vault manual refresh removes incompatible mounts from the index, reports the manifest error, and restores them after compatibility is fixed.
- [x] P6a-rest-rest-rest-rest-rest Recheck bot vault compatibility on manual index rebuild, removing incompatible items and restoring them after the manifest is repaired.
- [x] P6a-rest-rest-rest-rest-rest-rest Recheck bot vault compatibility on routine index refresh, removing incompatible items and restoring them after the manifest is repaired.
- [x] P6a-rest-rest-rest-rest-rest-rest-rest Recheck bot vault compatibility when opening a draft from an already-open review list; report an incompatible manifest in the review flow and allow retry after repair.
- [x] P6a-rest-rest-rest-rest-rest-rest-rest-rest Recheck bot vault compatibility in the shared index scan driver, including sync-triggered and queued scans; incompatible items disappear and return after repair.
- [x] P6a-rest-rest-rest-rest-rest-rest-rest-rest-rest Wait for a cooperating process holding the bot decision outbox lock instead of failing the review action; exercise contention across processes.
- [x] P6a-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Serialize bot decision writers across POSIX isolates while retaining the outbox lock for cooperating processes.
- [x] P6a-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Desktop bot review handoff: hide successfully decided drafts immediately and on reopening, using valid complete outbox rows; incompatible manifests still block review.
- [x] P6a-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Desktop bot review honors first valid outbox event IDs and ignores invalid schema rows when hiding drafts or retrying decisions.
- [x] (folded into P6a FINAL) P6a-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest Complete Incoming draft ingestion and review, isolated search/indexing, Android folder access, Windows isolate coordination and other writers, cross-process workflow coverage, and remaining compatibility paths.
- [ ] P6a FINAL: DONE WHEN bot drafts appear in Incoming and accept/reject writes to the bot outbox per contract-v1, with a fixture test; then close. Complete the shared bot handoff contract with P6b: draft ingestion into the Incoming review registry, isolated search/indexing, Android folder access, Windows isolate coordination and other writers, and a full cross-process workflow test; verify any remaining compatibility paths.
- [x] P6b Bot vaults, bot side in ~/Documents/GitHub/Amadora-News-Bot per the same design: the bot writes its vault (manifest, items as notes per docs/vault-format.md, entities), reads decisions from the outbox. Behind a config flag, default off; no change to posting behaviour. Tests in that repo; commit there.
