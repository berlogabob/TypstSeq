# Sync memory investigation — working-set plateau during large sync

> **Status: investigation note only. Nothing here is implemented.**
> Context: on a large sync (~7,300 remote files, ~1,500 transfers) the Android
> app's resident memory oscillates between 1.6 and 2.3 GB with ~135% CPU on a
> Huawei P30 (5.4 GB RAM), making the phone swap. Plateau, not monotonic
> growth. Investigated 2026-08-20 against `archive` 4.0.9 (pubspec.lock).

## Ranked suspects

### 1. `_RemoteArchiveSnapshot` retains every extracted file decompressed in the heap — **gigabytes** (prime suspect, confirmed mechanism)

**The retention chain, with evidence:**

- `_downloadArchive` streams the ZIP GET to a temp **file** (good) and decodes
  it lazily: `lib/nextcloud_sync/path_sync.dart:67-76`
  (`response.pipe(temporary.openWrite())`, then
  `ZipDecoder().decodeStream(InputFileStream(temporary.path))`). The raw ZIP
  itself is *not* the problem — `ZipFile._rawContent` is a file-backed subset
  stream (`archive-4.0.9/lib/src/codecs/zip/zip_file_header.dart:105`
  `_rawContent = input.readBytes(header!.compressedSize)`, and
  `input_file_stream.dart:199-210` returns a lazy `InputFileStream` view).
- Every download served from the archive calls `_RemoteArchiveSnapshot.read`
  → `files[path]?.readBytes()` (`lib/nextcloud_sync.dart:1060-1066`).
- In archive 4.0.9, `ArchiveFile.readBytes()` → `getContent()` →
  `decompress()` with no output, which **caches the full decompressed bytes
  on the entry**: `_content = FileContentMemory(bytes)`
  (`archive-4.0.9/lib/src/archive/archive_file.dart:172-184` and `:222-239`).
  Nothing in the app ever frees it per-entry.
- The only release point is `archiveSnapshot.close()` in `sync()`'s `finally`
  (`lib/nextcloud_sync.dart:765` → `_RemoteArchiveSnapshot.close()` at
  `lib/nextcloud_sync.dart:1068-1074`), i.e. **after the entire multi-minute
  run**. Until then, every file ever extracted stays resident, decompressed.

**Callers that feed the cache:** `_downloadStorage`
(`lib/nextcloud_sync/webdav_client.dart:241-263`), `_captureRemote`
(`lib/nextcloud_sync/conflicts.dart:18-21`).

**Size math.** Retained = Σ decompressed sizes of all paths read from the
archive during the run.
- ~1,500-transfer catch-up: if a few hundred of those are photo/image assets
  at 2–5 MB (typical of `assets/`), that alone is **1–2.5 GB** retained; the
  notes (~20 KB each) add ~30 MB.
- `initialMode == downloadRemote` bootstrap reads *every* remote path
  (`_shouldUseArchive` returns true unconditionally,
  `lib/nextcloud_sync/path_sync.dart:11`), so the retained set is the whole
  vault decompressed — for a ~5,000-file vault with images, ~2 GB.

This is exactly a **plateau, not a leak**: the cache tops out at the total
bytes transferred, and the 1.6→2.3→1.6 GB oscillation on top of it is GC
reclaiming the *transient* copies made per file:
- deflate extraction materializes the compressed entry **and** the
  decompressed output (`zip_file.dart:224-236`);
- `_downloadStorage` computes `sha256.convert(bytes)` **twice** on the same
  buffer (`webdav_client.dart:247` and `:262`);
- `storage.writeBytes(path, bytes)` copies the buffer again across the
  platform channel into SAF.

The CPU picture fits too: `sync()` runs on the **root isolate**
(`lib/workspace_controller.dart:816-840`), so inflate + 2×SHA-256 per file is
~100% of one core on the UI thread, plus SAF/platform-channel threads and GC
≈ the observed ~135%, and the UI "feels hung".

**Fix sketch.**
- In `_RemoteArchiveSnapshot.read` (`lib/nextcloud_sync.dart:1060`), extract
  via `file.writeContent(OutputMemoryStream(size: file.size),
  freeMemory: true)` instead of `readBytes()` — `writeContent` frees the
  `_content` cache after the write (`archive_file.dart:153-167`) while
  leaving the shared file-backed `_rawContent` untouched. **Do not** call
  `closeSync()` per entry: every entry's `InputFileStream.fromFileStream`
  shares the snapshot's single `FileBuffer`
  (`input_file_stream.dart:70-78`), so closing one entry closes the handle
  for all of them.
- Alternatively (belt and braces), after a successful
  `storage.writeBytes` in `_downloadStorage`, explicitly drop the entry's
  cached content so even an accidental future `readBytes()` path stays flat.
- Compute the SHA-256 once in `_downloadStorage`'s archive branch and reuse
  it for both the checksum check and `localSha256`.
- Expected effect: working set for the archive path drops from
  "total transferred bytes" to "one file at a time" — tens of MB.

### 2. Full-file buffering × 8 concurrent workers (per-file path) — **hundreds of MB** with large assets

The per-path loop runs **8 workers concurrently** when there is no archive
(`lib/nextcloud_sync.dart:675-680`; archive bootstrap is serial:
`math.min(archiveSnapshot == null ? 8 : 1, allPaths.length)`). Each worker
can hold several full copies of its file at once:

- `snapshotForUpload` holds `localBytes` for the rest of `_syncPath`
  (`lib/nextcloud_sync/path_sync.dart:241-248`), and `_upload` buffers the
  whole PUT body via `request.add(bytes)`
  (`lib/nextcloud_sync/webdav_client.dart:144,157`).
- Non-archive downloads stream to a temp file (good,
  `webdav_client.dart:206`), but then `_downloadStorage` re-reads it whole:
  `await temporary.readAsBytes()` + `storage.writeBytes(path, bytes)`
  (`webdav_client.dart:282-283`) ≈ 2–3 copies per file counting the
  platform-channel hop.
- `_sameImageDifferentMetadata` loads both sides fully, bounded at 32 MB
  (`lib/nextcloud_sync/path_sync.dart:825-833`).

Math: 8 workers × ~2.5 copies × 10–20 MB assets ≈ **200–400 MB** peak, plus
GC churn. Not the gigabytes, but a real amplifier on top of suspect 1 when a
run mixes archive misses with per-file transfers, and the whole of the
working set on non-archive runs.

**Fix sketch:** bound concurrency by *bytes in flight*, not path count
(e.g. a byte-budget semaphore: files > ~1 MB effectively serialize, small
notes keep the 8-way overlap); stream uploads from storage
(`contentLength` is already known); add a streaming `writeFromFile`/stream
variant to `VaultStorage` so downloads never round-trip through a single
`Uint8List`.

### 3. PROPFIND Depth:infinity body + `compute()` copy — **tens of MB**, transient

- The entire multistatus body is joined into one Dart string
  (`lib/nextcloud_sync/webdav_client.dart:14-17`). At ~1–1.5 KB XML per
  entry × 7,300 files ≈ 8–11 MB UTF-8 → **16–22 MB** as a UTF-16 Dart
  string.
- `compute(_parsePropfindBody, …)` copies that string into the parse isolate
  (`webdav_client.dart:31-35`) → transient peak ~2× ≈ **30–45 MB**, and the
  regex scan (`lib/nextcloud_sync.dart:929-976`) allocates per-block
  substrings on top.
- The archive path lists the remote **twice** per run (again at
  `lib/nextcloud_sync/path_sync.dart:79` for the changed-during-download
  check).
- Retained afterwards: the parsed map of 7,300 `_RemoteFile`s + path keys —
  a few MB for the whole run. Fine.

Megabytes, not gigabytes. **Fix sketch (low priority):** parse the response
incrementally from the byte stream (per `<d:response>` block) instead of
joining one string, or at least skip the `compute` copy by parsing in a
long-lived isolate; keep only the parsed map.

### 4. Cursor map checkpoint re-encode — **~2 MB per checkpoint**, CPU/GC churn only

Each time-based checkpoint clones the whole cursor map
(`Map<String, SyncCursor>.of(cursors)`, `lib/nextcloud_sync.dart:656`) and
re-encodes **every** cursor to JSON (`lib/nextcloud_sync/sync_state.dart:103-117`)
— ~250 B × 7,300 ≈ 1.8 MB string per save, at most every 5 s
(`checkpointInterval`, `lib/nextcloud_sync.dart:245`). Already deliberately
time-bounded (see the comment at `lib/nextcloud_sync.dart:640-652`).
Contributes GC churn and SAF-write stalls, not the plateau. Fix sketch, if
ever needed: encode incrementally / append a journal instead of rewriting the
full map.

### 5. `decisions` list and trace buffer — **negligible**

The `no-change` skip decisions are already filtered out
(`lib/nextcloud_sync.dart:634-637`), so ~1,500 transfer decisions ≈ well
under 1 MB; the trace file is trimmed at 512 KB and read/rewritten once per
run (`lib/nextcloud_sync/sync_state.dart:127-147`). Not a factor.

## Answers to the specific questions

1. **Does `_RemoteArchiveSnapshot` hold the ZIP in memory?** The compressed
   ZIP: no — it lives in a systemTemp file behind a lazy `InputFileStream`.
   The *decoded entries*: yes, incrementally — each entry read is cached
   decompressed on its `ArchiveFile` (`archive_file.dart:236`) until
   `close()` at end of run. For a ~5,000-file vault with image assets that
   converges on the full decompressed vault size, ~2 GB.
2. **Other suspects:** per-file buffering ×8 workers (hundreds of MB with
   large assets); PROPFIND string + compute copy (tens of MB, transient);
   cursor re-encode and decisions/trace (MBs, churn only).
3. **Gigabytes vs megabytes:** only suspect 1 reaches gigabytes; suspect 2
   reaches hundreds of MB; 3–5 are tens of MB or less.
4. **Concurrency:** 8 workers when no archive, **serial (1)** when an archive
   snapshot exists (`lib/nextcloud_sync.dart:675-680`) — so the observed
   gigabyte plateau during the bulk run is retention (suspect 1), not
   concurrency; concurrency multiplies the working set only on the per-file
   path.

## Recommended order of fixes

1. Free each archive entry's decompressed cache after use
   (`writeContent(freeMemory: true)` or explicit drop after
   `storage.writeBytes`) — removes the gigabytes.
2. Single SHA-256 per archive extraction — halves the biggest CPU term on
   the UI isolate.
3. Byte-budget concurrency + streaming upload/download for the per-file path.
4. (Optional) streaming PROPFIND parse.
