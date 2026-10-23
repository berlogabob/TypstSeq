# Phone AI with sign-in (sub-project 1 of 3)

## Goal

Regular, non-technical users (most use the phone app only) turn on AI in TyLog by
signing in, without knowing what an API key, server or model is. AI jobs run on
the phone itself when no desktop worker is set up.

The intent is to remove the barrier of technical setup: a user should never have
to understand keys, endpoints or model names in order to use AI. Instead they sign
in once, and the app handles the rest — running jobs locally on the phone when no
desktop worker is available to drain them.

## Overview

This is sub-project 1 of 3. The other two are "Sign in with ChatGPT" and a full
AI settings screen simplification. The scope here is deliberately narrow: add one
cloud sign-in path (OpenRouter) and make the phone able to run AI jobs itself.
Everything else is left for later sub-projects so this change stays small and
testable.

The three sub-projects build on each other: sub-project 1 establishes the
sign-in path and the phone job runner; sub-project 2 adds a second sign-in
provider once OpenAI accepts TyLog; sub-project 3 then simplifies the settings
screen that the user sees. This spec covers only the first.

## User decisions (verbatim intent)

- Phone-only users must get AI. Standard OAuth sign-in, not API keys, for regular users.
- Approach 1 chosen: sign-in first, everything technical under "Advanced".
- Order: this spec = sub-project 1 (phone runs jobs) + OpenRouter sign-in. Sub-project 2 = "Sign in with ChatGPT" (after OpenAI accepts TyLog; user applies in parallel). Sub-project 3 = full AI settings screen simplification.

## Facts that constrain the design (checked 2026-10-23)

| Constraint | Detail |
| --- | --- |
| Claude | Anthropic forbids third-party apps from offering claude.ai login or using Free/Pro/Max plan OAuth (policy Feb 2026). Claude models are reached through OpenRouter or an Anthropic API key only. No "Sign in with Claude" button. |
| ChatGPT | "Sign in with ChatGPT" with plan usage announced DevDay 2026-09-29; limited to approved apps/partners. Out of scope here; sub-project 2. |
| OpenRouter | OAuth PKCE (S256). App opens `https://openrouter.ai/auth?callback_url=...&code_challenge=...&code_challenge_method=S256`; callback receives `?code=`; app POSTs to `https://openrouter.ai/api/v1/auth/keys` with `{code, code_verifier, code_challenge_method}` and gets `{key}`. The key is user-owned and billed to the user's OpenRouter credits. Docs confirm localhost callbacks; custom-scheme (mobile) callback acceptance is UNVERIFIED -> task 0 spike. |

These facts drive the whole approach: because there is no "Sign in with Claude"
option and "Sign in with ChatGPT" is out of scope, OpenRouter OAuth is the only
sign-in path available today. Its key facts (PKCE S256, key exchange endpoint,
user-owned billed key) are captured above and must not be altered by the design.

## Today (existing code)

**Settings.** `lib/ai/ai_settings.dart` holds `AiConnection {id, kind, label, url, cloud}`, `AiTask`, `AiSettings`, `WorkerStatus`, stored in the vault `_system/settings/ai.json`. API keys live in `flutter_secure_storage` via `lib/ai/api_keys.dart` (key `'ai-key:<connectionId>'`); never in `ai.json` or the vault. `lib/ai/provider_presets.dart` lists presets (OpenRouter already present as openai-compatible `https://openrouter.ai/api/v1`). `lib/ai/connection_probe.dart` tests a connection.

**Jobs.** The app writes JSON job files under `_system/jobs/{articles,transcripts,translations}/<sha1>.json` with status `queued -> processing -> done|error` (`lib/article_jobs.dart`, `lib/audio/transcript_jobs.dart`). Only the desktop worker (`article-pipeline tylog-worker`, Python, on the Mac) drains them. Worker heartbeat files: `_system/workers/*.json` (`WorkerStatus.isOnline` within 15 min).

**Screenshot OCR** runs only in the Mac screenshot pipeline (out of scope).

The design in this spec intentionally reuses these existing pieces: it adds a new
cloud connection for OpenRouter and relies on the existing job file format and
status lifecycle, so the rest of the app does not need to change. There is no
cross-device claim today: the desktop worker's `drain_jobs` (article-pipeline
`worker.py`) takes every `queued` or `processing` job and coordinates only local
instances with `flock`. The worker therefore needs the claim rule below too
(task 3b).

## Design

### 1. Sign in with OpenRouter (phone + desktop)

A "Sign in with OpenRouter" button with the subtitle: *"Use Claude, GPT, Gemini and more. You pay OpenRouter directly; TyLog never sees your card."*

- **Flow.** Generate `code_verifier` (32 random bytes, base64url), `challenge = base64url(sha256(verifier))` using package `crypto` (already a dependency). Open the auth URL in the system browser via `url_launcher`. Callback: Android/iOS app link scheme `tylog://auth/openrouter` (if spike shows OpenRouter rejects custom schemes: fall back to an https app link on a TyLog-owned page, or on desktop a localhost loopback server on `127.0.0.1:<random port>`). Receive `code`, exchange for key, save with `writeApiKey('openrouter', key)`, and add/update `AiConnection(id:'openrouter', kind:'openai-compatible', label:'OpenRouter', url:'https://openrouter.ai/api/v1', cloud:true)`.
- **State check.** `verifier` kept in memory + a random `state` value compared on return; reject mismatches. Timeout 10 min.
- **Sign out.** Deletes the key (`writeApiKey(id, null)`); the connection stays but shows "Signed out".
- **Default model per task** chosen by TyLog (`constants` in one file `lib/ai/cloud_defaults.dart`), editable under Advanced: text tasks -> a cheap capable model (constant, e.g. `'google/gemini-2.5-flash'`); transcription -> an audio-capable model constant. Exact model ids are chosen in task 0 by testing on OpenRouter.

The sign-in keeps everything technical out of the user's view: the connection,
URL and model are all managed internally and exposed only under "Advanced". The
`state` check and 10-minute timeout defend the window between opening the auth
URL and returning to the app, so a stale or tampered callback is rejected.

### 2. Phone job runner (`lib/ai/job_runner.dart`, new)

Runs in the app on phone and desktop when: the task's connection is a cloud
connection with a key, **AND** no online desktop worker has claimed that task
kind. Rule: if a desktop worker is online and its heartbeat lists the connection,
leave jobs to it; otherwise the app runs them. (Avoids double processing.)

- Claims a job by rewriting status `queued -> processing` with fields `runner:'app:<deviceId>'` and `claimed_at`; skips processing jobs claimed by others less than 30 min ago; reclaims stale ones.
- Runs while the app is open and in the existing WorkManager background service on Android (`vaultServiceMain`); one job at a time; network errors -> status stays `queued` with `retry_after` (exponential, max 1 h); auth error 401/403 -> status `error` reason `'signed_out'` and the UI shows "Sign in again".
- Writes results in the same format the desktop worker writes, so the rest of the app needs no change.
- **Task coverage in this sub-project:**

| Task | Coverage |
| --- | --- |
| Translation (text in, text out) | YES |
| Transcription | YES via an audio-capable chat model (audio file sent base64; size limit 20 MB, longer audio -> error reason `'too_long'` with a clear message). |
| Articles | Summary + tags only: phone fetches the page, strips HTML to text (simple tag stripping + `<article>`/`<main>` preference, no new heavy dependency), sends to the model, writes the article note in the existing article Typst format. Full extraction parity (YouTube, PDF, images) stays desktop-only; unsupported sources -> error reason `'needs_desktop'`. |
| Screenshots | NO (desktop pipeline). |

- **Cost guard.** Per-day request cap per task (default 200), counted on device; over cap -> jobs wait until the next day; shown in the task row.

The claim rule (fields `runner`, `claimed_at`; a claim younger than 30 min is
respected, an older one may be taken over) is new and is added to the desktop
worker as well (task 3b), so phone and desktop never process the same job twice.
The worker writes `runner:'worker:<host>'`. The per-day cap is enforced on
device so a single user cannot exhaust their OpenRouter credits silently.

### 3. Minimal settings change in this sub-project

AI page top: a "Connect AI" card.

- **Not connected:** buttons "Sign in with OpenRouter", "Use my computer" (explains the desktop worker, links to existing Servers page), "Advanced" (existing Servers page).
- **Connected:** "Connected with OpenRouter · Sign out", and per task a one-line status: e.g. "Translation: on, runs on this phone" / "Articles: runs on your Mac".

Everything else (existing Audio / Articles / Screenshots pages) unchanged until sub-project 3.

The card's wording reflects the runner's decisions: each task's status names
where it runs, so the user understands why some tasks wait for the Mac.

## Error handling

| Situation | Behaviour |
| --- | --- |
| Browser closed / user denies | Card shows "Sign-in cancelled", nothing saved. |
| `state` mismatch or exchange fails | "Sign-in failed, try again"; nothing saved. |
| No credits on OpenRouter (HTTP 402) | Job error reason `'no_credits'`; card says "Your OpenRouter balance is empty" with link to `openrouter.ai/credits`. |
| Offline | Jobs stay queued. |
| Desktop worker comes online mid-job | App finishes its claimed job; worker skips jobs claimed < 30 min. |

## Security

- Key only in `flutter_secure_storage` (and the existing owner-only `~/.tylog/keys.json` mirror on macOS). Never in `ai.json`, vault, logs, or job files. Error reasons are fixed codes, never response bodies.
- PKCE S256 + `state`; only https `openrouter.ai` endpoints.

## Testing

- **Unit.** PKCE verifier/challenge against the RFC 7636 test vector; callback parser (code, state, error); key exchange with a fake HTTP client; runner claim/skip/reclaim rules; worker-online handoff; `retry_after` backoff; daily cap; 401/402 mapping.
- **Widget.** Connect AI card states (not connected, connected, cancelled, failed, no credits).
- **Device.** P30 real sign-in with an OpenRouter account the user provides; translate one audio note, transcribe one short audio, summarise one article; check vault files match the desktop worker format; check no key in any vault file (grep).

## Tasks (order)

0. Spike: does OpenRouter accept `tylog://` callback on Android? Pick default model ids (text, audio) by test calls. Output: 1-page note in the spec.
1. PKCE + callback + key exchange (`lib/ai/openrouter_auth.dart`) with tests.
2. Deep link registration (Android intent-filter, iOS URL type, macOS loopback).
3. Job runner core (claim rules, backoff, cap) with tests.
3b. Desktop worker (article-pipeline repo, `worker.py` `drain_jobs` and the transcript/translation drains): honour and write `runner`/`claimed_at`; pytest for skip-fresh-claim and take-over-stale-claim.
4. Translation + transcription executors.
5. Article summary executor.
6. Connect AI card.
7. Device verification on P30 + A24, then CHANGELOG/USER_MANUAL.

## Out of scope

Sign in with ChatGPT (sub-project 2). Full AI settings simplification (sub-project 3). Screenshots on phone. iOS store review. TyLog-hosted accounts or billing.
